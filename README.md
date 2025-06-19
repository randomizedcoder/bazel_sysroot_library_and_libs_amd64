# Bazel Sysroot Library and Libs AMD64

This repository contains a Nix derivation that creates a sysroot for Bazel C/C++ builds on AMD64 Linux systems. It provides a simplified set of libraries and headers that are commonly needed for C/C++ development.

## Design Decisions

### C++ Standard Library Choice: libstdc++ (GCC) over libc++ (LLVM)

This sysroot is configured to use GCC's libstdc++ as the C++ standard library implementation. This decision was made for the following reasons:

1. **Addressing Sysroot Compatibility**: This change aims to resolve issues encountered with a Clang/libc++ based sysroot and improve compatibility, particularly when GCC is the primary toolchain.
2. **GCC Toolchain Preference**: The sysroot now prioritizes components from the GCC toolchain, including its C++ standard library (`libstdc++`).
3. **Inclusion of libstdc++ Components**: The sysroot build process ensures that GCC's C++ headers (e.g., from `gcc.cc.dev`) and libraries (`libstdc++.so.*`, `libstdc++.a`, `libsupc++.a` from `gcc.cc.lib`) are included. Previous `rsync` exclusions that prevented these from being copied (like `c++/gcc*`, `libstdc++.*`) have been removed.
3. **Inclusion of libstdc++ Components**: The sysroot build process ensures that GCC's C++ headers (e.g., from `gcc-unwrapped.dev`) and libraries (`libstdc++.so.*`, `libstdc++.a`, `libsupc++.a` from `gcc`'s default output path, specifically its `lib/` subdirectory) are included. Previous `rsync` exclusions that prevented these from being copied (like `c++/gcc*`, `libstdc++.*`) have been removed.
To use this sysroot with Bazel, ensure your toolchain is configured for GCC. Typically, no special `-stdlib` flag is needed if `g++` is your compiler, as it defaults to libstdc++. Your include paths should point to the sysroot's include directory:
```python
copts = [
    "-stdlib=libc++",
    "-isystem", "external/+_repo_rules+bazel_sysroot_library_and_libs_amd64/sysroot/include/c++/v1",
    # ... other include paths ...
]
```

## What's Included

The sysroot includes:
- GCC runtime libraries and its C++ Standard Library (libstdc++)
- Common C++ utility libraries (abseil-cpp)
- Text processing libraries (pcre, pcre2, re2)
- Compression libraries (zlib, bzip2, xz, zstd)
- XML and parsing libraries (libxml2, expat)
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

## Static Library Linker Scripts

An interesting discovery during the development of this sysroot is the distinction between static libraries and static library linker scripts:

### Static Libraries vs. Static Library Linker Scripts

1. **Most `.a` files are real static libraries**: In a typical sysroot, the vast majority of `.a` files are actual static libraries (ar archives) containing compiled object code. For example:
   - `libc.a` - The C standard library (real static library)
   - `libstdc++.a` - The C++ standard library (real static library)
   - `libz.a` - zlib compression library (real static library)

2. **A few `.a` files are linker scripts**: Some `.a` files are actually text files (linker scripts) that reference other libraries. For example:
   - `libm.a` - A linker script that references `libm-2.40.a` and `libmvec.a`

### Processing Static Library Linker Scripts

The sysroot build process includes special handling for static library linker scripts:

1. **Detection**: The build script identifies `.a` files that are actually text files (linker scripts) using the `file` command
2. **Path Resolution**: For each linker script, it extracts references to Nix store paths (e.g., `/nix/store/.../lib/libm-2.40.a`)
3. **Library Copying**: Referenced libraries are copied to the sysroot if they don't already exist
4. **Path Rewriting**: The linker script is rewritten to use relative paths instead of absolute Nix store paths

Example transformation:
```
Before: GROUP ( /nix/store/vaybwmwx0hh03jcsmzizq28xxrnnzhyb-glibc-2.40-66-static/lib/libm-2.40.a /nix/store/vaybwmwx0hh03jcsmzizq28xxrnnzhyb-glibc-2.40-66-static/lib/libmvec.a )
After:  GROUP ( lib/libm-2.40.a lib/libmvec.a )
```

### Why This Matters

This distinction is important for Bazel builds because:
- **Real static libraries** can be linked directly by Bazel
- **Static library linker scripts** need to be processed to ensure all referenced libraries are available and paths are relative
- **Mixed static/shared builds** can use real static libraries for core components and shared libraries for third-party dependencies

In this sysroot, out of 175 `.a` files, only 1 (`libm.a`) is a linker script, while the rest are real static libraries. This is typical for most sysroots.

