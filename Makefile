override SHELL := /bin/zsh
override MAKE := /usr/bin/make

override PROJECT_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
DART ?= $(shell command -v dart)
DART_APPKIT_ROOT ?= $(abspath $(PROJECT_ROOT)/../dart_appkit)
DART_ENGINE_ROOT ?= $(DART_APPKIT_ROOT)/.dart_tool/dart-engine/sdk
RUNTIME_ARCH ?= $(shell uname -m)
RUNTIME_BUILD_DIR ?= $(PROJECT_ROOT)/build/runtime
RUNTIME_ARGUMENTS ?=
MACOSX_DEPLOYMENT_TARGET ?= 14.0

override CLANG := $(shell xcrun --find clang)
override CLANGXX := $(shell xcrun --find clang++)
override SDKROOT := $(shell xcrun --sdk macosx --show-sdk-path)
override PRODUCT_NATIVE_TEST_BUILD_DIR := $(PROJECT_ROOT)/build/native-tests
override PRODUCT_NATIVE_WARNINGS := -Wall -Wextra -Wpedantic -Werror
override PRODUCT_NATIVE_FLAGS := $(PRODUCT_NATIVE_WARNINGS) \
	-fvisibility=hidden -isysroot $(SDKROOT) \
	-mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET)
override DPTY_CHILD_OBJECT := \
	$(PRODUCT_NATIVE_TEST_BUILD_DIR)/dpty_exec_child.o
override DPTY_SPAWN_OBJECT := \
	$(PRODUCT_NATIVE_TEST_BUILD_DIR)/dpty_spawn.o
override DPTY_SESSION_OBJECT := \
	$(PRODUCT_NATIVE_TEST_BUILD_DIR)/dpty_session.o
override DPTY_LIBRARY := \
	$(PRODUCT_NATIVE_TEST_BUILD_DIR)/libdart_pty_macos.dylib
override DPTY_TEST_BINARY := \
	$(PRODUCT_NATIVE_TEST_BUILD_DIR)/dart_pty_macos_tests

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

.PHONY: help dependencies test dpty-contract-check dpty-child-audit \
	dpty-native-test dpty-dart-test \
	compatibility-inventory compatibility-inventory-check \
	compatibility-manifest compatibility-manifest-check terminal-differential-contract-check \
	terminal-differential-adapters-check terminal-differential-corpus-check terminal-differential-evidence-check \
	terminal-differential-acceptance-check terminal-application-matrix-contract-check terminal-application-evidence-check terminal-application-acceptance-check \
	terminal-terminfo terminal-terminfo-check \
	terminal-shell-integration terminal-shell-integration-check \
	product-parser-corpus product-parser-properties phase9-protocol-properties phase9-security-stress \
	product-parser-benchmark-build product-parser-benchmark vt-parser-table vt-parser-table-check \
	terminal-parser-trace terminal-parser-trace-check \
	configuration-reference configuration-reference-check \
	keybind-action-reference keybind-action-reference-check \
	phase7-appkit-acceptance phase7-appkit-acceptance-check \
	terminal-compatibility-regressions-check terminal-compatibility-regression-coverage terminal-compatibility-regression-coverage-check \
	product-damage-benchmark-build product-damage-benchmark \
	runtime-source-check runtime-architecture-check \
	developer-jit-build developer-jit-run developer-jit-audit \
	developer-jit-integration developer-jit-display developer-jit-hierarchy developer-jit-actions developer-jit-applescript developer-jit-system-automation developer-jit-native-content developer-jit-quick-terminal developer-jit-secure-keyboard-entry developer-jit-configuration developer-jit-theme developer-jit-shell-integration developer-jit-desktop-signals developer-jit-osc52 developer-jit-restoration developer-jit-clipboard developer-jit-lifecycle developer-jit-traffic \
	developer-jit-resource developer-jit-shutdown-fault \
	release-aot-build release-aot-run release-aot-audit \
	release-aot-integration release-aot-display release-aot-hierarchy release-aot-actions release-aot-applescript release-aot-system-automation release-aot-native-content release-aot-quick-terminal release-aot-secure-keyboard-entry release-aot-configuration release-aot-theme release-aot-shell-integration release-aot-desktop-signals release-aot-osc52 release-aot-restoration release-aot-clipboard release-aot-lifecycle release-aot-traffic \
	release-aot-resource release-aot-shutdown-fault runtime-bundle-audit \
	runtime-integration runtime-terminal-display-integration runtime-native-hierarchy-integration runtime-user-actions-integration runtime-applescript-integration runtime-system-automation-integration runtime-native-content-integration runtime-quick-terminal-integration runtime-secure-keyboard-entry-integration runtime-configuration-integration runtime-theme-integration runtime-shell-integration runtime-desktop-signals-integration runtime-osc52-integration runtime-restoration-integration runtime-clipboard-integration runtime-lifecycle-integration \
	runtime-traffic-integration runtime-resource-integration \
	runtime-shutdown-fault-integration runtime-verify clean

