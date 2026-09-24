{
  lib,
  stdenvNoCC,
  fetchurl,
  jdk,
  stripJavaArchivesHook,
}:

let
  javassist = fetchurl {
    name = "javassist-3.29.2-GA.jar";
    url = "https://github.com/jboss-javassist/javassist/releases/download/rel_3_29_2_ga/javassist.jar";
    hash = "sha256-rPp3yNxy7FYEEWpuzfRSCtmIGxw0Bm2f2dKsCKIwprU=";
  };
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "fetchrec";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = ./src;
  };

  # jar and javac come from jdk. stripJavaArchivesHook resets timestamps
  # and file order inside jar, so the output is reproducible.
  nativeBuildInputs = [
    jdk
    stripJavaArchivesHook
  ];

  buildPhase = ''
    runHook preBuild

    mkdir classes

    javac --release 21 -cp ${javassist} -d classes src/fetchrec/*.java

    # put javassist inside the agent jar
    (cd classes && jar xf ${javassist} javassist)

    # Premain-Class tells java which class has premain().
    echo 'Premain-Class: fetchrec.Agent' > manifest.txt
    jar --create --file fetchrec.jar --manifest manifest.txt -C classes .

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 fetchrec.jar $out/fetchrec.jar
    runHook postInstall
  '';

  passthru = {
    inherit javassist;

    jar = "${finalAttrs.finalPackage}/share/java/fetchrec.jar";

  };
})
