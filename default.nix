#
# default.nix - Simplified sysroot creation for Bazel C/C++ builds
#

{ pkgs ? import <nixpkgs> {} }:

let
  llvm = pkgs.llvmPackages_20;

  commonLibs = with pkgs; [

    # Core C system libraries (glibc is standard on Linux, Clang uses it)
    glibc glibc.dev glibc.static

    # GCC runtime libraries, C++ Standard Library, and C++ headers
    gcc                  # Provides gcc/g++ compilers, libgcc_s.so.1, and also libstdc++.so.*, libstdc++.a, libsupc++.a from its /lib subdir
    libgcc libgcc.lib
    gcc-unwrapped gcc-unwrapped.lib gcc-unwrapped.libgcc
    stdenv.cc            # Its 'include/' dir should provide C/C++ headers for the standard compiler (GCC in this case)
    # consider https://search.nixos.org/packages?channel=unstable&show=fastStdenv&from=0&size=50&sort=relevance&type=packages&query=fastStdenv

    # LLVM C++ Standard Library, compiler runtime, and unwind library
    llvm.stdenv
    llvm.libcxxStdenv
    llvm.libcxxClang
    llvm.libcxx          # Provides libc++.so, libc++.a (libraries)
    llvm.libcxx.dev      # Provides C++ headers
    # do NOT include llvm.libc-full, because it will override glibc
    #llvm.libc-full
    llvm.compiler-rt     # Provides libclang_rt.builtins*.a
    llvm.compiler-rt.dev # Provides libclang_rt headers
    llvm.libunwind       # Provides libunwind for exception handling
    llvm.libunwind.dev   # Provides libunwind headers

    libclang libclang.dev libclang.lib

    #https://abseil.io/
    abseil-cpp

    libuuid libuuid.dev libuuid.out

    # Compression libraries (compiler-agnostic)
    zlib zlib.dev zlib.static
    bzip2 bzip2.dev bzip2.out
    xz xz.dev xz.out
    zstd zstd.dev zstd.out

    # XML and parsing (compiler-agnostic)
    libxml2 libxml2.dev libxml2.out        # .out for .so.*
    expat expat.dev expat.out

    # Networking (compiler-agnostic)
    openssl openssl.dev openssl.out
    boringssl boringssl.dev boringssl.out
    curl curl.dev curl.out

    # Text processing (compiler-agnostic)
    pcre pcre.dev pcre.out
    pcre2 pcre2.dev pcre2.out
    re2 re2.dev re2.out

    # JSON (compiler-agnostic)
    jansson jansson.dev jansson.out

    # Database (compiler-agnostic)
    sqlite sqlite.dev sqlite.out

    # Image processing (compiler-agnostic)
    libpng libpng.dev libpng.out
    libjpeg libjpeg.dev libjpeg.out

    # System utilities
    util-linux util-linux.dev util-linux.out # Provides libuuid, libblkid, libmount
  ];

