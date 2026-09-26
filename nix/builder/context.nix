{
  lib,
  bazel,
  jdk,
  bazelFlags ? [ ],
  javaRuntime ? "remotejdk_25",
}:

rec {
  inherit bazel jdk;

  _startupFlags = [ ];

  commonFlags = [
    "--java_runtime_version=${javaRuntime}"
    "--tool_java_runtime_version=${javaRuntime}"
    "--lockfile_mode=error"
    "--remote_timeout=3600"
    "--curses=no"
    "--spawn_strategy=local"
    "--distdir="
  ]
  ++ bazelFlags;

  env = ''
    export HOME="$TMPDIR/home"
    export USER="''${USER:-nixbld}"
    export JAVA_HOME="${jdk}"
    mkdir -p "$HOME"
  '';

  # render bazel command line
  #   cmd          - "build", "vendor"
  #   targets      - targets to build
  #   flags        - build flags
  #   mounts       - cache mounts from caches.nix
  #   startupFlags - startup flags
  run =
    {
      cmd,
      targets ? [ ],
      flags ? [ ],
      mounts ? [ ],
      startupFlags ? [ ],
    }:
    lib.concatStringsSep " " (
      builtins.filter (s: s != "") [
        "bazel"
        (lib.concatStringsSep " " (_startupFlags ++ startupFlags))
        cmd
        (lib.escapeShellArgs targets)
        (lib.escapeShellArgs (flags ++ commonFlags))
        (lib.concatMapStringsSep " " (m: m.flag) mounts) # TODO move to caches
      ]
    );

  # startup flags must match the ones the server was started with
  shutdown =
    startupFlags:
    "bazel ${(lib.concatStringsSep " " (_startupFlags ++ startupFlags))} shutdown";
}
