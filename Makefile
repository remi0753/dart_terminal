override SHELL := /bin/zsh
override MAKE := /usr/bin/make

override PROJECT_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BUILD_DIR ?= $(PROJECT_ROOT)/build/phase0
MACOSX_DEPLOYMENT_TARGET ?= 14.0
DART_APPKIT_ROOT ?= $(abspath $(PROJECT_ROOT)/../dart_appkit)
DART_ENGINE_ROOT ?= $(DART_APPKIT_ROOT)/.dart_tool/dart-engine/sdk
override HOST_ARCH := $(shell uname -m)
override DART_EXECUTABLE := $(shell command -v dart)
override RUNTIME_DART_EXECUTABLE := \
	$(shell /bin/realpath "$(DART_EXECUTABLE)")
DART_SDK_ROOT ?= $(shell resolved="$(RUNTIME_DART_EXECUTABLE)"; \
	dirname "$$(dirname "$$resolved")")
override DART_SDK_VERSION := $(shell /bin/cat "$(DART_SDK_ROOT)/version")
override DART_SDK_REVISION := $(shell /bin/cat "$(DART_SDK_ROOT)/revision")
override DART_SDK_HASH := \
	$(shell /usr/bin/cut -c1-10 "$(DART_SDK_ROOT)/revision")

ifeq ($(HOST_ARCH),arm64)
override DART_ENGINE_RELEASE_ARCH := ARM64
override DART_ENGINE_SHARED_TOOLCHAIN := clang_arm64_shared
override DART_ENGINE_HOST_ARCH := arm64
else ifeq ($(HOST_ARCH),x86_64)
override DART_ENGINE_RELEASE_ARCH := X64
override DART_ENGINE_SHARED_TOOLCHAIN := clang_x64_shared
override DART_ENGINE_HOST_ARCH := x64
else
$(error Unsupported host architecture: $(HOST_ARCH))
endif

override DART_ENGINE_OUT := \
	$(DART_ENGINE_ROOT)/xcodebuild/Product$(DART_ENGINE_RELEASE_ARCH)
override DART_ENGINE_JIT_OUT := \
	$(DART_ENGINE_ROOT)/xcodebuild/Release$(DART_ENGINE_RELEASE_ARCH)
override DART_ENGINE_GN := $(DART_ENGINE_ROOT)/tools/gn.py
override DART_ENGINE_NINJA := $(DART_ENGINE_ROOT)/buildtools/ninja/ninja
override RUNTIME_ENGINE_PYTHON := /usr/bin/python3
override DART_ENGINE_AOT_LIBRARY := \
	$(DART_ENGINE_OUT)/libdart_engine_aot_shared.dylib
override DART_ENGINE_JIT_LIBRARY := \
	$(DART_ENGINE_JIT_OUT)/libdart_engine_jit_shared.dylib
override DART_ENGINE_KERNEL_COMPILER := \
	$(DART_ENGINE_JIT_OUT)/bootstrap_gen_kernel.exe
override DART_ENGINE_PLATFORM_KERNEL := \
	$(DART_ENGINE_JIT_OUT)/$(DART_ENGINE_SHARED_TOOLCHAIN)/vm_platform.dill

override UNMODIFIED_ENGINE_PROBE_BUILD_DIR := \
	$(PROJECT_ROOT)/build/runtime-probes/unmodified-engine/$(HOST_ARCH)
override UNMODIFIED_ENGINE_PROBE_DART_SOURCE := \
	$(PROJECT_ROOT)/tool/unmodified_engine_multiple_root.dart
override UNMODIFIED_ENGINE_PROBE_RUNNER_SOURCE := \
	$(PROJECT_ROOT)/tool/unmodified_engine_probe_runner.dart
override UNMODIFIED_ENGINE_PROBE_HOST_SOURCE := \
	$(PROJECT_ROOT)/native/macos/runtime/UnmodifiedEngineMultipleRootProbe.cc
override UNMODIFIED_ENGINE_PROBE_AOT_SNAPSHOT := \
	$(UNMODIFIED_ENGINE_PROBE_BUILD_DIR)/multiple_root.aot
override UNMODIFIED_ENGINE_PROBE_JIT_KERNEL := \
	$(UNMODIFIED_ENGINE_PROBE_BUILD_DIR)/multiple_root.dill
override UNMODIFIED_ENGINE_PROBE_AOT_HOST := \
	$(UNMODIFIED_ENGINE_PROBE_BUILD_DIR)/multiple_root_aot_probe
override UNMODIFIED_ENGINE_PROBE_JIT_HOST := \
	$(UNMODIFIED_ENGINE_PROBE_BUILD_DIR)/multiple_root_jit_probe
override PUBLIC_EMBEDDER_WORKER_PROBE_BUILD_DIR := \
	$(PROJECT_ROOT)/build/runtime-probes/public-embedder-worker/$(HOST_ARCH)
override PUBLIC_EMBEDDER_WORKER_PROBE_DART_SOURCE := \
	$(PROJECT_ROOT)/tool/public_embedder_worker_probe.dart
override PUBLIC_EMBEDDER_WORKER_PROBE_RUNNER_SOURCE := \
	$(PROJECT_ROOT)/tool/public_embedder_worker_probe_runner.dart
override PUBLIC_EMBEDDER_WORKER_PROBE_HOST_SOURCE := \
	$(PROJECT_ROOT)/native/macos/runtime/PublicEmbedderWorkerProbe.cc
override PUBLIC_EMBEDDER_WORKER_PROBE_AOT_SNAPSHOT := \
	$(PUBLIC_EMBEDDER_WORKER_PROBE_BUILD_DIR)/public_worker.aot
override PUBLIC_EMBEDDER_WORKER_PROBE_JIT_KERNEL := \
	$(PUBLIC_EMBEDDER_WORKER_PROBE_BUILD_DIR)/public_worker.dill
override PUBLIC_EMBEDDER_WORKER_PROBE_AOT_HOST := \
	$(PUBLIC_EMBEDDER_WORKER_PROBE_BUILD_DIR)/public_worker_aot_probe
override PUBLIC_EMBEDDER_WORKER_PROBE_JIT_HOST := \
	$(PUBLIC_EMBEDDER_WORKER_PROBE_BUILD_DIR)/public_worker_jit_probe
override PROCESS_WORKER_PROBE_BUILD_DIR := \
	$(PROJECT_ROOT)/build/runtime-probes/process-worker/$(HOST_ARCH)
override PROCESS_WORKER_PROBE_SOURCE := \
	$(PROJECT_ROOT)/tool/process_worker_probe.dart
override PROCESS_WORKER_PROBE_RUNNER_SOURCE := \
	$(PROJECT_ROOT)/tool/process_worker_probe_runner.dart
override PROCESS_WORKER_PROBE_AOT_EXECUTABLE := \
	$(PROCESS_WORKER_PROBE_BUILD_DIR)/process_worker_probe

CLANGXX ?= $(shell xcrun --find clang++)
CLANG := $(shell xcrun --find clang)
SDKROOT ?= $(shell xcrun --sdk macosx --show-sdk-path)
unexport CLANGXX
unexport SDKROOT
NATIVE_FLAGS ?= -Wall -Wextra -Wpedantic -Werror \
	-Wno-gnu-anonymous-struct -Wno-nested-anon-types \
	-std=c++20 -fobjc-arc \
	-isysroot $(SDKROOT) -mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET)
C_FLAGS := -Wall -Wextra -Wpedantic -Werror -std=c11 \
	-isysroot $(SDKROOT) -mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET)

AOT_BUILD_DIR := $(BUILD_DIR)/aot
AOT_SNAPSHOT := $(AOT_BUILD_DIR)/phase0_app.aot
AOT_HOST := $(AOT_BUILD_DIR)/dart_terminal_phase0_aot
AOT_BUNDLE := $(AOT_BUILD_DIR)/DartTerminalPhase0Aot.app
AOT_BUNDLE_STAMP := $(AOT_BUNDLE)/Contents/.phase0-built
AOT_SOURCE := $(PROJECT_ROOT)/tool/phase0/aot_app.dart
AOT_HOST_SOURCE := $(PROJECT_ROOT)/native/macos/phase0/AotHost.mm
AOT_INFO_PLIST := $(PROJECT_ROOT)/native/macos/phase0/AotHost-Info.plist

PTY_BUILD_DIR := $(BUILD_DIR)/pty
PTY_NATIVE_DIR := $(PROJECT_ROOT)/native/macos/phase0/pty
PTY_CHILD_OBJECT := $(PTY_BUILD_DIR)/PtyExecChild.o
PTY_AUDIT_SOURCE := $(PROJECT_ROOT)/tool/phase0/audit_pty_child.dart

IME_BUILD_DIR := $(BUILD_DIR)/ime
IME_SNAPSHOT := $(IME_BUILD_DIR)/ime_client.aot
IME_HOST := $(IME_BUILD_DIR)/dart_terminal_phase0_ime
IME_BUNDLE := $(IME_BUILD_DIR)/DartTerminalPhase0Ime.app
IME_BUNDLE_STAMP := $(IME_BUNDLE)/Contents/.phase0-built
IME_SOURCE := $(PROJECT_ROOT)/tool/phase0/ime_client.dart
IME_BRIDGE_SOURCE := $(PROJECT_ROOT)/native/macos/phase0/ime/ImeBridge.mm
IME_BRIDGE_OBJECT := $(IME_BUILD_DIR)/ImeBridge.o
IME_INFO_PLIST := $(PROJECT_ROOT)/native/macos/phase0/Ime-Info.plist

GRID_BUILD_DIR := $(BUILD_DIR)/grid
GRID_BENCHMARK_SOURCE := $(PROJECT_ROOT)/tool/phase0/grid_benchmark.dart
GRID_PROTOTYPE_SOURCE := $(PROJECT_ROOT)/tool/phase0/packed_grid.dart
GRID_BENCHMARK_EXE := $(GRID_BUILD_DIR)/grid_benchmark

PARSER_BUILD_DIR := $(BUILD_DIR)/parser
PARSER_HARNESS_SOURCE := $(PROJECT_ROOT)/tool/phase0/parser_corpus.dart
PARSER_PROBE_SOURCE := $(PROJECT_ROOT)/tool/phase0/parser_probe.dart
PARSER_CORPUS := $(PROJECT_ROOT)/test/corpus/parser/phase0.json
PARSER_HARNESS_EXE := $(PARSER_BUILD_DIR)/parser_harness

BENCHMARK_BUILD_DIR := $(BUILD_DIR)/benchmark
BENCHMARK_SOURCE := $(PROJECT_ROOT)/benchmark/phase0_benchmark.dart
INPUT_PROBE_SOURCE := $(PROJECT_ROOT)/tool/phase0/input_probe.dart
BENCHMARK_BASELINE := \
	$(PROJECT_ROOT)/benchmark/baselines/phase0-macos-arm64-m1.json
BENCHMARK_EXE := $(BENCHMARK_BUILD_DIR)/phase0_benchmark

DEBUG_BUILD_DIR := $(BUILD_DIR)/debug
DEBUG_KERNEL := $(DEBUG_BUILD_DIR)/dart_terminal.dill

RUNTIME_BUILD_DIR ?= $(PROJECT_ROOT)/build/runtime
RUNTIME_ARCH ?=
override RUNTIME_DEFAULT_PACKAGE_CONFIG := \
	$(PROJECT_ROOT)/.dart_tool/package_config.json
