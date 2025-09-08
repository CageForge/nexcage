.PHONY: all clean test build download_zig

all: build

build:
	zig build

test:
	zig build test

download_zig:
	@if [ ! -f "./zig/zig" ]; then \
		echo "Downloading Zig compiler..."; \
		chmod +x ./zig/download.sh; \
		./zig/download.sh; \
	else \
		echo "Zig compiler already downloaded."; \
	fi

clean:
	rm -rf zig-cache zig-out

install:
	zig build install

uninstall:
	zig build uninstall

format:
	find src -name "*.zig" -exec zig fmt {} \;

check:
	zig build test
	zig fmt --check src/*.zig

run:
	zig build run

dev: build-debug run 