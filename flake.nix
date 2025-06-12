{
  description = "Bazel sysroot for common libraries";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        sysroot = pkgs.callPackage ./default.nix { };
      in
      {
        packages = {
          # The main sysroot package
          sysroot = sysroot;

          # A package that creates a tarball of the sysroot
          tarball = pkgs.stdenv.mkDerivation {
            name = "bazel-sysroot-library-tarball";
            version = "1.0.0";
            src = sysroot;

            buildCommand = ''
              mkdir -p $out
              cd $src
              tar -czf $out/bazel-sysroot-library.tar.gz sysroot/
            '';
          };
        };

        # Make the sysroot the default package
        defaultPackage = self.packages.${system}.sysroot;
      }
    );
}