{
  description = "ww - A CLI tool to make jj (Jujutsu) workspaces easier to manage";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0"; # stable Nixpkgs
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-unstable,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        pkgsUnstable = nixpkgs-unstable.legacyPackages.${system};

        # Version from build.zig.zon
        version = "0.0.0";
      in {
        packages = {
          default = self.packages.${system}.ww;

          ww = pkgs.stdenv.mkDerivation {
            pname = "ww";
            inherit version;

            src = ./.;

            nativeBuildInputs = [pkgs.zig];

            dontConfigure = true;
            dontInstall = true;

            buildPhase = ''
              runHook preBuild

              # Set Zig cache directories to writable locations
              export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-cache"
              export ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local-cache"
              mkdir -p "$ZIG_GLOBAL_CACHE_DIR" "$ZIG_LOCAL_CACHE_DIR"

              zig build \
                --release=safe \
                -Dversion="${version}" \
                --prefix "$out"

              runHook postBuild
            '';

            meta = with pkgs.lib; {
              description = "A CLI tool to make jj (Jujutsu) workspaces easier to manage";
              homepage = "https://github.com/omihirofumi/ww";
              license = licenses.mit;
              maintainers = [];
              mainProgram = "ww";
              platforms = platforms.unix;
            };
          };
        };

        devShells.default = pkgs.mkShellNoCC {
          name = "ww-dev";

          packages = [
            pkgs.zig
            pkgs.zls # Zig Language Server
            pkgs.lldb
            pkgs.alejandra
            pkgs.nixd
            pkgs.statix
            pkgsUnstable.jujutsu
          ];

          shellHook = ''
            echo "ww development shell"
            echo "  zig: $(zig version)"
            echo "  jj:  $(jj --version)"
          '';
        };
      }
    );
}
