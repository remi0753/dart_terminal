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
override SWIFTC := $(shell xcrun --find swiftc)
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
override PRODUCT_APPKIT_BRIDGE_HEADERS := \
	$(DART_APPKIT_ROOT)/native/bridge/include/dart_appkit.h \
	$(DART_APPKIT_ROOT)/native/bridge/include/dart_appkit_custom_view.h \
	$(DART_APPKIT_ROOT)/native/bridge/include/dart_appkit_native_extension.h \
	$(DART_APPKIT_ROOT)/native/bridge/src/AppKitObjects.h \
	$(DART_APPKIT_ROOT)/native/bridge/src/BridgeInternal.h \
	$(DART_APPKIT_ROOT)/native/bridge/src/CustomViewRegistry.h \
	$(DART_APPKIT_ROOT)/native/bridge/src/ObjectRegistry.h
override PRODUCT_APPKIT_BRIDGE_SOURCES := \
	$(DART_APPKIT_ROOT)/native/bridge/src/AppKitBridge.mm \
	$(DART_APPKIT_ROOT)/native/bridge/src/CustomViewRegistry.mm \
	$(DART_APPKIT_ROOT)/native/bridge/src/EventSink.mm \
	$(DART_APPKIT_ROOT)/native/bridge/src/ObjectRegistry.mm \
	$(DART_APPKIT_ROOT)/native/bridge/src/TextView.mm
override PRODUCT_OBJCXX_FLAGS := $(PRODUCT_NATIVE_FLAGS) -std=c++20 \
	-fobjc-arc -fblocks
override PRODUCT_APPKIT_LIBS := -framework AppKit -framework CoreFoundation \
	-framework UserNotifications -framework UniformTypeIdentifiers \
	-framework Carbon
override TERMINAL_RENDERER_PLUGIN_LIBRARY := \
	$(PRODUCT_NATIVE_TEST_BUILD_DIR)/libdart_terminal_renderer_macos.dylib
override TERMINAL_RENDERER_TEST_BINARY := \
	$(PRODUCT_NATIVE_TEST_BUILD_DIR)/terminal_renderer_capability_tests
override TERMINAL_RENDERER_SHADER_SOURCE := \
	$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native/TerminalShaders.metal
override TERMINAL_RENDERER_SHADER_LIBRARY := \
	$(PRODUCT_NATIVE_TEST_BUILD_DIR)/TerminalShaders.metallib
override TERMINAL_APPLESCRIPT_PLUGIN_LIBRARY := \
	$(PRODUCT_NATIVE_TEST_BUILD_DIR)/libdart_terminal_applescript_macos.dylib
override TERMINAL_APPLESCRIPT_TEST_OBJECT := \
	$(PRODUCT_NATIVE_TEST_BUILD_DIR)/terminal_applescript_plugin_test.o
override TERMINAL_APPLESCRIPT_TEST_BINARY := \
	$(PRODUCT_NATIVE_TEST_BUILD_DIR)/terminal_applescript_capability_tests
override TERMINAL_APP_INTENTS_LIBRARY := \
	$(PRODUCT_NATIVE_TEST_BUILD_DIR)/libdart_terminal_app_intents_macos.dylib
override TERMINAL_APP_INTENTS_TEST_BINARY := \
	$(PRODUCT_NATIVE_TEST_BUILD_DIR)/terminal_app_intents_capability_tests
override TERMINAL_APP_INTENTS_PERFORM_TEST_BINARY := \
	$(PRODUCT_NATIVE_TEST_BUILD_DIR)/terminal_app_intents_perform_tests
override TERMINAL_APP_INTENTS_MODULE_CACHE := \
	$(PRODUCT_NATIVE_TEST_BUILD_DIR)/terminal_app_intents_module_cache

override APPLICATION_MANIFEST := $(PROJECT_ROOT)/macos_application.json
override DEVELOPER_JIT_BUILD_DIR := \
	$(RUNTIME_BUILD_DIR)/$(RUNTIME_ARCH)/developer-jit
override RELEASE_AOT_BUILD_DIR := \
	$(RUNTIME_BUILD_DIR)/$(RUNTIME_ARCH)/release-aot
override DEVELOPER_JIT_BUNDLE := $(DEVELOPER_JIT_BUILD_DIR)/DartTerminal.app
override RELEASE_AOT_BUNDLE := $(RELEASE_AOT_BUILD_DIR)/DartTerminal.app
override ARM64_RELEASE_AOT_BUILD_DIR := \
	$(RUNTIME_BUILD_DIR)/arm64/release-aot
override X86_64_RELEASE_AOT_BUILD_DIR := \
	$(RUNTIME_BUILD_DIR)/x86_64/release-aot
override UNIVERSAL_RELEASE_AOT_BUILD_DIR := \
	$(RUNTIME_BUILD_DIR)/universal/release-aot
override ARM64_RELEASE_AOT_BUNDLE := \
	$(ARM64_RELEASE_AOT_BUILD_DIR)/DartTerminal.app
override X86_64_RELEASE_AOT_BUNDLE := \
	$(X86_64_RELEASE_AOT_BUILD_DIR)/DartTerminal.app
override UNIVERSAL_RELEASE_AOT_BUNDLE := \
	$(UNIVERSAL_RELEASE_AOT_BUILD_DIR)/DartTerminal.app
DISTRIBUTION_OUTPUT_DIR ?= $(PROJECT_ROOT)/build/runtime/distribution
DISTRIBUTION_ENTITLEMENTS ?= \
	$(PROJECT_ROOT)/resources/DartTerminal.entitlements
DEVELOPER_ID_APPLICATION ?=
DEVELOPER_TEAM_ID ?=
NOTARY_KEYCHAIN_PROFILE ?=
UPDATE_FEED_OUTPUT_DIR ?= $(PROJECT_ROOT)/build/runtime/update-feed
UPDATE_ARCHIVE ?= $(DISTRIBUTION_OUTPUT_DIR)/DartTerminal.zip
UPDATE_ARCHIVE_URL ?=
UPDATE_VERSION ?=
UPDATE_BUILD ?=
UPDATE_MINIMUM_MACOS ?= 14.0
UPDATE_SEQUENCE ?=
UPDATE_EXPIRES_UNIX_SECONDS ?=
UPDATE_KEY_ID ?=
UPDATE_PUBLIC_KEY ?=
UPDATE_SIGNING_KEY ?=
RELEASE_SYMBOLS_OUTPUT_DIR ?= \
	$(PROJECT_ROOT)/build/runtime/release-symbols
