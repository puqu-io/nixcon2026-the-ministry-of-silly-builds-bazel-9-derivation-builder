{
  lib,
  bzlmod_parser_poc,
}:

{ ... }:

{
  script = ''
    mkdir -p "$TMPDIR/bzlmod-parser"

    ${lib.getExe' bzlmod_parser_poc "bzlmod_parser_poc"} \
      --bzl-module-file "$PWD/MODULE.bazel" \
      --bzl-module-lockfile "$PWD/MODULE.bazel.lock" \
      --starlark-defs "${bzlmod_parser_poc.starlark_defs}" \
      --tmp-dir "$TMPDIR/bzlmod-parser" \
      --output "$lockOut"
  '';
}
