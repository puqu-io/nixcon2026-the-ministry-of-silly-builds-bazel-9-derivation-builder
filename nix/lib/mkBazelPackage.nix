# mkBazelPackage — build a Bazel 9 project with the unmodified upstream Bazel
# binary and no network.
#
# The shape is two derivations and one script:
#
#   nix run .#update   (impure)  record → bazel-deps.lock.json, committed
#   mkBazelPackage     (pure)    serve  → bazel builds offline
#

{
  lib,
  stdenv,
  cacheLib,
  bazel,
  jdk,
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

  # opaque repos: { "@@canonical+name" = <store path>; }
  opaqueRepos ? { },
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

  hasOpaque = opaqueRepos != { };
  vendorDir = cacheLib.mkVendorDir {
    repos = opaqueRepos;
    name = "${pname}-vendor";
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

  buildFlags = [
    "--repository_disable_download"
  ];

  buildCacheFlags = cacheLib.cacheFlags {
    vendorDir = hasOpaque;
    repoCache = true;
    registryTree = false;
  };

  updateFlags = [
    "--repository_cache="
    "--lockfile_mode=update"
    "--experimental_convenience_symlinks=ignore"
  ];

  updateCacheFlags = cacheLib.cacheFlags {
    vendorDir = hasOpaque;
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
    ${lib.optionalString hasOpaque (cacheLib.vendorDirSetupHook vendorDir)}
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
    # It is a script rather than a fixed-output derivation on purpose: the lock
    # is committed to the repo, the same way cargoLock or npmDepsHash are, and
    # nixpkgs cannot use IFD. Wrap this in an FOD whose output is the lock file
    # (and only the lock file) if you want the flake to build it on demand.
    update = updater {
      inherit
        bazel
        jdk
        bazelEnv
        cacheLib
        commonFlags
        hasOpaque
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
