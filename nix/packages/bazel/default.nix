{
  stdenv,
  fetchurl,
  buildFHSEnv,
  zlib,
  jdk,
}:

let
  version = "9.2.0";

  bazel_nojdk = stdenv.mkDerivation rec {
    pname = "bazel_nojdk";
    inherit version;

    src = fetchurl {
      url = "https://github.com/bazelbuild/bazel/releases/download/${version}/bazel_nojdk-${version}-linux-x86_64";
      hash = "sha256-nPNJjm0TK2DKkLE5BJmgcmUITUcH6YwSjBPChNpMRw8=";
    };

    dontUnpack = true;
    dontPatch = true;
    dontBuild = true;
    dontStrip = true;
    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin
      install -Dm755 $src $out/bin/bazel

      runHook postInstall
    '';
  };
in
buildFHSEnv {
  pname = "bazel";
  inherit version;
  targetPkgs = _: [
    zlib
    jdk
    bazel_nojdk
  ];
  runScript = "bazel";
}