override RUNTIME_BUILDER := $(DART) run dart_macos_runtime:build \
	--manifest $(APPLICATION_MANIFEST) --engine-root $(DART_ENGINE_ROOT)
override RUNTIME_UNIVERSAL_ASSEMBLER := \
	$(DART) run dart_macos_runtime:universal
override RUNTIME_DISTRIBUTION_PUBLISHER := \
	$(DART) run dart_macos_runtime:distribute
override INTEGRATION_TOOL := $(DART) run tool/runtime_integration_smoke.dart
override BUNDLE_AUDIT_TOOL := $(DART) run tool/dart_only_bundle_audit.dart
override TERMINAL_DISTRIBUTION_POLICY_TOOL := \
	$(DART) run tool/terminal_distribution_policy.dart
override PRODUCT_PARSER_BENCHMARK_DIR := $(PROJECT_ROOT)/build/benchmarks
override PRODUCT_PARSER_BENCHMARK := $(PRODUCT_PARSER_BENCHMARK_DIR)/product_parser_benchmark
override PRODUCT_DAMAGE_BENCHMARK := $(PRODUCT_PARSER_BENCHMARK_DIR)/product_damage_benchmark
override PRODUCT_PERFORMANCE_BENCHMARK := $(PRODUCT_PARSER_BENCHMARK_DIR)/product_performance_benchmark
override PRODUCT_PERFORMANCE_BASELINE := $(PROJECT_ROOT)/benchmark/baselines/product-micro-macos-arm64-m1.json
override PRODUCT_PERFORMANCE_COMPARATOR_EVIDENCE := $(PROJECT_ROOT)/benchmark/evidence/ghostty-performance-comparator-macos-arm64-m1.json
override PRODUCT_RELATIVE_PERFORMANCE_EVIDENCE := $(PROJECT_ROOT)/benchmark/evidence/product-relative-performance-macos-arm64-m1.json
override PRODUCT_PERFORMANCE_MICRO_RESULT := $(PRODUCT_PARSER_BENCHMARK_DIR)/product-performance-micro-result.json
override PRODUCT_PERFORMANCE_RUNTIME_RESULT := $(PRODUCT_PARSER_BENCHMARK_DIR)/product-performance-runtime-result.log
override PRODUCT_PERFORMANCE_AGGREGATE_RESULT := $(PRODUCT_PARSER_BENCHMARK_DIR)/product-performance-regression-result.json

.PHONY: help dependencies test dpty-contract-check dpty-child-audit \
	dpty-native-test dpty-dart-test \
	terminal-renderer-contract-check terminal-renderer-native-test \
	terminal-renderer-dart-test \
	terminal-applescript-contract-check terminal-applescript-native-test \
	terminal-applescript-dart-test \
	terminal-app-intents-contract-check terminal-app-intents-native-test \
	terminal-app-intents-dart-test \
	compatibility-inventory compatibility-inventory-check \
	compatibility-manifest compatibility-manifest-check terminal-differential-contract-check \
	terminal-differential-adapters-check terminal-differential-corpus-check terminal-differential-evidence-check \
	terminal-differential-acceptance-check terminal-application-matrix-contract-check terminal-application-evidence-check terminal-application-acceptance-check \
	terminal-terminfo terminal-terminfo-check \
	terminal-shell-integration terminal-shell-integration-check \
	ghostty-p0-p1-gap-inventory ghostty-p0-p1-gap-inventory-check ghostty-p0-p1-gap-closure \
	product-parser-corpus product-parser-properties phase9-protocol-properties phase9-security-stress \
	product-native-sanitizer product-fault-injection product-sanitizer-fuzz-fault-gate \
	product-parser-benchmark-build product-parser-benchmark vt-parser-table vt-parser-table-check \
	terminal-parser-trace terminal-parser-trace-check \
	configuration-reference configuration-reference-check \
	keybind-action-reference keybind-action-reference-check \
	terminal-localization-check terminal-diagnostics-privacy-check \
	phase7-appkit-acceptance phase7-appkit-acceptance-check \
	terminal-compatibility-regressions-check terminal-compatibility-regression-coverage terminal-compatibility-regression-coverage-check \
	product-damage-benchmark-build product-damage-benchmark \
	product-performance-benchmark-build product-performance-benchmark \
	product-performance-comparator-check product-performance-regression-gate \
	runtime-source-check runtime-architecture-check \
	developer-jit-build developer-jit-run developer-jit-audit \
	developer-jit-integration developer-jit-display developer-jit-hierarchy developer-jit-performance developer-jit-reliability developer-jit-actions developer-jit-applescript developer-jit-system-automation developer-jit-native-content developer-jit-quick-terminal developer-jit-secure-keyboard-entry developer-jit-diagnostics developer-jit-configuration developer-jit-theme developer-jit-shell-integration developer-jit-desktop-signals developer-jit-osc52 developer-jit-restoration developer-jit-clipboard developer-jit-lifecycle developer-jit-traffic \
	developer-jit-resource developer-jit-shutdown-fault \
	release-aot-build release-aot-run release-aot-audit \
	release-aot-arm64-build release-aot-x86_64-build release-aot-thin-builds \
	release-aot-universal-build release-aot-arm64-audit release-aot-x86_64-audit \
	release-aot-universal-audit release-aot-distribution-audit \
	release-aot-arm64-integration release-aot-x86_64-integration \
	release-aot-universal-integration release-aot-distribution-integration \
	release-aot-distribution-verify \
	terminal-distribution-policy-test release-distribution-preflight \
	release-distribution-credentials-check release-distribution-build \
	release-distribution-audit release-distribution-verify \
	terminal-update-feed-test terminal-update-transaction-test terminal-update-controller-test terminal-release-symbols-test terminal-incident-service-test release-update-feed-credentials-check \
	release-update-feed \
	release-aot-symbols \
	release-aot-integration release-aot-display release-aot-hierarchy release-aot-performance release-aot-reliability release-aot-actions release-aot-applescript release-aot-system-automation release-aot-native-content release-aot-quick-terminal release-aot-secure-keyboard-entry release-aot-diagnostics release-aot-configuration release-aot-theme release-aot-shell-integration release-aot-desktop-signals release-aot-osc52 release-aot-restoration release-aot-clipboard release-aot-lifecycle release-aot-traffic \
	release-aot-resource release-aot-shutdown-fault runtime-bundle-audit \
	runtime-integration runtime-terminal-display-integration runtime-native-hierarchy-integration runtime-product-performance-integration runtime-bounded-reliability-integration runtime-user-actions-integration runtime-applescript-integration runtime-system-automation-integration runtime-native-content-integration runtime-quick-terminal-integration runtime-secure-keyboard-entry-integration runtime-diagnostics-integration runtime-configuration-integration runtime-theme-integration runtime-shell-integration runtime-desktop-signals-integration runtime-osc52-integration runtime-restoration-integration runtime-clipboard-integration runtime-lifecycle-integration \
	runtime-traffic-integration runtime-resource-integration \
	runtime-shutdown-fault-integration runtime-verify clean

