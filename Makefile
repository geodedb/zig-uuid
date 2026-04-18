# uuid - Zig Library Makefile
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2024-2025 CodePros

.PHONY: all build test test-unit test-integration clean check fmt help dev ci
.PHONY: test-release-safe test-release-fast test-release-small test-all-optimizations
.PHONY: pre-commit-install pre-commit pre-commit-run
.PHONY: cross-compile-required cross-compile
.PHONY: bench fuzz

# Default target: build and run tests
all: build test-unit
	@echo "✅ All builds and tests completed successfully!"

# Build the library (check + examples ensure all source compiles; the library is
# module-only and has no installable artifact separate from tests)
build:
	@echo "🔨 Building uuid..."
	@zig build check
	@zig build examples

# Run all tests
test: test-unit test-integration
	@echo "✅ All tests completed"

# Run unit tests only
test-unit:
	@echo "🧪 Running unit tests..."
	@zig build test --summary all

# Run integration tests only
test-integration:
	@echo "🔗 Running integration tests..."
	@zig build test-integration --summary all

# Clean build artifacts
clean:
	@echo "🧹 Cleaning build artifacts..."
	@rm -rf zig-cache zig-out .zig-cache

# Check for compilation errors (fast, no codegen)
check:
	@echo "🔍 Checking for compilation errors..."
	@zig build check

# Format source code
fmt:
	@echo "📝 Formatting code..."
	@zig fmt src/ tests/ examples/ build.zig

# Quick development iteration loop
dev: fmt check test-unit
	@echo "✅ Development checks passed"

# Full CI pipeline (clean slate)
ci: clean build test
	@echo "✅ CI pipeline passed"

# Release optimization level tests
test-release-safe:
	@echo "🧪 Testing with ReleaseSafe..."
	@zig build test -Doptimize=ReleaseSafe --summary all

test-release-fast:
	@echo "🧪 Testing with ReleaseFast..."
	@zig build test -Doptimize=ReleaseFast --summary all

test-release-small:
	@echo "🧪 Testing with ReleaseSmall..."
	@zig build test -Doptimize=ReleaseSmall --summary all

test-all-optimizations: test-unit test-release-safe test-release-fast test-release-small
	@echo "✅ All optimization levels passed"

# Cross-compilation: invoke `zig build -Dtarget=<triple>` for each required
# target. Previously build.zig had a dedicated `check-cross` step that
# iterated targets, but that step created per-target modules rooted at
# src/root.zig and caused duplicate-module diamond errors in downstream
# consumers. Driving cross checks from the Makefile keeps each build in its
# own process with its own build-graph state.
cross-compile-required:
	@echo "🔀 Cross-compile check for required targets..."
	@for t in x86_64-linux aarch64-linux x86_64-macos aarch64-macos x86_64-windows; do \
	    echo "  -> $$t"; \
	    zig build -Dtarget=$$t || exit 1; \
	done
	@echo "✅ All cross-compile targets pass"

cross-compile: cross-compile-required

# Run benchmarks in ReleaseFast mode (QC-61)
bench:
	@echo "Running benchmarks..."
	@zig build bench -Doptimize=ReleaseFast

# Run coverage-guided fuzz tests locally (QC-59, QC-61).
# Press Ctrl+C to stop; crashes are written to zig-out/fuzz/.
fuzz:
	@echo "Running fuzz tests (Ctrl+C to stop)..."
	@zig build test --fuzz

# Pre-commit hook management
pre-commit-install:
	@echo "📦 Installing pre-commit hooks..."
	@pre-commit install
	@pre-commit install --hook-type commit-msg
	@pre-commit install --hook-type pre-push

pre-commit:
	@echo "🔍 Running pre-commit checks..."
	@pre-commit run --all-files

pre-commit-run: pre-commit

# Display help
help:
	@echo "uuid - Zig Library"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Development:"
	@echo "  all                  Build and run tests (default)"
	@echo "  build                Build the library"
	@echo "  dev                  Quick iteration: fmt + check + test"
	@echo "  ci                   Full CI: clean + build + test"
	@echo ""
	@echo "Testing:"
	@echo "  test                 Run all tests"
	@echo "  test-unit            Run unit tests only"
	@echo "  test-integration     Run integration tests only"
	@echo "  test-release-safe    Test with ReleaseSafe"
	@echo "  test-release-fast    Test with ReleaseFast"
	@echo "  test-release-small   Test with ReleaseSmall"
	@echo "  test-all-optimizations  Test all optimization levels"
	@echo "  bench                Run benchmarks (ReleaseFast)"
	@echo "  fuzz                 Run coverage-guided fuzz tests (Ctrl+C to stop)"
	@echo ""
	@echo "Code Quality:"
	@echo "  fmt                  Format source code"
	@echo "  check                Check for compilation errors"
	@echo "  pre-commit           Run pre-commit hooks"
	@echo "  pre-commit-install   Install pre-commit hooks"
	@echo ""
	@echo "Cross-compilation:"
	@echo "  cross-compile-required  Check required targets (x86_64/aarch64 linux/macos, x86_64-windows)"
	@echo "  cross-compile           Alias for cross-compile-required"
	@echo ""
	@echo "Maintenance:"
	@echo "  clean                Remove build artifacts"
	@echo "  help                 Show this help message"
