#!/usr/bin/env bash
#
# verify_sysroot.bash - Verifies the contents of the Bazel sysroot
#                       based on the expected components.
#

set -euo pipefail

SYSROOT_DIR="./sysroot"

# Color codes for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_detail() {
    echo -e "  => $1"
}

# --- Global Counters ---
total_checked_items=0
total_found_items=0
total_missing_items=0

# Function to check for existence of files/patterns
# Arguments:
#   $1: Component Name (e.g., "Core C (glibc) (Headers)")
#   $2: Base directory (e.g., "$SYSROOT_DIR/include" or "$SYSROOT_DIR/lib")
#   $3...: List of files/patterns to find
check_files() {
    local component_display_name="$1" # More descriptive name for logging
    local base_dir="$2"
    shift 2
    local files_to_check=("$@")
    local all_found_for_this_check=true

    log_info "Checking: ${component_display_name} in ${base_dir}"

    if [ ! -d "$base_dir" ]; then
        log_error "Base directory ${base_dir} does not exist for ${component_display_name}."
        # This is a critical error for this check, so mark as failed and return
        return 1
    fi

    if [ ${#files_to_check[@]} -eq 0 ] || [ -z "${files_to_check[0]}" ]; then
        log_info "No specific files/patterns listed for ${component_display_name}. Skipping detailed search."
        return 0 # No files to check means success for this part
    fi

    for pattern in "${files_to_check[@]}"; do
        ((total_checked_items++))
        log_detail "Searching for pattern: '${pattern}'"
        local found_path=""

        if [[ "$base_dir" == *"/lib"* ]]; then
            # For libraries, search only in the top-level of the lib directory, allowing wildcards.
            found_path=$(find "$base_dir" -maxdepth 1 -name "$pattern" -print -quit 2>/dev/null)
        else
            # For headers:
            if [[ "$pattern" == *"/"* ]]; then
                # Pattern contains a path component (e.g., "sys/socket.h", "c++/*/vector")
                # Use -path to match paths ending with the pattern. find handles glob expansion.
                found_path=$(find "$base_dir" -path "*/${pattern}" -print -quit 2>/dev/null)
            else
                # Pattern is a simple filename (e.g., "stdio.h")
                # Search recursively by name.
                found_path=$(find "$base_dir" -name "$pattern" -print -quit 2>/dev/null)
            fi
        fi

        if [ -n "$found_path" ]; then
            log_detail "${GREEN}Found:${NC} '${pattern}' (at ${found_path})"
            ((total_found_items++))
        else
            log_warn "${RED}Not found:${NC} '${pattern}' in ${base_dir}"
            all_found_for_this_check=false
            ((total_missing_items++))
        fi
    done

    if $all_found_for_this_check; then
        return 0 # Success for this check_files call
    else
        return 1 # Failure for this check_files call
    fi
}

# --- Component Definitions ---
# We use associative arrays to store header and library patterns for each component.
# An ordered list `component_order` ensures checks are performed in a defined sequence.
declare -A components_headers
declare -A components_libs
declare -a component_order

# Helper function to define a component and its expected files
# Arguments:
#   $1: Component's canonical name (used as key)
#   $2: Space-separated string of header patterns
#   $3: Space-separated string of library patterns
add_component() {
    local name="$1"
    local headers="$2"
    local libs="$3"

    # Add to order if not already present (though typically called once per component)
    if ! [[ " ${component_order[*]} " == *" ${name} "* ]]; then
        component_order+=("$name")
    fi

    components_headers["$name"]="$headers"
    components_libs["$name"]="$libs"
}

# Define components based on the "What's Included" section of README.md
# (and general expectations for such a sysroot)

log_info "Defining components to verify..."

# 1. Core C system libraries (glibc)
add_component "Core C (glibc)" \
    "stdio.h stdlib.h string.h unistd.h sys/socket.h features.h ctype.h wchar.h" \
    "libc.so.6 libm.so.6 libpthread.so.0 libdl.so.2 librt.so.1 Scrt1.o crti.o crtn.o libc.a libm.a"

# 2. GCC runtime libraries and C++ Standard Library (libstdc++)
#    (Reflecting the intended GCC-centric nature, and README's "Design Decisions")
add_component "GCC C++/Runtime (libstdc++)" \
    "c++/*/vector c++/*/string c++/*/iostream c++/*/bits/c++config.h c++/*/exception" \
    "libstdc++.so.6* libgcc_s.so.1* libsupc++.a libstdc++.a"
    # Using c++/*/folder... to account for versioned include paths like c++/13/vector

# 3. LLVM C++ Standard Library and compiler runtime
#    (This is explicitly from the README's "What's Included" section.
#     If the sysroot is GCC-centric, these are expected to be NOT FOUND,
#     which helps identify README vs. reality discrepancies.)
add_component "LLVM C++/Runtime (per README)" \
    "c++/v1/vector llvm/Config/llvm-config.h clang/Basic/TargetInfo.h" \
    "libc++.so.* libc++abi.so.* libclang_rt.*.a libunwind.so.*"

# 4. Common compression libraries
add_component "Zlib" "zlib.h" "libz.so.* libz.a"
add_component "Bzip2" "bzlib.h" "libbz2.so.*"
add_component "XZ (lzma)" "lzma.h" "liblzma.so.*"
add_component "Zstd" "zstd.h" "libzstd.so.*"

# 5. XML and parsing libraries
add_component "Libxml2" "libxml2/libxml/parser.h libxml2/libxml/tree.h" "libxml2.so.*"
add_component "Expat" "expat.h" "libexpat.so.*"

# 6. Networking libraries
add_component "OpenSSL" "openssl/ssl.h openssl/crypto.h" "libssl.so.* libcrypto.so.* libssl.a libcrypto.a"
add_component "Curl" "curl/curl.h" "libcurl.so.*"

# 7. Text processing libraries
add_component "PCRE" "pcre.h" "libpcre.so.*"
add_component "PCRE2" "pcre2.h" "libpcre2-8.so.*" # Common is -8 (8-bit)
add_component "RE2" "re2/re2.h" "libre2.so.*"

# 8. JSON library (jansson)
add_component "Jansson" "jansson.h" "libjansson.so.*"

# 9. Database library (sqlite)
add_component "SQLite" "sqlite3.h" "libsqlite3.so.*"

# 10. Image processing libraries
add_component "LibPNG" "png.h" "libpng*.so.*" # e.g. libpng16.so.16
add_component "LibJPEG" "jpeglib.h" "libjpeg.so.*" # e.g. libjpeg.so.8 or libjpeg.so.62

# 11. System utilities (from util-linux)
add_component "System Utilities (util-linux: uuid, blkid, mount)" \
    "uuid/uuid.h blkid/blkid.h libmount/libmount.h" \
    "libuuid.so.* libblkid.so.* libmount.so.*"

# --- Main Script Logic ---
if [ ! -d "$SYSROOT_DIR" ]; then
    log_error "Sysroot directory '${SYSROOT_DIR}' not found."
    log_error "Please ensure the sysroot is built and you are in the correct directory, or update SYSROOT_DIR."
    exit 1
fi
log_info "Starting sysroot verification for '${SYSROOT_DIR}'"
echo "---"

overall_verification_failed=false

for component_key_name in "${component_order[@]}"; do
    echo # Add a blank line for readability between components
    log_info "Verifying Component: ${component_key_name}"

    current_component_failed=false

    # Check headers
    headers_to_check_str="${components_headers[$component_key_name]}"
    # Convert space-separated string to array
    read -r -a headers_to_check <<< "$headers_to_check_str"
    if ! check_files "${component_key_name} (Headers)" "$SYSROOT_DIR/include" "${headers_to_check[@]}"; then
        current_component_failed=true
    fi

    # Check libraries
    libs_to_check_str="${components_libs[$component_key_name]}"
    # Convert space-separated string to array
    read -r -a libs_to_check <<< "$libs_to_check_str"
    if ! check_files "${component_key_name} (Libraries)" "$SYSROOT_DIR/lib" "${libs_to_check[@]}"; then
        current_component_failed=true
    fi

    if $current_component_failed; then
        log_warn "Verification found missing items for component: ${component_key_name}"
        overall_verification_failed=true
    else
        log_info "Component ${component_key_name} items verified successfully."
    fi
    echo "---"
done

echo
log_info "--- Verification Summary ---"
log_info "Total items specified for checking: ${total_checked_items}"
log_info "Items successfully found:           ${GREEN}${total_found_items}${NC}"
if [ "$total_missing_items" -gt 0 ]; then
    log_warn "Items missing:                    ${RED}${total_missing_items}${NC}"
else
    log_info "Items missing:                    ${GREEN}0${NC}"
fi
log_info "--------------------------"
echo

if $overall_verification_failed; then
    log_error "Sysroot verification completed: One or more components have missing items."
    exit 1
else
    log_info "Sysroot verification completed successfully: All specified items for all components found."
    exit 0
fi
