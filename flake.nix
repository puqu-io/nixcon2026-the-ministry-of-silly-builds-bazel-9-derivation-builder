{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
    }:
    let
      system = "x86_64-linux";
      inherit (nixpkgs) lib;

      pkgs = import nixpkgs {
        inherit system;
        overlays = [ self.overlays.default ];
      };
    in
    {
      overlays = {
        #   overlays = [ bazel-builder.overlays.default ];
        default = lib.composeManyExtensions [
          rust-overlay.overlays.default
          self.overlays.rust
          (import ./nix/overlay.nix)
        ];

        rust = final: _prev: {
          custom_rust = final.callPackage ./nix/dev/rust.nix { };
        };
      };

      packages.${system} = {
        inherit (pkgs) fetchrec bzlmod_parser_poc;
        bazel = pkgs.bazel_prebuilt;
        default = pkgs.bazel_prebuilt;
      };

      devShells.${system}.default = pkgs.mkShell {
        TYPST_FONT_PATHS = "${pkgs.jetbrains-mono}/share/fonts/truetype";
        packages = [
          pkgs.bazel_prebuilt
          pkgs.fetchrec
          pkgs.jdk25_headless
          pkgs.git
          pkgs.helix
          pkgs.nixfmt
          pkgs.typst
          pkgs.custom_rust.bin
        ];
      };
    };
}
