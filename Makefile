override SHELL := /bin/zsh
override MAKE := /usr/bin/make

override PROJECT_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
DART ?= $(shell command -v dart)
DART_APPKIT_ROOT ?= $(abspath $(PROJECT_ROOT)/../dart_appkit)
DART_ENGINE_ROOT ?= $(DART_APPKIT_ROOT)/.dart_tool/dart-engine/sdk
RUNTIME_ARCH ?= $(shell uname -m)
RUNTIME_BUILD_DIR ?= $(PROJECT_ROOT)/build/runtime
RUNTIME_ARGUMENTS ?=

override APPLICATION_MANIFEST := $(PROJECT_ROOT)/macos_application.json
override DEVELOPER_JIT_BUILD_DIR := \
	$(RUNTIME_BUILD_DIR)/$(RUNTIME_ARCH)/developer-jit
override RELEASE_AOT_BUILD_DIR := \
	$(RUNTIME_BUILD_DIR)/$(RUNTIME_ARCH)/release-aot
override DEVELOPER_JIT_BUNDLE := $(DEVELOPER_JIT_BUILD_DIR)/DartTerminal.app
override RELEASE_AOT_BUNDLE := $(RELEASE_AOT_BUILD_DIR)/DartTerminal.app
override RUNTIME_BUILDER := $(DART) run dart_macos_runtime:build \
	--manifest $(APPLICATION_MANIFEST) --engine-root $(DART_ENGINE_ROOT)
override INTEGRATION_TOOL := $(DART) run tool/runtime_integration_smoke.dart
override BUNDLE_AUDIT_TOOL := $(DART) run tool/dart_only_bundle_audit.dart
override PRODUCT_PARSER_BENCHMARK_DIR := $(PROJECT_ROOT)/build/benchmarks
override PRODUCT_PARSER_BENCHMARK := $(PRODUCT_PARSER_BENCHMARK_DIR)/product_parser_benchmark
override PRODUCT_DAMAGE_BENCHMARK := $(PRODUCT_PARSER_BENCHMARK_DIR)/product_damage_benchmark

.PHONY: help dependencies test compatibility-inventory compatibility-inventory-check \
	compatibility-manifest compatibility-manifest-check terminal-differential-contract-check \
	terminal-differential-adapters-check terminal-differential-corpus-check terminal-differential-evidence-check \
	product-parser-corpus product-parser-properties \
	product-parser-benchmark-build product-parser-benchmark vt-parser-table vt-parser-table-check \
	product-damage-benchmark-build product-damage-benchmark \
	runtime-source-check runtime-architecture-check \
	developer-jit-build developer-jit-run developer-jit-audit \
	developer-jit-integration developer-jit-display developer-jit-clipboard developer-jit-lifecycle developer-jit-traffic \
	developer-jit-resource developer-jit-shutdown-fault \
	release-aot-build release-aot-run release-aot-audit \
	release-aot-integration release-aot-display release-aot-clipboard release-aot-lifecycle release-aot-traffic \
	release-aot-resource release-aot-shutdown-fault runtime-bundle-audit \
	runtime-integration runtime-terminal-display-integration runtime-clipboard-integration runtime-lifecycle-integration \
	runtime-traffic-integration runtime-resource-integration \
	runtime-shutdown-fault-integration runtime-verify clean

