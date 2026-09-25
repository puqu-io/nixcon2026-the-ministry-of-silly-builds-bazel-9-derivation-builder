{ #TODO: group flags
  lib,
  stdenv,
  pname,
  src,
  bazel,
  jdk,
  bazelEnv,
  cacheLib,
  startupFlags,
  commonFlags,
  buildFlags,
  repoCache,
  vendorRepos,
  vendorReposHash,
  useRepoCache,
  nativeBuildInputs ? [ ],
}:

let
  vendorCacheFlags = cacheLib.cacheFlags {
    repoCache = useRepoCache;
  };
in
stdenv.mkDerivation {
  name = "${pname}-vendor";
  inherit src;

  nativeBuildInputs = nativeBuildInputs ++ [
    bazel
    jdk
  ];

  outputHashMode = "recursive";
  outputHashAlgo = "sha256";
  outputHash = if vendorReposHash == "" then lib.fakeHash else vendorReposHash;

  impureEnvVars = lib.fetchers.proxyImpureEnvVars;

  dontConfigure = true;
  dontFixup = true;

  buildPhase = ''
    runHook preBuild

    ${bazelEnv}

    ${lib.optionalString useRepoCache (cacheLib.repoCacheSetupHook repoCache)}

    vendorDir="$TMPDIR/vendor"
    mkdir -p "$vendorDir"

    bazel \
      ${startupFlags} \
      vendor ${lib.escapeShellArgs (map (n: "--repo=@@${n}") vendorRepos)} \
      --vendor_dir="$vendorDir" \
      ${lib.escapeShellArgs (buildFlags ++ commonFlags)} \
      ${vendorCacheFlags}

    bazel ${startupFlags} shutdown

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    for name in ${lib.escapeShellArgs vendorRepos}; do
      cp -a "$vendorDir/$name" "$out/$name"
    done
    chmod -R u+w "$out"

    cat > "$out/VENDOR.bazel" <<'EOF'
    ${lib.concatMapStringsSep "\n" (n: ''pin("@@${n}")'') vendorRepos}
    EOF

    runHook postInstall
  '';
}
