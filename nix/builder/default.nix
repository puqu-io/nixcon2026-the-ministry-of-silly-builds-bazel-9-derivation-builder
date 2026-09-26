{
  lib,
  stdenv,
  callPackage,
  bazel,
  jdk,
}:

{
  pname,
  version,
  src,

  updater,
  lockFile ? null,
  lockHash ? "",

  targets ? [ "//..." ],

  bazelFlags ? [ ], # extra flags provided by user
  javaRuntime ? "remotejdk_25",

  vendorRepos ? [ ],
  vendorReposHash ? "",

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

  # the updater may only use the vendor directory once it has a real hash
  hasVendorRepos = vendorReposHash != "" || vendorRepos != [ ];

  lockFOD = callPackage ./lock-fod.nix { } {
    inherit
      pname
      src
      lockHash
      nativeBuildInputs
      ;
    updater = updater {
      inherit ctx caches targets;
      flags = [
        "--nobuild"
        "--repository_cache="
      ];
      mounts = lib.optional hasVendorRepos (caches.vendorMount vendorDir);
    };
  };

  effectiveLock = if lockFile != null then lockFile else lockFOD;
  repoCache = caches.mkRepoCache {
    lockFile = effectiveLock;
    name = "${pname}-repo-cache";
  };

  #TODO we cannot use lockfile hash because we would end up in a fod loop
  hasLockFile = lockFile != null;
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
    mounts = lib.optional hasLockFile (caches.repoCacheMount repoCache);
  };

  buildMounts = [
    (caches.repoCacheMount repoCache)
  ]
  ++ lib.optional hasVendorRepos (caches.vendorMount vendorDir);

  # builder-only arguments, everything else goes to mkDerivation
  builderArgs = [
    "lockFile"
    "updater"
    "lockHash"
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
        mounts = buildMounts;
      }}

      ${ctx.shutdown [ ]}

      runHook postBuild
    '';

    dontConfigure = true;
    dontFixup = true;

    passthru = passthru // {
      inherit repoCache;
      vendor = vendorDir;
      lock = lockFOD;
    };
  }
)
