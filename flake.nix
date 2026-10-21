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
      url = "github:nerima-lisp/cl-date-kit/v1.2.0";
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

      extraOutputs =
        ctx:
        let
          normalizeCoverageReport = ctx.pkgs.writeText "normalize-coverage-report.py" ''
            import hashlib
            import re
            import sys
            from pathlib import Path

            def fail(message):
                raise SystemExit("normalize coverage report: " + message)

            output = Path(sys.argv[1])
            index_path = output / "cover-index.html"
            if not output.is_dir() or not index_path.is_file():
                fail("report output or cover-index.html is missing")

            page_name = re.compile(r"[0-9a-f]{32}\.html\Z")
            heading = re.compile(
                rb"<h3>Coverage report: (?P<path>/[^<>\r\n]+/source/src/[^/<> \r\n]+\.lisp) <br\s*/>"
            )
            page_link = re.compile(
                rb"href=(?P<quote>[\x22\x27])(?P<name>[0-9a-f]{32}\.html)(?P=quote)"
            )
            pages = sorted(path for path in output.iterdir() if page_name.fullmatch(path.name))
            if not pages:
                fail("no hashed source report pages were found")

            rewrites = []
            source_directory = None
            new_names = set()
            for page in pages:
                contents = page.read_bytes()
                headings = list(heading.finditer(contents))
                if len(headings) != 1:
                    fail(page.name + " must contain exactly one source heading")
                source_path = headings[0].group("path")
                if source_path.count(b"/source/") != 1:
                    fail(page.name + " has an unexpected source path")
                relative_path = source_path.rsplit(b"/source/", 1)[1]
                if not re.fullmatch(rb"src/[^/]+\.lisp", relative_path):
                    fail(page.name + " is outside the expected src/ layout")
                current_directory = source_path.rsplit(b"/", 1)[0] + b"/"
                if source_directory is None:
                    source_directory = current_directory
                elif source_directory != current_directory:
                    fail("source report pages do not share one source directory")
                if page.name != hashlib.md5(source_path).hexdigest() + ".html":
                    fail(page.name + " does not match its source path hash")
                new_name = hashlib.md5(relative_path).hexdigest() + ".html"
                if new_name in new_names:
                    fail("two source report pages map to the same stable name")
                new_names.add(new_name)
                if contents.count(source_path) != 1:
                    fail(page.name + " must contain its absolute source path once")
                contents = contents.replace(source_path, relative_path, 1)
                rewrites.append(
                    (page, page.name, new_name, contents, page.stat().st_mode & 0o777)
                )

            index_contents = index_path.read_bytes()
            if source_directory is None or index_contents.count(source_directory) != 1:
                fail("cover-index.html must contain the source directory once")
            index_contents = index_contents.replace(source_directory, b"src/", 1)
            for _, old_name, new_name, _, _ in rewrites:
                link_pattern = re.compile(
                    rb"href=(?P<quote>[\x22\x27])"
                    + re.escape(old_name.encode("ascii"))
                    + rb"(?P=quote)"
                )
                if len(list(link_pattern.finditer(index_contents))) != 1:
                    fail("cover-index.html must link to " + old_name + " once")
                index_contents = link_pattern.sub(
                    lambda match: b"href=" + match.group("quote")
                    + new_name.encode("ascii") + match.group("quote"),
                    index_contents,
                    count=1,
                )

            linked_names = {
                match.group("name").decode("ascii")
                for match in page_link.finditer(index_contents)
            }
            if linked_names != new_names or len(list(page_link.finditer(index_contents))) != len(rewrites):
                fail("normalized report links do not match the source pages")
            if source_directory in index_contents or any(
                source_directory in contents for _, _, _, contents, _ in rewrites
            ):
                fail("an absolute source directory remains in the report")

            for page, _, _, _, _ in rewrites:
                page.unlink()
            for _, _, new_name, contents, mode in rewrites:
                new_page = output / new_name
                new_page.write_bytes(contents)
                new_page.chmod(mode)
            index_path.write_bytes(index_contents)
          '';
        in
        {
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
          # SB-COVER hashes absolute source pathnames into report page names.
          checks.coverage = (ctx.cl.mkCoverageReport {
            drv = ctx.package;
            systems = [ "cl-toml-kit" ];
            entryPoint = "scripts/run-coverage.lisp";
            timeoutSeconds = 900;
            killAfterSeconds = 30;
          }).overrideAttrs (old: {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ ctx.pkgs.python3 ];
            postInstall = (old.postInstall or "") + ''
              ${ctx.pkgs.python3}/bin/python3 ${normalizeCoverageReport} "$out"
            '';
          });
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
