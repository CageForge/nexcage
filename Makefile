# Proxmox LXC Runtime Interface - Makefile
# Enhanced with detailed test reporting

.PHONY: help build test test-unit test-e2e test-ci test-all clean install uninstall format lint check deps

# Default target
help:
	@echo "Nexcage OCI runetime - Available Commands:"
	@echo ""
	@echo "Build Commands:"
	@echo "  build          Build the project"
	@echo "  install        Install the binary"
	@echo "  uninstall      Uninstall the binary"
	@echo "  clean          Clean build artifacts"
	@echo ""
	@echo "Test Commands:"
	@echo "  test           Run all tests with detailed reporting"
	@echo "  test-unit      Run unit tests with detailed reporting"
	@echo "  test-e2e       Run E2E tests with detailed reporting"
	@echo "  test-proxmox   Run Proxmox only tests with detailed reporting"
	@echo "  test-ci        Run CI tests with detailed reporting"
	@echo "  test-all       Run all test suites with detailed reporting"
	@echo ""
	@echo "Development Commands:"
	@echo "  format         Format source code"
	@echo "  lint           Run linter checks"
	@echo "  check          Run all checks (format, lint, test)"
	@echo "  deps           Install dependencies"
	@echo ""
	@echo "Report Commands:"
	@echo "  report         Generate test report summary"
	@echo "  report-clean   Clean old test reports"
	@echo "  report-view    View latest test report"

# Build commands
build:
	@echo "🔨 Building project..."
	zig build
	@echo "✅ Build completed successfully"

install: build
	@echo "📦 Installing binary..."
	zig build install
	@echo "✅ Installation completed successfully"

uninstall:
	@echo "🗑️ Uninstalling binary..."
	rm -f /usr/local/bin/nexcage
	@echo "✅ Uninstallation completed successfully"

clean:
	@echo "🧹 Cleaning build artifacts..."
	rm -rf zig-out/
	rm -rf test-reports/
	@echo "✅ Cleanup completed successfully"

# Test commands
test: test-unit
	@echo "🧪 Running all tests with detailed reporting..."

test-unit:
	@echo "🧪 Running unit tests with detailed reporting..."
	@mkdir -p test-reports
	@chmod +x scripts/run_tests_with_report.sh
	@./scripts/run_tests_with_report.sh

test-e2e:
	@echo "🧪 Running E2E tests with detailed reporting..."
	@mkdir -p test-reports
	@chmod +x scripts/e2e_test_with_report.sh
	@./scripts/e2e_test_with_report.sh

test-proxmox:
	@echo "🧪 Running Proxmox only tests with detailed reporting..."
	@mkdir -p test-reports
	@chmod +x scripts/proxmox_only_test.sh
	@./scripts/proxmox_only_test.sh

test-ci:
	@echo "🧪 Running CI tests with detailed reporting..."
	@mkdir -p test-reports
	@chmod +x scripts/ci_test_with_report.sh
	@./scripts/ci_test_with_report.sh

test-all: test-unit test-e2e test-proxmox test-ci
	@echo "🧪 Running all test suites with detailed reporting..."

# Development commands
format:
	@echo "🎨 Formatting source code..."
	zig fmt src/
	zig fmt tests/
	@echo "✅ Formatting completed successfully"

lint:
	@echo "🔍 Running linter checks..."
	zig fmt --check src/
	zig fmt --check tests/
	@echo "✅ Linting completed successfully"

check: format lint test
	@echo "✅ All checks completed successfully"

deps:
	@echo "📦 Installing dependencies..."
	@echo "Installing system dependencies..."
	sudo apt-get update
	sudo apt-get install -y libcap-dev libseccomp-dev libyajl-dev
	@echo "✅ Dependencies installed successfully"

# Report commands
report:
	@echo "📊 Generating test report summary..."
	@mkdir -p test-reports
	@if [ -d "test-reports" ] && [ "$(ls -A test-reports)" ]; then \
		echo "## Test Report Summary - $(date)" > test-reports/summary.md; \
		echo "" >> test-reports/summary.md; \
		echo "### Available Reports:" >> test-reports/summary.md; \
		echo "" >> test-reports/summary.md; \
		ls -la test-reports/*.md | while read line; do \
			file=$$(echo $$line | awk '{print $$9}'); \
			size=$$(echo $$line | awk '{print $$5}'); \
			date=$$(echo $$line | awk '{print $$6, $$7, $$8}'); \
			echo "- **$$(basename $$file)**: $$size bytes ($$date)" >> test-reports/summary.md; \
		done; \
		echo "" >> test-reports/summary.md; \
		echo "### Latest Reports:" >> test-reports/summary.md; \
		echo "" >> test-reports/summary.md; \
		ls -t test-reports/*.md | head -5 | while read file; do \
			echo "#### $$(basename $$file)" >> test-reports/summary.md; \
			echo "" >> test-reports/summary.md; \
			head -20 "$$file" >> test-reports/summary.md; \
			echo "" >> test-reports/summary.md; \
			echo "---" >> test-reports/summary.md; \
			echo "" >> test-reports/summary.md; \
		done; \
		echo "📊 Report summary generated: test-reports/summary.md"; \
	else \
		echo "❌ No test reports found. Run 'make test' first."; \
	fi

report-clean:
	@echo "🧹 Cleaning old test reports..."
	@if [ -d "test-reports" ]; then \
		find test-reports -name "*.md" -mtime +7 -delete; \
		find test-reports -name "*.log" -mtime +7 -delete; \
		echo "✅ Old test reports cleaned successfully"; \
	else \
		echo "ℹ️ No test reports directory found"; \
	fi

report-view:
	@echo "📖 Viewing latest test report..."
	@if [ -d "test-reports" ] && [ "$(ls -A test-reports)" ]; then \
		latest_report=$$(ls -t test-reports/*.md | head -1); \
		echo "📄 Latest report: $$latest_report"; \
		echo ""; \
		cat "$$latest_report"; \
	else \
		echo "❌ No test reports found. Run 'make test' first."; \
	fi

# Special targets
.PHONY: help build test test-unit test-e2e test-ci test-all clean install uninstall format lint check deps report report-clean report-view

# Default target
.DEFAULT_GOAL := help