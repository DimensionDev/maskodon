{
  description = "A Nix-flake-based Ruby development environment";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/2e7b72c52f89a7b66130fd81a3b31250596cbacd";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forEachSupportedSystem = f: nixpkgs.lib.genAttrs supportedSystems (system: f {
        pkgs = import nixpkgs { inherit system; };
      });
    in
    {
      devShells = forEachSupportedSystem ({ pkgs }: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            ruby_3_0
            bundler
            postgresql

            icu
            libidn
            zlib
            openssl

            nodejs_20
            yarn
          ];
        };
      });
    };
}
