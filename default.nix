#
# default.nix - Simplified sysroot creation for Bazel C/C++ builds
#

{ pkgs ? import <nixpkgs> {} }:

let
  #llvm = pkgs.llvmPackages_20;

  commonLibs = with pkgs; [
    # Core C system libraries (glibc is standard on Linux, Clang uses it)
    glibc glibc.dev glibc.static

    # GCC runtime libraries, C++ Standard Library, and C++ headers
    gcc                  # Provides libgcc_s.so (from gcc.lib), and the gcc compiler itself
    gcc.cc               # Provides the g++ compiler toolchain
    gcc.cc.lib           # Provides libstdc++.so, libsupc++.a (GCC's C++ standard library)
    libgcc               # Provides C++ headers for libstdc++ (e.g. <vector>)

    # # LLVM C++ Standard Library, compiler runtime, and unwind library
    # llvm.libcxx          # Provides libc++.so, libc++.a (libraries)
    # llvm.libcxx.dev      # Provides C++ headers
    # llvm.compiler-rt     # Provides libclang_rt.builtins*.a
    # llvm.compiler-rt.dev # Provides libclang_rt headers
    # llvm.libunwind       # Provides libunwind for exception handling
    # llvm.libunwind.dev   # Provides libunwind headers

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

  # Helper function to create a linker script
  createLinkerScript = name: version: asNeeded: ''
    echo "Creating linker script for $name.so pointing to $name.$version"
    echo "/* GNU ld script */" > "$out/sysroot/lib/$name.so"
    echo "OUTPUT_FORMAT(elf64-x86-64)" >> "$out/sysroot/lib/$name.so"
    if [ -n "${asNeeded}" ]; then
      echo "GROUP ( $name.$version AS_NEEDED ( ${asNeeded} ) )" >> "$out/sysroot/lib/$name.so"
    else
      echo "GROUP ( $name.$version )" >> "$out/sysroot/lib/$name.so"
    fi
  '';

in
pkgs.stdenv.mkDerivation {
  name = "bazel-sysroot-library-and-libs-amd64";
  version = "1.0.0";
  src = ./.;

  # buildInputs are for runtime dependencies of the *output*
  # nativeBuildInputs are for build-time tools
  nativeBuildInputs = [ pkgs.rsync pkgs.patchelf pkgs.binutils ]; # Add binutils for readelf
  buildInputs = commonLibs; # Makes commonLibs' paths available

  buildCommand = ''
    # Exit immediately on error, print commands, fail on unset variables, fail on pipe errors
    set -euxo pipefail

    mkdir -p "$out/sysroot/include"
    mkdir -p "$out/sysroot/lib"

    echo "Copying files from commonLibs to sysroot..."

    ${pkgs.lib.concatMapStringsSep "\n" (pkg: ''
      if [ -d "${pkg}/include" ]; then # Check if the package has an include directory
        echo "Copying include files from (generic) ${pkg} to $out/sysroot/include/"
        # rsync -rL is like cp -RL (recursive, dereference symlinks)
        # --no-perms, --no-owner, --no-group aim to mimic cp --no-preserve=mode,ownership.
        rsync --recursive --copy-links --no-perms --no-owner --no-group \
          --verbose \
          --prune-empty-dirs \
          "${pkg}/include/" "$out/sysroot/include/" || true
      else
        echo "Info: Package ${pkg} does not have an /include directory, skipping include copy."
      fi

      if [ -d "${pkg}/lib" ]; then
        echo "Copying lib files from ${pkg} to $out/sysroot/lib/ (excluding .pc, .la, pkgconfig/, cmake/, and .so files)"
        # Explicitly using --recursive --copy-links and --no-perms, --no-owner, --no-group.
        # Exclude .so files (linker scripts) but keep .so.X.Y.Z files (actual shared libraries)
        # Exclude gcc's libstdc++ and libsupc++
        rsync --recursive --copy-links --no-perms --no-owner --no-group \
          --exclude='*.pc' \
          --exclude='*.la' \
          --exclude='pkgconfig/' \
          --exclude='cmake/' \
          --exclude='*.so' \
          "${pkg}/lib/" "$out/sysroot/lib/" || true
      else
        echo "Info: Package ${pkg} does not have a /lib directory, skipping lib copy."
      fi
    '') commonLibs}

    echo "Finished copying files from commonLibs."

    # Create linker scripts for all shared libraries
    echo "Creating linker scripts with relative paths..."
    echo "First, listing all .so.* files we'll process:"
    find "$out/sysroot/lib" -maxdepth 1 -type f -name "*.so.*" ! -name "*.py" ! -name "*.la" ! -name "*.pc" -ls

    # First, find all base library names (without version)
    echo "Finding base library names..."
    base_libs=$(find "$out/sysroot/lib" -maxdepth 1 -type f -name "*.so.*" ! -name "*.py" ! -name "*.la" ! -name "*.pc" | while read -r sofile; do
      basename=$(basename "$sofile")
      if [[ $basename =~ ^(.*)\.so\.([0-9]+(\.[0-9]+)*)$ ]]; then
        echo "''${BASH_REMATCH[1]}"
      fi
    done | sort -u)

    # For each base library, find the most specific version
    echo "Finding most specific versions..."
    for lib in $base_libs; do
      echo "Processing base library: $lib"

      # Skip ld-linux-x86-64 as it's a special case
      if [[ "$lib" == "ld-linux-x86-64" ]]; then
        echo "  Skipping ld-linux-x86-64 as it's the dynamic linker"
        continue
      fi

      # Find all versions of this library
      versions=$(find "$out/sysroot/lib" -maxdepth 1 -type f -name "$lib.so.*" ! -name "*.py" ! -name "*.la" ! -name "*.pc" | while read -r sofile; do
        basename=$(basename "$sofile")
        if [[ $basename =~ ^.*\.so\.([0-9]+(\.[0-9]+)*)$ ]]; then
          echo "''${BASH_REMATCH[1]}"
        fi
      done | sort -V)

      # Get the most specific version (last in sorted order)
      most_specific_version=$(echo "$versions" | tail -n1)
      if [ -n "$most_specific_version" ]; then
        echo "  Most specific version: $most_specific_version"
        sofile="$out/sysroot/lib/$lib.so.$most_specific_version"

        # Check for AS_NEEDED dependencies
        as_needed=""
        needed_libs=$(readelf -d "$sofile" 2>/dev/null | grep "NEEDED" | sed -n 's/.*\[\(.*\)\]/\1/p')
        if [ -n "$needed_libs" ]; then
          echo "  Found NEEDED dependencies:"
          for needed in $needed_libs; do
            echo "    - $needed"
            if [[ $needed =~ ^(.*)\.so\.(.*)$ ]]; then
              needed_base="''${BASH_REMATCH[1]}"
              needed_version="''${BASH_REMATCH[2]}"
              if [ -f "$out/sysroot/lib/$needed" ]; then
                if [ -z "$as_needed" ]; then
                  as_needed="$needed"
                else
                  as_needed="$as_needed $needed"
                fi
                echo "      Added to AS_NEEDED: $needed"
              else
                echo "      Warning: NEEDED dependency $needed not found in sysroot"
              fi
            fi
          done
        fi

        # Create the linker script
        echo "Creating linker script for $lib.so pointing to $lib.so.$most_specific_version"
        echo "/* GNU ld script */" > "$out/sysroot/lib/$lib.so"
        echo "OUTPUT_FORMAT(elf64-x86-64)" >> "$out/sysroot/lib/$lib.so"
        if [ -n "$as_needed" ]; then
          echo "GROUP ( $lib.so.$most_specific_version AS_NEEDED ( $as_needed ) )" >> "$out/sysroot/lib/$lib.so"
        else
          echo "GROUP ( $lib.so.$most_specific_version )" >> "$out/sysroot/lib/$lib.so"
        fi
        echo "  Created linker script: $out/sysroot/lib/$lib.so"
      fi
    done

    # Fix RPATH entries in shared libraries
    echo "Fixing RPATH entries in shared libraries..."
    find "$out/sysroot/lib" -type f -name "*.so*" -exec patchelf --set-rpath '$ORIGIN' {} \;
    echo "RPATH entries fixed."

    echo ""
    echo "Sysroot successfully created at: $out/sysroot"

    # Debug output
    echo "Final listing of all .so files:"
    find "$out/sysroot/lib" -name "*.so" -ls
    echo "Final listing of all .so.* files:"
    find "$out/sysroot/lib" -name "*.so.*" -ls
  '';

  meta = with pkgs.lib; {
    description = "Simplified libraries and headers for Bazel C/C++ builds";
    homepage = "https://github.com/randomizedcoder/bazel_sysroot_library_and_libs_amd64";
    license = licenses.mit;
  };
}
