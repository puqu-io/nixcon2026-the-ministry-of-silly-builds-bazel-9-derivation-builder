{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    bazel-builder = {
      url = "path:../../";
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

      example_java = pkgs.mkBazelPackage {
        pname = "example_java";
        version = "1.0.0";
        src = ./.;
        #lockFile = ./fetches.jsonl;
        lockHash = "sha256-0b+R7zYt+fAI5ZEd5YMR+zoaivYzISSZTHXUSw2t/V4=";
        updater = pkgs.bazelUpdaters.fetchrec;
        targets = [ "//:hello" ];
        installPhase = ''
          install -Dm755 bazel-bin/hello $out/bin/hello
        '';
      };
    in
    {
      packages.${system} = {
        default = example_java;
        inherit (example_java) lock repoCache;
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [ pkgs.bazel_prebuilt ];
      };
    };
}
