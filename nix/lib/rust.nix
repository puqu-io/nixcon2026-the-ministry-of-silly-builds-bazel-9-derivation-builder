{ rust-bin, makeRustPlatform, ... }:
let
  bin = rust-bin.stable.latest.default.override {
    extensions = [
      "cargo"
      "clippy"
      "rustfmt"
      "rust-analyzer"
      "rust-docs"
      "rust-src"
    ];
    targets = [ "x86_64-unknown-linux-musl" ];
  };
  platform = makeRustPlatform {
    cargo = bin;
    rustc = bin;
  };
in
{
  inherit bin platform;
}