help:
	@echo "Dart-only macOS application targets:"
	@echo "  make test                         Format, analyze, and unit-test Dart source"
	@echo "  make dpty-native-test             Test the product-owned PTY native asset"
	@echo "  make dpty-dart-test               Test its Dart facade and build-hook asset"
	@echo "  make terminal-renderer-native-test  Test the product renderer capability"
	@echo "  make terminal-renderer-dart-test  Test its Dart facade and build-hook asset"
	@echo "  make terminal-applescript-native-test  Test the product scripting capability"
	@echo "  make terminal-applescript-dart-test  Test its Dart facade and build-hook asset"
	@echo "  make terminal-app-intents-native-test  Test the product App Intents capability"
	@echo "  make terminal-app-intents-dart-test  Test its Dart facade and metadata"
	@echo "  make product-parser-corpus        Replay reviewed product parser fixtures"
	@echo "  make product-parser-properties    Run deterministic property and fuzz cases"
	@echo "  make phase9-protocol-properties   Run deterministic modern-protocol properties"
	@echo "  make phase9-security-stress       Stress modern authority and resource bounds"
	@echo "  make product-native-sanitizer     Run isolated ASan/UBSan native capability gates"
	@echo "  make product-fault-injection      Run bounded native/Dart ownership recovery faults"
	@echo "  make product-sanitizer-fuzz-fault-gate  Run the complete bounded safety/recovery gate"
	@echo "  make product-parser-benchmark     Run the Release AOT 100 MiB/s parser gate"
	@echo "  make product-damage-benchmark     Run the Release AOT 100,000-cell damage gate"
	@echo "  make product-performance-benchmark  Run product microbenchmarks against the M1 baseline"
	@echo "  make product-performance-comparator-check  Validate pinned Ghostty relative evidence"
	@echo "  make product-performance-regression-gate  Run the complete Release AOT performance gate"
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
	@echo "  make ghostty-p0-p1-gap-inventory  Regenerate the pinned P0/P1 gap inventory"
	@echo "  make ghostty-p0-p1-gap-inventory-check  Reject stale pinned P0/P1 gap evidence"
	@echo "  make ghostty-p0-p1-gap-closure  Run ordinary and two-mode product parity closure"
	@echo "  make vt-parser-table              Regenerate the Dart VT transition table"
	@echo "  make vt-parser-table-check        Reject a stale generated parser table"
	@echo "  make terminal-parser-trace        Regenerate the bounded parser trace"
	@echo "  make terminal-parser-trace-check  Reject a stale parser trace fixture"
	@echo "  make configuration-reference      Regenerate configuration/CLI documentation"
	@echo "  make configuration-reference-check  Reject stale configuration/CLI documentation"
	@echo "  make keybind-action-reference     Regenerate keybinding/action documentation"
	@echo "  make keybind-action-reference-check  Reject stale keybinding/action documentation"
	@echo "  make terminal-localization-check    Reject static UI leaks and incomplete resources"
	@echo "  make terminal-diagnostics-privacy-check  Reject diagnostics schema/source privacy expansion"
	@echo "  make phase7-appkit-acceptance    Regenerate the Phase 7 AppKit test inventory"
	@echo "  make phase7-appkit-acceptance-check  Reject stale Phase 7 AppKit test evidence"
	@echo "  make terminal-compatibility-regressions-check  Replay byte-level compatibility fixes"
	@echo "  make terminal-compatibility-regression-coverage  Regenerate Phase 6 coverage reconciliation"
	@echo "  make terminal-compatibility-regression-coverage-check  Reject stale or incomplete reconciliation"
	@echo "  make developer-jit-build          Build the generic-host JIT application"
	@echo "  make developer-jit-run            Build and run the JIT application"
	@echo "  make release-aot-build             Build the generic-host AOT application"
	@echo "  make release-aot-run               Build and run the AOT application"
	@echo "  make release-aot-thin-builds       Build arm64 and x86_64 thin AOT applications"
	@echo "  make release-aot-universal-build   Assemble both thin applications as Universal"
	@echo "  make release-aot-distribution-verify  Audit and smoke-test all release architectures"
	@echo "  make release-distribution-preflight  Validate product signing policy without credentials"
	@echo "  make release-distribution-verify     Sign, notarize, staple, and audit a distribution"
	@echo "  make terminal-update-feed-test       Test canonical signed update feeds and release generation"
	@echo "  make terminal-update-transaction-test  Test candidate validation and rollback recovery"
	@echo "  make terminal-update-controller-test  Test update actions, status, and release-note UI"
	@echo "  make release-update-feed             Generate and sign an atomic update-feed directory"
	@echo "  make terminal-release-symbols-test   Test bounded symbol packaging and publication"
	@echo "  make release-aot-symbols             Package UUID-verified symbols for the host AOT app"
	@echo "  make terminal-incident-service-test  Test local report export and current-process sampling"
	@echo "  make runtime-terminal-display-integration  Verify the live Metal terminal in both modes"
	@echo "  make runtime-native-hierarchy-integration  Verify four-pane hierarchy and Close/Quit in both modes"
	@echo "  make runtime-product-performance-integration  Gate latency, resources, and memory-pressure recovery"
	@echo "  make runtime-bounded-reliability-integration  Repeat bounded system recovery in both modes"
	@echo "  make runtime-user-actions-integration  Verify normal-product window/tab/split actions in both modes"
	@echo "  make runtime-native-content-integration  Verify Quick Look, Services, drops, and context actions in both modes"
	@echo "  make runtime-quick-terminal-integration  Verify Quick Terminal in both modes"
	@echo "  make runtime-secure-keyboard-entry-integration  Verify Secure Keyboard Entry in both modes"
	@echo "  make runtime-diagnostics-integration  Verify inspector and diagnostics export in both modes"
	@echo "  make runtime-configuration-integration  Verify configured product projection in both modes"
	@echo "  make runtime-theme-integration  Verify theme and system appearance in both modes"
	@echo "  make runtime-shell-integration  Verify bundled zsh integration and disablement in both modes"
	@echo "  make runtime-desktop-signals-integration  Verify bounded desktop signals in both modes"
	@echo "  make runtime-osc52-integration     Verify bounded OSC 52 policy and confirmation in both modes"
	@echo "  make runtime-restoration-integration  Verify fullscreen, system recovery, restoration, and reopen in both modes"
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
	$(CLANGXX) $(PRODUCT_NATIVE_FLAGS) -std=c++20 -pthread -DDPTY_TESTING -c \
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
	$(CLANGXX) $(PRODUCT_NATIVE_FLAGS) -std=c++20 -pthread -DDPTY_TESTING \
		-I$(PROJECT_ROOT)/packages/dart_pty_macos/native $< -o $@

