# Bazel Sysroot Library and Libs AMD64

This repository contains a Nix derivation that creates a sysroot for Bazel C/C++ builds on AMD64 Linux systems. It provides a simplified set of libraries and headers that are commonly needed for C/C++ development.

## Design Decisions

### C++ Standard Library Choice: libc++ over libstdc++

This sysroot is configured to use LLVM's libc++ as the C++ standard library implementation, rather than GCC's libstdc++. This decision was made for several reasons:

1. **Consistency with LLVM Toolchain**: Since we're using the LLVM toolchain (via `toolchains_llvm`), using libc++ provides better integration and compatibility.

2. **Avoiding Mixed Implementations**: The sysroot explicitly excludes libstdc++ headers (using rsync exclude patterns for `c++/14.*` and `c++/gcc*`) to prevent any potential conflicts or confusion between different C++ standard library implementations.

3. **Cleaner Build Configuration**: By using only libc++, we can simplify our build configurations and avoid potential issues that might arise from mixing different C++ standard library implementations.

To use this sysroot, ensure your BUILD.bazel files are configured to use libc++:
```python
copts = [
    "-stdlib=libc++",
    "-isystem", "external/+_repo_rules+bazel_sysroot_library_and_libs_amd64/sysroot/include/c++/v1",
    # ... other include paths ...
]
```

## What's Included

The sysroot includes:

- Core C system libraries (glibc)
- GCC runtime libraries
- LLVM C++ Standard Library and compiler runtime
- Common compression libraries (zlib, bzip2, xz, zstd)
- XML and parsing libraries (libxml2, expat)
- Networking libraries (openssl, curl)
- Text processing libraries (pcre, pcre2)
- JSON library (jansson)
- Database library (sqlite)
- Image processing libraries (libpng, libjpeg)
- System utilities

## Shared Library Handling

The sysroot includes a sophisticated shared library handling system that manages versioned shared libraries (`.so.*` files) and creates appropriate linker scripts (`.so` files). Here's how it works:

1. **Versioned Libraries**: Each library can have multiple versioned files (e.g., `libasan.so.8.0.0`, `libasan.so.8`). These follow the standard Linux shared library versioning scheme:
   - Major version (e.g., `8` in `libasan.so.8`)
   - Minor version (e.g., `0` in `libasan.so.8.0`)
   - Patch version (e.g., `0` in `libasan.so.8.0.0`)

2. **Linker Scripts**: For each library, we create a single `.so` file that points to the most specific version. For example:
   - `libasan.so` points to `libasan.so.8.0.0`
   - `libcurl.so` points to `libcurl.so.4.8.0`
   - `libstdc++.so` points to `libstdc++.so.6.0.33`

   Here's an example of a correctly formatted linker script (`libunwind.so`):
   ```
   /* GNU ld script */
   OUTPUT_FORMAT(elf64-x86-64)
   GROUP ( libunwind.so.1.0 AS_NEEDED ( libdl.so.2 libpthread.so.0 libc.so.6 ) )
   ```
   This script:
   - Points to the most specific version (`libunwind.so.1.0`)
   - Lists all required dependencies using AS_NEEDED
   - Uses relative paths for all libraries
   - Specifies the correct output format

3. **Special Case Handling**: The dynamic linker/loader (`ld-linux-x86-64.so.2`) is handled specially:
   - It is excluded from the `.so` file creation process
   - This is because it's not a regular shared library but rather the program that loads shared libraries

4. **Dependency Tracking**: The system also tracks library dependencies using the `AS_NEEDED` directive in the linker scripts. This ensures that:
   - Only required libraries are loaded at runtime
   - Dependencies are properly resolved
   - Circular dependencies are handled correctly

## Usage

To use this sysroot in your Bazel project:

1. Build the sysroot:
   ```bash
   make copy
   ```

2. The sysroot will be created in `./sysroot/` with the following structure:
   ```
   sysroot/
   ├── include/  # Header files
   └── lib/      # Library files
       ├── *.so  # Linker scripts
       └── *.so.* # Versioned shared libraries
   ```

3. Configure Bazel to use this sysroot by setting the appropriate compiler and linker flags.

## Building

The sysroot is built using Nix. The build process:

1. Copies all necessary libraries and headers from the Nix store
2. Creates appropriate linker scripts for shared libraries
3. Fixes RPATH entries in shared libraries to use relative paths
4. Excludes unnecessary files (`.pc`, `.la`, pkgconfig/, cmake/)

## License

This project is licensed under the MIT License - see the LICENSE file for details.

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

## Important Notes About Nix-Built Libraries

### Linker Scripts and Shared Libraries
When using Nix-built libraries, there are two important things to be aware of:

1. **Linker Scripts**: Many `.so` files in Linux are actually linker scripts (text files) that point to the real shared libraries. For example:
   - `libm.so` is a linker script that points to `libm.so.6`
   - These scripts often contain absolute paths to the Nix store (e.g., `/nix/store/.../lib/libm.so.6`)
   - We need to rewrite these scripts to use relative paths instead

2. **Shared Library Dependencies**: The actual shared libraries (`.so.6` files) have their own dependencies:
   - They may reference other libraries via absolute paths
   - They may have embedded RPATH entries pointing to the Nix store
   - We need to ensure all dependencies are present in the sysroot

### How We Handle This
In our `default.nix`:
1. We copy the actual shared libraries (`.so.6` files)
2. We create our own linker scripts with relative paths
3. We ensure all required dependencies are present in the sysroot
4. We use `patchelf` to fix RPATH entries if needed

This ensures that the sysroot is truly hermetic and doesn't depend on the Nix store or host system.

## Handling Nix-Built Shared Libraries

When working with Nix-built libraries, there's a specific challenge we need to address: the shared library linker scripts (`.so` files) contain absolute paths to the Nix store. For example, a typical `libm.so` from Nix might look like:

```
GROUP ( /nix/store/.../lib/libm.so.6 AS_NEEDED ( /nix/store/.../lib/libmvec.so.1 ) )
```

To make our sysroot truly hermetic and independent of the Nix store, we:

1. **Skip copying `.so` files**: We exclude `.so` files during the initial copy from Nix packages, as these are the linker scripts containing Nix store paths.

2. **Copy actual shared libraries**: We copy the versioned `.so.*` files (e.g., `libm.so.6`) which are the actual shared library binaries.

3. **Create our own linker scripts**: We generate new `.so` linker scripts that use relative paths instead of Nix store paths. For example:
   ```
   GROUP ( libm.so.6 AS_NEEDED ( libmvec.so.1 ) )
   ```

4. **Fix RPATH entries**: We use `patchelf` to ensure all shared libraries use `$ORIGIN` for their RPATH, making them relocatable.

This approach ensures that:
- The sysroot is completely independent of the Nix store
- All shared libraries can be found using relative paths
- The sysroot remains hermetic and portable