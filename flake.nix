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
      systems = [ "x86_64-linux" ];
      forAllSystems =
        f: nixpkgs.lib.genAttrs systems (system:
          let
            overlays = [
              (import rust-overlay)
              (final: prev: {
                custom_rust = final.callPackage ./nix/lib/rust.nix {};
              })
            ];
            pkgs = import nixpkgs {
              inherit system overlays;
            };
          in
            f pkgs
        );
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          bazel = pkgs.callPackage ./nix/packages/bazel.nix {
            jdk = pkgs.jdk25_headless;
          };

          bzlmod_parser_poc = pkgs.callPackage ./bzlmod_parser_poc/default.nix {};

          fetchrec = pkgs.callPackage ./nix/packages/fetchrec {
            jdk = pkgs.jdk25_headless;
          };

          mkBazelPackageWith =
            let
              cacheLib = pkgs.callPackage ./nix/lib/cacheLib.nix { };

              mkBazelPackage = pkgs.callPackage ./nix/lib/mkBazelPackage.nix {
                inherit cacheLib bazel;
                jdk = pkgs.jdk25_headless;
              };
              fetchrec_updater = pkgs.callPackage ./nix/lib/fetchrecUpdater.nix {
                inherit fetchrec;
              };
              dummy_updater = pkgs.callPackage ./nix/lib/dummyUpdater.nix { };
            in
            {
              fetchrec = mkBazelPackage fetchrec_updater;
              dummy = mkBazelPackage dummy_updater;
            };

          bazelPackageAttrs = {
            bazelFlags = [ ];
            pname = "hello";
            version = "0.1.0";
            src = ./.;

            # Produced by `nix run .#update`, committed alongside MODULE.bazel
            # and MODULE.bazel.lock.
            lockFile = ./fetches.jsonl;

            targets = [
              "//examples/..."
            ];

            installPhase = ''
              runHook preInstall
              install -Dm755 bazel-bin/examples/c/hello "$out/bin/hello_c"
              runHook postInstall
            '';

            # Repositories that fetch by shelling out never reach the
            # downloader, so they cannot be locked as artifacts. Capture each
            # one as its own derivation and pin it here; `pin()` in the
            # generated VENDOR.bazel tells Bazel to treat the tree as an
            # override and not re-run the rule.
            #
            # opaqueRepos = {
            #   "com_example_thing+" = pkgs.fetchgit {
            #     url = "https://github.com/example/thing";
            #     rev = "abc123...";
            #     hash = "sha256-...";
            #   };
            # };
            opaqueRepos = {
              "gazelle++go_deps+org_golang_x_tools_go_vcs" = builtins.path {
                path = ./vendor_src/gazelle++go_deps+org_golang_x_tools_go_vcs;
                name = "gazelle++go_deps+org_golang_x_tools_go_vcr";
              };
              "gazelle++go_deps+org_golang_x_mod" = builtins.path {
                path = ./vendor_src/gazelle++go_deps+org_golang_x_mod;
                name = "gazelle++go_deps+org_golang_x_mod";
              };
              "gazelle++go_deps+com_github_pmezard_go_difflib" = builtins.path {
                path = ./vendor_src/gazelle++go_deps+com_github_pmezard_go_difflib;
                name = "gazelle++go_deps+com_github_pmezard_go_difflib";
              };
              "gazelle++go_deps+com_github_bazelbuild_buildtools" = builtins.path {
                path = ./vendor_src/gazelle++go_deps+com_github_bazelbuild_buildtools;
                name = "gazelle++go_deps+com_github_bazelbuild_buildtools";
              };
              "gazelle++go_deps+org_golang_x_sys" = builtins.path {
                path = ./vendor_src/gazelle++go_deps+org_golang_x_sys;
                name = "gazelle++go_deps+org_golang_x_sys";
              };
              "gazelle++go_deps+org_golang_x_sync" = builtins.path {
                path = ./vendor_src/gazelle++go_deps+org_golang_x_sync;
                name = "gazelle++go_deps+org_golang_x_sync";
              };
              "gazelle++go_deps+org_golang_x_net" = builtins.path {
                path = ./vendor_src/gazelle++go_deps+org_golang_x_net;
                name = "gazelle++go_deps+org_golang_x_net";
              };
              "gazelle++go_deps+org_golang_x_tools" = builtins.path {
                path = ./vendor_src/gazelle++go_deps+org_golang_x_tools;
                name = "gazelle++go_deps+org_golang_x_tools";
              };
              "gazelle++go_deps+com_github_bmatcuk_doublestar_v4" = builtins.path {
                path = ./vendor_src/gazelle++go_deps+com_github_bmatcuk_doublestar_v4;
                name = "gazelle++go_deps+com_github_bmatcuk_doublestar_v4";
              };
            };
          };

          helloWith = {
            dummy = mkBazelPackageWith.dummy bazelPackageAttrs;
            fetchrec = mkBazelPackageWith.fetchrec bazelPackageAttrs;
          };
        in
        {
          inherit helloWith bazel fetchrec bzlmod_parser_poc;
          default = helloWith.dummy;
        }
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            self.packages.${pkgs.system}.bazel
            self.packages.${pkgs.system}.fetchrec
            pkgs.jdk25_headless
            pkgs.git
            pkgs.helix
            pkgs.nixfmt
            pkgs.custom_rust.bin
          ];
        };
      });
    };
}
