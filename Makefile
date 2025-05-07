.PHONY: all clean test build

all: build

build:
	zig build

test:
	zig build test

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