{
  writeShellApplication,
  fetchrec,
}:

{
  ctx,
  caches,
  pname,
  targets,
  lockPath,
  flags,
  mounts,
}:

let
  # watch a fetch happen and write it down
  agentFlags = ''--host_jvm_args=-javaagent:${fetchrec}/fetchrec.jar="$repo/${lockPath}"'';
in
writeShellApplication {
  name = "update-${pname}-lock";
  runtimeInputs = [
    ctx.bazel
    ctx.jdk
    fetchrec
  ];
  text = ''
    repo="$(pwd)"
    workdir="$(mktemp -d)"

    cleanup() {
      ${ctx.shutdown agentFlags} || true
      chmod -R u+w "$workdir"
      rm -rf "$workdir"
    }
    trap cleanup EXIT

    export TMPDIR="$workdir"

    ${ctx.env}
    ${caches.setup mounts}

    ${ctx.run {
      cmd = "build";
      inherit flags mounts targets;
      extraStartup = agentFlags;
    }}
  '';
}
