{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    bazel-builder = {
      url = "path:../..";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      bazel-builder,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ bazel-builder.overlays.default ];
      };

      example = pkgs.mkBazelPackage {
        pname = "example";
        version = "1.0.0";
        src = ./.;
        lockFile = ./fetches.jsonl;
        updater = pkgs.bazelUpdaters.bzlmodParser;
        targets = [ "//:hello" ];
        installPhase = ''
          install -Dm755 bazel-bin/hello $out/bin/hello
        '';
      };
    in
    {
      packages.${system}.default = example;

      apps.${system}.update = {
        type = "app";
        program = pkgs.lib.getExe example.update;
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.bazel_prebuilt ];
      };
    };
}
