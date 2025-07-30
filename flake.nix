{
  description = "Hyprshot Cloud - Upload hyprshot screenshots to S3";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      packages.hyprshot-cloud = pkgs.stdenv.mkDerivation {
        pname = "hyprshot-cloud";
        version = "0.1.0";
        
        src = ./.;
        
        nativeBuildInputs = with pkgs; [ zig pkg-config ];
        buildInputs = with pkgs; [ curl openssl ];
        
        # Set Zig cache directory to a writable location
        ZIG_GLOBAL_CACHE_DIR = "${placeholder "out"}/.cache/zig";
        ZIG_LOCAL_CACHE_DIR = "${placeholder "out"}/.cache/zig";
        
        buildPhase = ''
          mkdir -p $ZIG_GLOBAL_CACHE_DIR
          zig build -Doptimize=ReleaseSafe
        '';
        
        installPhase = ''
          mkdir -p $out/bin
          cp zig-out/bin/hyprshot-cloud $out/bin/
        '';
      };
      
      packages.default = self.packages.${system}.hyprshot-cloud;

      apps.hyprshot-cloud = flake-utils.lib.mkApp {
        drv = self.packages.${system}.hyprshot-cloud;
      };

      devShells.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          zig
          zls
          pkg-config
          curl
          openssl
        ];
        
        # For development, set cache directories
        ZIG_GLOBAL_CACHE_DIR = builtins.getEnv "HOME" + "/.cache/zig";
        ZIG_LOCAL_CACHE_DIR = builtins.getEnv "HOME" + "/.cache/zig";
      };
    });
}