dpty-native-test: dpty-contract-check dpty-child-audit $(DPTY_LIBRARY) \
		$(DPTY_TEST_BINARY)
	@$(DPTY_TEST_BINARY) $(DPTY_LIBRARY)

dpty-dart-test:
	@cd $(PROJECT_ROOT)/packages/dart_pty_macos && $(DART) pub get
	@cd $(PROJECT_ROOT)/packages/dart_pty_macos && $(DART) analyze
	@cd $(PROJECT_ROOT)/packages/dart_pty_macos && \
		$(DART) run test/run_tests.dart

terminal-renderer-contract-check:
	@$(CLANG) $(PRODUCT_NATIVE_FLAGS) -std=c11 \
		-I$(DART_APPKIT_ROOT)/native/bridge/include \
		-I$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native \
		-fsyntax-only \
		$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native/test/header_compile.c
	@$(CLANGXX) $(PRODUCT_NATIVE_FLAGS) -std=c++20 \
		-I$(DART_APPKIT_ROOT)/native/bridge/include \
		-I$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native \
		-fsyntax-only \
		$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native/test/header_compile.cc

$(TERMINAL_RENDERER_SHADER_LIBRARY): $(TERMINAL_RENDERER_SHADER_SOURCE)
	@mkdir -p $(PRODUCT_NATIVE_TEST_BUILD_DIR)
	xcrun -sdk macosx metal -target air64-apple-macos14.0 $< -o $@

$(TERMINAL_RENDERER_PLUGIN_LIBRARY): $(TERMINAL_RENDERER_SHADER_LIBRARY) \
		$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native/TerminalRendererPlugin.h \
		$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native/TerminalRendererPlugin.m \
		$(DART_APPKIT_ROOT)/native/bridge/include/dart_appkit.h \
		$(DART_APPKIT_ROOT)/native/bridge/include/dart_appkit_native_extension.h
	@mkdir -p $(PRODUCT_NATIVE_TEST_BUILD_DIR)
	$(CLANG) $(PRODUCT_NATIVE_FLAGS) -fobjc-arc -fblocks -dynamiclib \
		-I$(DART_APPKIT_ROOT)/native/bridge/include \
		-I$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native \
		$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native/TerminalRendererPlugin.m \
		-framework AppKit -framework CoreText -framework Metal -framework MetalKit \
		-Wl,-sectcreate,__DATA,__dtrlib,$(TERMINAL_RENDERER_SHADER_LIBRARY) \
		-Wl,-install_name,@rpath/libdart_terminal_renderer_macos.dylib -o $@

$(TERMINAL_RENDERER_TEST_BINARY): $(PRODUCT_APPKIT_BRIDGE_HEADERS) \
		$(PRODUCT_APPKIT_BRIDGE_SOURCES) \
		$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native/TerminalRendererPlugin.h \
		$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native/test/TerminalRendererCapabilityTests.mm
	@mkdir -p $(PRODUCT_NATIVE_TEST_BUILD_DIR)
	$(CLANGXX) $(PRODUCT_OBJCXX_FLAGS) \
		-I$(DART_APPKIT_ROOT)/native/bridge/include \
		-I$(DART_APPKIT_ROOT)/native/bridge/src \
		-I$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native \
		$(PRODUCT_APPKIT_BRIDGE_SOURCES) \
		$(PROJECT_ROOT)/packages/dart_terminal_renderer_macos/native/test/TerminalRendererCapabilityTests.mm \
		$(PRODUCT_APPKIT_LIBS) -framework Metal -framework MetalKit -o $@

terminal-renderer-native-test: terminal-renderer-contract-check \
		$(TERMINAL_RENDERER_PLUGIN_LIBRARY) $(TERMINAL_RENDERER_TEST_BINARY)
	@$(TERMINAL_RENDERER_TEST_BINARY) $(TERMINAL_RENDERER_PLUGIN_LIBRARY)

terminal-renderer-dart-test:
	@cd $(PROJECT_ROOT)/packages/dart_terminal_renderer_macos && $(DART) pub get
	@cd $(PROJECT_ROOT)/packages/dart_terminal_renderer_macos && $(DART) analyze
	@cd $(PROJECT_ROOT)/packages/dart_terminal_renderer_macos && \
		$(DART) run test/run_tests.dart

