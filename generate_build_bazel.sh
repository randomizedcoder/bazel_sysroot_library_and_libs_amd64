#!/bin/bash
set -e

# Function to check if a path is a directory
is_directory() {
  [ -d "$1" ]
}

# Declare associative arrays to store library information
declare -A libs

# Function to collect library information
collect_libs() {
  local path="$1"
  local entry
  local name
  local relative_path

  entry="$(basename "$path")"
  relative_path="${path#./sysroot/}"

  # Clean up the name
  # Remove lib prefix and extension
  name="${entry#lib}"
  name="${name%.*}"

  if is_directory "$path"; then
    local f
    for f in "$path"/*; do
      if [ -e "$f" ]; then
        collect_libs "$f"
      fi
    done
  elif echo "$entry" | grep -qE '\.(o|a|so)$'; then
    # For .o files, use objects
    if echo "$entry" | grep -q '\.o$'; then
      libs["${entry%.o}"]+="objects:${relative_path} "
    # For .a files, use static_library
    elif echo "$entry" | grep -q '\.a$'; then
      libs["$name"]+="static:${relative_path} "
    # For .so files, use shared_library
    elif echo "$entry" | grep -q '\.so$'; then
      libs["$name"]+="shared:${relative_path} "
    fi
  fi
}

# Function to generate rules from collected information
generate_rules() {
  local name
  for name in "${!libs[@]}"; do
    local objects=""
    local static_lib=""
    local shared_lib=""

    # Parse the collected information
    for item in ${libs[$name]}; do
      case "$item" in
        objects:*)
          objects="${item#objects:}"
          ;;
        static:*)
          static_lib="${item#static:}"
          ;;
        shared:*)
          shared_lib="${item#shared:}"
          ;;
      esac
    done

    echo "cc_import("
    echo "  name = \"$name\","
    [ -n "$objects" ] && echo "  objects = [\"$objects\"],"
    [ -n "$static_lib" ] && echo "  static_library = \"$static_lib\","
    [ -n "$shared_lib" ] && echo "  shared_library = \"$shared_lib\","
    echo "  visibility = [\"//visibility:public\"],"
    echo ")"
    echo
  done
}

# Start generating BUILD.bazel
echo "#"
echo "# BUILD.bazel"
echo "#"
echo
echo "package(default_visibility = [\"//visibility:public\"])"
echo
echo "# Startup files and libraries"
echo "# Note: Some startup files (crt1.o, crti.o) may be missing from the sysroot."
echo "# If needed, copy them from the original sysroot."
echo
# First collect all library information
collect_libs "./sysroot/lib"

# Then generate rules from collected information
generate_rules

echo "# Usr directory filegroup"
echo "filegroup("
echo "  name = \"sysroot\","
echo "  srcs = glob(["
echo "    \"include/**\","
echo "    \"lib/**\","
echo "  ]),"
echo ")"
echo
echo "# Include directory filegroup"
echo "filegroup("
echo "  name = \"include\","
echo "  srcs = glob([\"include/**\"]),"
echo ")"
echo
echo "# Library directory filegroup"
echo "filegroup("
echo "  name = \"lib\","
echo "  srcs = glob([\"lib/**\"]),"
echo ")"
echo
echo "# end"