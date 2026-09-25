{
  lib,
  stdenv,
  cacheLib,
  bazel,
  jdk,
  callPackage,
}:

updater:

{
  pname,
  version,
  src,

  # The lock produced by `nix run .#update`, committed to the repo.
  lockFile,

  targets ? [ "//..." ],
  installPhase,

  # Extra flags for both the recording and the build. Anything that
  # changes *what gets fetched* must be here rather than only on one side, or
  # the recording will not match the build.
  bazelFlags ? [ ],

  vendorRepos ? [ ],
  vendorReposHash ? "",
  vendorReposUseRepoCache ? true,
  ...
}@args:

let
  repoCache = cacheLib.mkRepoCache {
    inherit lockFile;
    name = "${pname}-repo-cache";
  };
  registryCache = cacheLib.mkRegistryCache {
    inherit lockFile;
    name = "${pname}-registry-cache";
  };
  registryTree = cacheLib.mkRegistryTree {
    inherit lockFile;
    name = "${pname}-registry";
  };

  startupFlags = lib.concatStringsSep " " [
    ''--output_user_root="$TMPDIR/bazel-root"''
  ];

  commonFlags = [
    "--java_runtime_version=remotejdk_25"
    "--tool_java_runtime_version=remotejdk_25"
    "--remote_timeout=3600"
    "--distdir="
  ]
  ++ bazelFlags;

  hasVendorRepos = vendorRepos != [ ];

  updateHasVendorRepos = hasVendorRepos && vendorReposHash != "";

  vendorDir = callPackage ./vendorRepos.nix {
    nativeBuildInputs = args.nativeBuildInputs or [ ];
    useRepoCache = vendorReposUseRepoCache;
    inherit
      pname
      src
      bazel
      jdk
      bazelEnv
      cacheLib
      startupFlags
      commonFlags
      buildFlags
      repoCache
      vendorRepos
      vendorReposHash
      ;
  };

  buildFlags = [
    "--lockfile_mode=error"
    "--repository_disable_download"
  ];

  buildCacheFlags = cacheLib.cacheFlags {
    vendorDir = hasVendorRepos;
    repoCache = true;
    registryTree = false;
  };

  updateFlags = [
    "--repository_cache="
    "--lockfile_mode=update"
    "--experimental_convenience_symlinks=ignore"
  ];

  updateCacheFlags = cacheLib.cacheFlags {
    vendorDir = updateHasVendorRepos;
    repoCache = false;
    registryTree = false;
  };

  # Bazel keeps state under $HOME and wants a $USER. Neither exists in a build
  # sandbox, and Bazel's failure when they are missing is not obvious.
  bazelEnv = ''
    export HOME="$TMPDIR/home"
    export USER="''${USER:-nixbld}"
    export JAVA_HOME="${jdk}"
    mkdir -p "$HOME"
  '';
in
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = (args.nativeBuildInputs or [ ]) ++ [
    bazel
    jdk
  ];

  # No network
  buildPhase = ''
    runHook preBuild

    ${bazelEnv}
    ${lib.optionalString hasVendorRepos (cacheLib.vendorDirSetupHook vendorDir)}
    ${cacheLib.repoCacheSetupHook repoCache}

    bazel \
      ${startupFlags} \
      build ${lib.escapeShellArgs targets} \
      ${lib.escapeShellArgs (buildFlags ++ commonFlags)} \
      ${buildCacheFlags}

    runHook postBuild
  '';

  inherit installPhase;

  # bazel leaves a server running; shut it down so the build does not hang.
  postInstall = (args.postInstall or "") + ''
    bazel ${startupFlags} shutdown || true
  '';

  passthru = (args.passthru or { }) // {
    # nix build .#default.vendor
    vendor = vendorDir;

    # It is a script rather than a fixed-output derivation on purpose: the lock
    # is committed to the repo, the same way cargoLock or npmDepsHash are, and
    # nixpkgs cannot use IFD. Wrap this in an FOD whose output is the lock file
    # (and only the lock file) if you want the flake to build it on demand.
    update = updater {

      # updater may only use the vendor directory once it has a real hash
      hasVendorRepos = updateHasVendorRepos;
      inherit
        bazel
        jdk
        bazelEnv
        cacheLib
        commonFlags
        pname
        targets
        startupFlags
        updateCacheFlags
        updateFlags
        vendorDir
        ;
    };
  };
}
