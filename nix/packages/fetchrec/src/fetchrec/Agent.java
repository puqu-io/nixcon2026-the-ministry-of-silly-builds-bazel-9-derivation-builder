package fetchrec;

import java.io.ByteArrayInputStream;
import java.io.FileWriter;
import java.io.IOException; // bazel DownloadManager throws these
import java.io.PrintWriter;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.lang.instrument.ClassFileTransformer;
import java.lang.instrument.Instrumentation;
import java.security.ProtectionDomain;
import java.util.HexFormat;
import java.util.List;
import java.util.Optional;
import javassist.ClassClassPath;
import javassist.ClassPool;
import javassist.CtClass;
import javassist.CtMethod;
import javassist.LoaderClassPath;

/**
 * record all downloads done by bazel
 *
 *   bazel --host_jvm_args=-javaagent:/somepath/fetchrec.jar=/somepath/fetches.jsonl ...
 *
 *  1. "-javaagent" makes java run premain() before anything else
 *  2. premain() catches every piece of java code before it is run
 *     when DownloadManager shows up one extra call to record is added in places
 *     where downloads finish
 *  3. every time bazel finishes a download, record() adds a line to the log:
 *       {"kind":"archive","urls":["https://..."],"sha256":"a1b2...",
 *        "id_hash":null,"context":"repository @@rules_cc+"}
 */
public class Agent implements ClassFileTransformer {

  // happens once, when Bazel starts

  private static PrintWriter log;

  // set by transform() if DownloadManager could not be changed
  private static Throwable transformError;

  /**
   * entrypoint of javaagent
   * @param logFilePath whatever comes after "=" in the -javaagent option
   */
  public static void premain(String logFilePath, Instrumentation jvm) throws Exception {
    log = new PrintWriter(
        new FileWriter(logFilePath), // out
        true                         // autoFlush. write the line rightaway, in case bazel dies
    );

    // run every class through transform() below
    jvm.addTransformer(new Agent());

    // ok ths is cursed, but hear me out. java ignores exceptions thrown
    // from transform(), so load DownloadManager now (false = don't run any of its code yet) 
    // and throw here instead. an exception from premain() stops bazel
    // from starting.
    Class.forName(
        "com.google.devtools.build.lib.bazel.repository.downloader.DownloadManager",
        false,
        ClassLoader.getSystemClassLoader());
    if (transformError != null) {
      throw new IllegalStateException(
          "fetchrec: could not change DownloadManager", transformError);
    }
  }

  /**
   * java calls this for every class and hands over its compiled code (bytecode).
   * then if the class is what we want, we modify it and return changed version
   */
  @Override
  public byte[] transform(
      ClassLoader bazelClassLoader,
      String className, // written with "/" instead of ".", e.g. "java/some/Class"
      Class<?> ignored1, // not sure what thats for
      ProtectionDomain ignored2,
      byte[] originalBytecode) {

    if (!className.equals(
        "com/google/devtools/build/lib/bazel/repository/downloader/DownloadManager")) {
      return null; // not DownloadManager, skip it
    }

    try {
      // collect all places where classes are defined
      ClassPool classPool = ClassPool.getDefault();

      // turn the bytecode into something editable.
      CtClass downloadManager = classPool.makeClass(new ByteArrayInputStream(originalBytecode));

      // downloads for repository rules and module extensions (http_archive,
      // ctx.download). inputs from original function:
      //   $1 urls, $2 headers, $3 authHeaders, $4 checksum, $5 canonicalId,
      //   $6 type, $7 output, $8 clientEnv, $9 context, $10 mayHardlink
      // for javassist, $1 means "the 1st input", $2 "the 2nd", and so on.
      //
      // our own copy of method
      CtMethod downloadInExecutor = downloadManager.getDeclaredMethod("downloadInExecutor");
      // insertAfter() injects record function right at the end, just before the method returns.
      downloadInExecutor.insertAfter("fetchrec.Agent.record(\"archive\", $1, $4, $5, $9);");

      // downloads registry files (MODULE.bazel, source.json, ...)
      //   $1 url, $2 clientEnv, $3 checksum
      CtMethod downloadAndReadOneUrlForBzlmod =
          downloadManager.getDeclaredMethod("downloadAndReadOneUrlForBzlmod");
      downloadAndReadOneUrlForBzlmod.insertAfter("fetchrec.Agent.record(\"registry\", $1, $3, null, null);");

      return downloadManager.toBytecode(); // hand the changed class back to Java

    } catch (Throwable error) {
      transformError = error; // thrown by premain(), we cannot throw it here because it would be silently ignored
      return null;
    }
  }


