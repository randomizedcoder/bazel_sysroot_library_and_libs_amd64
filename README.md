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

### Building the Sysroot

To build the sysroot, run:

```bash
make build
```

This will create the sysroot in the `./sysroot` directory.

### Generating BUILD.bazel

After building the sysroot, you can generate a `BUILD.bazel` file that exposes all libraries and object files to Bazel. Run:

```bash
make generate-build
```

This will run the `generate_build_bazel.sh` script to create a `BUILD.bazel` file in the `./sysroot` directory. The generated file includes `cc_import` rules for all `.o`, `.a`, and `.so` files, making them available to Bazel builds.

### Using the Sysroot in Bazel

In your Bazel `WORKSPACE` file, add:

```python
local_repository(
    name = "sysroot",
    path = "/path/to/your/sysroot",
)
```

Then, in your `BUILD` files, you can depend on the libraries using targets like `@sysroot//:asan` or `@sysroot//:atomic`.

## Additional Information

- The `generate_build_bazel.sh` script is used to create the `BUILD.bazel` file. It traverses the `./sysroot` directory and generates `cc_import` rules for all libraries and object files.
- The generated `BUILD.bazel` file is designed to be maximally Bazel-friendly, exposing all libraries and object files for use in Bazel builds.

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