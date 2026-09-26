{
  lib,
  stdenv,
  callPackage,
  bazel,
  jdk,
  bazelUpdaters,
}:

{
  pname,
  version,
  src,

  lockFile,
  lockPath ? "fetches.jsonl", # where the updater writes the lock
  updater,

  targets ? [ "//..." ],
  installPhase,

  bazelFlags ? [ ], # extra flags provided by user
  javaRuntime ? "remotejdk_25",

  vendorRepos ? [ ],
  vendorReposHash ? "",
  vendorReposUseRepoCache ? true,

  nativeBuildInputs ? [ ],
  passthru ? { },
  ...
}@args:

let
  lock = callPackage ./lock.nix { };
  caches = callPackage ./caches.nix { inherit lock; };
  ctx = import ./context.nix {
    inherit
      lib
      bazel
      jdk
      bazelFlags
      javaRuntime
      ;
  };

  repoCache = caches.mkRepoCache {
    inherit lockFile;
    name = "${pname}-repo-cache";
  };

  hasVendorRepos = vendorRepos != [ ];
  # the updater may only use the vendor directory once it has a real hash
  updateHasVendorRepos = hasVendorRepos && vendorReposHash != "";

  vendorDir = callPackage ./vendor.nix {
    inherit
      ctx
      caches
      pname
      src
      vendorRepos
      vendorReposHash
      nativeBuildInputs
      ;
    flags = [ "--lockfile_mode=error" ];
    mounts = lib.optional vendorReposUseRepoCache (caches.repoCacheMount repoCache);
  };

  buildMounts = [
    (caches.repoCacheMount repoCache)
  ]
  ++ lib.optional hasVendorRepos (caches.vendorMount vendorDir);

  updateMounts = lib.optional updateHasVendorRepos (caches.vendorMount vendorDir);

  # builder-only arguments, everything else goe's to mkDerivation
  builderArgs = [
    "lockFile"
    "lockPath"
    "updater"
    "targets"
    "bazelFlags"
    "javaRuntime"
    "vendorRepos"
    "vendorReposHash"
    "vendorReposUseRepoCache"
  ];
in
stdenv.mkDerivation (
  removeAttrs args builderArgs
  // {
    inherit pname version src;

    nativeBuildInputs = nativeBuildInputs ++ [
      bazel
      jdk
    ];

    # No network
    buildPhase = ''
      runHook preBuild

      ${ctx.env}
      ${caches.setup buildMounts}

      ${ctx.run {
        cmd = "build";
        inherit targets;
        flags = [
          "--lockfile_mode=error"
          "--repository_disable_download"
        ];
        mounts = buildMounts;
      }}

      ${ctx.shutdown ""}

      runHook postBuild
    '';

    inherit installPhase;

    passthru = passthru // {
      inherit repoCache;

      vendor = vendorDir;
      update = updater {
        inherit
          ctx
          caches
          pname
          targets
          lockPath
          ;
        flags = [
          "--nobuild"
          "--repository_cache="
          "--lockfile_mode=update"
          "--experimental_convenience_symlinks=ignore"
        ];
        mounts = updateMounts;
      };
    };
  }
)