help:
	@echo "Dart-only macOS application targets:"
	@echo "  make test                         Format, analyze, and unit-test Dart source"
	@echo "  make product-parser-corpus        Replay reviewed product parser fixtures"
	@echo "  make product-parser-properties    Run deterministic property and fuzz cases"
	@echo "  make product-parser-benchmark     Run the Release AOT 100 MiB/s parser gate"
	@echo "  make product-damage-benchmark     Run the Release AOT 100,000-cell damage gate"
	@echo "  make compatibility-inventory      Regenerate sequence inventory and summary"
	@echo "  make compatibility-inventory-check  Validate the terminal sequence/mode inventory"
	@echo "  make compatibility-manifest       Regenerate the implemented sequence manifest"
	@echo "  make compatibility-manifest-check Reject a stale implemented sequence manifest"
	@echo "  make terminal-differential-contract-check  Validate the bounded black-box driver contract"
	@echo "  make terminal-differential-adapters-check  Validate pinned comparators and capture evidence"
	@echo "  make terminal-differential-corpus-check  Validate reviewed Dart baseline observations"
	@echo "  make terminal-differential-evidence-check  Validate pinned external corpus evidence"
	@echo "  make vt-parser-table              Regenerate the Dart VT transition table"
	@echo "  make vt-parser-table-check        Reject a stale generated parser table"
	@echo "  make developer-jit-build          Build the generic-host JIT application"
	@echo "  make developer-jit-run            Build and run the JIT application"
	@echo "  make release-aot-build             Build the generic-host AOT application"
	@echo "  make release-aot-run               Build and run the AOT application"
	@echo "  make runtime-terminal-display-integration  Verify the live Metal terminal in both modes"
	@echo "  make runtime-clipboard-integration  Verify bounded Copy/Paste in both modes"
	@echo "  make runtime-verify                Audit and integration-test both modes"

dependencies:
	@cd $(PROJECT_ROOT) && $(DART) pub get

runtime-architecture-check:
	@if [[ "$(RUNTIME_ARCH)" != "arm64" && "$(RUNTIME_ARCH)" != "x86_64" ]]; then \
		echo "RUNTIME_ARCH must be arm64 or x86_64" >&2; exit 64; \
	fi
	@if [[ "$(RUNTIME_ARCH)" != "$$(uname -m)" ]]; then \
		echo "The generic builder currently builds the host architecture only" >&2; \
		exit 69; \
	fi

vt-parser-table:
	@cd $(PROJECT_ROOT) && $(DART) run tool/generate_vt_parser_table.dart

vt-parser-table-check:
	@cd $(PROJECT_ROOT) && $(DART) run tool/generate_vt_parser_table.dart --check

compatibility-inventory: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/generate_terminal_compatibility_inventory.dart
	@cd $(PROJECT_ROOT) && $(DART) run tool/generate_terminal_compatibility_summary.dart

compatibility-inventory-check: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/generate_terminal_compatibility_inventory.dart --check
	@cd $(PROJECT_ROOT) && $(DART) run tool/terminal_compatibility_inventory.dart --check
	@cd $(PROJECT_ROOT) && $(DART) run tool/generate_terminal_compatibility_summary.dart --check

compatibility-manifest: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/generate_terminal_compatibility_manifest.dart

compatibility-manifest-check: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/generate_terminal_compatibility_manifest.dart --check

terminal-differential-contract-check: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/terminal_differential_harness.dart --check

terminal-differential-adapters-check: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/terminal_differential_adapters.dart --check

terminal-differential-corpus-check: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/terminal_differential_corpus.dart --check

terminal-differential-evidence-check: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/terminal_differential_evidence.dart --check

test: dependencies vt-parser-table-check compatibility-inventory-check compatibility-manifest-check terminal-differential-contract-check terminal-differential-adapters-check terminal-differential-corpus-check terminal-differential-evidence-check
	@cd $(PROJECT_ROOT) && $(DART) format --output=none --set-exit-if-changed bin lib test tool
	@cd $(PROJECT_ROOT) && $(DART) analyze
	@cd $(PROJECT_ROOT) && $(DART) run test/run_tests.dart

product-parser-corpus: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/product_parser_corpus.dart

product-parser-properties: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run test/terminal_property_fuzz_test.dart

product-parser-benchmark-build: dependencies
	@mkdir -p $(PRODUCT_PARSER_BENCHMARK_DIR)
	@cd $(PROJECT_ROOT) && $(DART) compile exe tool/product_parser_benchmark.dart \
		-o $(PRODUCT_PARSER_BENCHMARK)

product-parser-benchmark: product-parser-benchmark-build
	@$(PRODUCT_PARSER_BENCHMARK)

product-damage-benchmark-build: dependencies
	@mkdir -p $(PRODUCT_PARSER_BENCHMARK_DIR)
	@cd $(PROJECT_ROOT) && $(DART) compile exe tool/terminal_damage_benchmark.dart \
		-o $(PRODUCT_DAMAGE_BENCHMARK)

