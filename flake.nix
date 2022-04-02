{
  description = "A thorough example of a featureful REST API in Axum";

  inputs = {
    crane.url = "github:ipetkov/crane";
    crane.inputs.flake-compat.follows = "flake-compat";
    crane.inputs.nixpkgs.follows = "nixpkgs";
    crane.inputs.utils.follows = "flake-utils";
    flake-compat.url = "github:edolstra/flake-compat";
    flake-compat.flake = false;
    flake-utils.url = "github:numtide/flake-utils";
    master.url = "nixpkgs/master";
    nixpkgs.url = "nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.flake-utils.follows = "flake-utils";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, flake-utils, nixpkgs, ... }:
    flake-utils.lib.eachSystem [ "x86_64-darwin" "x86_64-linux" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;

          overlays = [
            (import inputs.rust-overlay)
            (final: prev: { master = inputs.master.legacyPackages.${system}; })
          ];
        };

        sharedInputs = with pkgs;
          [
            cargo-asm
            cargo-audit
            cargo-bloat
            cargo-cache
            cargo-deny
            cargo-edit
            cargo-expand
            cargo-flamegraph
            cargo-generate
            cargo-geiger
            cargo-make
            cargo-release
            cargo-sweep
            cargo-udeps
            cargo-watch
            cargo-whatfeatures
            clang
            git-cliff
            just
            lld
            mdbook
            openssl.dev
            pkg-config
            zlib.dev
          ] ++ (with self.packages."${system}"; [
            cargo-outdated
            rust-analyzer
            sccache
            sqlx-cli
          ]) ++ lib.optionals (stdenv.isDarwin)
          (with pkgs.darwin.apple_sdk.frameworks; [
            CoreServices
            Security
            SystemConfiguration
          ]) ++ lib.optionals (stdenv.isLinux) [
            cargo-tarpaulin
            perf-tools
            strace
            valgrind
          ];

        rustChannel =
          pkgs.lib.removeSuffix "\n" (builtins.readFile ./rust-toolchain);

        rustTools = pkgs.rust-bin.stable.${rustChannel};

        src = ./.;

        craneLib = (inputs.crane.mkLib pkgs).overrideScope' (final: prev: {
          rustc = rustTools.default;
          cargo = rustTools.default;
          rustfmt = rustTools.default;
        });

        cargoArtifacts = craneLib.buildDepsOnly { inherit src; };

        axum-rest-example = craneLib.buildPackage {
          inherit cargoArtifacts src;
          nativeBuildInputs = with pkgs; [ clang lld ];
        };

        axum-rest-example-clippy = craneLib.cargoClippy {
          inherit cargoArtifacts src;
          # nativeBuildInputs = with pkgs; [ clang lld ];
        };

        app = flake-utils.lib.mkApp {
          drv = self.packages."${system}".axum-rest-example;
        };
      in {
        defaultApp = app;
        apps.axum-rest-example = app;

        checks = { inherit axum-rest-example axum-rest-example-clippy; };

        devShell = pkgs.mkShell {
          name = "axum-rest-example-nightly";
          nativeBuildInputs = [ rustTools.default ] ++ sharedInputs;

          NIX_PATH = "nixpkgs=${nixpkgs}:master=${inputs.master}";
          RUST_SRC_PATH = "${rustTools.rust-src}/lib/rustlib/src/rust/library";
        };

        devShells.nightly = pkgs.mkShell {
          nativeBuildInputs = [ pkgs.rust-bin.nightly.latest.default ]
            ++ sharedInputs;
          RUSTFLAGS = "-Z macro-backtrace";
        };

        defaultPackage = axum-rest-example;
        packages = {
          inherit (pkgs.master) rust-analyzer sqlx-cli;
          inherit (pkgs) sccache;

          cargo-outdated = pkgs.symlinkJoin {
            name = "cargo-outdated";
            paths = [ pkgs.cargo-outdated ];
            buildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram $out/bin/cargo-outdated \
                --unset RUST_LOG
            '';
          };

          clippy = pkgs.symlinkJoin {
            name = "clippy";
            paths = [ pkgs.clang rustTools.clippy pkgs.lld ];
            buildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram $out/bin/cargo-clippy \
                --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.clang pkgs.lld ]}
            '';
          };

          # Uncomment to build Docker image without using a Docker daemon
          # docker = pkgs.dockerTools.streamLayeredImage {
          #   name = "my_app";
          #   tag = "latest";
          #   contents = with self.packages.x86_64-linux; [
          #     my_app_web
          #     my_app_cli
          #   ];
          #   config = {
          #     Cmd =
          #       [ "${self.packages.x86_64-linux.my_app_web}/bin/my_app_web" ];
          #     Env = [ "RUST_LOG=debug" ];
          #   };
          # };

          inherit axum-rest-example;

          gcroot = pkgs.linkFarmFromDrvs "axum-rest-example"
            (with self.outputs; [
              devShell."${system}".inputDerivation
              devShells."${system}".nightly.inputDerivation
            ]);
        };
      });
}
