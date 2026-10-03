{
  description = "Common Lisp toolkit for parsing and emitting TOML";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    cl-nix-forge = {
      url = "github:nerima-lisp/cl-nix-forge/v0.6.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cl-parser-kit = {
      url = "github:nerima-lisp/cl-parser-kit/v1.1.1";
      flake = false;
    };

    cl-date-kit = {
      url = "github:nerima-lisp/cl-date-kit/v1.1.1";
      flake = false;
    };

    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.3.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cl-json-kit = {
      url = "github:nerima-lisp/cl-json-kit/v1.2.0";
      flake = false;
    };

    paredit-cli = {
      url = "github:nerima-lisp/paredit-cli/v1.6.3";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      cl-nix-forge,
      cl-parser-kit,
      cl-date-kit,
      cl-weave,
      cl-json-kit,
      paredit-cli,
      treefmt-nix,
    }:
    let
      systems = [
        "x86_64-linux"
      ];
    in
    cl-nix-forge.lib.${builtins.head systems}.mkPackageFlake {
      inherit self systems nixpkgs;
      pname = "cl-toml-kit";
      asd = ./cl-toml-kit.asd;
      root = ./.;
      sourceInclude = [ ./t/fixtures ];

      meta = {
        description = "Common Lisp toolkit for parsing and emitting TOML";
        homepage = "https://github.com/nerima-lisp/cl-toml-kit";
        license = nixpkgs.lib.licenses.mit;
      };

      lispDependencies = ctx: [
        (ctx.cl.lispDerivation {
          pname = "cl-parser-kit";
          version = ctx.cl.fromAsdSystem "${cl-parser-kit}/cl-parser-kit.asd";
          src = cl-parser-kit;
          lispSystem = "cl-parser-kit";
        })
        (ctx.cl.lispDerivation {
          pname = "cl-date-kit";
          version = ctx.cl.fromAsdSystem "${cl-date-kit}/cl-date-kit.asd";
          src = cl-date-kit;
          lispSystem = "cl-date-kit";
        })
      ];
      lispCheckDependencies = ctx: [
        cl-weave.packages.${ctx.system}.cl-weave
        (ctx.cl.lispDerivation {
          pname = "cl-json-kit";
          version = ctx.cl.fromAsdSystem "${cl-json-kit}/cl-json-kit.asd";
          src = cl-json-kit;
          lispSystem = "cl-json-kit";
        })
      ];

      # Allow the full 1006-case suite to finish after the Nix build phase.
      timeoutSeconds = 600;
      killAfterSeconds = 30;
      docs.root = ./docs;

      devShellPackages = ctx: [
        ctx.pkgs.sbcl
        paredit-cli.packages.${ctx.system}.default
      ];
      treefmt.evalModule = treefmt-nix.lib.evalModule;

      extraOutputs = ctx: {
        checks.paredit-lint = paredit-cli.lib.${ctx.system}.mkLintCheck {
          src = ./.;
          name = "cl-toml-kit-paredit-lint";
        };
      };
    };
}