product-damage-benchmark: product-damage-benchmark-build
	@$(PRODUCT_DAMAGE_BENCHMARK)

runtime-source-check: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/dart_only_source_audit.dart

developer-jit-build: runtime-architecture-check dependencies
	@cd $(PROJECT_ROOT) && $(RUNTIME_BUILDER) --mode developer-jit \
		--build-dir $(DEVELOPER_JIT_BUILD_DIR)

developer-jit-run: runtime-architecture-check dependencies
	@cd $(PROJECT_ROOT) && $(RUNTIME_BUILDER) --mode developer-jit \
		--build-dir $(DEVELOPER_JIT_BUILD_DIR) --run -- $(RUNTIME_ARGUMENTS)

developer-jit-audit: developer-jit-build
	@cd $(PROJECT_ROOT) && $(BUNDLE_AUDIT_TOOL) \
		--mode=developer-jit --architecture=$(RUNTIME_ARCH) $(DEVELOPER_JIT_BUNDLE)

developer-jit-integration: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=smoke $(DEVELOPER_JIT_BUNDLE)

developer-jit-display: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=display $(DEVELOPER_JIT_BUNDLE)

developer-jit-clipboard: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=clipboard $(DEVELOPER_JIT_BUNDLE)

developer-jit-lifecycle: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=lifecycle $(DEVELOPER_JIT_BUNDLE)

developer-jit-traffic: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=traffic $(DEVELOPER_JIT_BUNDLE)

developer-jit-resource: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=resource $(DEVELOPER_JIT_BUNDLE)

developer-jit-shutdown-fault: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=fault $(DEVELOPER_JIT_BUNDLE)

release-aot-build: runtime-architecture-check dependencies
	@cd $(PROJECT_ROOT) && $(RUNTIME_BUILDER) --mode release-aot \
		--build-dir $(RELEASE_AOT_BUILD_DIR)

release-aot-run: runtime-architecture-check dependencies
	@cd $(PROJECT_ROOT) && $(RUNTIME_BUILDER) --mode release-aot \
		--build-dir $(RELEASE_AOT_BUILD_DIR) --run -- $(RUNTIME_ARGUMENTS)

release-aot-audit: release-aot-build
	@cd $(PROJECT_ROOT) && $(BUNDLE_AUDIT_TOOL) \
		--mode=release-aot --architecture=$(RUNTIME_ARCH) $(RELEASE_AOT_BUNDLE)

release-aot-integration: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=smoke $(RELEASE_AOT_BUNDLE)

release-aot-display: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=display $(RELEASE_AOT_BUNDLE)

release-aot-clipboard: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=clipboard $(RELEASE_AOT_BUNDLE)

release-aot-lifecycle: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=lifecycle $(RELEASE_AOT_BUNDLE)

release-aot-traffic: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=traffic $(RELEASE_AOT_BUNDLE)

release-aot-resource: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=resource $(RELEASE_AOT_BUNDLE)

release-aot-shutdown-fault: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=fault $(RELEASE_AOT_BUNDLE)

runtime-bundle-audit: developer-jit-audit release-aot-audit

runtime-integration: developer-jit-integration release-aot-integration

runtime-terminal-display-integration: \
	developer-jit-display release-aot-display

runtime-clipboard-integration: \
	developer-jit-clipboard release-aot-clipboard

runtime-lifecycle-integration: developer-jit-lifecycle release-aot-lifecycle

runtime-traffic-integration: developer-jit-traffic release-aot-traffic

runtime-resource-integration: developer-jit-resource release-aot-resource

runtime-shutdown-fault-integration: \
	developer-jit-shutdown-fault release-aot-shutdown-fault

runtime-verify: test runtime-source-check runtime-bundle-audit \
	runtime-integration runtime-terminal-display-integration \
	runtime-clipboard-integration \
	runtime-lifecycle-integration \
	runtime-traffic-integration runtime-resource-integration \
	runtime-shutdown-fault-integration

clean:
	@echo "Build outputs are under $(RUNTIME_BUILD_DIR); remove them explicitly if needed."
