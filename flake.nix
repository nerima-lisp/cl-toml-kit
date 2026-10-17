{
  description = "Common Lisp toolkit for parsing and emitting TOML";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    cl-nix-forge = {
      url = "github:nerima-lisp/cl-nix-forge/v0.6.1";
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

    cl-codec-kit = {
      url = "github:nerima-lisp/cl-codec-kit/v0.6.0";
      flake = false;
    };

    cl-weave = {
      url = "github:nerima-lisp/cl-weave/v1.4.0";
      flake = false;
    };

    cl-json-kit = {
      url = "github:nerima-lisp/cl-json-kit/v1.2.0";
      flake = false;
    };

    paredit-cli = {
      url = "github:nerima-lisp/paredit-cli/v1.7.1";
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
      cl-codec-kit,
      cl-weave,
      cl-json-kit,
      paredit-cli,
      treefmt-nix,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      # mkdocs and treefmt finish in seconds; 300 s stops a hung command
      # without failing a slow runner.
      timeLimit = command: "timeout --kill-after=30 300 ${command}";

      limitCommand =
        command: script:
        if nixpkgs.lib.hasInfix command script then
          builtins.replaceStrings [ command ] [ (timeLimit command) ] script
        else
          throw "cl-toml-kit: `${command}` is missing from a generated check, so its time limit would not apply";
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
        (ctx.cl.lispDerivation {
          pname = "cl-codec-kit";
          version = ctx.cl.fromAsdSystem "${cl-codec-kit}/cl-codec-kit.asd";
          src = cl-codec-kit;
          lispSystem = "cl-codec-kit";
        })
      ];
      lispCheckDependencies = ctx: [
        (ctx.cl.lispDerivation {
          pname = "cl-weave";
          version = ctx.cl.fromAsdSystem "${cl-weave}/cl-weave.asd";
          src = cl-weave;
          lispSystem = "cl-weave";
        })
        (ctx.cl.lispDerivation {
          pname = "cl-json-kit";
          version = ctx.cl.fromAsdSystem "${cl-json-kit}/cl-json-kit.asd";
          src = cl-json-kit;
          lispSystem = "cl-json-kit";
        })
      ];

      # Time limit for the test suite, including the toml-test corpus.
      timeoutSeconds = 600;
      killAfterSeconds = 30;
      docs.root = ./docs;

      devShellPackages = ctx: [
        ctx.pkgs.sbcl
        paredit-cli.packages.${ctx.system}.default
      ];
      treefmt.evalModule = treefmt-nix.lib.evalModule;

      extraOutputs = ctx: {
        checks.paredit-lint =
          ctx.pkgs.runCommand "cl-toml-kit-paredit-lint"
            {
              nativeBuildInputs = [
                ctx.pkgs.coreutils
                paredit-cli.packages.${ctx.system}.lint
              ];
            }
            ''
              ${timeLimit "paredit-lint ${./.}"}
              touch "$out"
            '';
        checks.coverage = ctx.cl.mkCoverageReport {
          drv = ctx.package;
          systems = [ "cl-toml-kit" ];
          entryPoint = "scripts/run-coverage.lisp";
          timeoutSeconds = 900;
          killAfterSeconds = 30;
        };
      };

      # mkPackageFlake generates the docs site and the formatting check without
      # a time limit. checks.docs reads the site through its `site` attribute,
      # so it is pointed at the time-limited site.
      overrideOutputs =
        ctx:
        let
          docsSite = ctx.generated.packages.docs.overrideAttrs (old: {
            buildPhase = limitCommand "mkdocs build" old.buildPhase;
          });
        in
        {
          packages.docs = docsSite;
          checks.docs = ctx.generated.checks.docs.overrideAttrs { site = docsSite; };
          checks.formatting = ctx.generated.checks.formatting.overrideAttrs (old: {
            buildCommand = limitCommand "treefmt --no-cache" old.buildCommand;
          });
        };
    };
}
