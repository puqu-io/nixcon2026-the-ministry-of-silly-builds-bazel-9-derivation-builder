{ fetchrec }:

{
  ctx,
  caches,
  targets,
  flags,
  mounts,
}:

let
  # watch a fetch happen and write it down
  agentFlags = ''--host_jvm_args=-javaagent:${fetchrec}/fetchrec.jar="$lockOut"'';
in
{
  nativeBuildInputs = [
    ctx.bazel
    ctx.jdk
  ];

  script = ''
    ${ctx.env}
    ${caches.setup mounts}

    ${ctx.run {
      cmd = "build";
      inherit flags mounts targets;
      extraStartup = agentFlags;
    }}

    # stop the server so the agent flushes the log before it is read
    ${ctx.shutdown agentFlags}
  '';
}