terminal-applescript-contract-check:
	@$(CLANG) $(PRODUCT_NATIVE_FLAGS) -std=c11 \
		-I$(DART_APPKIT_ROOT)/native/bridge/include \
		-I$(PROJECT_ROOT)/packages/dart_terminal_applescript_macos/native \
		-fsyntax-only \
		$(PROJECT_ROOT)/packages/dart_terminal_applescript_macos/native/test/header_compile.c
	@$(CLANGXX) $(PRODUCT_NATIVE_FLAGS) -std=c++20 \
		-I$(DART_APPKIT_ROOT)/native/bridge/include \
		-I$(PROJECT_ROOT)/packages/dart_terminal_applescript_macos/native \
		-fsyntax-only \
		$(PROJECT_ROOT)/packages/dart_terminal_applescript_macos/native/test/header_compile.cc
	@/usr/bin/xmllint --noout --valid \
		$(PROJECT_ROOT)/packages/dart_terminal_applescript_macos/native/DartTerminal.sdef

$(TERMINAL_APPLESCRIPT_PLUGIN_LIBRARY): \
		$(PROJECT_ROOT)/packages/dart_terminal_applescript_macos/native/TerminalAppleScriptPlugin.h \
		$(PROJECT_ROOT)/packages/dart_terminal_applescript_macos/native/TerminalAppleScriptPlugin.m \
		$(DART_APPKIT_ROOT)/native/bridge/include/dart_appkit.h \
		$(DART_APPKIT_ROOT)/native/bridge/include/dart_appkit_native_extension.h
	@mkdir -p $(PRODUCT_NATIVE_TEST_BUILD_DIR)
	$(CLANG) $(PRODUCT_NATIVE_FLAGS) -fobjc-arc -fblocks -dynamiclib \
		-I$(DART_APPKIT_ROOT)/native/bridge/include \
		-I$(PROJECT_ROOT)/packages/dart_terminal_applescript_macos/native \
		$(PROJECT_ROOT)/packages/dart_terminal_applescript_macos/native/TerminalAppleScriptPlugin.m \
		-framework AppKit -framework Foundation \
		-Wl,-install_name,@rpath/libdart_terminal_applescript_macos.dylib -o $@

$(TERMINAL_APPLESCRIPT_TEST_OBJECT): \
		$(PROJECT_ROOT)/packages/dart_terminal_applescript_macos/native/TerminalAppleScriptPlugin.h \
		$(PROJECT_ROOT)/packages/dart_terminal_applescript_macos/native/TerminalAppleScriptPlugin.m
	@mkdir -p $(PRODUCT_NATIVE_TEST_BUILD_DIR)
	$(CLANG) $(PRODUCT_NATIVE_FLAGS) -fobjc-arc -fblocks -DDTAS_TESTING \
		-I$(DART_APPKIT_ROOT)/native/bridge/include \
		-I$(PROJECT_ROOT)/packages/dart_terminal_applescript_macos/native \
		-c $(PROJECT_ROOT)/packages/dart_terminal_applescript_macos/native/TerminalAppleScriptPlugin.m \
		-o $@

$(TERMINAL_APPLESCRIPT_TEST_BINARY): \
		$(TERMINAL_APPLESCRIPT_TEST_OBJECT) \
		$(PROJECT_ROOT)/packages/dart_terminal_applescript_macos/native/test/TerminalAppleScriptCapabilityTests.mm
	@mkdir -p $(PRODUCT_NATIVE_TEST_BUILD_DIR)
	$(CLANGXX) $(PRODUCT_OBJCXX_FLAGS) -DDTAS_TESTING \
		-I$(DART_APPKIT_ROOT)/native/bridge/include \
		-I$(PROJECT_ROOT)/packages/dart_terminal_applescript_macos/native \
		$(PROJECT_ROOT)/packages/dart_terminal_applescript_macos/native/test/TerminalAppleScriptCapabilityTests.mm \
		$(TERMINAL_APPLESCRIPT_TEST_OBJECT) \
		-framework AppKit -framework Foundation -o $@

terminal-applescript-native-test: terminal-applescript-contract-check \
		$(TERMINAL_APPLESCRIPT_PLUGIN_LIBRARY) \
		$(TERMINAL_APPLESCRIPT_TEST_BINARY)
	@$(TERMINAL_APPLESCRIPT_TEST_BINARY)

terminal-applescript-dart-test:
	@cd $(PROJECT_ROOT)/packages/dart_terminal_applescript_macos && $(DART) pub get
	@cd $(PROJECT_ROOT)/packages/dart_terminal_applescript_macos && $(DART) analyze
	@cd $(PROJECT_ROOT)/packages/dart_terminal_applescript_macos && \
		$(DART) run test/run_tests.dart
	@cd $(PROJECT_ROOT)/packages/dart_terminal_applescript_macos && \
		$(DART) run test/native_asset_test.dart

terminal-app-intents-contract-check:
	@$(CLANG) $(PRODUCT_NATIVE_FLAGS) -std=c11 \
		-I$(PROJECT_ROOT)/packages/dart_terminal_app_intents_macos/native \
		-fsyntax-only \
		$(PROJECT_ROOT)/packages/dart_terminal_app_intents_macos/native/test/header_compile.c
	@$(CLANGXX) $(PRODUCT_NATIVE_FLAGS) -std=c++20 \
		-I$(PROJECT_ROOT)/packages/dart_terminal_app_intents_macos/native \
		-fsyntax-only \
		$(PROJECT_ROOT)/packages/dart_terminal_app_intents_macos/native/test/header_compile.cc

$(TERMINAL_APP_INTENTS_LIBRARY): \
		$(PROJECT_ROOT)/packages/dart_terminal_app_intents_macos/native/TerminalAppIntents.swift
	@mkdir -p $(PRODUCT_NATIVE_TEST_BUILD_DIR) $(TERMINAL_APP_INTENTS_MODULE_CACHE)
	$(SWIFTC) -parse-as-library -swift-version 6 -warnings-as-errors \
		-target $(RUNTIME_ARCH)-apple-macos$(MACOSX_DEPLOYMENT_TARGET) \
		-sdk $(SDKROOT) -module-cache-path $(TERMINAL_APP_INTENTS_MODULE_CACHE) \
		-emit-library -module-name DartTerminalAppIntents \
		-Xlinker -install_name \
		-Xlinker @rpath/libdart_terminal_app_intents_macos.dylib \
		-o $@ $<

