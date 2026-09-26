{
  lib,
  writeShellApplication,
  bzlmod_parser_poc,
}:

{
  pname,
  lockPath,
  ...
}@args:
writeShellApplication {
  name = "update-${pname}-lock";
  text = ''
    set -euo pipefail

    #temp="$(mktemp -d)"

    ${bzlmod_parser_poc}/bin/bzlmod_parser_poc\
      --bzl-module-file "$(pwd)/MODULE.bazel"\
      --bzl-module-lockfile "$(pwd)/MODULE.bazel.lock"\
      --starlark-defs "$(pwd)/bzlmod_parser_poc/starlark_defs"\
      --tmp-dir "$(pwd)/tmp_out"\
      --output "$(pwd)/${lockPath}"
  '';
}
