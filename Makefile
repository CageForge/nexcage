# nexcage - Makefile
#
# Thin wrappers around zig build. The default build is Proxmox LXC only.

PREFIX ?= /usr/local
ZIG ?= zig

.PHONY: help build release test install uninstall clean format lint check deb crun-docker crun-headers docs-serve docs-build
.DEFAULT_GOAL := help

help:
	@echo "nexcage - available targets:"
	@echo ""
	@echo "  build         Debug build (zig-out/bin/nexcage)"
	@echo "  release       ReleaseSafe build"
	@echo "  test          Run the unit tests (zig build test)"
	@echo "  install       Install to \$$(PREFIX)/bin (default /usr/local/bin)"
	@echo "  uninstall     Remove the installed binary"
	@echo "  clean         Remove build outputs"
	@echo "  format        zig fmt src/ tests/"
	@echo "  lint          zig fmt --check src/ tests/"
	@echo "  check         lint + test"
	@echo "  deb           Build dist/nexcage-<version>-amd64.deb"
	@echo "  crun-docker   Build the opt-in crun backend in Docker"
	@echo "  crun-headers  Generate vendored crun headers in Docker"
	@echo "  docs-serve    Serve the docs locally (Docker mkdocs)"
	@echo "  docs-build    Build the docs site (Docker mkdocs)"

build:
	$(ZIG) build

release:
	$(ZIG) build -Doptimize=ReleaseSafe

test:
	$(ZIG) build test --summary all

install: release
	install -D -m 0755 zig-out/bin/nexcage $(DESTDIR)$(PREFIX)/bin/nexcage

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/nexcage

clean:
	rm -rf zig-out/ .zig-cache/ dist/

format:
	$(ZIG) fmt src/ tests/

lint:
	$(ZIG) fmt --check src/ tests/

check: lint test

deb:
	bash scripts/build_deb_local.sh

# The crun backend needs the deps/crun submodules plus generated headers;
# the Dockerfile does all of it from a clean clone.
crun-docker:
	docker build --build-arg BUILD_FLAGS=-Denable-backend-crun=true -t nexcage:crun .

crun-headers:
	bash scripts/gen_crun_headers_docker.sh

docs-serve:
	bash scripts/mkdocs_serve.sh

docs-build:
	bash scripts/mkdocs_build.sh
