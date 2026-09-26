{
  lib,
  bazel,
  jdk,
  bazelFlags ? [ ],
  javaRuntime ? "remotejdk_25",
}:

rec {
  inherit bazel jdk;

  startupFlags = ''--output_user_root="$TMPDIR/bazel-root"'';

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
  #   extraStartup - raw startup flags
  run =
    {
      cmd,
      targets ? [ ],
      flags ? [ ],
      mounts ? [ ],
      extraStartup ? "",
    }:
    lib.concatStringsSep " " (
      builtins.filter (s: s != "") [
        "bazel"
        startupFlags
        extraStartup
        cmd
        (lib.escapeShellArgs targets)
        (lib.escapeShellArgs (flags ++ commonFlags))
        (lib.concatMapStringsSep " " (m: m.flag) mounts) # TODO move to caches
      ]
    );

  # startup flags must match the ones the server was started with
  shutdown = extraStartup: "bazel ${startupFlags} ${extraStartup} shutdown";
}
