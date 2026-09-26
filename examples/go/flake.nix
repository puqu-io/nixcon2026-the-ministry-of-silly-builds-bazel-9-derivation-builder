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

      example = pkgs.mkBazelPackage {
        pname = "example";
        version = "1.0.0";
        src = ./.;
        lockFile = ./fetches.jsonl;
        updater = pkgs.bazelUpdaters.fetchrec;
        targets = [ "//:hello" ];
        installPhase = ''
          install -Dm755 bazel-bin/hello_/hello $out/bin/hello
        '';
        vendorRepos = [
          "gazelle++go_deps+org_golang_x_tools_go_vcs"
          "gazelle++go_deps+org_golang_x_mod"
          "gazelle++go_deps+com_github_pmezard_go_difflib"
          "gazelle++go_deps+com_github_bazelbuild_buildtools"
          "gazelle++go_deps+org_golang_x_sys"
          "gazelle++go_deps+org_golang_x_sync"
          "gazelle++go_deps+org_golang_x_tools"
          "gazelle++go_deps+com_github_google_uuid"
          "gazelle++go_deps+com_github_bmatcuk_doublestar_v4"
        ];
        vendorReposHash = "";
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