    /**
   * add a line to the log file
   *
   * @param kind "archive" or "registry"
   * @param urls list of urls (archives) or just one URL (registry files)
   * @param checksum what bazel expects the file to be. might be empty(?)
   * @param canonicalId bazel's canonical id for the download, or null
   * @param context which repo wanted the download, or null
   * @throws IOException if the checksum is somethng else than sha256
   *     "download failed", so the message shows up in Bazel's output.
   */
  public static void record(
      String kind, Object urls, Optional<?> checksum, String canonicalId, String context)
      throws IOException, NoSuchAlgorithmException {
    String urlsJson = urlsAsJson(urls);
    String sha256 = sha256Of(checksum, urlsJson); 

    writeToLog(
        "{\"kind\":" + quote(kind)
            + ",\"urls\":" + urlsJson
            + ",\"sha256\":" + quote(sha256)
            + ",\"id_hash\":" + quote(idHash(canonicalId))
            + ",\"context\":" + quote(context)
            + "}");
  }

  /**
   * extract sha256, or null if theres no checksum.
   *
   * bazel keeps checksums in its own Checksum class. this agent is built without bazel, so it
   * can't just call Checksum's methods. Instead it looks them up using reflection`
   */
  private static String sha256Of(Optional<?> checksum, String urlsJson) throws IOException {
    if (checksum.isEmpty()) {
      return null; // TODO throw error instead? bazel allows for downloading stuff without
		   // specifying checksum. should this fail early on here or later when the lockfile
		   // is parsed in nix?
    }
    Object bazelChecksum = checksum.get();

    String algorithm;
    try {
      algorithm =
          bazelChecksum.getClass().getMethod("getKeyType").invoke(bazelChecksum).toString(); //bakflip
    } catch (ReflectiveOperationException error) {
      throw new IOException("fetchrec: cannot read the checksum algorithm", error);
    }

    if (!algorithm.equals("SHA-256")) {
      String message =
          "fetchrec: only SHA-256 checksums are supported, but " + urlsJson
              + " has a " + algorithm + " checksum";
      throw new IOException(message);
    }
    return bazelChecksum.toString();
  }

  /** compute the hash part of "id-<idHash>" marker file bazel puts next to a cached file. mimic the approach used in DownloadCache. */
  private static String idHash(String canonicalId) throws NoSuchAlgorithmException {
    if (canonicalId == null || canonicalId.isEmpty()) {
      return null; // yep, it is possible that there's no canonial id
    }
    byte[] hash = MessageDigest.getInstance("SHA-256").digest(canonicalId.getBytes(StandardCharsets.UTF_8));
    return HexFormat.of().formatHex(hash);
  }

  /** turn a list of URLs (or just one) into JSON, like ["a","b"]. */
  private static String urlsAsJson(Object urls) {
    List<?> urlList;
    if (urls instanceof List) {
      urlList = (List<?>) urls;
    } else {
      urlList = List.of(urls);
    }

    String json = "[";
    for (int i = 0; i < urlList.size(); i++) {
      if (i > 0) {
        json += ",";
      }
      json += quote(urlList.get(i).toString());
    }
    return json + "]";
  }

  /**
   * wrap text in quotes for json. empty text turns into null.
   */
  private static String quote(String text) {
    if (text == null || text.isEmpty()) {
      return "null";
    }
    // god i hate this
    return "\"" + text.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
  }

  /**
   * write one line to the log. ibazel downloads lots of files at once, so "synchronized" makes
   * them take turns 
   */
  private static synchronized void writeToLog(String line) {
    log.println(line);
  }
}