help:
	@echo "Dart-only macOS application targets:"
	@echo "  make test                         Format, analyze, and unit-test Dart source"
	@echo "  make dpty-native-test             Test the product-owned PTY native asset"
	@echo "  make dpty-dart-test               Test its Dart facade and build-hook asset"
	@echo "  make product-parser-corpus        Replay reviewed product parser fixtures"
	@echo "  make product-parser-properties    Run deterministic property and fuzz cases"
	@echo "  make phase9-protocol-properties   Run deterministic modern-protocol properties"
	@echo "  make phase9-security-stress       Stress modern authority and resource bounds"
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
	@echo "  make terminal-differential-acceptance-check  Validate classified differential results"
	@echo "  make terminal-application-matrix-contract-check  Validate the real-application matrix contract"
	@echo "  make terminal-application-evidence-check  Validate pinned real-application evidence"
	@echo "  make terminal-application-acceptance-check  Validate classified real-application results"
	@echo "  make terminal-terminfo             Regenerate the pinned compiled terminfo entry"
	@echo "  make terminal-terminfo-check       Reject stale or over-advertised terminfo resources"
	@echo "  make terminal-shell-integration    Regenerate shell integration resource hashes"
	@echo "  make terminal-shell-integration-check  Reject stale shell integration resources"
	@echo "  make vt-parser-table              Regenerate the Dart VT transition table"
	@echo "  make vt-parser-table-check        Reject a stale generated parser table"
	@echo "  make terminal-parser-trace        Regenerate the bounded parser trace"
	@echo "  make terminal-parser-trace-check  Reject a stale parser trace fixture"
	@echo "  make configuration-reference      Regenerate configuration/CLI documentation"
	@echo "  make configuration-reference-check  Reject stale configuration/CLI documentation"
	@echo "  make keybind-action-reference     Regenerate keybinding/action documentation"
	@echo "  make keybind-action-reference-check  Reject stale keybinding/action documentation"
	@echo "  make phase7-appkit-acceptance    Regenerate the Phase 7 AppKit test inventory"
	@echo "  make phase7-appkit-acceptance-check  Reject stale Phase 7 AppKit test evidence"
	@echo "  make terminal-compatibility-regressions-check  Replay byte-level compatibility fixes"
	@echo "  make terminal-compatibility-regression-coverage  Regenerate Phase 6 coverage reconciliation"
	@echo "  make terminal-compatibility-regression-coverage-check  Reject stale or incomplete reconciliation"
	@echo "  make developer-jit-build          Build the generic-host JIT application"
	@echo "  make developer-jit-run            Build and run the JIT application"
	@echo "  make release-aot-build             Build the generic-host AOT application"
	@echo "  make release-aot-run               Build and run the AOT application"
	@echo "  make runtime-terminal-display-integration  Verify the live Metal terminal in both modes"
	@echo "  make runtime-native-hierarchy-integration  Verify four-pane hierarchy and Close/Quit in both modes"
	@echo "  make runtime-user-actions-integration  Verify normal-product window/tab/split actions in both modes"
	@echo "  make runtime-native-content-integration  Verify Quick Look, Services, drops, and context actions in both modes"
	@echo "  make runtime-quick-terminal-integration  Verify Quick Terminal in both modes"
	@echo "  make runtime-secure-keyboard-entry-integration  Verify Secure Keyboard Entry in both modes"
	@echo "  make runtime-configuration-integration  Verify configured product projection in both modes"
	@echo "  make runtime-theme-integration  Verify theme and system appearance in both modes"
	@echo "  make runtime-shell-integration  Verify bundled zsh integration and disablement in both modes"
	@echo "  make runtime-desktop-signals-integration  Verify bounded desktop signals in both modes"
	@echo "  make runtime-osc52-integration     Verify bounded OSC 52 policy and confirmation in both modes"
	@echo "  make runtime-restoration-integration  Verify fullscreen, migration, restoration, and reopen in both modes"
	@echo "  make runtime-clipboard-integration  Verify bounded Copy/Paste in both modes"
	@echo "  make runtime-verify                Audit and integration-test both modes"

