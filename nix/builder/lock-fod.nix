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

    lockOut="$TMPDIR/fetches.raw.jsonl"
    touch "$lockOut"

    ${updater.script}

    sort -u "$lockOut" > "$TMPDIR/fetches.jsonl"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cp "$TMPDIR/fetches.jsonl" "$out"
    runHook postInstall
  '';
}
