{
  lib,
  stdenv,
}:

{
  pname,
  src,
  updater,
  lockHash ? "",
  nativeBuildInputs ? [ ],
}:

stdenv.mkDerivation {
  name = "${pname}-fetches.jsonl";
  inherit src;

  nativeBuildInputs = nativeBuildInputs ++ (updater.nativeBuildInputs or [ ]);

  outputHashMode = "flat";
  outputHashAlgo = "sha256";
  outputHash = if lockHash == "" then lib.fakeHash else lockHash;

  impureEnvVars = lib.fetchers.proxyImpureEnvVars;

  dontConfigure = true;
  dontFixup = true;

  buildPhase = ''
    runHook preBuild

    lockOut="fetches.raw.jsonl"
    touch "$lockOut"

    ${updater.script}

    sort -u "$lockOut" > fetches.jsonl

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cp fetches.jsonl "$out"
    runHook postInstall
  '';
}