RUNTIME_PACKAGE_CONFIG ?= $(RUNTIME_DEFAULT_PACKAGE_CONFIG)
override RUNTIME_DART_SOURCES := \
	$(wildcard $(PROJECT_ROOT)/bin/*.dart) \
	$(wildcard $(PROJECT_ROOT)/lib/*.dart) \
	$(wildcard $(PROJECT_ROOT)/lib/src/*.dart) \
	$(wildcard $(DART_APPKIT_ROOT)/packages/dart_appkit/lib/*.dart) \
	$(wildcard $(DART_APPKIT_ROOT)/packages/dart_appkit/lib/src/*.dart) \
	$(wildcard $(DART_APPKIT_ROOT)/packages/dart_appkit/lib/src/api/*.dart) \
	$(wildcard $(DART_APPKIT_ROOT)/packages/dart_appkit/lib/src/native/*.dart)
override RUNTIME_BRIDGE_HEADERS := \
	$(DART_APPKIT_ROOT)/native/bridge/include/dart_appkit.h \
	$(DART_APPKIT_ROOT)/native/bridge/include/dart_appkit_custom_view.h \
	$(DART_APPKIT_ROOT)/native/bridge/src/AppKitObjects.h \
	$(DART_APPKIT_ROOT)/native/bridge/src/BridgeInternal.h \
	$(DART_APPKIT_ROOT)/native/bridge/src/CustomViewRegistry.h \
	$(DART_APPKIT_ROOT)/native/bridge/src/ObjectRegistry.h
override RUNTIME_BRIDGE_SOURCES := \
	$(DART_APPKIT_ROOT)/native/bridge/src/AppKitBridge.mm \
	$(DART_APPKIT_ROOT)/native/bridge/src/CustomViewRegistry.mm \
	$(DART_APPKIT_ROOT)/native/bridge/src/EventSink.mm \
	$(DART_APPKIT_ROOT)/native/bridge/src/ObjectRegistry.mm \
	$(DART_APPKIT_ROOT)/native/bridge/src/TextView.mm
override RUNTIME_LIFECYCLE_HEADER := \
	$(PROJECT_ROOT)/native/macos/runtime/RuntimeLifecycleBridge.h
override RUNTIME_LIFECYCLE_SOURCE := \
	$(PROJECT_ROOT)/native/macos/runtime/RuntimeLifecycleBridge.mm
override RUNTIME_DIAGNOSTICS_HEADER := \
	$(PROJECT_ROOT)/native/macos/runtime/RuntimeDiagnostics.h
override RUNTIME_DIAGNOSTICS_SOURCE := \
	$(PROJECT_ROOT)/native/macos/runtime/RuntimeDiagnostics.mm
override RUNTIME_DIAGNOSTICS_TEST_SOURCE := \
	$(PROJECT_ROOT)/native/macos/runtime/test/RuntimeDiagnosticsTests.mm
override RUNTIME_DIAGNOSTICS_TEST_BINARY := \
	$(PROJECT_ROOT)/build/native/runtime_diagnostics_tests
override RUNTIME_TERMINAL_VIEW_HEADER := \
	$(PROJECT_ROOT)/native/macos/renderer/TerminalMetalView.h
override RUNTIME_TERMINAL_VIEW_SOURCE := \
	$(PROJECT_ROOT)/native/macos/renderer/TerminalMetalView.mm
override RUNTIME_TERMINAL_VIEW_TEST_SOURCE := \
	$(PROJECT_ROOT)/native/macos/renderer/test/TerminalMetalViewTests.mm
override RUNTIME_TERMINAL_VIEW_TEST_BINARY := \
	$(PROJECT_ROOT)/build/native/terminal_metal_view_tests
override RUNTIME_WORKER_CONFIGURATION_HEADER := \
	$(PROJECT_ROOT)/native/macos/runtime/RuntimeWorkerConfiguration.h
override RUNTIME_WORKER_CONFIGURATION_SOURCE := \
	$(PROJECT_ROOT)/native/macos/runtime/RuntimeWorkerConfiguration.cc
override RUNTIME_JIT_MAIN_SOURCE := \
	$(PROJECT_ROOT)/native/macos/runtime/DeveloperJitRunner.mm
override RUNTIME_JIT_RUNNER_HEADERS := \
	$(DART_APPKIT_ROOT)/native/runner/AppDelegate.h \
	$(DART_APPKIT_ROOT)/native/runner/DartEventEncoder.h \
	$(DART_APPKIT_ROOT)/native/runner/DartHost.h \
	$(DART_APPKIT_ROOT)/native/runner/DartMessagePump.h \
	$(DART_APPKIT_ROOT)/native/runner/RunnerArguments.h \
	$(DART_APPKIT_ROOT)/native/runner/RunnerConfiguration.h
override RUNTIME_JIT_RUNNER_SOURCES := \
	$(RUNTIME_JIT_MAIN_SOURCE) \
	$(DART_APPKIT_ROOT)/native/runner/AppDelegate.mm \
	$(DART_APPKIT_ROOT)/native/runner/DartEventEncoder.cc \
	$(DART_APPKIT_ROOT)/native/runner/DartHost.mm \
	$(DART_APPKIT_ROOT)/native/runner/DartMessagePump.mm \
	$(DART_APPKIT_ROOT)/native/runner/RunnerArguments.cc
override RUNTIME_MESSAGE_PUMP_HEADERS := \
	$(DART_APPKIT_ROOT)/native/runner/DartEventEncoder.h \
	$(DART_APPKIT_ROOT)/native/runner/DartMessagePump.h
override RUNTIME_MESSAGE_PUMP_SOURCE := \
	$(DART_APPKIT_ROOT)/native/runner/DartMessagePump.mm
override RUNTIME_EVENT_ENCODER_SOURCE := \
	$(DART_APPKIT_ROOT)/native/runner/DartEventEncoder.cc
override RUNTIME_AUDIT_SOURCE := \
	$(PROJECT_ROOT)/tool/runtime_bundle_audit.dart
override RUNTIME_FINGERPRINT_SOURCE := \
	$(PROJECT_ROOT)/tool/runtime_build_fingerprint.dart
override RUNTIME_ENGINE_ATTESTATION_SOURCE := \
	$(PROJECT_ROOT)/tool/runtime_engine_attestation.dart
override RUNTIME_FRESHNESS_TEST_SOURCE := \
	$(PROJECT_ROOT)/tool/runtime_build_freshness_test.dart
override RUNTIME_MANIFEST_SOURCE := \
	$(PROJECT_ROOT)/tool/runtime_build_manifest.dart
override RUNTIME_RELEASE_SUPPORT_SOURCE := \
	$(PROJECT_ROOT)/tool/src/runtime_release_support.dart
override RUNTIME_UNIVERSAL_ASSEMBLER_SOURCE := \
	$(PROJECT_ROOT)/tool/runtime_universal_assembler.dart
override RUNTIME_RELEASE_NEGATIVE_SOURCE := \
	$(PROJECT_ROOT)/tool/runtime_release_negative_tests.dart
override RUNTIME_NATIVE_HANDOFF_SOURCE := \
	$(PROJECT_ROOT)/tool/runtime_native_handoff.dart
override RUNTIME_INTEGRATION_SOURCE := \
	$(PROJECT_ROOT)/tool/runtime_integration_smoke.dart
RUNTIME_ARGUMENTS ?=
RUNTIME_EXTRA_BUILD_INPUT ?=
override RUNTIME_WORKER_KERNEL_FLAGS := \
	--link-platform --no-embed-sources --verbosity=warning
override RUNTIME_EXTRA_BUILD_INPUT_ARGUMENT = $(if \
	$(strip $(RUNTIME_EXTRA_BUILD_INPUT)),\
	--extra-build-input=$(abspath $(RUNTIME_EXTRA_BUILD_INPUT)),)
override RUNTIME_BUNDLE_VERSION := 0.1.0
override RUNTIME_NATIVE_FLAG_PREFIX := \
	-Wall -Wextra -Wpedantic -Werror \
	-Wno-gnu-anonymous-struct -Wno-nested-anon-types \
	-std=c++20 -fobjc-arc
override RUNTIME_NATIVE_FLAG_SUFFIX := \
	-mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET) \
	-fblocks -fvisibility=hidden

ifeq ($(RUNTIME_ARCH),arm64)
override RUNTIME_DART_TARGET_ARCH := arm64
override RUNTIME_ENGINE_ARCH := ARM64
override RUNTIME_ENGINE_TOOLCHAIN := clang_arm64_shared
override RUNTIME_SNAPSHOTTER_RUNNER_ARGUMENTS := -arm64
else ifeq ($(RUNTIME_ARCH),x86_64)
override RUNTIME_DART_TARGET_ARCH := x64
override RUNTIME_ENGINE_ARCH := X64
override RUNTIME_ENGINE_TOOLCHAIN := clang_x64_shared
override RUNTIME_SNAPSHOTTER_RUNNER_ARGUMENTS := -x86_64
else
override RUNTIME_DART_TARGET_ARCH := invalid
override RUNTIME_ENGINE_ARCH := INVALID
override RUNTIME_ENGINE_TOOLCHAIN := invalid
override RUNTIME_SNAPSHOTTER_RUNNER_ARGUMENTS := invalid
endif
override RUNTIME_WORKER_EXECUTABLE_FLAGS := \
	--target-os=macos --target-arch=$(RUNTIME_DART_TARGET_ARCH) \
	--verbosity=warning
RUNTIME_SNAPSHOTTER_RUNNER_EXECUTABLE ?= /usr/bin/arch
unexport RUNTIME_SNAPSHOTTER_RUNNER_EXECUTABLE

override RUNTIME_ENGINE_PRODUCT_OUT := \
	$(DART_ENGINE_ROOT)/xcodebuild/Product$(RUNTIME_ENGINE_ARCH)
override RUNTIME_ENGINE_RELEASE_OUT := \
	$(DART_ENGINE_ROOT)/xcodebuild/Release$(RUNTIME_ENGINE_ARCH)
override RUNTIME_ENGINE_AOT_LIBRARY := \
	$(RUNTIME_ENGINE_PRODUCT_OUT)/libdart_engine_aot_shared.dylib
override RUNTIME_ENGINE_JIT_LIBRARY := \
	$(RUNTIME_ENGINE_RELEASE_OUT)/libdart_engine_jit_shared.dylib
override RUNTIME_ENGINE_KERNEL_COMPILER := \
	$(RUNTIME_ENGINE_RELEASE_OUT)/bootstrap_gen_kernel.exe
override RUNTIME_ENGINE_PLATFORM_KERNEL := \
	$(RUNTIME_ENGINE_RELEASE_OUT)/$(RUNTIME_ENGINE_TOOLCHAIN)/vm_platform.dill
override RUNTIME_ENGINE_JIT_ATTESTATION := \
	$(RUNTIME_ENGINE_RELEASE_OUT)/.dart-terminal-official-engine.json
override RUNTIME_ENGINE_AOT_ATTESTATION := \
	$(RUNTIME_ENGINE_PRODUCT_OUT)/.dart-terminal-official-engine.json
override RUNTIME_ENGINE_AOT_KERNEL_COMPILER := \
	$(RUNTIME_ENGINE_PRODUCT_OUT)/bootstrap_gen_kernel.exe
override RUNTIME_ENGINE_AOT_PLATFORM_KERNEL := \
	$(RUNTIME_ENGINE_PRODUCT_OUT)/$(RUNTIME_ENGINE_TOOLCHAIN)/vm_platform.dill
override RUNTIME_ENGINE_AOT_SNAPSHOTTER := \
	$(RUNTIME_ENGINE_PRODUCT_OUT)/gen_snapshot

override DEVELOPER_JIT_BUILD_DIR := \
	$(RUNTIME_BUILD_DIR)/$(RUNTIME_ARCH)/developer-jit
override DEVELOPER_JIT_RUNNER := \
	$(DEVELOPER_JIT_BUILD_DIR)/dart_terminal_developer_jit
override DEVELOPER_JIT_KERNEL := $(DEVELOPER_JIT_BUILD_DIR)/application.dill
override DEVELOPER_JIT_KERNEL_DEPFILE := $(DEVELOPER_JIT_KERNEL).d
override DEVELOPER_JIT_WORKER_KERNEL := \
	$(DEVELOPER_JIT_BUILD_DIR)/runtime_worker.dill
override DEVELOPER_JIT_WORKER_KERNEL_DEPFILE := \
	$(DEVELOPER_JIT_WORKER_KERNEL).d
override DEVELOPER_JIT_MANIFEST := \
	$(DEVELOPER_JIT_BUILD_DIR)/runtime-build-manifest.json
override DEVELOPER_JIT_FINGERPRINT := \
	$(DEVELOPER_JIT_BUILD_DIR)/.effective-build-inputs.json
override DEVELOPER_JIT_BUNDLE := \
	$(DEVELOPER_JIT_BUILD_DIR)/DartTerminalDeveloper.app
override DEVELOPER_JIT_EXECUTABLE := \
	$(DEVELOPER_JIT_BUNDLE)/Contents/MacOS/dart_terminal_developer_jit
override DEVELOPER_JIT_BUNDLED_KERNEL := \
	$(DEVELOPER_JIT_BUNDLE)/Contents/Resources/application.dill
override DEVELOPER_JIT_BUNDLED_WORKER_KERNEL := \
	$(DEVELOPER_JIT_BUNDLE)/Contents/Resources/runtime_worker.dill
override DEVELOPER_JIT_BUNDLE_STAMP := \
	$(DEVELOPER_JIT_BUILD_DIR)/.developer-jit-built
override DEVELOPER_JIT_INFO_PLIST := \
	$(PROJECT_ROOT)/native/macos/runtime/DeveloperJit-Info.plist
override DEVELOPER_JIT_AUDIT_REPORT := \
	$(DEVELOPER_JIT_BUILD_DIR)/thin-audit.json

override RELEASE_AOT_BUILD_DIR := \
	$(RUNTIME_BUILD_DIR)/$(RUNTIME_ARCH)/release-aot
override RELEASE_AOT_KERNEL := $(RELEASE_AOT_BUILD_DIR)/application.aot.dill
override RELEASE_AOT_KERNEL_DEPFILE := $(RELEASE_AOT_KERNEL).d
override RELEASE_AOT_SNAPSHOT := $(RELEASE_AOT_BUILD_DIR)/application.aot
override RELEASE_AOT_WORKER_EXECUTABLE := \
	$(RELEASE_AOT_BUILD_DIR)/dart_terminal_runtime_worker
override RELEASE_AOT_WORKER_DEPFILE := $(RELEASE_AOT_WORKER_EXECUTABLE).d
override RELEASE_AOT_HOST := \
	$(RELEASE_AOT_BUILD_DIR)/dart_terminal_release_aot
override RELEASE_AOT_PACKAGED_DIR := $(RELEASE_AOT_BUILD_DIR)/packaged
override RELEASE_AOT_PACKAGED_HOST := \
	$(RELEASE_AOT_PACKAGED_DIR)/dart_terminal_release_aot
override RELEASE_AOT_PACKAGED_ENGINE := \
	$(RELEASE_AOT_PACKAGED_DIR)/libdart_engine_aot_shared.dylib
override RELEASE_AOT_PACKAGED_SNAPSHOT := \
	$(RELEASE_AOT_PACKAGED_DIR)/application.aot
override RELEASE_AOT_PACKAGED_WORKER_EXECUTABLE := \
	$(RELEASE_AOT_PACKAGED_DIR)/dart_terminal_runtime_worker
override RELEASE_AOT_MANIFEST := \
	$(RELEASE_AOT_BUILD_DIR)/runtime-build-manifest.json
override RELEASE_AOT_FINGERPRINT := \
	$(RELEASE_AOT_BUILD_DIR)/.effective-build-inputs.json
override RELEASE_AOT_BUNDLE := $(RELEASE_AOT_BUILD_DIR)/DartTerminal.app
override RELEASE_AOT_EXECUTABLE := \
	$(RELEASE_AOT_BUNDLE)/Contents/MacOS/dart_terminal_release_aot
override RELEASE_AOT_BUNDLED_WORKER_EXECUTABLE := \
	$(RELEASE_AOT_BUNDLE)/Contents/Helpers/dart_terminal_runtime_worker
override RELEASE_AOT_BUNDLE_STAMP := \
	$(RELEASE_AOT_BUILD_DIR)/.release-aot-built
override RELEASE_AOT_HOST_SOURCE := \
	$(PROJECT_ROOT)/native/macos/runtime/ReleaseAotRunner.mm
override RELEASE_AOT_INFO_PLIST := \
	$(PROJECT_ROOT)/native/macos/runtime/ReleaseAot-Info.plist
override RELEASE_AOT_AUDIT_REPORT := \
	$(RELEASE_AOT_BUILD_DIR)/thin-audit.json

override UNIVERSAL_RELEASE_BUILD_DIR := \
	$(RUNTIME_BUILD_DIR)/universal/release-aot
override UNIVERSAL_RELEASE_BUNDLE := \
	$(UNIVERSAL_RELEASE_BUILD_DIR)/DartTerminal.app
override UNIVERSAL_RELEASE_REPORT := \
	$(UNIVERSAL_RELEASE_BUILD_DIR)/assembly-report.json
override UNIVERSAL_RELEASE_AUDIT_REPORT := \
	$(UNIVERSAL_RELEASE_BUILD_DIR)/universal-audit.json
override ARM64_RELEASE_BUNDLE := \
	$(RUNTIME_BUILD_DIR)/arm64/release-aot/DartTerminal.app
override X86_64_RELEASE_BUNDLE := \
	$(RUNTIME_BUILD_DIR)/x86_64/release-aot/DartTerminal.app
override ARM64_RELEASE_AUDIT_REPORT := \
	$(RUNTIME_BUILD_DIR)/arm64/release-aot/thin-audit.json
override X86_64_RELEASE_AUDIT_REPORT := \
	$(RUNTIME_BUILD_DIR)/x86_64/release-aot/thin-audit.json

INTEL_DEVELOPER_JIT_BUNDLE ?=
INTEL_DEVELOPER_JIT_REPORT ?=
INTEL_RELEASE_AOT_BUNDLE ?=
INTEL_RELEASE_AOT_REPORT ?=
INTEL_UNIVERSAL_BUNDLE ?=
INTEL_UNIVERSAL_REPORT ?=
INTEL_HARDWARE_LABEL ?=
INTEL_EVIDENCE_OUTPUT ?=

-include $(DEVELOPER_JIT_KERNEL_DEPFILE)
-include $(DEVELOPER_JIT_WORKER_KERNEL_DEPFILE)
-include $(RELEASE_AOT_KERNEL_DEPFILE)

.PHONY: help runtime-architecture-check runtime-dart-tool-check \
	runtime-fingerprint-force \
	runtime-jit-engine \
	runtime-aot-engine release-aot-engine \
	unmodified-engine-sdk-clean unmodified-engine-probe-aot-engine \
	unmodified-engine-probe-jit-engine \
	unmodified-engine-multiple-root-probe \
	public-embedder-worker-probe \
	process-worker-probe \
	developer-jit-build developer-jit-run developer-jit-audit \
	developer-jit-clean-sdk-test \
	developer-jit-integration developer-jit-lifecycle developer-jit-traffic \
	release-aot-build release-aot-run release-aot-audit \
	release-aot-clean-sdk-test \
	release-aot-integration release-aot-lifecycle release-aot-traffic \
	runtime-source-check \
	runtime-diagnostics-test terminal-metal-view-test \
	runtime-bundle-audit runtime-integration \
	runtime-lifecycle-integration runtime-traffic-integration runtime-verify \
	runtime-matrix-build runtime-matrix-audit runtime-matrix-integration \
	runtime-matrix-verify runtime-build-freshness-test \
	universal-release-aot-build universal-release-aot-assemble \
	universal-release-aot-audit universal-release-aot-integration \
	runtime-release-negative-tests runtime-intel-native-status \
	intel-native-runtime-verify \
	phase0-aot-engine \
	phase0-aot-build phase0-aot-run \
	phase0-pty-child-audit \
	phase0-ime-build phase0-ime-run \
	phase0-grid-build phase0-grid-run \
	phase0-parser-build phase0-parser-run \
	phase0-benchmark-build phase0-benchmark-run \
	phase0-debug-check phase0-debug-smoke

help:
	@echo "Dart Terminal product runtime targets:"
	@echo "  Thin targets require RUNTIME_ARCH=arm64 or RUNTIME_ARCH=x86_64"
	@echo "  make unmodified-engine-multiple-root-probe"
	@echo "  make public-embedder-worker-probe"
	@echo "  make process-worker-probe Validate official Dart process workers"
	@echo "  make developer-jit-build Build one thin product developer-JIT app"
	@echo "  make developer-jit-run   Run one thin product developer-JIT app"
	@echo "  make developer-jit-audit Audit one JIT-only thin bundle contract"
	@echo "  make developer-jit-clean-sdk-test Verify stock-SDK worker provenance"
	@echo "  make developer-jit-traffic Verify bounded worker traffic and GUI close"
	@echo "  make release-aot-build   Build one thin release-AOT product app"
	@echo "  make release-aot-run     Run one thin release-AOT product app"
	@echo "  make release-aot-audit   Audit one AOT-only thin bundle contract"
	@echo "  make release-aot-clean-sdk-test Verify stock-SDK AOT worker provenance"
	@echo "  make release-aot-traffic Verify bounded worker traffic and GUI close"
	@echo "  make runtime-integration Run shared smoke, lifecycle, and traffic suites"
	@echo "  make runtime-lifecycle-integration Run shared lifecycle faults"
	@echo "  make runtime-traffic-integration Run bounded traffic in both modes"
	@echo "  make terminal-metal-view-test Verify native custom-view attachment"
	@echo "  make runtime-verify      Verify both modes for one explicit architecture"
	@echo "  make runtime-matrix-build Build arm64 and x86_64 thin products"
	@echo "  make runtime-matrix-audit Audit the complete thin-product matrix"
	@echo "  make universal-release-aot-build Assemble fresh Universal release AOT"
	@echo "  make universal-release-aot-audit Audit exact arm64+x86_64 slices"
	@echo "  make runtime-matrix-verify Run matrix, Universal, negative, and smoke gates"
	@echo "  make intel-native-runtime-verify Audit transferred artifacts on an Intel Mac"
	@echo ""
	@echo "Historical Phase 0 feasibility/regression targets:"
	@echo "  make phase0-aot-engine  Build the revision-matched AOT Dart Engine"
	@echo "  make phase0-aot-build   Build the release AOT AppKit spike bundle"
	@echo "  make phase0-aot-run     Launch, validate, and auto-close the AOT spike"
	@echo "  make phase0-pty-child-audit Audit post-fork child symbol dependencies"
	@echo "  make phase0-ime-build    Build the NSTextInputClient Japanese IME spike"
	@echo "  make phase0-ime-run      Validate marked/commit/candidate-rect behavior"
	@echo "  make phase0-grid-build   Build the packed-grid release-AOT benchmark"
	@echo "  make phase0-grid-run     Measure grid, damage, and isolate transfer"
	@echo "  make phase0-parser-build Build the release-AOT corpus/snapshot harness"
	@echo "  make phase0-parser-run   Check all splits and parser throughput"
	@echo "  make phase0-benchmark-build Build the unified release-AOT benchmark"
	@echo "  make phase0-benchmark-run Compare parser/render/input with baseline"
	@echo "  make phase0-debug-check   Analyze, test, and compile the JIT Kernel path"
	@echo "  make phase0-debug-smoke   Launch and auto-close the developer JIT app"

$(RUNTIME_DEFAULT_PACKAGE_CONFIG): pubspec.yaml pubspec.lock \
		| runtime-dart-tool-check
	"$(RUNTIME_DART_EXECUTABLE)" pub get

runtime-architecture-check:
	@if [[ "$(RUNTIME_ARCH)" != "arm64" && \
		"$(RUNTIME_ARCH)" != "x86_64" ]]; then \
		echo "RUNTIME_ARCH=arm64 or RUNTIME_ARCH=x86_64 is required" >&2; \
		exit 64; \
	fi

runtime-dart-tool-check:
	@trusted="$(RUNTIME_DART_EXECUTABLE)"; \
	selected="$(DART_SDK_ROOT)/bin/dart"; \
	[[ -x "$$trusted" && -x "$$selected" ]] || { \
		echo "runtime Dart executable or selected SDK is not executable" >&2; \
		exit 64; \
	}; \
	trusted_identity="$$(/bin/realpath "$$trusted")"; \
	selected_identity="$$(/bin/realpath "$$selected")"; \
	[[ "$$trusted_identity" == "$$selected_identity" ]] || { \
		echo "selected Dart SDK does not identify the trusted bootstrap" >&2; \
		exit 64; \
	}; \
	version="$$("$$trusted" --version 2>&1)"; \
	[[ "$$version" == "Dart SDK version: $(DART_SDK_VERSION) "* ]] || { \
		echo "trusted Dart version does not match selected SDK" >&2; \
		exit 64; \
	}

unmodified-engine-sdk-clean: runtime-dart-tool-check
	@actual_revision="$$('/usr/bin/git' -C "$(DART_ENGINE_ROOT)" rev-parse HEAD)"; \
	expected_revision="$(DART_SDK_REVISION)"; \
	[[ "$$actual_revision" == "$$expected_revision" ]] || { \
		echo "Engine and selected Dart SDK revisions differ" >&2; \
		exit 64; \
	}; \
	changes="$$('/usr/bin/git' -C "$(DART_ENGINE_ROOT)" status --porcelain)"; \
	[[ -z "$$changes" ]] || { \
		echo "unmodified Engine probe requires a clean SDK checkout" >&2; \
		echo "$$changes" >&2; \
		exit 64; \
	}

unmodified-engine-probe-aot-engine: unmodified-engine-sdk-clean
	"$(RUNTIME_ENGINE_PYTHON)" "$(DART_ENGINE_GN)" --mode=product \
		--arch=$(DART_ENGINE_HOST_ARCH)
	"$(DART_ENGINE_NINJA)" -C $(DART_ENGINE_OUT) dart_engine_aot_shared
	@changes="$$('/usr/bin/git' -C "$(DART_ENGINE_ROOT)" status --porcelain)"; \
	[[ -z "$$changes" ]] || { \
		echo "Engine build changed the SDK checkout" >&2; \
		echo "$$changes" >&2; \
		exit 70; \
	}

unmodified-engine-probe-jit-engine: unmodified-engine-sdk-clean
	"$(RUNTIME_ENGINE_PYTHON)" "$(DART_ENGINE_GN)" --mode=release \
		--arch=$(DART_ENGINE_HOST_ARCH)
	"$(DART_ENGINE_NINJA)" -C $(DART_ENGINE_JIT_OUT) \
		dart_engine_jit_shared bootstrap_gen_kernel.exe \
		$(DART_ENGINE_SHARED_TOOLCHAIN)/vm_platform.dill
	@changes="$$('/usr/bin/git' -C "$(DART_ENGINE_ROOT)" status --porcelain)"; \
	[[ -z "$$changes" ]] || { \
		echo "Engine build changed the SDK checkout" >&2; \
		echo "$$changes" >&2; \
		exit 70; \
	}

$(UNMODIFIED_ENGINE_PROBE_AOT_SNAPSHOT): \
		$(UNMODIFIED_ENGINE_PROBE_DART_SOURCE) | runtime-dart-tool-check
	@mkdir -p $(UNMODIFIED_ENGINE_PROBE_BUILD_DIR)
	"$(RUNTIME_DART_EXECUTABLE)" compile aot-snapshot --verbosity=warning \
		-o $@ $(UNMODIFIED_ENGINE_PROBE_DART_SOURCE)

$(UNMODIFIED_ENGINE_PROBE_JIT_KERNEL): \
		$(UNMODIFIED_ENGINE_PROBE_DART_SOURCE) | \
		unmodified-engine-probe-jit-engine
	@mkdir -p $(UNMODIFIED_ENGINE_PROBE_BUILD_DIR)
	"$(DART_ENGINE_KERNEL_COMPILER)" \
		--platform=$(DART_ENGINE_PLATFORM_KERNEL) \
		--no-aot --link-platform --no-embed-sources \
		--output=$@ \
		-Dsdk_hash=$(DART_SDK_HASH) \
		-Ddart.vm.product=false -Ddart.vm.asan=false \
		-Ddart.vm.msan=false -Ddart.vm.tsan=false \
		$(UNMODIFIED_ENGINE_PROBE_DART_SOURCE)

$(UNMODIFIED_ENGINE_PROBE_AOT_HOST): \
		$(UNMODIFIED_ENGINE_PROBE_HOST_SOURCE) | \
		unmodified-engine-probe-aot-engine
	@mkdir -p $(UNMODIFIED_ENGINE_PROBE_BUILD_DIR)
	"$(CLANGXX)" -Wall -Wextra -Wpedantic -Werror \
		-Wno-gnu-anonymous-struct -Wno-nested-anon-types -std=c++20 \
		-isysroot "$(SDKROOT)" \
		-mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET) \
		-arch $(HOST_ARCH) \
		-I$(DART_ENGINE_ROOT)/runtime \
		-I$(DART_ENGINE_ROOT)/runtime/engine \
		$(UNMODIFIED_ENGINE_PROBE_HOST_SOURCE) \
		$(DART_ENGINE_AOT_LIBRARY) \
		-Wl,-rpath,$(DART_ENGINE_OUT) -o $@

$(UNMODIFIED_ENGINE_PROBE_JIT_HOST): \
		$(UNMODIFIED_ENGINE_PROBE_HOST_SOURCE) | \
		unmodified-engine-probe-jit-engine
	@mkdir -p $(UNMODIFIED_ENGINE_PROBE_BUILD_DIR)
	"$(CLANGXX)" -Wall -Wextra -Wpedantic -Werror \
		-Wno-gnu-anonymous-struct -Wno-nested-anon-types -std=c++20 \
		-isysroot "$(SDKROOT)" \
		-mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET) \
		-arch $(HOST_ARCH) \
		-I$(DART_ENGINE_ROOT)/runtime \
		-I$(DART_ENGINE_ROOT)/runtime/engine \
		$(UNMODIFIED_ENGINE_PROBE_HOST_SOURCE) \
		$(DART_ENGINE_JIT_LIBRARY) \
		-Wl,-rpath,$(DART_ENGINE_JIT_OUT) -o $@

unmodified-engine-multiple-root-probe: \
		$(UNMODIFIED_ENGINE_PROBE_AOT_HOST) \
		$(UNMODIFIED_ENGINE_PROBE_AOT_SNAPSHOT) \
		$(UNMODIFIED_ENGINE_PROBE_JIT_HOST) \
		$(UNMODIFIED_ENGINE_PROBE_JIT_KERNEL) \
		$(UNMODIFIED_ENGINE_PROBE_RUNNER_SOURCE)
	"$(RUNTIME_DART_EXECUTABLE)" run \
		$(UNMODIFIED_ENGINE_PROBE_RUNNER_SOURCE) \
		--engine-root=$(DART_ENGINE_ROOT) \
		--host=$(UNMODIFIED_ENGINE_PROBE_AOT_HOST) \
		--snapshot=$(UNMODIFIED_ENGINE_PROBE_AOT_SNAPSHOT) \
		--mode=aot
	"$(RUNTIME_DART_EXECUTABLE)" run \
		$(UNMODIFIED_ENGINE_PROBE_RUNNER_SOURCE) \
		--engine-root=$(DART_ENGINE_ROOT) \
		--host=$(UNMODIFIED_ENGINE_PROBE_JIT_HOST) \
		--snapshot=$(UNMODIFIED_ENGINE_PROBE_JIT_KERNEL) \
		--mode=jit

$(PUBLIC_EMBEDDER_WORKER_PROBE_AOT_SNAPSHOT): \
		$(PUBLIC_EMBEDDER_WORKER_PROBE_DART_SOURCE) | runtime-dart-tool-check
	@mkdir -p $(PUBLIC_EMBEDDER_WORKER_PROBE_BUILD_DIR)
	"$(RUNTIME_DART_EXECUTABLE)" compile aot-snapshot --verbosity=warning \
		-o $@ $(PUBLIC_EMBEDDER_WORKER_PROBE_DART_SOURCE)

$(PUBLIC_EMBEDDER_WORKER_PROBE_JIT_KERNEL): \
		$(PUBLIC_EMBEDDER_WORKER_PROBE_DART_SOURCE) | \
		unmodified-engine-probe-jit-engine
	@mkdir -p $(PUBLIC_EMBEDDER_WORKER_PROBE_BUILD_DIR)
	"$(DART_ENGINE_KERNEL_COMPILER)" \
		--platform=$(DART_ENGINE_PLATFORM_KERNEL) \
		--no-aot --link-platform --no-embed-sources \
		--output=$@ \
		-Dsdk_hash=$(DART_SDK_HASH) \
		-Ddart.vm.product=false -Ddart.vm.asan=false \
		-Ddart.vm.msan=false -Ddart.vm.tsan=false \
		$(PUBLIC_EMBEDDER_WORKER_PROBE_DART_SOURCE)

$(PUBLIC_EMBEDDER_WORKER_PROBE_AOT_HOST): \
		$(PUBLIC_EMBEDDER_WORKER_PROBE_HOST_SOURCE) | \
		unmodified-engine-probe-aot-engine
	@mkdir -p $(PUBLIC_EMBEDDER_WORKER_PROBE_BUILD_DIR)
	"$(CLANGXX)" -Wall -Wextra -Wpedantic -Werror \
		-Wno-gnu-anonymous-struct -Wno-nested-anon-types -std=c++20 \
		-isysroot "$(SDKROOT)" \
		-mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET) \
		-arch $(HOST_ARCH) \
		-I$(DART_ENGINE_ROOT)/runtime \
		-I$(DART_ENGINE_ROOT)/runtime/engine \
		$(PUBLIC_EMBEDDER_WORKER_PROBE_HOST_SOURCE) \
		$(DART_ENGINE_AOT_LIBRARY) \
		-Wl,-rpath,$(DART_ENGINE_OUT) -Wl,-export_dynamic -o $@

$(PUBLIC_EMBEDDER_WORKER_PROBE_JIT_HOST): \
		$(PUBLIC_EMBEDDER_WORKER_PROBE_HOST_SOURCE) | \
		unmodified-engine-probe-jit-engine
	@mkdir -p $(PUBLIC_EMBEDDER_WORKER_PROBE_BUILD_DIR)
	"$(CLANGXX)" -Wall -Wextra -Wpedantic -Werror \
		-Wno-gnu-anonymous-struct -Wno-nested-anon-types -std=c++20 \
		-isysroot "$(SDKROOT)" \
		-mmacosx-version-min=$(MACOSX_DEPLOYMENT_TARGET) \
		-arch $(HOST_ARCH) \
		-I$(DART_ENGINE_ROOT)/runtime \
		-I$(DART_ENGINE_ROOT)/runtime/engine \
		$(PUBLIC_EMBEDDER_WORKER_PROBE_HOST_SOURCE) \
		$(DART_ENGINE_JIT_LIBRARY) \
		-Wl,-rpath,$(DART_ENGINE_JIT_OUT) -Wl,-export_dynamic -o $@

public-embedder-worker-probe: \
		$(PUBLIC_EMBEDDER_WORKER_PROBE_AOT_HOST) \
		$(PUBLIC_EMBEDDER_WORKER_PROBE_AOT_SNAPSHOT) \
		$(PUBLIC_EMBEDDER_WORKER_PROBE_JIT_HOST) \
		$(PUBLIC_EMBEDDER_WORKER_PROBE_JIT_KERNEL) \
		$(PUBLIC_EMBEDDER_WORKER_PROBE_RUNNER_SOURCE)
	"$(RUNTIME_DART_EXECUTABLE)" run \
		$(PUBLIC_EMBEDDER_WORKER_PROBE_RUNNER_SOURCE) \
		--engine-root=$(DART_ENGINE_ROOT) \
		--host=$(PUBLIC_EMBEDDER_WORKER_PROBE_AOT_HOST) \
		--snapshot=$(PUBLIC_EMBEDDER_WORKER_PROBE_AOT_SNAPSHOT) \
		--dart-source=$(PUBLIC_EMBEDDER_WORKER_PROBE_DART_SOURCE) \
		--native-source=$(PUBLIC_EMBEDDER_WORKER_PROBE_HOST_SOURCE) \
		--mode=aot
	"$(RUNTIME_DART_EXECUTABLE)" run \
		$(PUBLIC_EMBEDDER_WORKER_PROBE_RUNNER_SOURCE) \
		--engine-root=$(DART_ENGINE_ROOT) \
		--host=$(PUBLIC_EMBEDDER_WORKER_PROBE_JIT_HOST) \
		--snapshot=$(PUBLIC_EMBEDDER_WORKER_PROBE_JIT_KERNEL) \
		--dart-source=$(PUBLIC_EMBEDDER_WORKER_PROBE_DART_SOURCE) \
		--native-source=$(PUBLIC_EMBEDDER_WORKER_PROBE_HOST_SOURCE) \
		--mode=jit

$(PROCESS_WORKER_PROBE_AOT_EXECUTABLE): $(PROCESS_WORKER_PROBE_SOURCE) | \
		runtime-dart-tool-check
	@mkdir -p $(PROCESS_WORKER_PROBE_BUILD_DIR)
	"$(RUNTIME_DART_EXECUTABLE)" compile exe --verbosity=warning \
		-DPROCESS_PROBE_SELF_EXEC=true \
		-o $@ $(PROCESS_WORKER_PROBE_SOURCE)

process-worker-probe: unmodified-engine-sdk-clean \
		$(PROCESS_WORKER_PROBE_SOURCE) \
		$(PROCESS_WORKER_PROBE_RUNNER_SOURCE) \
		$(PROCESS_WORKER_PROBE_AOT_EXECUTABLE)
	"$(RUNTIME_DART_EXECUTABLE)" run \
		$(PROCESS_WORKER_PROBE_RUNNER_SOURCE) \
		--engine-root=$(DART_ENGINE_ROOT) \
		--command=$(RUNTIME_DART_EXECUTABLE) \
		--source=$(PROCESS_WORKER_PROBE_SOURCE) \
		--expected-arch=$(HOST_ARCH) \
		--mode=jit
	"$(RUNTIME_DART_EXECUTABLE)" run \
		$(PROCESS_WORKER_PROBE_RUNNER_SOURCE) \
		--engine-root=$(DART_ENGINE_ROOT) \
		--command=$(PROCESS_WORKER_PROBE_AOT_EXECUTABLE) \
		--source=$(PROCESS_WORKER_PROBE_SOURCE) \
		--expected-arch=$(HOST_ARCH) \
		--mode=aot

runtime-fingerprint-force:

runtime-jit-engine: runtime-architecture-check unmodified-engine-sdk-clean \
		$(RUNTIME_ENGINE_ATTESTATION_SOURCE) $(RUNTIME_RELEASE_SUPPORT_SOURCE)
	"$(RUNTIME_ENGINE_PYTHON)" "$(DART_ENGINE_GN)" --mode=release \
		--arch=$(RUNTIME_DART_TARGET_ARCH)
	@"$(RUNTIME_DART_EXECUTABLE)" --suppress-analytics run \
		$(RUNTIME_ENGINE_ATTESTATION_SOURCE) --mode=validate \
		--engine-root=$(DART_ENGINE_ROOT) \
		--expected-revision=$(DART_SDK_REVISION) \
		--engine-library=$(RUNTIME_ENGINE_JIT_LIBRARY) \
		--kernel-compiler=$(RUNTIME_ENGINE_KERNEL_COMPILER) \
		--platform-dill=$(RUNTIME_ENGINE_PLATFORM_KERNEL) \
		--output=$(RUNTIME_ENGINE_JIT_ATTESTATION); \
	attestation_exit=$$?; \
	if [[ $$attestation_exit -eq 3 ]]; then \
		"$(DART_ENGINE_NINJA)" -C $(RUNTIME_ENGINE_RELEASE_OUT) \
			-t clean dart_engine_jit_shared bootstrap_gen_kernel.exe \
			$(RUNTIME_ENGINE_TOOLCHAIN)/vm_platform.dill; \
	elif [[ $$attestation_exit -ne 0 ]]; then \
		exit $$attestation_exit; \
	fi
	"$(DART_ENGINE_NINJA)" -C $(RUNTIME_ENGINE_RELEASE_OUT) \
		dart_engine_jit_shared bootstrap_gen_kernel.exe \
		$(RUNTIME_ENGINE_TOOLCHAIN)/vm_platform.dill
	@test -x $(RUNTIME_ENGINE_KERNEL_COMPILER)
	@test -f $(RUNTIME_ENGINE_PLATFORM_KERNEL)
	"$(RUNTIME_DART_EXECUTABLE)" --suppress-analytics run \
		$(RUNTIME_ENGINE_ATTESTATION_SOURCE) --mode=record \
		--engine-root=$(DART_ENGINE_ROOT) \
		--expected-revision=$(DART_SDK_REVISION) \
		--engine-library=$(RUNTIME_ENGINE_JIT_LIBRARY) \
		--kernel-compiler=$(RUNTIME_ENGINE_KERNEL_COMPILER) \
		--platform-dill=$(RUNTIME_ENGINE_PLATFORM_KERNEL) \
		--output=$(RUNTIME_ENGINE_JIT_ATTESTATION)
	@$(MAKE) unmodified-engine-sdk-clean

runtime-aot-engine: runtime-architecture-check unmodified-engine-sdk-clean \
		$(RUNTIME_ENGINE_ATTESTATION_SOURCE) $(RUNTIME_RELEASE_SUPPORT_SOURCE)
	"$(RUNTIME_ENGINE_PYTHON)" "$(DART_ENGINE_GN)" --mode=product \
		--arch=$(RUNTIME_DART_TARGET_ARCH)
	@"$(RUNTIME_DART_EXECUTABLE)" --suppress-analytics run \
		$(RUNTIME_ENGINE_ATTESTATION_SOURCE) --mode=validate \
		--engine-root=$(DART_ENGINE_ROOT) \
		--expected-revision=$(DART_SDK_REVISION) \
		--engine-library=$(RUNTIME_ENGINE_AOT_LIBRARY) \
		--kernel-compiler=$(RUNTIME_ENGINE_AOT_KERNEL_COMPILER) \
		--platform-dill=$(RUNTIME_ENGINE_AOT_PLATFORM_KERNEL) \
		--snapshotter=$(RUNTIME_ENGINE_AOT_SNAPSHOTTER) \
		--output=$(RUNTIME_ENGINE_AOT_ATTESTATION); \
	attestation_exit=$$?; \
	if [[ $$attestation_exit -eq 3 ]]; then \
		"$(DART_ENGINE_NINJA)" -C $(RUNTIME_ENGINE_PRODUCT_OUT) \
			-t clean dart_engine_aot_shared gen_snapshot \
			bootstrap_gen_kernel.exe \
			$(RUNTIME_ENGINE_TOOLCHAIN)/vm_platform.dill; \
	elif [[ $$attestation_exit -ne 0 ]]; then \
		exit $$attestation_exit; \
	fi
	"$(DART_ENGINE_NINJA)" -C $(RUNTIME_ENGINE_PRODUCT_OUT) \
		dart_engine_aot_shared gen_snapshot bootstrap_gen_kernel.exe \
		$(RUNTIME_ENGINE_TOOLCHAIN)/vm_platform.dill
	@test -x $(RUNTIME_ENGINE_AOT_KERNEL_COMPILER)
	@test -f $(RUNTIME_ENGINE_AOT_PLATFORM_KERNEL)
	@test -x $(RUNTIME_ENGINE_AOT_SNAPSHOTTER)
	"$(RUNTIME_DART_EXECUTABLE)" --suppress-analytics run \
		$(RUNTIME_ENGINE_ATTESTATION_SOURCE) --mode=record \
		--engine-root=$(DART_ENGINE_ROOT) \
		--expected-revision=$(DART_SDK_REVISION) \
		--engine-library=$(RUNTIME_ENGINE_AOT_LIBRARY) \
		--kernel-compiler=$(RUNTIME_ENGINE_AOT_KERNEL_COMPILER) \
		--platform-dill=$(RUNTIME_ENGINE_AOT_PLATFORM_KERNEL) \
		--snapshotter=$(RUNTIME_ENGINE_AOT_SNAPSHOTTER) \
		--output=$(RUNTIME_ENGINE_AOT_ATTESTATION)
	@$(MAKE) unmodified-engine-sdk-clean

$(DEVELOPER_JIT_FINGERPRINT): runtime-fingerprint-force \
		$(RUNTIME_PACKAGE_CONFIG) \
		| runtime-jit-engine runtime-dart-tool-check
	@mkdir -p $(DEVELOPER_JIT_BUILD_DIR)
	"$(RUNTIME_DART_EXECUTABLE)" --suppress-analytics run \
		$(RUNTIME_FINGERPRINT_SOURCE) \
		--mode=developer-jit \
		--architecture=$(RUNTIME_ARCH) \
		--deployment-target=$(MACOSX_DEPLOYMENT_TARGET) \
		--bundle-version=$(RUNTIME_BUNDLE_VERSION) \
		--project-root=$(PROJECT_ROOT) \
		--dart-appkit-root=$(DART_APPKIT_ROOT) \
		--dart-engine-root=$(DART_ENGINE_ROOT) \
		--dart-sdk-root=$(DART_SDK_ROOT) \
		--dart-executable="$(RUNTIME_DART_EXECUTABLE)" \
		--engine-gn-script="$(DART_ENGINE_GN)" \
		--engine-ninja="$(DART_ENGINE_NINJA)" \
		--engine-python="$(RUNTIME_ENGINE_PYTHON)" \
		--make-executable="$(MAKE)" \
		--runtime-build-root=$(RUNTIME_BUILD_DIR) \
		--package-config=$(RUNTIME_PACKAGE_CONFIG) \
		--engine-library=$(RUNTIME_ENGINE_JIT_LIBRARY) \
		--kernel-compiler=$(RUNTIME_ENGINE_KERNEL_COMPILER) \
		--platform-dill=$(RUNTIME_ENGINE_PLATFORM_KERNEL) \
		--clang="$(CLANGXX)" --sdk-root="$(SDKROOT)" \
		--native-flags="$(NATIVE_FLAGS) -fblocks -fvisibility=hidden" \
		--kernel-flags="--no-aot --link-platform --no-embed-sources \
		-Dsdk_hash=$(DART_SDK_HASH) -Ddart.vm.product=false \
		-Ddart.vm.asan=false -Ddart.vm.msan=false -Ddart.vm.tsan=false" \
		--worker-kernel-flags="$(RUNTIME_WORKER_KERNEL_FLAGS)" \
		--snapshot-flags=not-applicable \
		$(RUNTIME_EXTRA_BUILD_INPUT_ARGUMENT) --output=$@

$(RELEASE_AOT_FINGERPRINT): runtime-fingerprint-force \
		$(RUNTIME_PACKAGE_CONFIG) \
		| runtime-aot-engine runtime-dart-tool-check
	@mkdir -p $(RELEASE_AOT_BUILD_DIR)
	"$(RUNTIME_DART_EXECUTABLE)" run $(RUNTIME_FINGERPRINT_SOURCE) \
		--mode=release-aot \
		--architecture=$(RUNTIME_ARCH) \
		--deployment-target=$(MACOSX_DEPLOYMENT_TARGET) \
		--bundle-version=$(RUNTIME_BUNDLE_VERSION) \
		--project-root=$(PROJECT_ROOT) \
		--dart-appkit-root=$(DART_APPKIT_ROOT) \
		--dart-engine-root=$(DART_ENGINE_ROOT) \
		--dart-sdk-root=$(DART_SDK_ROOT) \
		--dart-executable="$(RUNTIME_DART_EXECUTABLE)" \
		--engine-gn-script="$(DART_ENGINE_GN)" \
		--engine-ninja="$(DART_ENGINE_NINJA)" \
		--engine-python="$(RUNTIME_ENGINE_PYTHON)" \
		--make-executable="$(MAKE)" \
		--runtime-build-root=$(RUNTIME_BUILD_DIR) \
		--package-config=$(RUNTIME_PACKAGE_CONFIG) \
		--engine-library=$(RUNTIME_ENGINE_AOT_LIBRARY) \
		--kernel-compiler=$(RUNTIME_ENGINE_AOT_KERNEL_COMPILER) \
		--platform-dill=$(RUNTIME_ENGINE_AOT_PLATFORM_KERNEL) \
		--snapshotter=$(RUNTIME_ENGINE_AOT_SNAPSHOTTER) \
		--snapshotter-runner-executable="$(RUNTIME_SNAPSHOTTER_RUNNER_EXECUTABLE)" \
		--snapshotter-runner-arguments="$(RUNTIME_SNAPSHOTTER_RUNNER_ARGUMENTS)" \
		--clang="$(CLANGXX)" --sdk-root="$(SDKROOT)" \
		--native-flags="$(NATIVE_FLAGS) -fblocks -fvisibility=hidden" \
		--kernel-flags="--aot --link-platform --no-embed-sources \
		--target-os=macos --invocation-modes=compile --verbosity=error \
		-Ddart.vm.product=true -Ddart.vm.asan=false \
		-Ddart.vm.msan=false -Ddart.vm.tsan=false" \
		--worker-executable-flags="$(RUNTIME_WORKER_EXECUTABLE_FLAGS)" \
		--snapshot-flags="--snapshot-kind=app-aot-macho-dylib --macho" \
		$(RUNTIME_EXTRA_BUILD_INPUT_ARGUMENT) --output=$@

$(DEVELOPER_JIT_RUNNER): $(RUNTIME_BRIDGE_HEADERS) \
		$(RUNTIME_BRIDGE_SOURCES) $(RUNTIME_LIFECYCLE_HEADER) \
		$(RUNTIME_LIFECYCLE_SOURCE) $(RUNTIME_TERMINAL_VIEW_HEADER) \
		$(RUNTIME_TERMINAL_VIEW_SOURCE) $(RUNTIME_WORKER_CONFIGURATION_HEADER) \
		$(RUNTIME_WORKER_CONFIGURATION_SOURCE) $(RUNTIME_JIT_RUNNER_HEADERS) \
		$(RUNTIME_JIT_RUNNER_SOURCES) $(DART_APPKIT_ROOT)/Makefile \
		$(DEVELOPER_JIT_FINGERPRINT)
	@mkdir -p $(DEVELOPER_JIT_BUILD_DIR)
	"$(CLANGXX)" $(RUNTIME_NATIVE_FLAG_PREFIX) \
		-isysroot "$(SDKROOT)" $(RUNTIME_NATIVE_FLAG_SUFFIX) \
		-arch $(RUNTIME_ARCH) \
		-DDA_DART_ENGINE_REVISION=\"$(shell /usr/bin/git -C $(DART_ENGINE_ROOT) rev-parse HEAD)\" \
		-DDT_RUNTIME_WORKER_EXECUTABLE=\"$(RUNTIME_DART_EXECUTABLE)\" \
		-I$(DART_APPKIT_ROOT)/native/bridge/include \
		-I$(DART_APPKIT_ROOT)/native/bridge/src \
		-I$(DART_APPKIT_ROOT)/native/runner \
		-I$(PROJECT_ROOT)/native/macos/runtime \
		-I$(PROJECT_ROOT)/native/macos/renderer \
		-I$(DART_ENGINE_ROOT)/runtime \
		-I$(DART_ENGINE_ROOT)/runtime/engine \
		$(RUNTIME_BRIDGE_SOURCES) $(RUNTIME_LIFECYCLE_SOURCE) \
		$(RUNTIME_TERMINAL_VIEW_SOURCE) \
		$(RUNTIME_WORKER_CONFIGURATION_SOURCE) \
		$(RUNTIME_JIT_RUNNER_SOURCES) \
		$(RUNTIME_ENGINE_JIT_LIBRARY) \
		-framework AppKit -framework CoreFoundation -framework Metal \
		-framework MetalKit \
		-Wl,-rpath,@executable_path/../Frameworks \
		-Wl,-export_dynamic -o $@

$(DEVELOPER_JIT_KERNEL): $(RUNTIME_DART_SOURCES) $(RUNTIME_PACKAGE_CONFIG) \
		$(DEVELOPER_JIT_FINGERPRINT)
	@mkdir -p $(DEVELOPER_JIT_BUILD_DIR)
	$(RUNTIME_ENGINE_KERNEL_COMPILER) \
		--platform=$(RUNTIME_ENGINE_PLATFORM_KERNEL) \
		--packages=$(RUNTIME_PACKAGE_CONFIG) \
		--no-aot --link-platform --no-embed-sources \
		--output=$@ --depfile=$(DEVELOPER_JIT_KERNEL_DEPFILE) \
		-Dsdk_hash=$(DART_SDK_HASH) \
		-Ddart.vm.product=false -Ddart.vm.asan=false \
		-Ddart.vm.msan=false -Ddart.vm.tsan=false \
		$(PROJECT_ROOT)/bin/main.dart

$(DEVELOPER_JIT_WORKER_KERNEL): $(RUNTIME_DART_SOURCES) \
		$(RUNTIME_PACKAGE_CONFIG) $(DEVELOPER_JIT_FINGERPRINT)
	@mkdir -p $(DEVELOPER_JIT_BUILD_DIR)
	"$(RUNTIME_DART_EXECUTABLE)" --suppress-analytics compile kernel \
		$(RUNTIME_WORKER_KERNEL_FLAGS) \
		--packages=$(RUNTIME_PACKAGE_CONFIG) \
		--depfile=$(DEVELOPER_JIT_WORKER_KERNEL_DEPFILE) \
		--output=$@ $(PROJECT_ROOT)/bin/runtime_worker.dart

$(DEVELOPER_JIT_MANIFEST): $(RUNTIME_MANIFEST_SOURCE) \
		$(RUNTIME_RELEASE_SUPPORT_SOURCE) $(DEVELOPER_JIT_FINGERPRINT) \
		$(DEVELOPER_JIT_RUNNER) $(DEVELOPER_JIT_KERNEL) \
		$(DEVELOPER_JIT_WORKER_KERNEL)
	"$(RUNTIME_DART_EXECUTABLE)" --suppress-analytics run \
		$(RUNTIME_MANIFEST_SOURCE) \
		--mode=developer-jit \
		--architecture=$(RUNTIME_ARCH) \
		--fingerprint=$(DEVELOPER_JIT_FINGERPRINT) \
		--launcher=$(DEVELOPER_JIT_RUNNER) \
		--engine=$(RUNTIME_ENGINE_JIT_LIBRARY) \
		--payload=$(DEVELOPER_JIT_KERNEL) \
		--worker-payload=$(DEVELOPER_JIT_WORKER_KERNEL) --output=$@

$(DEVELOPER_JIT_BUNDLE_STAMP): $(DEVELOPER_JIT_RUNNER) \
		$(DEVELOPER_JIT_KERNEL) $(DEVELOPER_JIT_WORKER_KERNEL) \
		$(DEVELOPER_JIT_MANIFEST) \
		$(DEVELOPER_JIT_INFO_PLIST) $(DART_ENGINE_ROOT)/LICENSE Makefile
	@rm -rf $(DEVELOPER_JIT_BUNDLE)
	@rm -f $(DEVELOPER_JIT_AUDIT_REPORT)
	@mkdir -p $(DEVELOPER_JIT_BUNDLE)/Contents/MacOS
	@mkdir -p $(DEVELOPER_JIT_BUNDLE)/Contents/Frameworks
	@mkdir -p $(DEVELOPER_JIT_BUNDLE)/Contents/Resources
	cp $(DEVELOPER_JIT_RUNNER) $(DEVELOPER_JIT_EXECUTABLE)
	cp $(RUNTIME_ENGINE_JIT_LIBRARY) \
		$(DEVELOPER_JIT_BUNDLE)/Contents/Frameworks/libdart_engine_jit_shared.dylib
	cp $(DEVELOPER_JIT_KERNEL) $(DEVELOPER_JIT_BUNDLED_KERNEL)
	cp $(DEVELOPER_JIT_WORKER_KERNEL) \
		$(DEVELOPER_JIT_BUNDLED_WORKER_KERNEL)
	cp $(DEVELOPER_JIT_MANIFEST) \
		$(DEVELOPER_JIT_BUNDLE)/Contents/Resources/runtime-build-manifest.json
	cp $(DART_ENGINE_ROOT)/LICENSE \
		$(DEVELOPER_JIT_BUNDLE)/Contents/Resources/DART_SDK_LICENSE.txt
	cp $(DEVELOPER_JIT_INFO_PLIST) \
		$(DEVELOPER_JIT_BUNDLE)/Contents/Info.plist
	chmod 755 $(DEVELOPER_JIT_EXECUTABLE)
	codesign --force --deep --sign - $(DEVELOPER_JIT_BUNDLE)
	@$(MAKE) unmodified-engine-sdk-clean
	touch $@

developer-jit-build: runtime-architecture-check $(DEVELOPER_JIT_BUNDLE_STAMP)

developer-jit-run: developer-jit-build
	$(DEVELOPER_JIT_EXECUTABLE) \
		--kernel $(DEVELOPER_JIT_BUNDLED_KERNEL) \
		--sdk-version $(DART_SDK_VERSION) \
		--sdk-revision $(DART_SDK_REVISION) -- $(RUNTIME_ARGUMENTS)

developer-jit-audit: developer-jit-build
	@if [[ -f $(DEVELOPER_JIT_AUDIT_REPORT) ]]; then \
		"$(RUNTIME_DART_EXECUTABLE)" --suppress-analytics run \
			$(RUNTIME_AUDIT_SOURCE) \
			--mode=developer-jit \
			--expected-architectures=$(RUNTIME_ARCH) \
			--deployment-target=$(MACOSX_DEPLOYMENT_TARGET) \
			--validate-report=$(DEVELOPER_JIT_AUDIT_REPORT) \
			$(DEVELOPER_JIT_BUNDLE); \
	else \
		"$(RUNTIME_DART_EXECUTABLE)" --suppress-analytics run \
			$(RUNTIME_AUDIT_SOURCE) \
			--mode=developer-jit \
			--expected-architectures=$(RUNTIME_ARCH) \
			--deployment-target=$(MACOSX_DEPLOYMENT_TARGET) \
			--output-report=$(DEVELOPER_JIT_AUDIT_REPORT) \
			$(DEVELOPER_JIT_BUNDLE); \
	fi

developer-jit-clean-sdk-test: runtime-dart-tool-check
	"$(RUNTIME_DART_EXECUTABLE)" --suppress-analytics run \
		$(RUNTIME_FRESHNESS_TEST_SOURCE) \
		--project-root=$(PROJECT_ROOT) --make=/usr/bin/make \
		--focus=developer-clean-sdk

developer-jit-integration: developer-jit-build
	"$(RUNTIME_DART_EXECUTABLE)" --suppress-analytics run \
		$(RUNTIME_INTEGRATION_SOURCE) \
		--mode=developer-jit \
		--launch-architecture=$(RUNTIME_ARCH) \
		$(DEVELOPER_JIT_BUNDLE)

developer-jit-lifecycle: developer-jit-build
	"$(RUNTIME_DART_EXECUTABLE)" --suppress-analytics run \
		$(RUNTIME_INTEGRATION_SOURCE) \
		--mode=developer-jit --suite=lifecycle \
		--launch-architecture=$(RUNTIME_ARCH) \
		$(DEVELOPER_JIT_BUNDLE)

developer-jit-traffic: developer-jit-build
	"$(RUNTIME_DART_EXECUTABLE)" --suppress-analytics run \
		$(RUNTIME_INTEGRATION_SOURCE) \
		--mode=developer-jit --suite=traffic \
		--launch-architecture=$(RUNTIME_ARCH) \
		$(DEVELOPER_JIT_BUNDLE)

$(RELEASE_AOT_KERNEL): $(RUNTIME_DART_SOURCES) $(RUNTIME_PACKAGE_CONFIG) \
		$(RELEASE_AOT_FINGERPRINT)
	@mkdir -p $(RELEASE_AOT_BUILD_DIR)
	$(RUNTIME_ENGINE_AOT_KERNEL_COMPILER) \
		--platform=$(RUNTIME_ENGINE_AOT_PLATFORM_KERNEL) \
		--packages=$(RUNTIME_PACKAGE_CONFIG) --aot --link-platform \
		--no-embed-sources --target-os=macos \
		--invocation-modes=compile --verbosity=error \
		--output=$@ --depfile=$(RELEASE_AOT_KERNEL_DEPFILE) \
		--depfile-target=$(RELEASE_AOT_SNAPSHOT) \
		-Ddart.vm.product=true -Ddart.vm.asan=false \
		-Ddart.vm.msan=false -Ddart.vm.tsan=false \
		$(PROJECT_ROOT)/bin/main.dart

$(RELEASE_AOT_SNAPSHOT): $(RELEASE_AOT_KERNEL) $(RELEASE_AOT_FINGERPRINT)
	"$(RUNTIME_SNAPSHOTTER_RUNNER_EXECUTABLE)" \
		$(RUNTIME_SNAPSHOTTER_RUNNER_ARGUMENTS) \
		$(RUNTIME_ENGINE_AOT_SNAPSHOTTER) \
		--snapshot-kind=app-aot-macho-dylib --macho=$@ \
		$(RELEASE_AOT_KERNEL)

$(RELEASE_AOT_WORKER_EXECUTABLE): $(RUNTIME_DART_SOURCES) \
		$(RUNTIME_PACKAGE_CONFIG) $(RELEASE_AOT_FINGERPRINT)
	@mkdir -p $(RELEASE_AOT_BUILD_DIR)
	"$(RUNTIME_DART_EXECUTABLE)" --suppress-analytics compile exe \
		$(RUNTIME_WORKER_EXECUTABLE_FLAGS) \
		--packages=$(RUNTIME_PACKAGE_CONFIG) \
		--depfile=$(RELEASE_AOT_WORKER_DEPFILE) \
		--output=$@ $(PROJECT_ROOT)/bin/runtime_worker.dart

$(RELEASE_AOT_HOST): $(RELEASE_AOT_HOST_SOURCE) \
		$(RUNTIME_BRIDGE_HEADERS) $(RUNTIME_BRIDGE_SOURCES) \
		$(RUNTIME_LIFECYCLE_HEADER) $(RUNTIME_LIFECYCLE_SOURCE) \
		$(RUNTIME_TERMINAL_VIEW_HEADER) $(RUNTIME_TERMINAL_VIEW_SOURCE) \
		$(RUNTIME_WORKER_CONFIGURATION_HEADER) \
		$(RUNTIME_WORKER_CONFIGURATION_SOURCE) \
		$(RUNTIME_MESSAGE_PUMP_HEADERS) $(RUNTIME_MESSAGE_PUMP_SOURCE) \
		$(RUNTIME_EVENT_ENCODER_SOURCE) \
		$(RELEASE_AOT_FINGERPRINT)
	@mkdir -p $(RELEASE_AOT_BUILD_DIR)
	"$(CLANGXX)" $(RUNTIME_NATIVE_FLAG_PREFIX) \
		-isysroot "$(SDKROOT)" $(RUNTIME_NATIVE_FLAG_SUFFIX) \
		-arch $(RUNTIME_ARCH) \
		-DDT_DART_SDK_VERSION=\"$(DART_SDK_VERSION)\" \
		-I$(DART_APPKIT_ROOT)/native/bridge/include \
		-I$(DART_APPKIT_ROOT)/native/bridge/src \
		-I$(DART_APPKIT_ROOT)/native/runner \
		-I$(PROJECT_ROOT)/native/macos/runtime \
		-I$(PROJECT_ROOT)/native/macos/renderer \
		-I$(DART_ENGINE_ROOT)/runtime \
		-I$(DART_ENGINE_ROOT)/runtime/engine \
		$(RUNTIME_BRIDGE_SOURCES) $(RUNTIME_LIFECYCLE_SOURCE) \
		$(RUNTIME_TERMINAL_VIEW_SOURCE) \
		$(RUNTIME_WORKER_CONFIGURATION_SOURCE) \
		$(RUNTIME_MESSAGE_PUMP_SOURCE) \
		$(RUNTIME_EVENT_ENCODER_SOURCE) \
		$(RELEASE_AOT_HOST_SOURCE) $(RUNTIME_ENGINE_AOT_LIBRARY) \
		-framework AppKit -framework CoreFoundation -framework Metal \
		-framework MetalKit \
		-Wl,-rpath,@executable_path/../Frameworks \
		-Wl,-export_dynamic -o $@

$(RELEASE_AOT_PACKAGED_HOST): $(RELEASE_AOT_HOST) Makefile
	@mkdir -p $(RELEASE_AOT_PACKAGED_DIR)
	cp $(RELEASE_AOT_HOST) $@
	chmod 755 $@
	/usr/bin/codesign --force --sign - --timestamp=none $@

$(RELEASE_AOT_PACKAGED_ENGINE): $(RELEASE_AOT_FINGERPRINT) Makefile \
		| runtime-aot-engine
	@mkdir -p $(RELEASE_AOT_PACKAGED_DIR)
	cp $(RUNTIME_ENGINE_AOT_LIBRARY) $@
	chmod 755 $@
	/usr/bin/codesign --force --sign - --timestamp=none $@

$(RELEASE_AOT_PACKAGED_SNAPSHOT): $(RELEASE_AOT_SNAPSHOT) Makefile
	@mkdir -p $(RELEASE_AOT_PACKAGED_DIR)
	cp $(RELEASE_AOT_SNAPSHOT) $@
	chmod 755 $@
	/usr/bin/codesign --force --sign - --timestamp=none $@

$(RELEASE_AOT_PACKAGED_WORKER_EXECUTABLE): \
		$(RELEASE_AOT_WORKER_EXECUTABLE) Makefile
	@mkdir -p $(RELEASE_AOT_PACKAGED_DIR)
	cp $(RELEASE_AOT_WORKER_EXECUTABLE) $@
	chmod 755 $@
	/usr/bin/codesign --force --sign - --timestamp=none $@

$(RELEASE_AOT_MANIFEST): $(RUNTIME_MANIFEST_SOURCE) \
		$(RUNTIME_RELEASE_SUPPORT_SOURCE) $(RELEASE_AOT_FINGERPRINT) \
		$(RELEASE_AOT_PACKAGED_HOST) $(RELEASE_AOT_KERNEL) \
		$(RELEASE_AOT_PACKAGED_ENGINE) $(RELEASE_AOT_PACKAGED_SNAPSHOT) \
		$(RELEASE_AOT_PACKAGED_WORKER_EXECUTABLE)
	"$(RUNTIME_DART_EXECUTABLE)" run $(RUNTIME_MANIFEST_SOURCE) \
		--mode=release-aot \
		--architecture=$(RUNTIME_ARCH) \
		--fingerprint=$(RELEASE_AOT_FINGERPRINT) \
		--launcher=$(RELEASE_AOT_PACKAGED_HOST) \
		--engine=$(RELEASE_AOT_PACKAGED_ENGINE) \
		--payload=$(RELEASE_AOT_PACKAGED_SNAPSHOT) \
		--worker-executable=$(RELEASE_AOT_PACKAGED_WORKER_EXECUTABLE) \
		--intermediate=$(RELEASE_AOT_KERNEL) --output=$@

$(RELEASE_AOT_BUNDLE_STAMP): $(RELEASE_AOT_PACKAGED_HOST) \
		$(RELEASE_AOT_PACKAGED_ENGINE) $(RELEASE_AOT_PACKAGED_SNAPSHOT) \
		$(RELEASE_AOT_PACKAGED_WORKER_EXECUTABLE) \
		$(RELEASE_AOT_MANIFEST) \
		$(RELEASE_AOT_INFO_PLIST) $(DART_ENGINE_ROOT)/LICENSE Makefile
	@rm -rf $(RELEASE_AOT_BUNDLE)
	@rm -f $(RELEASE_AOT_AUDIT_REPORT)
	@mkdir -p $(RELEASE_AOT_BUNDLE)/Contents/MacOS
	@mkdir -p $(RELEASE_AOT_BUNDLE)/Contents/Helpers
	@mkdir -p $(RELEASE_AOT_BUNDLE)/Contents/Frameworks
	@mkdir -p $(RELEASE_AOT_BUNDLE)/Contents/Resources
	cp $(RELEASE_AOT_PACKAGED_HOST) $(RELEASE_AOT_EXECUTABLE)
	cp $(RELEASE_AOT_PACKAGED_ENGINE) \
		$(RELEASE_AOT_BUNDLE)/Contents/Frameworks/libdart_engine_aot_shared.dylib
	cp $(RELEASE_AOT_PACKAGED_SNAPSHOT) \
		$(RELEASE_AOT_BUNDLE)/Contents/Resources/application.aot
	cp $(RELEASE_AOT_PACKAGED_WORKER_EXECUTABLE) \
		$(RELEASE_AOT_BUNDLED_WORKER_EXECUTABLE)
	cp $(RELEASE_AOT_MANIFEST) \
		$(RELEASE_AOT_BUNDLE)/Contents/Resources/runtime-build-manifest.json
	cp $(DART_ENGINE_ROOT)/LICENSE \
		$(RELEASE_AOT_BUNDLE)/Contents/Resources/DART_SDK_LICENSE.txt
	cp $(RELEASE_AOT_INFO_PLIST) \
		$(RELEASE_AOT_BUNDLE)/Contents/Info.plist
	/usr/bin/codesign --force --sign - --timestamp=none $(RELEASE_AOT_BUNDLE)
	touch $@

release-aot-build: runtime-architecture-check $(RELEASE_AOT_BUNDLE_STAMP)

release-aot-run: release-aot-build
	$(RELEASE_AOT_EXECUTABLE) $(RUNTIME_ARGUMENTS)

release-aot-audit: release-aot-build
	@if [[ -f $(RELEASE_AOT_AUDIT_REPORT) ]]; then \
		"$(RUNTIME_DART_EXECUTABLE)" run $(RUNTIME_AUDIT_SOURCE) \
			--mode=release-aot \
			--expected-architectures=$(RUNTIME_ARCH) \
			--deployment-target=$(MACOSX_DEPLOYMENT_TARGET) \
			--validate-report=$(RELEASE_AOT_AUDIT_REPORT) \
			$(RELEASE_AOT_BUNDLE); \
	else \
		"$(RUNTIME_DART_EXECUTABLE)" run $(RUNTIME_AUDIT_SOURCE) \
			--mode=release-aot \
			--expected-architectures=$(RUNTIME_ARCH) \
			--deployment-target=$(MACOSX_DEPLOYMENT_TARGET) \
			--output-report=$(RELEASE_AOT_AUDIT_REPORT) \
			$(RELEASE_AOT_BUNDLE); \
	fi

release-aot-clean-sdk-test: runtime-dart-tool-check
	"$(RUNTIME_DART_EXECUTABLE)" --suppress-analytics run \
		$(RUNTIME_FRESHNESS_TEST_SOURCE) \
		--project-root=$(PROJECT_ROOT) --make=/usr/bin/make \
		--focus=release-clean-sdk

release-aot-integration: release-aot-build
	"$(RUNTIME_DART_EXECUTABLE)" run $(RUNTIME_INTEGRATION_SOURCE) \
		--mode=release-aot \
		--launch-architecture=$(RUNTIME_ARCH) \
		$(RELEASE_AOT_BUNDLE)

release-aot-lifecycle: release-aot-build
	"$(RUNTIME_DART_EXECUTABLE)" run $(RUNTIME_INTEGRATION_SOURCE) \
		--mode=release-aot --suite=lifecycle \
		--launch-architecture=$(RUNTIME_ARCH) \
		$(RELEASE_AOT_BUNDLE)

release-aot-traffic: release-aot-build
	"$(RUNTIME_DART_EXECUTABLE)" run $(RUNTIME_INTEGRATION_SOURCE) \
		--mode=release-aot --suite=traffic \
		--launch-architecture=$(RUNTIME_ARCH) \
		$(RELEASE_AOT_BUNDLE)

runtime-source-check: runtime-dart-tool-check
	"$(RUNTIME_DART_EXECUTABLE)" format --output=none \
		--set-exit-if-changed \
		bin lib test tool benchmark
	/usr/bin/xcrun clang-format --style=file:$(DART_APPKIT_ROOT)/.clang-format \
		--dry-run --Werror $(RUNTIME_LIFECYCLE_HEADER) \
		$(RUNTIME_LIFECYCLE_SOURCE) $(RUNTIME_DIAGNOSTICS_HEADER) \
		$(RUNTIME_DIAGNOSTICS_SOURCE) $(RUNTIME_DIAGNOSTICS_TEST_SOURCE) \
		$(RUNTIME_TERMINAL_VIEW_HEADER) \
		$(RUNTIME_TERMINAL_VIEW_SOURCE) $(RUNTIME_TERMINAL_VIEW_TEST_SOURCE) \
		$(RUNTIME_WORKER_CONFIGURATION_HEADER) \
		$(RUNTIME_WORKER_CONFIGURATION_SOURCE) $(RUNTIME_JIT_MAIN_SOURCE) \
		$(RUNTIME_EVENT_ENCODER_SOURCE) $(RELEASE_AOT_HOST_SOURCE)
	/usr/bin/xcrun clang -x c -std=c11 -Wall -Wextra -Wpedantic -Werror \
		-fsyntax-only $(RUNTIME_LIFECYCLE_HEADER)
	/usr/bin/xcrun clang++ -x c++ -std=c++20 -Wall -Wextra -Wpedantic \
		-Werror -fsyntax-only $(RUNTIME_LIFECYCLE_HEADER)
	/usr/bin/xcrun clang -x c -std=c11 -Wall -Wextra -Wpedantic -Werror \
		-fsyntax-only $(RUNTIME_DIAGNOSTICS_HEADER)
	/usr/bin/xcrun clang++ -x c++ -std=c++20 -Wall -Wextra -Wpedantic \
		-Werror -fsyntax-only $(RUNTIME_DIAGNOSTICS_HEADER)
	/usr/bin/plutil -lint \
		$(DEVELOPER_JIT_INFO_PLIST) $(RELEASE_AOT_INFO_PLIST)
	"$(RUNTIME_DART_EXECUTABLE)" analyze
	"$(RUNTIME_DART_EXECUTABLE)" run test/run_tests.dart
	@$(MAKE) runtime-diagnostics-test
	@$(MAKE) terminal-metal-view-test

$(RUNTIME_DIAGNOSTICS_TEST_BINARY): $(RUNTIME_DIAGNOSTICS_HEADER) \
		$(RUNTIME_DIAGNOSTICS_SOURCE) $(RUNTIME_DIAGNOSTICS_TEST_SOURCE)
	@mkdir -p $(dir $@)
	"$(CLANGXX)" $(NATIVE_FLAGS) -fblocks -fvisibility=hidden \
		-arch $(HOST_ARCH) \
		-I$(PROJECT_ROOT)/native/macos/runtime \
		$(RUNTIME_DIAGNOSTICS_SOURCE) $(RUNTIME_DIAGNOSTICS_TEST_SOURCE) \
		-framework Foundation -o $@

runtime-diagnostics-test: $(RUNTIME_DIAGNOSTICS_TEST_BINARY)
	$(RUNTIME_DIAGNOSTICS_TEST_BINARY)

$(RUNTIME_TERMINAL_VIEW_TEST_BINARY): $(RUNTIME_BRIDGE_HEADERS) \
		$(RUNTIME_BRIDGE_SOURCES) $(RUNTIME_TERMINAL_VIEW_HEADER) \
		$(RUNTIME_TERMINAL_VIEW_SOURCE) $(RUNTIME_TERMINAL_VIEW_TEST_SOURCE)
	@mkdir -p $(dir $@)
	"$(CLANGXX)" $(NATIVE_FLAGS) -fblocks -fvisibility=hidden \
		-arch $(HOST_ARCH) \
		-I$(DART_APPKIT_ROOT)/native/bridge/include \
		-I$(DART_APPKIT_ROOT)/native/bridge/src \
		-I$(PROJECT_ROOT)/native/macos/renderer \
		$(RUNTIME_BRIDGE_SOURCES) $(RUNTIME_TERMINAL_VIEW_SOURCE) \
		$(RUNTIME_TERMINAL_VIEW_TEST_SOURCE) \
		-framework AppKit -framework CoreFoundation -framework Metal \
		-framework MetalKit -o $@

terminal-metal-view-test: $(RUNTIME_TERMINAL_VIEW_TEST_BINARY)
	$(RUNTIME_TERMINAL_VIEW_TEST_BINARY)

runtime-bundle-audit: developer-jit-build release-aot-build
	@$(MAKE) developer-jit-audit
	@$(MAKE) release-aot-audit

runtime-integration: developer-jit-build release-aot-build
	@$(MAKE) developer-jit-integration
	@$(MAKE) release-aot-integration
	@$(MAKE) runtime-lifecycle-integration
	@$(MAKE) runtime-traffic-integration

runtime-lifecycle-integration: developer-jit-build release-aot-build
	@$(MAKE) developer-jit-lifecycle
	@$(MAKE) release-aot-lifecycle

runtime-traffic-integration: developer-jit-build release-aot-build
	@$(MAKE) developer-jit-traffic
	@$(MAKE) release-aot-traffic

runtime-verify:
	@$(MAKE) runtime-source-check
	@$(MAKE) RUNTIME_ARCH=$(RUNTIME_ARCH) runtime-bundle-audit
	@$(MAKE) RUNTIME_ARCH=$(RUNTIME_ARCH) runtime-integration

runtime-matrix-build:
	@$(MAKE) RUNTIME_ARCH=arm64 developer-jit-build release-aot-build
	@$(MAKE) RUNTIME_ARCH=x86_64 developer-jit-build release-aot-build

runtime-matrix-audit:
	@$(MAKE) RUNTIME_ARCH=arm64 developer-jit-audit release-aot-audit
	@$(MAKE) RUNTIME_ARCH=x86_64 developer-jit-audit release-aot-audit

runtime-matrix-integration:
	@$(MAKE) RUNTIME_ARCH=$(HOST_ARCH) \
		developer-jit-integration release-aot-integration
ifeq ($(HOST_ARCH),arm64)
	@$(MAKE) RUNTIME_ARCH=x86_64 \
		developer-jit-integration release-aot-integration
endif

universal-release-aot-build:
	@$(MAKE) RUNTIME_ARCH=arm64 release-aot-audit
	@$(MAKE) RUNTIME_ARCH=x86_64 release-aot-audit
	@$(MAKE) universal-release-aot-assemble

universal-release-aot-assemble: runtime-dart-tool-check
	"$(RUNTIME_DART_EXECUTABLE)" run \
		$(RUNTIME_UNIVERSAL_ASSEMBLER_SOURCE) \
		--arm64-bundle=$(ARM64_RELEASE_BUNDLE) \
		--arm64-report=$(ARM64_RELEASE_AUDIT_REPORT) \
		--x86_64-bundle=$(X86_64_RELEASE_BUNDLE) \
		--x86_64-report=$(X86_64_RELEASE_AUDIT_REPORT) \
		--output-directory=$(UNIVERSAL_RELEASE_BUILD_DIR) \
		--deployment-target=$(MACOSX_DEPLOYMENT_TARGET)


universal-release-aot-audit: universal-release-aot-build
	"$(RUNTIME_DART_EXECUTABLE)" run $(RUNTIME_AUDIT_SOURCE) \
		--mode=release-aot \
		--expected-architectures=arm64,x86_64 \
		--deployment-target=$(MACOSX_DEPLOYMENT_TARGET) \
		--validate-report=$(UNIVERSAL_RELEASE_AUDIT_REPORT) \
		$(UNIVERSAL_RELEASE_BUNDLE)

universal-release-aot-integration: universal-release-aot-build
	"$(RUNTIME_DART_EXECUTABLE)" run $(RUNTIME_INTEGRATION_SOURCE) \
		--mode=release-aot \
		--launch-architecture=$(HOST_ARCH) \
		$(UNIVERSAL_RELEASE_BUNDLE)
ifeq ($(HOST_ARCH),arm64)
	"$(RUNTIME_DART_EXECUTABLE)" run $(RUNTIME_INTEGRATION_SOURCE) \
		--mode=release-aot \
		--launch-architecture=x86_64 \
		$(UNIVERSAL_RELEASE_BUNDLE)
endif

runtime-release-negative-tests: universal-release-aot-audit
	"$(RUNTIME_DART_EXECUTABLE)" run $(RUNTIME_RELEASE_NEGATIVE_SOURCE) \
		--arm64-bundle=$(ARM64_RELEASE_BUNDLE) \
		--arm64-report=$(ARM64_RELEASE_AUDIT_REPORT) \
		--x86_64-bundle=$(X86_64_RELEASE_BUNDLE) \
		--x86_64-report=$(X86_64_RELEASE_AUDIT_REPORT) \
		--universal-artifact-directory=$(UNIVERSAL_RELEASE_BUILD_DIR) \
		--universal-bundle=$(UNIVERSAL_RELEASE_BUNDLE) \
		--universal-report=$(UNIVERSAL_RELEASE_AUDIT_REPORT) \
		--deployment-target=$(MACOSX_DEPLOYMENT_TARGET) \
		--assembler=$(RUNTIME_UNIVERSAL_ASSEMBLER_SOURCE) \
		--auditor=$(RUNTIME_AUDIT_SOURCE) \
		--handoff=$(RUNTIME_NATIVE_HANDOFF_SOURCE) \
		--project-root=$(PROJECT_ROOT)

runtime-build-freshness-test: runtime-dart-tool-check
	"$(RUNTIME_DART_EXECUTABLE)" run $(RUNTIME_FRESHNESS_TEST_SOURCE) \
		--project-root=$(PROJECT_ROOT) --make=/usr/bin/make

runtime-intel-native-status:
	@echo "RUNTIME_INTEL_NATIVE_GATE_UNVERIFIED: no Intel-native handoff was run"

intel-native-runtime-verify: runtime-dart-tool-check
	"$(RUNTIME_DART_EXECUTABLE)" run $(RUNTIME_NATIVE_HANDOFF_SOURCE) \
		--developer-jit-bundle=$(INTEL_DEVELOPER_JIT_BUNDLE) \
		--developer-jit-report=$(INTEL_DEVELOPER_JIT_REPORT) \
		--release-aot-bundle=$(INTEL_RELEASE_AOT_BUNDLE) \
		--release-aot-report=$(INTEL_RELEASE_AOT_REPORT) \
		--universal-bundle=$(INTEL_UNIVERSAL_BUNDLE) \
		--universal-report=$(INTEL_UNIVERSAL_REPORT) \
		--deployment-target=$(MACOSX_DEPLOYMENT_TARGET) \
		--smoke=$(RUNTIME_INTEGRATION_SOURCE) \
		--hardware-label=$(INTEL_HARDWARE_LABEL) \
		--output-evidence=$(INTEL_EVIDENCE_OUTPUT)

runtime-matrix-verify:
	@$(MAKE) runtime-source-check
	@$(MAKE) runtime-build-freshness-test
	@$(MAKE) runtime-matrix-audit
	@$(MAKE) universal-release-aot-audit
	@$(MAKE) runtime-release-negative-tests
	@$(MAKE) runtime-matrix-integration
	@$(MAKE) universal-release-aot-integration
	@$(MAKE) runtime-intel-native-status

release-aot-engine: runtime-aot-engine

phase0-aot-engine: unmodified-engine-probe-aot-engine

$(AOT_SNAPSHOT): $(AOT_SOURCE) pubspec.yaml pubspec.lock
	@mkdir -p $(AOT_BUILD_DIR)
	dart compile aot-snapshot --verbosity=warning -o $@ $(AOT_SOURCE)

$(AOT_HOST): $(AOT_HOST_SOURCE) | unmodified-engine-probe-aot-engine
	@mkdir -p $(AOT_BUILD_DIR)
	$(CLANGXX) $(NATIVE_FLAGS) \
		-I$(DART_ENGINE_ROOT)/runtime \
		-I$(DART_ENGINE_ROOT)/runtime/engine \
		$(AOT_HOST_SOURCE) $(DART_ENGINE_AOT_LIBRARY) \
		-framework AppKit -framework CoreFoundation \
		-Wl,-rpath,@executable_path/../Frameworks \
		-Wl,-export_dynamic -o $@

$(AOT_BUNDLE_STAMP): $(AOT_HOST) $(AOT_SNAPSHOT) $(AOT_INFO_PLIST) Makefile
	@mkdir -p $(AOT_BUNDLE)/Contents/MacOS
	@mkdir -p $(AOT_BUNDLE)/Contents/Frameworks
	@mkdir -p $(AOT_BUNDLE)/Contents/Resources
	cp $(AOT_HOST) $(AOT_BUNDLE)/Contents/MacOS/dart_terminal_phase0_aot
	cp $(DART_ENGINE_AOT_LIBRARY) $(AOT_BUNDLE)/Contents/Frameworks/libdart_engine_aot_shared.dylib
	cp $(AOT_SNAPSHOT) $(AOT_BUNDLE)/Contents/Resources/phase0_app.aot
	cp $(AOT_INFO_PLIST) $(AOT_BUNDLE)/Contents/Info.plist
	chmod 755 $(AOT_BUNDLE)/Contents/MacOS/dart_terminal_phase0_aot
	codesign --force --deep --sign - $(AOT_BUNDLE)
	touch $@

phase0-aot-build: $(AOT_BUNDLE_STAMP)

phase0-aot-run: phase0-aot-build
	$(AOT_BUNDLE)/Contents/MacOS/dart_terminal_phase0_aot

$(PTY_CHILD_OBJECT): $(PTY_NATIVE_DIR)/PtyExecChild.c \
		$(PTY_NATIVE_DIR)/PtySpawn.h
	@mkdir -p $(PTY_BUILD_DIR)
	$(CLANG) $(C_FLAGS) -fno-stack-protector -I$(PTY_NATIVE_DIR) \
		-c $(PTY_NATIVE_DIR)/PtyExecChild.c -o $@

phase0-pty-child-audit: $(PTY_CHILD_OBJECT) $(PTY_AUDIT_SOURCE)
	dart run $(PTY_AUDIT_SOURCE) $(PTY_CHILD_OBJECT)

$(IME_SNAPSHOT): $(IME_SOURCE) pubspec.yaml pubspec.lock
	@mkdir -p $(IME_BUILD_DIR)
	dart compile aot-snapshot --verbosity=warning -o $@ $(IME_SOURCE)

$(IME_BRIDGE_OBJECT): $(IME_BRIDGE_SOURCE)
	@mkdir -p $(IME_BUILD_DIR)
	$(CLANGXX) $(NATIVE_FLAGS) \
		-c $(IME_BRIDGE_SOURCE) -o $@

$(IME_HOST): $(AOT_HOST_SOURCE) $(IME_BRIDGE_OBJECT) | \
		unmodified-engine-probe-aot-engine
	@mkdir -p $(IME_BUILD_DIR)
	$(CLANGXX) $(NATIVE_FLAGS) \
		-I$(DART_ENGINE_ROOT)/runtime \
		-I$(DART_ENGINE_ROOT)/runtime/engine \
		$(AOT_HOST_SOURCE) $(IME_BRIDGE_OBJECT) \
		$(DART_ENGINE_AOT_LIBRARY) \
		-framework AppKit -framework CoreFoundation \
		-Wl,-rpath,@executable_path/../Frameworks \
		-Wl,-export_dynamic -o $@

$(IME_BUNDLE_STAMP): $(IME_HOST) $(IME_SNAPSHOT) $(IME_INFO_PLIST) Makefile
	@mkdir -p $(IME_BUNDLE)/Contents/MacOS
	@mkdir -p $(IME_BUNDLE)/Contents/Frameworks
	@mkdir -p $(IME_BUNDLE)/Contents/Resources
	cp $(IME_HOST) \
		$(IME_BUNDLE)/Contents/MacOS/dart_terminal_phase0_ime
	cp $(DART_ENGINE_AOT_LIBRARY) \
		$(IME_BUNDLE)/Contents/Frameworks/libdart_engine_aot_shared.dylib
	cp $(IME_SNAPSHOT) $(IME_BUNDLE)/Contents/Resources/phase0_app.aot
	cp $(IME_INFO_PLIST) $(IME_BUNDLE)/Contents/Info.plist
	chmod 755 $(IME_BUNDLE)/Contents/MacOS/dart_terminal_phase0_ime
	codesign --force --deep --sign - $(IME_BUNDLE)
	touch $@

phase0-ime-build: $(IME_BUNDLE_STAMP)

phase0-ime-run: phase0-ime-build
	$(IME_BUNDLE)/Contents/MacOS/dart_terminal_phase0_ime

$(GRID_BENCHMARK_EXE): $(GRID_BENCHMARK_SOURCE) $(GRID_PROTOTYPE_SOURCE) \
		pubspec.yaml pubspec.lock
	@mkdir -p $(GRID_BUILD_DIR)
	dart compile exe --verbosity=warning -o $@ $(GRID_BENCHMARK_SOURCE)

phase0-grid-build: $(GRID_BENCHMARK_EXE)

phase0-grid-run: phase0-grid-build
	$(GRID_BENCHMARK_EXE)

$(PARSER_HARNESS_EXE): $(PARSER_HARNESS_SOURCE) $(PARSER_PROBE_SOURCE) \
		$(PARSER_CORPUS) pubspec.yaml pubspec.lock
	@mkdir -p $(PARSER_BUILD_DIR)
	dart compile exe --verbosity=warning -o $@ $(PARSER_HARNESS_SOURCE)

phase0-parser-build: $(PARSER_HARNESS_EXE)

phase0-parser-run: phase0-parser-build
	$(PARSER_HARNESS_EXE) --corpus=$(PARSER_CORPUS)

$(BENCHMARK_EXE): $(BENCHMARK_SOURCE) $(INPUT_PROBE_SOURCE) \
		$(GRID_PROTOTYPE_SOURCE) $(PARSER_PROBE_SOURCE) \
		$(BENCHMARK_BASELINE) pubspec.yaml pubspec.lock
	@mkdir -p $(BENCHMARK_BUILD_DIR)
	dart compile exe --verbosity=warning -o $@ $(BENCHMARK_SOURCE)

phase0-benchmark-build: $(BENCHMARK_EXE)

phase0-benchmark-run: phase0-benchmark-build
	$(BENCHMARK_EXE) --baseline=$(BENCHMARK_BASELINE)

phase0-debug-check:
	dart format --output=none --set-exit-if-changed \
		bin lib test tool benchmark
	dart analyze
	dart run test/run_tests.dart
	@mkdir -p $(DEBUG_BUILD_DIR)
	dart compile kernel --link-platform \
		--packages=$(PROJECT_ROOT)/.dart_tool/package_config.json \
		-o $(DEBUG_KERNEL) $(PROJECT_ROOT)/bin/main.dart

phase0-debug-smoke: phase0-debug-check
	dart run dart_appkit:run bin/main.dart -- --auto-close-after=1
