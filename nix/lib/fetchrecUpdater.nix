{
  lib,
  stdenv,
  fetchrec,
  writeShellApplication,
}:

{
  bazel,
  jdk,
  bazelEnv,
  pname,
  targets,
  commonFlags,
  updateFlags,
  updateCacheFlags,
  startupFlags,
  cacheLib,
  vendorDir,
  hasVendorRepos,
}:

let
  # Recording always goes through the shim: it is the only thing that can
  # watch a fetch happen and write it down.
  proxyFlags = lib.concatStringsSep " " [
      ''--host_jvm_args=-javaagent:${fetchrec}/fetchrec.jar="$(pwd)/fetches.jsonl"''
  ];
in
writeShellApplication {
  name = "update-${pname}-lock";
  runtimeInputs = [
    bazel
    jdk
    fetchrec
  ];
  text = ''
    set -euo pipefail

    workdir="$(mktemp -d)"
    trap 'bazel ${startupFlags} ${proxyFlags} shutdown && chmod -R +w "$workdir" && rm -rf "$workdir"' EXIT
    
    export TMPDIR="$workdir"

    ${bazelEnv}
    ${lib.optionalString hasVendorRepos (cacheLib.vendorDirSetupHook vendorDir)}

    bazel \
      ${startupFlags} \
      ${proxyFlags} \
      build ${lib.escapeShellArgs targets} \
      ${lib.escapeShellArgs (updateFlags ++ commonFlags)} \
      ${updateCacheFlags}

  '';
}
