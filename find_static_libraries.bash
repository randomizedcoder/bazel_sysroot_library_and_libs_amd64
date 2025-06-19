#!/bin/bash

# find_static_libraries.bash
# Script to find static libraries in Nix packages used by our sysroot

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "found")
            echo -e "${GREEN}✓${NC} $message"
            ;;
        "not_found")
            echo -e "${RED}✗${NC} $message"
            ;;
        "info")
            echo -e "${BLUE}ℹ${NC} $message"
            ;;
        "warning")
            echo -e "${YELLOW}⚠${NC} $message"
            ;;
    esac
}

# Function to check if a package has static libraries
check_package_static_libs() {
    local pkg_path=$1
    local pkg_name=$2

    echo "Checking package: $pkg_name"

    # Check if package has a lib directory
    if [ ! -d "$pkg_path/lib" ]; then
        print_status "not_found" "No lib directory found"
        return 1
    fi

    # Find all .a files in the lib directory
    local static_libs=$(find "$pkg_path/lib" -maxdepth 1 -name "*.a" 2>/dev/null || true)

    if [ -z "$static_libs" ]; then
        print_status "not_found" "No static libraries found"
        return 1
    fi

    # Count and list static libraries
    local count=$(echo "$static_libs" | wc -l)
    print_status "found" "Found $count static library(ies):"

    # List each static library with details
    while IFS= read -r lib; do
        if [ -n "$lib" ]; then
            local lib_name=$(basename "$lib")
            local lib_size=$(stat -c %s "$lib" 2>/dev/null || echo "unknown")
            local lib_type=$(file "$lib" 2>/dev/null | cut -d: -f2 | xargs || echo "unknown")

            # Check if it's a linker script or real static library
            if echo "$lib_type" | grep -q "text"; then
                print_status "info" "  $lib_name (linker script, ${lib_size} bytes)"
                # Show what it references
                local refs=$(grep -o '/nix/store/[^[:space:]]*\.a' "$lib" 2>/dev/null || true)
                if [ -n "$refs" ]; then
                    echo "    References:"
                    echo "$refs" | while read -r ref; do
                        local ref_name=$(basename "$ref")
                        echo "      - $ref_name"
                    done
                fi
            else
                print_status "found" "  $lib_name (static library, ${lib_size} bytes)"
            fi
        fi
    done <<< "$static_libs"

    return 0
}

# Main script
echo "=== Static Library Discovery Report ==="
echo "Checking Nix packages for static libraries..."
echo ""

# Get the list of packages from default.nix
# We'll extract the package names from the commonLibs list
echo "Extracting package list from default.nix..."

# Create a temporary file with the package list
cat > /tmp/package_list.txt << 'EOF'
# Core C system libraries
glibc
glibc.dev
glibc.static

# GCC runtime libraries
gcc
libgcc
gcc-unwrapped
stdenv.cc

# LLVM libraries
llvm.stdenv
llvm.libcxxStdenv
llvm.libcxxClang
llvm.libcxx
llvm.libcxx.dev
llvm.compiler-rt
llvm.compiler-rt.dev
llvm.libunwind
llvm.libunwind.dev

# Clang
libclang
libclang.dev
libclang.lib

# Abseil
abseil-cpp

# UUID
libuuid
libuuid.dev
libuuid.out

# Compression libraries
zlib
zlib.dev
zlib.static
bzip2
bzip2.dev
bzip2.out
xz
xz.dev
xz.out
zstd
zstd.dev
zstd.out

# XML and parsing
libxml2
libxml2.dev
libxml2.out
expat
expat.dev
expat.out

# Networking
openssl
openssl.dev
openssl.out
boringssl
boringssl.dev
boringssl.out
curl
curl.dev
curl.out

# Text processing
pcre
pcre.dev
pcre.out
pcre2
pcre2.dev
pcre2.out
re2
re2.dev
re2.out

# JSON
jansson
jansson.dev
jansson.out

# Database
sqlite
sqlite.dev
sqlite.out

# Image processing
libpng
libpng.dev
libpng.out
libjpeg
libjpeg.dev
libjpeg.out

# System utilities
util-linux
util-linux.dev
util-linux.out
EOF

# Initialize counters
total_packages=0
packages_with_static=0
packages_without_static=0
packages_with_static_list=""

