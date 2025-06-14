#
# default.nix - Simplified sysroot creation for Bazel C/C++ builds
#

{ pkgs ? import <nixpkgs> {} }:

let
  llvm = pkgs.llvmPackages_20;

  commonLibs = with pkgs; [
    # Core C system libraries (glibc is standard on Linux, Clang uses it)
    glibc glibc.dev glibc.static

    # GCC runtime libraries (needed for libgcc_s)
    gcc gcc.cc gcc.cc.lib

    # LLVM C++ Standard Library, compiler runtime, and unwind library
    llvm.libcxx          # Provides libc++.so, libc++.a (libraries)
    llvm.libcxx.dev      # Provides C++ headers
    llvm.compiler-rt     # Provides libclang_rt.builtins*.a
    llvm.compiler-rt.dev # Provides libclang_rt headers
    llvm.libunwind       # Provides libunwind for exception handling
    llvm.libunwind.dev   # Provides libunwind headers

    # Compression libraries (compiler-agnostic)
    zlib zlib.dev zlib.static
    bzip2 bzip2.dev
    xz xz.dev
    zstd zstd.dev

    # XML and parsing (compiler-agnostic)
    libxml2 libxml2.dev libxml2.out
    expat expat.dev expat.out

    # Networking (compiler-agnostic)
    openssl openssl.dev openssl.out
    curl curl.dev curl.out

    # Text processing (compiler-agnostic)
    pcre pcre.dev pcre.out
    pcre2 pcre2.dev pcre2.out

    # JSON (compiler-agnostic)
    jansson jansson.dev jansson.out

    # Database (compiler-agnostic)
    sqlite sqlite.dev sqlite.out

    # Image processing (compiler-agnostic)
    libpng libpng.dev libpng.out
    libjpeg libjpeg.dev libjpeg.out

    # System utilities
    util-linux util-linux.dev util-linux.out
  ];

in
pkgs.stdenv.mkDerivation {
  name = "bazel-sysroot-library-and-libs-amd64";
  version = "1.0.0";
  src = ./.;

  # buildInputs are for runtime dependencies of the *output*
  # nativeBuildInputs are for build-time tools
  nativeBuildInputs = [ pkgs.rsync ]; # Add rsync here
  buildInputs = commonLibs; # Makes commonLibs' paths available

  buildCommand = ''
    # Exit immediately on error, print commands, fail on unset variables, fail on pipe errors
    #set -euxo pipefail

    mkdir -p "$out/sysroot/include"
    mkdir -p "$out/sysroot/lib"

    echo "Copying files from commonLibs to sysroot..."

    ${pkgs.lib.concatMapStringsSep "\n" (pkg: ''
      if [ -d "${pkg}/include" ]; then # Check if the package has an include directory
        echo "Copying include files from (generic) ${pkg} to $out/sysroot/include/"
        # rsync -rL is like cp -RL (recursive, dereference symlinks)
        # --no-perms, --no-owner, --no-group aim to mimic cp --no-preserve=mode,ownership.
        rsync -rL --no-perms --no-owner --no-group "${pkg}/include/" "$out/sysroot/include/" || true
      else
        echo "Info: Package ${pkg} does not have an /include directory, skipping include copy."
      fi

      if [ -d "${pkg}/lib" ]; then
        echo "Copying lib files from ${pkg} to $out/sysroot/lib/ (excluding .pc, .la, pkgconfig/, cmake/)"
        # Explicitly using -rL and --no-perms, --no-owner, --no-group.
        rsync -rL --no-perms --no-owner --no-group \
          --exclude='*.pc' \
          --exclude='*.la' \
          --exclude='pkgconfig/' \
          --exclude='cmake/' \
          "${pkg}/lib/" "$out/sysroot/lib/" || true
      else
        echo "Info: Package ${pkg} does not have a /lib directory, skipping lib copy."
      fi
    '') commonLibs}

    echo "Finished copying files from commonLibs."

    echo ""
    echo "Sysroot successfully created at: $out/sysroot"
  '';

  meta = with pkgs.lib; {
    description = "Simplified libraries and headers for Bazel C/C++ builds";
    homepage = "https://github.com/randomizedcoder/bazel_sysroot_library_and_libs_amd64";
    license = licenses.mit;
  };
}
