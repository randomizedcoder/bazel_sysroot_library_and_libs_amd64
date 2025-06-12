# Bazel Sysroot Library and Libraries for AMD64

This repository provides a combined sysroot for Bazel that includes both header files and libraries for AMD64 architecture. It's designed to work with Bazel's C/C++ build system, providing a complete set of development files needed for compilation and linking.

## Overview

The sysroot combines two main components:
1. Header files (`/include`) - Essential for compiling C/C++ code
2. Libraries (`/lib`) - Both static (`.a`) and shared (`.so`) libraries for linking

### Components

- `default.nix`: The main Nix configuration file that:
  - Sets up the sysroot structure
  - Copies header files from various packages
  - Copies static and shared libraries
  - Handles special cases like GCC paths and symlinks
  - Creates the necessary directory structure
  - Copies the BUILD.bazel file to the sysroot

- `bazel/BUILD.bazel`: Bazel configuration that:
  - Exposes header files through the `headers` filegroup
  - Exposes libraries through the `lib` filegroup
  - Provides a `system_libs` target for shared libraries
  - Sets up proper visibility rules

- `Makefile`: Provides convenient commands to:
  - Build the sysroot
  - Copy the sysroot to a target location
  - List available options
  - Clean up build artifacts

## Usage

1. Clone the repository:
   ```bash
   git clone https://github.com/randomizedcoder/bazel_sysroot_library_and_libs_amd64/
   cd bazel_sysroot_library_and_libs_amd64
   ```

2. View available options:
   ```bash
   make
   ```

3. Build the sysroot:
   ```bash
   make build
   ```

4. Copy the sysroot to the target location (requires sudo):
   ```bash
   make copy
   ```

## Dependencies

The sysroot includes:
- Core system libraries (glibc, gcc)
- Compression libraries (zlib, bzip2, xz, zstd)
- XML and parsing libraries (libxml2, expat)
- Networking libraries (openssl, curl)
- Text processing libraries (pcre, pcre2)
- JSON libraries (jansson)
- Database libraries (sqlite)
- Image processing libraries (libpng, libjpeg)
- System utilities (util-linux)

## Sysroot directory listing

This repo also contains the [list of all the files](./sysroot_file_list.txt) in the sysroot

## NOTE for Bazel users

When writing BUILD.bazel rules for this sysroot, be aware:

- For startup files (such as crt1.o, crti.o, crtbeginS.o, crtendS.o, crtn.o), you must use the `objects` attribute of `cc_import` instead of `static_library`. This is because Bazel expects `static_library` to be an archive (.a or .lib), not a single object file (.o).
- For static libraries (.a), use the `static_library` attribute.
- For shared libraries (.so), use the `shared_library` attribute.

Example:
```python
cc_import(
    name = "crt1",
    objects = ["lib/Scrt1.o"],
)
cc_import(
    name = "libm",
    static_library = "lib/libm.a",
)
cc_import(
    name = "libstdc++",
    static_library = "lib/libstdc++.a",
    shared_library = "lib/libstdc++.so",
)
```

This ensures Bazel can correctly use all sysroot files for linking and building.

## License

MIT License