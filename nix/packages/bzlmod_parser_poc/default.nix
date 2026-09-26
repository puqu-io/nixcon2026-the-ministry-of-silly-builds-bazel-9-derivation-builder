{ custom_rust, ... }:
let
  cargo-toml = builtins.path {
    path = ./Cargo.toml;
    name = "bzlmod_parser_poc_cargo";
  };
  cargo-lock = builtins.path {
    path = ./Cargo.lock;
    name = "bzlmod_parser_poc_lock";
  };
  bazelrisk-src = builtins.path {
    path = ./.;
    name = "bzlmod_parser_poc_src";
    filter = path: _type: builtins.match ".*starlark_defs.*" path == null;
  };
  version = (builtins.fromTOML (builtins.readFile cargo-toml)).package.version;
in
custom_rust.platform.buildRustPackage {
  pname = "bzlmod_parser_poc";
  inherit version;

  cargoLock = {
    lockFile = cargo-lock;
  };

  src = bazelrisk-src;

  meta = {
    description = "To be described";
    homepage = "https://github.com/puqu-io/nixcon2026-the-ministry-of-silly-builds-bazel-9-derivation-builder";
  };

  passthru.starlark_defs = builtins.path {
    path = ./starlark_defs;
    name = "bzlmod_parser_poc_starlark_defs";
  };
}