dependencies:
	@cd $(PROJECT_ROOT) && $(DART) pub get

dpty-contract-check:
	@$(CLANG) $(PRODUCT_NATIVE_FLAGS) -std=c11 \
		-I$(PROJECT_ROOT)/packages/dart_pty_macos/native -fsyntax-only \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/test/header_compile.c
	@$(CLANGXX) $(PRODUCT_NATIVE_FLAGS) -std=c++20 \
		-I$(PROJECT_ROOT)/packages/dart_pty_macos/native -fsyntax-only \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/test/header_compile.cc

$(DPTY_CHILD_OBJECT): \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/PtyExecChild.c \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/PtySpawnInternal.h
	@mkdir -p $(PRODUCT_NATIVE_TEST_BUILD_DIR)
	$(CLANG) $(PRODUCT_NATIVE_FLAGS) -std=c11 -c \
		-I$(PROJECT_ROOT)/packages/dart_pty_macos/native $< -o $@

$(DPTY_SPAWN_OBJECT): \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/PtySpawn.c \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/PtySpawnInternal.h \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/dart_pty_macos.h
	@mkdir -p $(PRODUCT_NATIVE_TEST_BUILD_DIR)
	$(CLANG) $(PRODUCT_NATIVE_FLAGS) -std=c11 -c \
		-I$(PROJECT_ROOT)/packages/dart_pty_macos/native $< -o $@

$(DPTY_SESSION_OBJECT): \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/PtySession.cc \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/PtySpawnInternal.h \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/dart_pty_macos.h
	@mkdir -p $(PRODUCT_NATIVE_TEST_BUILD_DIR)
	$(CLANGXX) $(PRODUCT_NATIVE_FLAGS) -std=c++20 -pthread -c \
		-I$(PROJECT_ROOT)/packages/dart_pty_macos/native $< -o $@

dpty-child-audit: $(DPTY_CHILD_OBJECT)
	@$(DART) $(PROJECT_ROOT)/packages/dart_pty_macos/tool/audit_pty_child.dart $<

$(DPTY_LIBRARY): $(DPTY_CHILD_OBJECT) $(DPTY_SPAWN_OBJECT) \
		$(DPTY_SESSION_OBJECT)
	$(CLANGXX) $(PRODUCT_NATIVE_FLAGS) -std=c++20 -pthread -dynamiclib \
		$(DPTY_SESSION_OBJECT) $(DPTY_SPAWN_OBJECT) $(DPTY_CHILD_OBJECT) \
		-Wl,-install_name,@rpath/libdart_pty_macos.dylib -o $@

$(DPTY_TEST_BINARY): \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/test/PtyCapabilityTests.cc \
		$(PROJECT_ROOT)/packages/dart_pty_macos/native/dart_pty_macos.h
	@mkdir -p $(PRODUCT_NATIVE_TEST_BUILD_DIR)
	$(CLANGXX) $(PRODUCT_NATIVE_FLAGS) -std=c++20 -pthread \
		-I$(PROJECT_ROOT)/packages/dart_pty_macos/native $< -o $@

dpty-native-test: dpty-contract-check dpty-child-audit $(DPTY_LIBRARY) \
		$(DPTY_TEST_BINARY)
	@$(DPTY_TEST_BINARY) $(DPTY_LIBRARY)

