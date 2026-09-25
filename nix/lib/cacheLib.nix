{
  lib,
  fetchurl,
  linkFarm,
  emptyFile,
}:

let
  inherit (lib) concatMapStringsSep substring;

  # Fetch log written by updater: one JSON object per line.
  #
  #  {"kind":"archive","urls":["https://..."],"sha256":"a1b2..." "canonical_id_marker":null,"context":"repository @@rules_cc+"}
  #  {"kind":"registry","urls":["https://..."],"sha256":"b2c3..." "canonical_id_marker":"id-c3d4...","context":null}
  readLock =
    lockFile:
    let
      lines = builtins.filter (line: line != "") (lib.splitString "\n" (builtins.readFile lockFile));
    in
    map builtins.fromJSON lines;

  # downloads recorded without a checksum. bazel only looks in the repository cache
  # when a checksum is declared, so these can never be served offline.
  missingChecksums =
    entries:
    lib.unique (lib.concatMap (e: e.urls) (builtins.filter (e: e.sha256 == null) entries));

  # the same bytes are usually recorded many times: once per Bazel command, under
  # mirror URLs, or by several repos. Merge them into one artifact per sha256, keeping
  # every URL (fetchurl tries them in order) and every canonical id marker (each needs
  # its own file in the cache).

  # [
  # {
  #   sha256 = "1849602c86cb60da8613d2de887f9566a6d354a6df6d7009f9d04a14402f9a84";
  #   urls = [ "https://bcr.bazel.build/modules/rules_foo/0.1.1/MODULE.bazel" ];
  #   idMarkers = [ ];
  #   kinds = [ "registry" "archive" ];
  # }
  # {
  #   sha256 = "283fa1cdaaf172337898749cf4b9b1ef5ea269da59540954e51fba0e7b8f277a";
  #   urls = [
  #     "https://github.com/bazelbuild/rules_bar/releases/download/0.9.9/rules_bar-0.9.9.tar.gz"
  #     "https://mirror.example/rules_bar-0.9.9.tar.gz"
  #   ];
  #   idMarkers = [
  #     "id-569116aedef0cb6f2ee8ec73c2b97cc9ba36d3cbfb4e9b7f6bed3bdcb416b699"
  #     "id-93e8304d8070f91afe578de0b0b90e926c920df83bd3c30b07cc4f36c4a04482"
  #   ];
  #   kinds = [ "archive" ];
  # }
  # ] 
  artifactsOf =
    entries:
    lib.mapAttrsToList (sha256: group: {
      inherit sha256;
      urls = lib.unique (lib.concatMap (e: e.urls) group);
      idMarkers = lib.unique (
        builtins.filter (idMarker: idMarker != null) (map (e: e.canonical_id_marker) group)
      );
      kinds = lib.unique (map (e: e.kind) group);
    }) (lib.groupBy (e: e.sha256) (builtins.filter (e: e.sha256 != null) entries));

  fetchArtifact =
    a:
    fetchurl {
      inherit (a) urls sha256;
      name = a.name or "bazel-blob-${substring 0 12 a.sha256}";
    };

  recordedDirSetupHook = writableDirName: frozenDir: ''
    writableDir="$TMPDIR/${writableDirName}"
    if [[ ! -d "''${writableDir}" ]]; then
      mkdir -p "''${writableDir}"
    fi
    cp -rs ${frozenDir}/. "''${writableDir}/"
    chmod -R u+w "''${writableDir}"
  '';

in
rec {
  inherit
    readLock
    missingChecksums
    artifactsOf
    fetchArtifact
    ;

  # every artifact in the lock file, as a list of store paths.
  artifacts = lockFile: map fetchArtifact (artifactsOf (readLock lockFile));

  # layout is exactly what bazel expects below the path given to
  # --repository_cache:
  #
  #  <dir>/content_addressable/sha256/<hex>/file                 the bytes
  #  <dir>/content_addressable/sha256/<hex>/id-<sha256(canonId)> a marker file
  #
  # DownloadManager checks the repository cache for both downloadInExecutor and downloadAndReadOneUrlForBzlmod
  # keyed by the declared checksum. 
  # Registry files get their checksums from MODULE.bazel.lock, so record with an up-to-date lockfile.
  #
  # Download whose rule declared no checksum is never looked up here at all.
  mkRepoCache =
    {
      lockFile,
      name ? "bazel-repo-cache",
      allowMissingChecksums ? false,
    }:
    let
      entries = readLock lockFile;
      missing = missingChecksums entries;

      blob = a: {
        name = "content_addressable/sha256/${a.sha256}/file";
        path = fetchArtifact a;
      };

      # canonical id restricts cache hits to entries carrying its marker:
      # DownloadCache.hasCanonicalId hashes the id and looks for "id-<hash>"
      # beside the file. Without these, every rule that sets one misses and
      # falls through to a disabled download.
      idMarkers =
        a:
        map (idMarker: {
          name = "content_addressable/sha256/${a.sha256}/${idMarker}";
          path = emptyFile;
        }) a.idMarkers;
    in
    if missing != [ ] && !allowMissingChecksums then
      throw ''
        ${toString lockFile}: ${toString (builtins.length missing)} download(s) have no declared
        sha256, so Bazel cannot find them in the repository cache offline:
        ${concatMapStringsSep "\n" (url: "  ${url}") missing}
        Add a sha256/integrity to the rule, re-record with an up-to-date MODULE.bazel.lock
        (for registry files), or pass allowMissingChecksums = true to skip them.''
    else
      linkFarm name (lib.concatMap (a: [ (blob a) ] ++ idMarkers a) (artifactsOf entries));

  # Bazel needs to acquire a lock on repository cache, so the directory needs to be writable
  # at build time.
  repoCacheSetupHook = repoCache: recordedDirSetupHook "repo-cache" repoCache;

  # registry directory for --registry=file://<out>, as an alternative to serving registry
  # files from the repository cache. the log records full URLs, so each file's place in
  # the tree is its URL minus registryUrl. Registry files recorded without a sha256
  # cannot be fetched and are left out.
  mkRegistryTree =
    {
      lockFile,
      registryUrl ? "https://bcr.bazel.build",
      name ? "bazel-registry",
    }:
    let
      prefix = lib.removeSuffix "/" registryUrl + "/";
      files = builtins.filter (e: e.kind == "registry" && e.sha256 != null) (readLock lockFile);
      inRegistry = e: builtins.filter (lib.hasPrefix prefix) e.urls;
    in
    linkFarm name (
      lib.unique (
        lib.concatMap (
          e:
          map (url: {
            name = lib.removePrefix prefix url;
            path = fetchArtifact e;
          }) (inRegistry e)
        ) files
      )
    );

  registryDirSetupHook = registryDir: recordedDirSetupHook "registry" registryDir;

  # vendor directory must be writable: Bazel refreshes
  # <vendor_dir>/bazel-external on every command. Materialise a symlink
  # skeleton the build can write into without copying any content.
  vendorDirSetupHook = vendorDir: recordedDirSetupHook "vendor" vendorDir;

  cacheFlags =
    {
      repoCache ? false,
      vendorDir ? false,
      registryTree ? false,
    }:
    lib.concatStringsSep " " (
      lib.optional repoCache ''--repository_cache="$TMPDIR/repo-cache"''
      ++ lib.optional vendorDir ''--vendor_dir="$TMPDIR/vendor"''
      ++ lib.optional registryTree ''--registry="$TMPDIR/registry"''
    );
}