$(TERMINAL_APP_INTENTS_TEST_BINARY): \
		$(TERMINAL_APP_INTENTS_LIBRARY) \
		$(PROJECT_ROOT)/packages/dart_terminal_app_intents_macos/native/TerminalAppIntents.h \
		$(PROJECT_ROOT)/packages/dart_terminal_app_intents_macos/native/test/TerminalAppIntentsCapabilityTests.cc
	@mkdir -p $(PRODUCT_NATIVE_TEST_BUILD_DIR)
	$(CLANGXX) $(PRODUCT_NATIVE_FLAGS) -std=c++20 \
		-I$(PROJECT_ROOT)/packages/dart_terminal_app_intents_macos/native \
		$(PROJECT_ROOT)/packages/dart_terminal_app_intents_macos/native/test/TerminalAppIntentsCapabilityTests.cc \
		$(TERMINAL_APP_INTENTS_LIBRARY) \
		-Wl,-rpath,$(PRODUCT_NATIVE_TEST_BUILD_DIR) -o $@

$(TERMINAL_APP_INTENTS_PERFORM_TEST_BINARY): \
		$(PROJECT_ROOT)/packages/dart_terminal_app_intents_macos/native/TerminalAppIntents.swift \
		$(PROJECT_ROOT)/packages/dart_terminal_app_intents_macos/native/test/TerminalAppIntentsPerformTests.swift
	@mkdir -p $(PRODUCT_NATIVE_TEST_BUILD_DIR) $(TERMINAL_APP_INTENTS_MODULE_CACHE)
	$(SWIFTC) -parse-as-library -swift-version 6 -warnings-as-errors \
		-target $(RUNTIME_ARCH)-apple-macos$(MACOSX_DEPLOYMENT_TARGET) \
		-sdk $(SDKROOT) -module-cache-path $(TERMINAL_APP_INTENTS_MODULE_CACHE) \
		-module-name DartTerminalAppIntentsPerformTests $^ -o $@

terminal-app-intents-native-test: terminal-app-intents-contract-check \
		$(TERMINAL_APP_INTENTS_TEST_BINARY) \
		$(TERMINAL_APP_INTENTS_PERFORM_TEST_BINARY)
	@$(TERMINAL_APP_INTENTS_TEST_BINARY)
	@$(TERMINAL_APP_INTENTS_PERFORM_TEST_BINARY)

terminal-app-intents-dart-test: $(TERMINAL_APP_INTENTS_LIBRARY)
	@cd $(PROJECT_ROOT)/packages/dart_terminal_app_intents_macos && $(DART) pub get
	@cd $(PROJECT_ROOT)/packages/dart_terminal_app_intents_macos && $(DART) analyze
	@cd $(PROJECT_ROOT)/packages/dart_terminal_app_intents_macos && \
		$(DART) run test/run_tests.dart $(TERMINAL_APP_INTENTS_LIBRARY)

runtime-architecture-check:
	@if [[ "$(RUNTIME_ARCH)" != "arm64" && "$(RUNTIME_ARCH)" != "x86_64" ]]; then \
		echo "RUNTIME_ARCH must be arm64 or x86_64" >&2; exit 64; \
	fi
	@if [[ "$(RUNTIME_ARCH)" != "$$(uname -m)" ]]; then \
		echo "This target requires the host architecture; use the explicit release distribution targets for cross-builds" >&2; \
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

ghostty-p0-p1-gap-inventory: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/ghostty_p0_p1_gap_inventory.dart --generate

ghostty-p0-p1-gap-inventory-check: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/ghostty_p0_p1_gap_inventory.dart --check

ghostty-p0-p1-gap-closure:
	@$(MAKE) test
	@$(MAKE) RUNTIME_ARCH=$(RUNTIME_ARCH) runtime-terminal-display-integration
	@echo "GHOSTTY_P0_P1_GAP_CLOSURE_PASS ordinary=true runtime_modes=2"

terminal-localization-check: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/terminal_localization_audit.dart

terminal-diagnostics-privacy-check: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/terminal_diagnostics_privacy_audit.dart

test: dependencies dpty-native-test dpty-dart-test terminal-renderer-native-test terminal-renderer-dart-test terminal-applescript-native-test terminal-applescript-dart-test terminal-app-intents-native-test terminal-app-intents-dart-test vt-parser-table-check terminal-parser-trace-check configuration-reference-check keybind-action-reference-check terminal-localization-check terminal-diagnostics-privacy-check phase7-appkit-acceptance-check terminal-compatibility-regression-coverage-check compatibility-inventory-check compatibility-manifest-check terminal-differential-contract-check terminal-differential-adapters-check terminal-differential-corpus-check terminal-differential-evidence-check terminal-differential-acceptance-check terminal-application-matrix-contract-check terminal-application-evidence-check terminal-application-acceptance-check terminal-terminfo-check terminal-shell-integration-check ghostty-p0-p1-gap-inventory-check terminal-distribution-policy-test
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

product-native-sanitizer: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run tool/native_sanitizer_gate.dart

product-fault-injection: dependencies dpty-native-test
	@cd $(PROJECT_ROOT) && $(DART) run test/terminal_reply_test.dart
	@cd $(PROJECT_ROOT) && $(DART) run test/terminal_kitty_graphics_controller_test.dart
	@cd $(PROJECT_ROOT) && $(DART) run test/metal_failure_recovery_test.dart
	@echo "PRODUCT_FAULT_INJECTION_PASS native_boundaries=1 dart_boundaries=3"

product-sanitizer-fuzz-fault-gate:
	@$(MAKE) test
	@$(MAKE) product-parser-properties
	@$(MAKE) product-native-sanitizer
	@$(MAKE) product-fault-injection
	@$(MAKE) RUNTIME_ARCH=$(RUNTIME_ARCH) runtime-shutdown-fault-integration
	@echo "PRODUCT_SANITIZER_FUZZ_FAULT_PASS native_suites=4 native_artifacts=9 fuzz_executions=1296 fault_boundaries=4 runtime_modes=2"

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

