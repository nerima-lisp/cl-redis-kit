{
  description = "Binary-safe Redis RESP2/RESP3 client for Common Lisp";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    cl-nix-forge = {
      url = "github:nerima-lisp/cl-nix-forge/v0.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    paredit-cli = {
      url = "github:takeokunn/paredit-cli/v1.5.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cl-codec-kit = {
      url = "github:nerima-lisp/cl-codec-kit/v0.5.0";
      flake = false;
    };
    cl-concurrent-kit = {
      url = "github:nerima-lisp/cl-concurrent-kit/v0.6.1";
      flake = false;
    };
    cl-date-kit = {
      url = "github:nerima-lisp/cl-date-kit/v1.0.0";
      flake = false;
    };
    cl-boundary-kit = {
      url = "github:nerima-lisp/cl-boundary-kit/v2.3.0";
      flake = false;
    };
    cl-host-kit = {
      url = "github:nerima-lisp/cl-host-kit/v0.3.1";
      flake = false;
    };
    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.3.0";
      flake = false;
    };

    # No release tag is published yet; pin the reviewed upstream commit so
    # dependency resolution remains reproducible.
    cl-observability-kit = {
      url = "github:nerima-lisp/cl-observability-kit/3af5d47d7bc1178f2bf47027c91acbd8f9468351";
      flake = false;
    };

  };

  outputs =
    {
      self,
      nixpkgs,
      cl-nix-forge,
      treefmt-nix,
      paredit-cli,
      cl-codec-kit,
      cl-concurrent-kit,
      cl-date-kit,
      cl-boundary-kit,
      cl-host-kit,
      cl-weave,
      cl-observability-kit,
    }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      testTimeout = 900;
    in
    cl-nix-forge.lib.${builtins.head systems}.mkPackageFlake {
      inherit self systems nixpkgs;
      pname = "cl-redis-kit";
      asd = ./cl-redis-kit.asd;
      root = ./.;

      meta = {
        description = "A binary-safe Redis RESP2/RESP3 client for Common Lisp.";
        homepage = "https://github.com/nerima-lisp/cl-redis-kit";
        license = lib.licenses.mit;
      };

      lispDependencies = ctx:
        let
          host = ctx.cl.lispDerivation {
            lispSystem = "cl-host-kit";
            version = ctx.fromAsdSystem (cl-host-kit + "/cl-host-kit.asd");
            src = cl-host-kit;
          };
          codec = ctx.cl.lispDerivation {
            lispSystem = "cl-codec-kit";
            version = ctx.fromAsdSystem (cl-codec-kit + "/cl-codec-kit.asd");
            src = cl-codec-kit;
          };
          date = ctx.cl.lispDerivation {
            lispSystem = "cl-date-kit";
            version = ctx.fromAsdSystem (cl-date-kit + "/cl-date-kit.asd");
            src = cl-date-kit;
          };
          boundary = ctx.cl.lispDerivation {
            lispSystem = "cl-boundary-kit";
            version = ctx.fromAsdSystem (cl-boundary-kit + "/cl-boundary-kit.asd");
            src = cl-boundary-kit;
            lispDependencies = [ host ];
          };
          concurrent = ctx.cl.lispDerivation {
            lispSystem = "cl-concurrent-kit";
            version = ctx.fromAsdSystem (cl-concurrent-kit + "/cl-concurrent-kit.asd");
            src = cl-concurrent-kit;
            lispDependencies = [ boundary date ];
          };
          observability = ctx.cl.lispDerivation {
            lispSystem = "cl-observability-kit";
            version = ctx.fromAsdSystem (cl-observability-kit + "/cl-observability-kit.asd");
            src = cl-observability-kit;
            lispDependencies = [ concurrent ];
          };
          splitSequence = ctx.cl.fromNixpkgsLisp {
            drv = ctx.pkgs.sbclPackages.split-sequence;
            lispImplementation = "sbcl";
          };
          usocket = ctx.cl.fromNixpkgsLisp {
            drv = ctx.pkgs.sbclPackages.usocket;
            lispImplementation = "sbcl";
          };
          ssl = ctx.cl.fromNixpkgsLisp {
            drv = ctx.pkgs.sbclPackages.cl_plus_ssl;
            lispImplementation = "sbcl";
          };
          alexandria = ctx.cl.fromNixpkgsLisp {
            drv = ctx.pkgs.sbclPackages.alexandria;
            lispImplementation = "sbcl";
          };
          babel = ctx.cl.fromNixpkgsLisp {
            drv = ctx.pkgs.sbclPackages.babel;
            lispImplementation = "sbcl";
          };
          bordeauxThreads = ctx.cl.fromNixpkgsLisp {
            drv = ctx.pkgs.sbclPackages.bordeaux-threads;
            lispImplementation = "sbcl";
          };
          cffi = ctx.cl.fromNixpkgsLisp {
            drv = ctx.pkgs.sbclPackages.cffi;
            lispImplementation = "sbcl";
          };
          flexiStreams = ctx.cl.fromNixpkgsLisp {
            drv = ctx.pkgs.sbclPackages.flexi-streams;
            lispImplementation = "sbcl";
          };
          globalVars = ctx.cl.fromNixpkgsLisp {
            drv = ctx.pkgs.sbclPackages.global-vars;
            lispImplementation = "sbcl";
          };
          trivialFeatures = ctx.cl.fromNixpkgsLisp {
            drv = ctx.pkgs.sbclPackages.trivial-features;
            lispImplementation = "sbcl";
          };
          trivialGarbage = ctx.cl.fromNixpkgsLisp {
            drv = ctx.pkgs.sbclPackages.trivial-garbage;
            lispImplementation = "sbcl";
          };
          trivialGrayStreams = ctx.cl.fromNixpkgsLisp {
            drv = ctx.pkgs.sbclPackages.trivial-gray-streams;
            lispImplementation = "sbcl";
          };
        in
        [
          host
          codec
          date
          boundary
          concurrent
          observability
          splitSequence
          usocket
          ssl
          alexandria
          babel
          bordeauxThreads
          cffi
          flexiStreams
          globalVars
          trivialFeatures
          trivialGarbage
          trivialGrayStreams
        ];

      lispCheckDependencies = ctx: [
        (ctx.cl.lispDerivation {
          lispSystem = "cl-weave";
          version = ctx.fromAsdSystem (cl-weave + "/cl-weave.asd");
          src = cl-weave;
        })
      ];

      timeoutSeconds = testTimeout;
      treefmt.evalModule = treefmt-nix.lib.evalModule;

      devShellPackages = ctx: [
        paredit-cli.packages.${ctx.system}.default
      ];

      extraOutputs = ctx: {
        packages.coverage = ctx.cl.mkCoverageReport {
          drv = ctx.package.enableCheck;
          systems = [ "cl-redis-kit" ];
          timeoutSeconds = testTimeout;
        };
        checks.paredit-lint = paredit-cli.lib.${ctx.system}.mkLintCheck {
          inherit (ctx) src;
          name = "cl-redis-kit-paredit-lint";
        };
      };
    };
}
