#
# Makefile
#

.PHONY: help update-flake build tarball push update-all nix-tarball clean copy generate-build

# Default target
help:
	@echo "Available targets:"
	@echo "  update-flake  - Update flake.lock with latest dependencies"
	@echo "  build        - Build the sysroot using Nix"
	@echo "  generate-build - Generate BUILD.bazel from sysroot contents"
	@echo "  tarball      - Create a tarball of the sysroot"
	@echo "  push         - Push the tarball to a remote location"
	@echo "  update-all   - Update flake and rebuild"
	@echo "  nix-tarball  - Create a tarball using Nix"
	@echo "  clean        - Clean build artifacts"
	@echo "  copy         - Copy the sysroot to a local directory"

update-flake:
	nix flake update

build:
	# Add -L to see build logs if it fails, or use build_debug for more verbose output
	nix build -L --max-jobs 100

build_debug:
	nix build -L --max-jobs 100 -vv
#nix --max-jobs 100 -vvv build

# Create tarball using nix
nix-tarball:
	nix build .#tarball
	cp result/bazel-sysroot-library.tar.gz .

# Create tarball directly from the sysroot
tarball:
	tar -czf bazel-sysroot-library.tar.gz sysroot/

# Copy files from Nix store to sysroot directory
copy: build
	rm -rf sysroot
	mkdir -p sysroot
	rsync -av result/sysroot/ sysroot/

	echo "Setting permissions on the sysroot files"
	chmod -R 755 sysroot
	chown -R $(shell id -u):$(shell id -g) sysroot

	echo "Updating the sysroot file list"
	find ./sysroot > sysroot_file_list.txt

	echo "Update the BUILD.bazel file"
	$(MAKE) generate-build

push:
	git add .
	git commit -m "Update common library sysroot $(shell date +%Y-%m-%d)" || true
	git remote set-url origin git@github.com:randomizedcoder/bazel_sysroot_library.git
	git push

update-all: update-flake build copy push

clean:
	rm -f bazel-sysroot-library.tar.gz
	rm -rf result result-*
	rm -rf sysroot

generate-build:
	@echo "Generating BUILD.bazel..."
	./generate_build_bazel.sh > ./sysroot/BUILD.bazel

shellcheck:
	nix-shell -p shellcheck --run "shellcheck ./generate_build_bazel.sh"

# Show help by default
.DEFAULT_GOAL := help

# end