product-performance-benchmark-build: dependencies
	@mkdir -p $(PRODUCT_PARSER_BENCHMARK_DIR)
	@cd $(PROJECT_ROOT) && $(DART) compile exe tool/product_performance_benchmark.dart \
		-o $(PRODUCT_PERFORMANCE_BENCHMARK)

product-performance-benchmark: product-performance-benchmark-build
	@$(PRODUCT_PERFORMANCE_BENCHMARK) --baseline=$(PRODUCT_PERFORMANCE_BASELINE)

product-performance-comparator-check: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run test/product_performance_comparator_test.dart
	@cd $(PROJECT_ROOT) && $(DART) run test/ghostty_performance_capture_test.dart

product-performance-regression-gate: product-performance-benchmark-build \
	release-aot-build product-performance-comparator-check
	@cd $(PROJECT_ROOT) && $(DART) run test/product_performance_regression_gate_test.dart
	@mkdir -p $(PRODUCT_PARSER_BENCHMARK_DIR)
	@$(PRODUCT_PERFORMANCE_BENCHMARK) \
		--baseline=$(PRODUCT_PERFORMANCE_BASELINE) \
		> $(PRODUCT_PERFORMANCE_MICRO_RESULT)
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=performance $(RELEASE_AOT_BUNDLE) \
		> $(PRODUCT_PERFORMANCE_RUNTIME_RESULT)
	@cd $(PROJECT_ROOT) && $(DART) run \
		tool/product_performance_regression_gate.dart \
		--product-micro=$(PRODUCT_PERFORMANCE_MICRO_RESULT) \
		--product-runtime=$(PRODUCT_PERFORMANCE_RUNTIME_RESULT) \
		--comparator=$(PRODUCT_PERFORMANCE_COMPARATOR_EVIDENCE) \
		--output=$(PRODUCT_PERFORMANCE_AGGREGATE_RESULT)

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

developer-jit-performance: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=performance $(DEVELOPER_JIT_BUNDLE)

developer-jit-reliability: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=reliability $(DEVELOPER_JIT_BUNDLE)

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

developer-jit-diagnostics: developer-jit-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=developer-jit \
		--suite=diagnostics $(DEVELOPER_JIT_BUNDLE)

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

release-aot-arm64-build: dependencies
	@cd $(PROJECT_ROOT) && $(RUNTIME_BUILDER) --mode release-aot \
		--target-architecture arm64 \
		--build-dir $(ARM64_RELEASE_AOT_BUILD_DIR)

release-aot-x86_64-build: dependencies
	@cd $(PROJECT_ROOT) && $(RUNTIME_BUILDER) --mode release-aot \
		--target-architecture x86_64 \
		--build-dir $(X86_64_RELEASE_AOT_BUILD_DIR)

release-aot-thin-builds: release-aot-arm64-build release-aot-x86_64-build

release-aot-universal-build: release-aot-thin-builds
	@mkdir -p $(UNIVERSAL_RELEASE_AOT_BUILD_DIR)
	@cd $(PROJECT_ROOT) && $(RUNTIME_UNIVERSAL_ASSEMBLER) \
		--input-app $(ARM64_RELEASE_AOT_BUNDLE) \
		--input-app $(X86_64_RELEASE_AOT_BUNDLE) \
		--output-app $(UNIVERSAL_RELEASE_AOT_BUNDLE)

release-aot-run: runtime-architecture-check dependencies
	@cd $(PROJECT_ROOT) && $(RUNTIME_BUILDER) --mode release-aot \
		--build-dir $(RELEASE_AOT_BUILD_DIR) --run -- $(RUNTIME_ARGUMENTS)

release-aot-audit: release-aot-build
	@cd $(PROJECT_ROOT) && $(BUNDLE_AUDIT_TOOL) \
		--mode=release-aot --architecture=$(RUNTIME_ARCH) $(RELEASE_AOT_BUNDLE)

release-aot-arm64-audit: release-aot-arm64-build
	@cd $(PROJECT_ROOT) && $(BUNDLE_AUDIT_TOOL) \
		--mode=release-aot --architecture=arm64 $(ARM64_RELEASE_AOT_BUNDLE)

release-aot-x86_64-audit: release-aot-x86_64-build
	@cd $(PROJECT_ROOT) && $(BUNDLE_AUDIT_TOOL) \
		--mode=release-aot --architecture=x86_64 $(X86_64_RELEASE_AOT_BUNDLE)

release-aot-universal-audit: release-aot-universal-build
	@cd $(PROJECT_ROOT) && $(BUNDLE_AUDIT_TOOL) \
		--mode=release-aot --architecture=universal \
		$(UNIVERSAL_RELEASE_AOT_BUNDLE)

release-aot-distribution-audit: release-aot-arm64-audit \
	release-aot-x86_64-audit release-aot-universal-audit

release-aot-integration: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=smoke $(RELEASE_AOT_BUNDLE)

release-aot-arm64-integration: release-aot-arm64-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=smoke --launch-architecture=arm64 $(ARM64_RELEASE_AOT_BUNDLE)

release-aot-x86_64-integration: release-aot-x86_64-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=smoke --launch-architecture=x86_64 $(X86_64_RELEASE_AOT_BUNDLE)

release-aot-universal-integration: release-aot-universal-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=smoke $(UNIVERSAL_RELEASE_AOT_BUNDLE)

release-aot-distribution-integration: release-aot-arm64-integration \
	release-aot-x86_64-integration release-aot-universal-integration

release-aot-distribution-verify: test release-aot-distribution-audit \
	release-aot-distribution-integration

terminal-distribution-policy-test: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run \
		test/terminal_distribution_policy_test.dart

release-distribution-preflight: release-aot-universal-audit \
	terminal-distribution-policy-test
	@cd $(PROJECT_ROOT) && $(TERMINAL_DISTRIBUTION_POLICY_TOOL) \
		--source-app=$(UNIVERSAL_RELEASE_AOT_BUNDLE) \
		--entitlements=$(DISTRIBUTION_ENTITLEMENTS)
	@cd $(PROJECT_ROOT) && $(RUNTIME_DISTRIBUTION_PUBLISHER) \
		--input-app $(UNIVERSAL_RELEASE_AOT_BUNDLE) \
		--output-directory $(DISTRIBUTION_OUTPUT_DIR) \
		--signing-identity "Developer ID Application: Preflight Placeholder (ABCDE12345)" \
		--team-id ABCDE12345 \
		--entitlements $(DISTRIBUTION_ENTITLEMENTS) \
		--keychain-profile preflight-placeholder --validate-only