## Static Library Availability in Nix Packages

Through systematic analysis of the Nix packages used in this sysroot, we discovered which packages contain static libraries:

### Packages with Static Libraries (17% of packages checked)

The following packages contain static libraries (`.a` files) that can be used for fully static builds:

- **Core System Libraries**: `glibc`, `glibc.dev`, `glibc.static`
- **GCC Runtime**: `libgcc`, `gcc-unwrapped`
- **Clang Libraries**: `libclang.lib`
- **Compression**: `zlib`, `zlib.dev`, `zlib.static`
- **Cryptography**: `boringssl`, `boringssl.dev`, `boringssl.out`
- **Image Processing**: `libpng`

### Packages Without Static Libraries

The majority of packages (83%) only provide shared libraries. These include:
- `bzip2`, `xz`, `zstd` (compression)
- `libxml2`, `expat` (XML parsing)
- `openssl`, `curl` (networking)
- `pcre`, `pcre2`, `re2` (text processing)
- `jansson` (JSON)
- `sqlite` (database)
- `libjpeg` (image processing)
- `util-linux` (system utilities)

### Implications for Static Linking

This discovery has important implications for our build strategy:

1. **Mixed Static/Shared Approach**: Since only 17% of packages have static libraries, a fully static build is not feasible for most applications. The current mixed approach (static core libraries + shared third-party libraries) is appropriate.

2. **Core Library Static Linking**: We can statically link core system libraries (glibc, libgcc, zlib) while using shared libraries for third-party dependencies.

3. **Future Considerations**: When new packages are added to the sysroot, we should check if they provide static libraries and update the build configuration accordingly.

### Discovery Methodology

We used a custom script (`find_static_libraries.bash`) that:
- Searches the Nix store for all versions of each package
- Checks for `.a` files in package `lib/` directories
- Distinguishes between real static libraries and linker scripts
- Provides a comprehensive report of static library availability

This analysis helps inform build decisions and ensures we're using the most appropriate linking strategy for each library.

## Usage

To use this sysroot in your Bazel project:

1. Build the sysroot:
   ```bash
   make copy
   ```

2. The sysroot will be created in `./sysroot/` with the following structure:
   ```
   sysroot/
   ├── include/   # Header files
   └── lib/       # Library files
       ├── *.so   # Linker scripts for shared libraries
       └── *.so.* # Versioned shared libraries
       └── *.a    # Static libraries

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
- Common C++ utility libraries (abseil-cpp)
- Compression libraries (zlib, bzip2, xz, zstd)
- XML and parsing libraries (libxml2, expat)
- Networking libraries (openssl, curl)
- Text processing libraries (pcre, pcre2, re2)
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
- **Note**: Most third-party libraries in this sysroot are provided as shared libraries. Static versions (`.a` files) are generally included only for core components like glibc, libstdc++, zlib, and OpenSSL.
- For shared libraries (represented by `.so` linker scripts in this sysroot), use the `shared_library` attribute.

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

### Linker Scripts and Static Libraries
Similar to shared libraries, some static libraries (`.a` files) can also be linker scripts rather than actual archive files. This is particularly common with Nix-built libraries:

1. **Static Library Linker Scripts**: Some `.a` files are actually linker scripts pointing to other static libraries:
   - `libm.a` might be a linker script pointing to `libm-2.40.a` and `libmvec.a`
   - These scripts often contain absolute paths to the Nix store (e.g., `/nix/store/.../lib/libm-2.40.a`)
   - We need to rewrite these scripts to use relative paths instead

2. **Static Library Dependencies**: The referenced static libraries may have their own dependencies:
   - They may reference other static libraries via absolute paths
   - We need to ensure all referenced static libraries are present in the sysroot
   - The referenced libraries must be copied from the Nix store to the sysroot

### How We Handle This
In our `default.nix`:
1. **For Shared Libraries**:
   - We copy the actual shared libraries (`.so.6` files)
   - We create our own linker scripts with relative paths
   - We ensure all required dependencies are present in the sysroot
   - We use `patchelf` to fix RPATH entries if needed

2. **For Static Libraries**:
   - We identify static library linker scripts (`.a` files that are text files)
   - We copy the referenced static libraries from the Nix store to the sysroot
   - We rewrite the linker scripts to use relative paths instead of Nix store paths
   - We ensure all referenced static libraries are present in the sysroot

This ensures that the sysroot is truly hermetic and doesn't depend on the Nix store or host system for both shared and static linking.

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

## Additional reading

(https://nixos.wiki/wiki/C)[https://nixos.wiki/wiki/C]

https://registry.bazel.build/modules/pkg-config