dpty-dart-test:
	@cd $(PROJECT_ROOT)/packages/dart_pty_macos && $(DART) pub get
	@cd $(PROJECT_ROOT)/packages/dart_pty_macos && $(DART) analyze
	@cd $(PROJECT_ROOT)/packages/dart_pty_macos && \
		$(DART) run test/run_tests.dart

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

terminal-parser-trace: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/terminal_parser_trace.dart --generate

terminal-parser-trace-check: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/terminal_parser_trace.dart --check

configuration-reference: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/generate_configuration_reference.dart --generate

configuration-reference-check: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/generate_configuration_reference.dart --check

keybind-action-reference: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/generate_keybind_action_reference.dart --generate

keybind-action-reference-check: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/generate_keybind_action_reference.dart --check

phase7-appkit-acceptance: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/phase7_appkit_acceptance.dart --generate

phase7-appkit-acceptance-check: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/phase7_appkit_acceptance.dart --check

terminal-compatibility-regressions-check: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/terminal_compatibility_regressions.dart --check

terminal-compatibility-regression-coverage: dependencies terminal-compatibility-regressions-check
	@cd $(PROJECT_ROOT) && $(DART) run tool/terminal_compatibility_regression_coverage.dart --generate

terminal-compatibility-regression-coverage-check: dependencies terminal-compatibility-regressions-check
	@cd $(PROJECT_ROOT) && $(DART) run tool/terminal_compatibility_regression_coverage.dart --check

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

terminal-differential-acceptance-check: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/terminal_differential_acceptance.dart --check

terminal-application-matrix-contract-check: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/terminal_application_matrix.dart --check

terminal-application-evidence-check: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/terminal_application_evidence.dart --check

terminal-application-acceptance-check: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/terminal_application_acceptance.dart --check

terminal-terminfo: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/terminal_terminfo.dart --generate

terminal-terminfo-check: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/terminal_terminfo.dart --check

terminal-shell-integration: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/terminal_shell_integration.dart --generate

terminal-shell-integration-check: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/terminal_shell_integration.dart --check

test: dependencies dpty-native-test dpty-dart-test vt-parser-table-check terminal-parser-trace-check configuration-reference-check keybind-action-reference-check phase7-appkit-acceptance-check terminal-compatibility-regression-coverage-check compatibility-inventory-check compatibility-manifest-check terminal-differential-contract-check terminal-differential-adapters-check terminal-differential-corpus-check terminal-differential-evidence-check terminal-differential-acceptance-check terminal-application-matrix-contract-check terminal-application-evidence-check terminal-application-acceptance-check terminal-terminfo-check terminal-shell-integration-check
	@cd $(PROJECT_ROOT) && $(DART) format --output=none --set-exit-if-changed bin lib test tool
	@cd $(PROJECT_ROOT) && $(DART) analyze
	@cd $(PROJECT_ROOT) && $(DART) run test/run_tests.dart

product-parser-corpus: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/product_parser_corpus.dart

product-parser-properties: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run test/terminal_property_fuzz_test.dart

phase9-protocol-properties: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run test/terminal_phase9_protocol_property_test.dart

phase9-security-stress: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run test/terminal_phase9_security_stress_test.dart

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

developer-jit-hierarchy: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=hierarchy $(DEVELOPER_JIT_BUNDLE)

developer-jit-actions: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=actions $(DEVELOPER_JIT_BUNDLE)

developer-jit-applescript: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=applescript $(DEVELOPER_JIT_BUNDLE)

developer-jit-system-automation: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=system-automation $(DEVELOPER_JIT_BUNDLE)

developer-jit-native-content: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=native-content $(DEVELOPER_JIT_BUNDLE)

developer-jit-quick-terminal: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=quick-terminal $(DEVELOPER_JIT_BUNDLE)

developer-jit-secure-keyboard-entry: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=secure-keyboard-entry $(DEVELOPER_JIT_BUNDLE)

developer-jit-configuration: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=configuration $(DEVELOPER_JIT_BUNDLE)

developer-jit-theme: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=theme $(DEVELOPER_JIT_BUNDLE)