# Read package list and check each one
while IFS= read -r line; do
    # Skip comments and empty lines
    if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// }" ]]; then
        continue
    fi

    # Extract package name (remove any trailing comments)
    pkg_name=$(echo "$line" | sed 's/[[:space:]]*#.*$//' | xargs)

    if [ -z "$pkg_name" ]; then
        continue
    fi

    total_packages=$((total_packages + 1))

    # Try to find the package in the Nix store using multiple approaches
    pkg_path=""
    found_static_libs=false

    # Method 1: Try to find by exact name in store (this finds all versions)
    pkg_paths=$(find /nix/store -maxdepth 1 -name "*$pkg_name*" 2>/dev/null | grep -v "\.drv$" | head -5 || true)

    # Check each found package for static libraries
    while IFS= read -r pkg_path; do
        if [ -n "$pkg_path" ] && [ -d "$pkg_path" ]; then
            echo ""
            echo "=== $pkg_name (found at: $pkg_path) ==="

            # Check for static libraries
            if check_package_static_libs "$pkg_path" "$pkg_name"; then
                found_static_libs=true
                packages_with_static=$((packages_with_static + 1))
                # Add to the list of packages with static libraries
                if [ -z "$packages_with_static_list" ]; then
                    packages_with_static_list="$pkg_name"
                else
                    packages_with_static_list="$packages_with_static_list, $pkg_name"
                fi
                break  # Found static libraries, no need to check more versions
            fi
        fi
    done <<< "$pkg_paths"

    # Method 2: If no static libraries found, try to get it from nixpkgs
    if [ "$found_static_libs" = false ]; then
        pkg_path=$(nix eval --raw nixpkgs#$pkg_name.outPath 2>/dev/null || true)

        if [ -n "$pkg_path" ] && [ -d "$pkg_path" ]; then
            echo ""
            echo "=== $pkg_name (nixpkgs: $pkg_path) ==="

            if check_package_static_libs "$pkg_path" "$pkg_name"; then
                found_static_libs=true
                packages_with_static=$((packages_with_static + 1))
                if [ -z "$packages_with_static_list" ]; then
                    packages_with_static_list="$pkg_name"
                else
                    packages_with_static_list="$packages_with_static_list, $pkg_name"
                fi
            fi
        fi
    fi

    # Method 3: Try with .out suffix
    if [ "$found_static_libs" = false ]; then
        pkg_path=$(nix eval --raw nixpkgs#$pkg_name.out.outPath 2>/dev/null || true)

        if [ -n "$pkg_path" ] && [ -d "$pkg_path" ]; then
            echo ""
            echo "=== $pkg_name (.out: $pkg_path) ==="

            if check_package_static_libs "$pkg_path" "$pkg_name"; then
                found_static_libs=true
                packages_with_static=$((packages_with_static + 1))
                if [ -z "$packages_with_static_list" ]; then
                    packages_with_static_list="$pkg_name"
                else
                    packages_with_static_list="$packages_with_static_list, $pkg_name"
                fi
            fi
        fi
    fi

    # Method 4: Try with .dev suffix
    if [ "$found_static_libs" = false ]; then
        pkg_path=$(nix eval --raw nixpkgs#$pkg_name.dev.outPath 2>/dev/null || true)

        if [ -n "$pkg_path" ] && [ -d "$pkg_path" ]; then
            echo ""
            echo "=== $pkg_name (.dev: $pkg_path) ==="

            if check_package_static_libs "$pkg_path" "$pkg_name"; then
                found_static_libs=true
                packages_with_static=$((packages_with_static + 1))
                if [ -z "$packages_with_static_list" ]; then
                    packages_with_static_list="$pkg_name"
                else
                    packages_with_static_list="$packages_with_static_list, $pkg_name"
                fi
            fi
        fi
    fi

    # Method 5: Try with .static suffix
    if [ "$found_static_libs" = false ]; then
        pkg_path=$(nix eval --raw nixpkgs#$pkg_name.static.outPath 2>/dev/null || true)

        if [ -n "$pkg_path" ] && [ -d "$pkg_path" ]; then
            echo ""
            echo "=== $pkg_name (.static: $pkg_path) ==="

            if check_package_static_libs "$pkg_path" "$pkg_name"; then
                found_static_libs=true
                packages_with_static=$((packages_with_static + 1))
                if [ -z "$packages_with_static_list" ]; then
                    packages_with_static_list="$pkg_name"
                else
                    packages_with_static_list="$packages_with_static_list, $pkg_name"
                fi
            fi
        fi
    fi

    # If we still haven't found static libraries, count it as not found
    if [ "$found_static_libs" = false ]; then
        print_status "warning" "Could not find package with static libraries: $pkg_name"
        packages_without_static=$((packages_without_static + 1))
    fi

done < /tmp/package_list.txt

# Clean up
rm -f /tmp/package_list.txt

# Print summary
echo ""
echo "=== Summary ==="
echo "Total packages checked: $total_packages"
print_status "found" "Packages with static libraries: $packages_with_static"
print_status "not_found" "Packages without static libraries: $packages_without_static"

# Calculate percentage
if [ $total_packages -gt 0 ]; then
    percentage=$((packages_with_static * 100 / total_packages))
    echo "Percentage with static libraries: ${percentage}%"
fi

# Display packages with static libraries
if [ -n "$packages_with_static_list" ]; then
    echo ""
    echo "=== Packages with Static Libraries ==="
    print_status "found" "Found static libraries in: $packages_with_static_list"
fi

echo ""
echo "=== Recommendations ==="
if [ $packages_with_static -gt 0 ]; then
    print_status "info" "Consider adding static versions of libraries to the sysroot for fully static builds"
    print_status "info" "Update default.nix to include .static outputs where available"
else
    print_status "warning" "No static libraries found - current mixed static/shared approach is appropriate"
fi

echo ""
echo "Report completed."