release-distribution-credentials-check:
	@if [[ -z "$(DEVELOPER_ID_APPLICATION)" || -z "$(NOTARY_KEYCHAIN_PROFILE)" ]]; then \
		echo "DEVELOPER_ID_APPLICATION and NOTARY_KEYCHAIN_PROFILE are required" >&2; \
		exit 69; \
	fi
	@if [[ ! "$(DEVELOPER_TEAM_ID)" =~ ^[A-Z0-9]{10}$$ ]]; then \
		echo "DEVELOPER_TEAM_ID must be ten uppercase letters or digits" >&2; \
		exit 64; \
	fi

release-distribution-build: release-distribution-preflight \
	release-distribution-credentials-check
	@mkdir -p $(dir $(DISTRIBUTION_OUTPUT_DIR))
	@cd $(PROJECT_ROOT) && $(RUNTIME_DISTRIBUTION_PUBLISHER) \
		--input-app $(UNIVERSAL_RELEASE_AOT_BUNDLE) \
		--output-directory $(DISTRIBUTION_OUTPUT_DIR) \
		--signing-identity "$(DEVELOPER_ID_APPLICATION)" \
		--team-id $(DEVELOPER_TEAM_ID) \
		--entitlements $(DISTRIBUTION_ENTITLEMENTS) \
		--keychain-profile "$(NOTARY_KEYCHAIN_PROFILE)"

release-distribution-audit: release-distribution-build
	@cd $(PROJECT_ROOT) && $(TERMINAL_DISTRIBUTION_POLICY_TOOL) \
		--source-app=$(UNIVERSAL_RELEASE_AOT_BUNDLE) \
		--entitlements=$(DISTRIBUTION_ENTITLEMENTS) \
		--distribution-directory=$(DISTRIBUTION_OUTPUT_DIR) \
		--signing-identity="$(DEVELOPER_ID_APPLICATION)" \
		--team-id=$(DEVELOPER_TEAM_ID)

release-distribution-verify: test release-distribution-audit

terminal-update-feed-test: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run test/terminal_update_feed_test.dart

terminal-update-transaction-test: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run test/terminal_update_transaction_test.dart

terminal-update-controller-test: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run test/terminal_update_controller_test.dart

terminal-release-symbols-test: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run test/terminal_release_symbols_test.dart

terminal-incident-service-test: dependencies
	@cd $(PROJECT_ROOT) && $(DART) run test/terminal_incident_service_test.dart

release-aot-symbols: release-aot-audit terminal-release-symbols-test
	@cd $(PROJECT_ROOT) && $(DART) run tool/terminal_release_symbols.dart \
		--application=$(RELEASE_AOT_BUNDLE) \
		--output=$(RELEASE_SYMBOLS_OUTPUT_DIR)

release-update-feed-credentials-check:
	@if [[ -z "$(UPDATE_ARCHIVE_URL)" || -z "$(UPDATE_VERSION)" || \
		-z "$(UPDATE_BUILD)" || -z "$(UPDATE_SEQUENCE)" || \
		-z "$(UPDATE_EXPIRES_UNIX_SECONDS)" || -z "$(UPDATE_KEY_ID)" || \
		-z "$(UPDATE_PUBLIC_KEY)" || -z "$(UPDATE_SIGNING_KEY)" ]]; then \
		echo "UPDATE_ARCHIVE_URL, UPDATE_VERSION, UPDATE_BUILD, UPDATE_SEQUENCE, UPDATE_EXPIRES_UNIX_SECONDS, UPDATE_KEY_ID, UPDATE_PUBLIC_KEY, and UPDATE_SIGNING_KEY are required" >&2; \
		exit 69; \
	fi

release-update-feed: terminal-update-feed-test \
	release-update-feed-credentials-check
	@cd $(PROJECT_ROOT) && $(DART) run tool/terminal_update_feed.dart \
		"--archive=$(UPDATE_ARCHIVE)" \
		"--archive-url=$(UPDATE_ARCHIVE_URL)" \
		"--version=$(UPDATE_VERSION)" \
		"--build=$(UPDATE_BUILD)" \
		"--minimum-macos=$(UPDATE_MINIMUM_MACOS)" \
		"--sequence=$(UPDATE_SEQUENCE)" \
		"--expires-unix-seconds=$(UPDATE_EXPIRES_UNIX_SECONDS)" \
		"--key-id=$(UPDATE_KEY_ID)" \
		"--public-key=$(UPDATE_PUBLIC_KEY)" \
		"--signing-key=$(UPDATE_SIGNING_KEY)" \
		"--output-directory=$(UPDATE_FEED_OUTPUT_DIR)"

release-aot-display: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=display $(RELEASE_AOT_BUNDLE)

release-aot-hierarchy: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=hierarchy $(RELEASE_AOT_BUNDLE)

release-aot-performance: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=performance $(RELEASE_AOT_BUNDLE)

release-aot-reliability: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=reliability $(RELEASE_AOT_BUNDLE)

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

release-aot-diagnostics: release-aot-build
	@cd $(PROJECT_ROOT) && $(INTEGRATION_TOOL) --mode=release-aot \
		--suite=diagnostics $(RELEASE_AOT_BUNDLE)

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

runtime-product-performance-integration: \
	developer-jit-performance release-aot-performance

runtime-bounded-reliability-integration: \
	developer-jit-reliability release-aot-reliability

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

runtime-diagnostics-integration: \
	developer-jit-diagnostics release-aot-diagnostics

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
	runtime-bounded-reliability-integration \
	runtime-user-actions-integration \
	runtime-applescript-integration \
	runtime-system-automation-integration \
	runtime-native-content-integration \
	runtime-quick-terminal-integration \
	runtime-secure-keyboard-entry-integration \
	runtime-diagnostics-integration \
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