developer-jit-shell-integration: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=shell-integration $(DEVELOPER_JIT_BUNDLE)

developer-jit-desktop-signals: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=desktop-signals $(DEVELOPER_JIT_BUNDLE)

developer-jit-osc52: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=osc52 $(DEVELOPER_JIT_BUNDLE)

developer-jit-restoration: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=restoration $(DEVELOPER_JIT_BUNDLE)

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

release-aot-hierarchy: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=hierarchy $(RELEASE_AOT_BUNDLE)

release-aot-actions: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=actions $(RELEASE_AOT_BUNDLE)

release-aot-applescript: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=applescript $(RELEASE_AOT_BUNDLE)

release-aot-system-automation: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=system-automation $(RELEASE_AOT_BUNDLE)

release-aot-native-content: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=native-content $(RELEASE_AOT_BUNDLE)

release-aot-quick-terminal: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=quick-terminal $(RELEASE_AOT_BUNDLE)

release-aot-secure-keyboard-entry: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=secure-keyboard-entry $(RELEASE_AOT_BUNDLE)

release-aot-configuration: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=configuration $(RELEASE_AOT_BUNDLE)

release-aot-theme: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=theme $(RELEASE_AOT_BUNDLE)

release-aot-shell-integration: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=shell-integration $(RELEASE_AOT_BUNDLE)

release-aot-desktop-signals: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=desktop-signals $(RELEASE_AOT_BUNDLE)

release-aot-osc52: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=osc52 $(RELEASE_AOT_BUNDLE)

release-aot-restoration: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=restoration $(RELEASE_AOT_BUNDLE)

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

runtime-native-hierarchy-integration: \
	developer-jit-hierarchy release-aot-hierarchy

runtime-user-actions-integration: \
	developer-jit-actions release-aot-actions

runtime-applescript-integration: \
	developer-jit-applescript release-aot-applescript

runtime-system-automation-integration: \
	developer-jit-system-automation release-aot-system-automation

runtime-native-content-integration: \
	developer-jit-native-content release-aot-native-content

runtime-quick-terminal-integration: \
	developer-jit-quick-terminal release-aot-quick-terminal

runtime-secure-keyboard-entry-integration: \
	developer-jit-secure-keyboard-entry release-aot-secure-keyboard-entry

runtime-configuration-integration: \
	developer-jit-configuration release-aot-configuration

runtime-theme-integration: developer-jit-theme release-aot-theme

runtime-shell-integration: \
	developer-jit-shell-integration release-aot-shell-integration

runtime-desktop-signals-integration: \
	developer-jit-desktop-signals release-aot-desktop-signals

runtime-osc52-integration: developer-jit-osc52 release-aot-osc52

runtime-restoration-integration: \
	developer-jit-restoration release-aot-restoration

runtime-clipboard-integration: \
	developer-jit-clipboard release-aot-clipboard

runtime-lifecycle-integration: developer-jit-lifecycle release-aot-lifecycle

runtime-traffic-integration: developer-jit-traffic release-aot-traffic

runtime-resource-integration: developer-jit-resource release-aot-resource

runtime-shutdown-fault-integration: \
	developer-jit-shutdown-fault release-aot-shutdown-fault

runtime-verify: test runtime-source-check runtime-bundle-audit \
	runtime-integration runtime-terminal-display-integration \
	runtime-native-hierarchy-integration \
	runtime-user-actions-integration \
	runtime-applescript-integration \
	runtime-system-automation-integration \
	runtime-native-content-integration \
	runtime-quick-terminal-integration \
	runtime-secure-keyboard-entry-integration \
	runtime-configuration-integration \
	runtime-theme-integration \
	runtime-shell-integration \
	runtime-desktop-signals-integration \
	runtime-osc52-integration \
	runtime-restoration-integration \
	runtime-clipboard-integration \
	runtime-lifecycle-integration \
	runtime-traffic-integration runtime-resource-integration \
	runtime-shutdown-fault-integration

clean:
	@echo "Build outputs are under $(RUNTIME_BUILD_DIR); remove them explicitly if needed."
