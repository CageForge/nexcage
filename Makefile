.PHONY: all build test clean install uninstall proto

all: proto build test

build:
	zig build -Drelease-safe

build-debug:
	zig build -Drelease-debug

test:
	zig test src/test.zig

clean:
	rm -rf zig-cache zig-out
	rm -f proxmox-lxcri.log test.log error.log

proto:
	protoc --zig_out=. --grpc-zig_out=. proto/runtime_service.proto

install:
	sudo ./scripts/install.sh

uninstall:
	sudo systemctl stop proxmox-lxcri || true
	sudo systemctl disable proxmox-lxcri || true
	sudo rm -f /etc/systemd/system/proxmox-lxcri.service
	sudo rm -f /usr/local/bin/proxmox-lxcri
	sudo rm -rf /etc/proxmox-lxcri
	sudo systemctl daemon-reload

format:
	find src -name "*.zig" -exec zig fmt {} \;

check:
	zig build test
	zig fmt --check src/*.zig

run:
	zig build run

dev: build-debug run 