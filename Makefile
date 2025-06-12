#
# Makefile
#

.PHONY: help update-flake build tarball push update-all nix-tarball clean copy

# Default target
help:
	@echo "Available targets:"
	@echo "  update-flake  - Update flake.lock with latest dependencies"
	@echo "  build        - Build the common library sysroot using nix build"
	@echo "  tarball      - Create a .tar.gz archive of the common library sysroot"
	@echo "  push         - Push changes to GitHub with dated commit"
	@echo "  update-all   - Update flake, build, copy, and push"
	@echo "  nix-tarball  - Create a .tar.gz archive of the common library sysroot using nix"
	@echo "  copy         - Copy files from Nix store to sysroot directory"
	@echo "  clean        - Clean up build artifacts"
	@echo "  help         - Show this help message"

update-flake:
	nix flake update

build:
	nix build

build_debug:
	nix --max-jobs 100 -vv build
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

# Show help by default
.DEFAULT_GOAL := help

# end