in
pkgs.stdenv.mkDerivation {
  name = "bazel-sysroot-library-and-libs-amd64";
  version = "1.0.0";
  src = ./.;

  # buildInputs are for runtime dependencies of the *output*
  # nativeBuildInputs are for build-time tools
  nativeBuildInputs = [ pkgs.rsync pkgs.patchelf pkgs.binutils ]; # Add binutils for readelf
  buildInputs = commonLibs; # Makes commonLibs' paths available

  # Pass commonLibs paths as an environment variable to the buildCommand
  commonLibsPaths = pkgs.lib.concatStringsSep " " (map (pkg: "${pkg}") commonLibs);

  buildCommand = ''
    # Exit immediately on error, print commands, fail on unset variables, fail on pipe errors
    set -euxo pipefail

    mkdir -p "$out/sysroot/include"
    mkdir -p "$out/sysroot/lib"

    echo "Copying files from commonLibs to sysroot..."

    for pkg_path in $commonLibsPaths; do
      if [ -d "$pkg_path/include" ]; then # Check if the package has an include directory
        echo "Copying include files from (generic) $pkg_path to $out/sysroot/include/"
        # rsync -rL is like cp -RL (recursive, dereference symlinks)
        # --no-perms, --no-owner, --no-group aim to mimic cp --no-preserve=mode,ownership.
        rsync --recursive --copy-links --no-perms --no-owner --no-group \
          --verbose \
          --prune-empty-dirs \
          "$pkg_path/include/" "$out/sysroot/include/" || true
      else
        echo "Info: Package $pkg_path does not have an /include directory, skipping include copy."
      fi

      if [ -d "$pkg_path/lib" ]; then
        echo "Copying lib files from $pkg_path to $out/sysroot/lib/ (excluding .pc, .la, pkgconfig/, cmake/, and .so files)"
        # Explicitly using --recursive --copy-links and --no-perms, --no-owner, --no-group.
        # Exclude .so files (linker scripts) but keep .so.X.Y.Z files (actual shared libraries)
        # Include .a files (static libraries) when they exist
        # Exclude gcc's libstdc++ and libsupc++
        rsync --recursive --copy-links --no-perms --no-owner --no-group \
          --exclude='*.pc' \
          --exclude='*.la' \
          --exclude='pkgconfig/' \
          --exclude='cmake/' \
          --exclude='*.so' \
          "$pkg_path/lib/" "$out/sysroot/lib/" || true
      else
        echo "Info: Package $pkg_path does not have a /lib directory, skipping lib copy."
      fi
    done

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

    # Handle static library linker scripts
    echo "Processing static library linker scripts..."
    echo "First, identifying .a files that are actually linker scripts:"

    # Find all .a files and check which ones are linker scripts (text files)
    static_libs=$(find "$out/sysroot/lib" -maxdepth 1 -type f -name "*.a" | while read -r afile; do
      if file "$afile" | grep -q "text"; then
        echo "$afile"
      fi
    done)

    if [ -n "$static_libs" ]; then
      echo "Found static library linker scripts:"
      echo "$static_libs"

      for afile in $static_libs; do
        echo "Processing static library linker script: $afile"

        # Read the linker script and extract referenced libraries
        referenced_libs=$(grep -o '/nix/store/[^[:space:]]*\.a' "$afile" || true)

        if [ -n "$referenced_libs" ]; then
          echo "  Found referenced libraries:"
          for ref_lib in $referenced_libs; do
            echo "    - $ref_lib"

            # Extract the library name from the full path
            lib_name=$(basename "$ref_lib")

            # Check if the referenced library exists
            if [ -f "$ref_lib" ]; then
              # Check if the library is already in the sysroot
              if [ -f "$out/sysroot/lib/$lib_name" ]; then
                echo "      Library $lib_name already exists in sysroot"
                # Check if it's the same file (same inode)
                if [ "$(stat -c %i "$ref_lib")" = "$(stat -c %i "$out/sysroot/lib/$lib_name")" ]; then
                  echo "      Files are identical (same inode), skipping copy"
                else
                  echo "      Files are different, but target exists - skipping copy to avoid permission issues"
                fi
              else
                echo "      Copying $lib_name to sysroot..."
                if cp "$ref_lib" "$out/sysroot/lib/"; then
                  echo "      Successfully copied $lib_name"
                else
                  echo "      Warning: Failed to copy $lib_name (permission denied or other error)"
                fi
              fi
            else
              echo "      Warning: Referenced library $ref_lib not found"
            fi
          done

          # Rewrite the linker script to use relative paths
          echo "  Rewriting linker script to use relative paths..."
          temp_file=$(mktemp)
          if sed 's|/nix/store/[^[:space:]]*lib/||g' "$afile" > "$temp_file"; then
            mv "$temp_file" "$afile"
            echo "  Updated linker script: $afile"
          else
            echo "  Warning: Failed to update linker script $afile"
            rm -f "$temp_file"
          fi
        else
          echo "  No Nix store paths found in linker script"
        fi
      done
    else
      echo "No static library linker scripts found"
    fi

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
