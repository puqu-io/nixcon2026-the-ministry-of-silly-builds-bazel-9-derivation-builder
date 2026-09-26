{
  lib,
  stdenv,
  ctx,
  caches,
  pname,
  src,
  vendorRepos,
  vendorReposHash,
  flags ? [ ],
  mounts,
  nativeBuildInputs ? [ ],
}:

stdenv.mkDerivation {
  name = "${pname}-vendor";
  inherit src;

  nativeBuildInputs = nativeBuildInputs ++ [
    ctx.bazel
    ctx.jdk
  ];

  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash = if vendorReposHash == "" then lib.fakeHash else vendorReposHash;

  impureEnvVars = lib.fetchers.proxyImpureEnvVars;

  dontConfigure = true;
  dontFixup = true;

  buildPhase = ''
    runHook preBuild

    ${ctx.env}
    ${caches.setup mounts}

    mkdir -p "vendor"

    ${ctx.run {
      cmd = "vendor";
      flags = (
        flags ++ (map (n: "--repo=@@${n}") vendorRepos) ++ [ "--vendor_dir=vendor" ]
      );
      inherit mounts;
    }}

    ${ctx.shutdown []}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    for name in ${lib.escapeShellArgs vendorRepos}; do
      cp -a "vendor/$name" "$out/$name"
    done
    chmod -R u+w "$out"

    cat > "$out/VENDOR.bazel" <<'EOF'
    ${lib.concatMapStringsSep "\n" (n: ''pin("@@${n}")'') vendorRepos}
    EOF

    runHook postInstall
  '';
}
