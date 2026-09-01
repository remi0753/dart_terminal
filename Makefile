SHELL := /bin/zsh

PROJECT_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BUILD_DIR ?= $(PROJECT_ROOT)/build/phase0
MACOSX_DEPLOYMENT_TARGET ?= 14.0
DART_APPKIT_ROOT ?= $(abspath $(PROJECT_ROOT)/../dart_appkit)
DART_ENGINE_ROOT ?= $(DART_APPKIT_ROOT)/.dart_tool/dart-engine/sdk
HOST_ARCH := $(shell uname -m)
DART_EXECUTABLE := $(shell command -v dart)
DART_SDK_ROOT ?= $(shell realpath $(DART_EXECUTABLE) | xargs dirname | xargs dirname)
DART_SDK_VERSION := $(shell cat $(DART_SDK_ROOT)/version)
DART_SDK_REVISION := $(shell cat $(DART_SDK_ROOT)/revision)
DART_SDK_HASH := $(shell cut -c1-10 $(DART_SDK_ROOT)/revision)

ifeq ($(HOST_ARCH),arm64)
DART_ENGINE_RELEASE_ARCH := ARM64
DART_ENGINE_SHARED_TOOLCHAIN := clang_arm64_shared
else ifeq ($(HOST_ARCH),x86_64)
DART_ENGINE_RELEASE_ARCH := X64
DART_ENGINE_SHARED_TOOLCHAIN := clang_x64_shared
else
$(error Unsupported host architecture: $(HOST_ARCH))
endif

DART_ENGINE_OUT ?= $(DART_ENGINE_ROOT)/xcodebuild/Product$(DART_ENGINE_RELEASE_ARCH)
DART_ENGINE_JIT_OUT ?= $(DART_ENGINE_ROOT)/xcodebuild/Release$(DART_ENGINE_RELEASE_ARCH)
DART_ENGINE_NINJA ?= $(DART_ENGINE_ROOT)/buildtools/ninja/ninja
DART_ENGINE_AOT_LIBRARY ?= $(DART_ENGINE_OUT)/libdart_engine_aot_shared.dylib
DART_ENGINE_JIT_LIBRARY ?= $(DART_ENGINE_JIT_OUT)/libdart_engine_jit_shared.dylib
DART_ENGINE_KERNEL_COMPILER ?= $(DART_ENGINE_JIT_OUT)/bootstrap_gen_kernel.exe
DART_ENGINE_PLATFORM_KERNEL ?= \
	$(DART_ENGINE_JIT_OUT)/$(DART_ENGINE_SHARED_TOOLCHAIN)/vm_platform.dill
DART_ENGINE_WORKER_PATCH := \
	$(PROJECT_ROOT)/patches/dart-engine-worker-isolates.patch

CLANGXX := $(shell xcrun --find clang++)
CLANG := $(shell xcrun --find clang)
SDKROOT := $(shell xcrun --sdk macosx --show-sdk-path)
NATIVE_FLAGS := -Wall -Wextra -Wpedantic -Werror \
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

WORKER_BUILD_DIR := $(BUILD_DIR)/worker
WORKER_SNAPSHOT := $(WORKER_BUILD_DIR)/worker_isolate.aot
WORKER_BUNDLE := $(WORKER_BUILD_DIR)/DartTerminalPhase0Worker.app
WORKER_BUNDLE_STAMP := $(WORKER_BUNDLE)/Contents/.phase0-built
WORKER_SOURCE := $(PROJECT_ROOT)/tool/phase0/worker_isolate.dart
WORKER_INFO_PLIST := $(PROJECT_ROOT)/native/macos/phase0/Worker-Info.plist

PTY_BUILD_DIR := $(BUILD_DIR)/pty
PTY_SNAPSHOT := $(PTY_BUILD_DIR)/pty_port.aot
PTY_HOST := $(PTY_BUILD_DIR)/dart_terminal_phase0_pty
PTY_BUNDLE := $(PTY_BUILD_DIR)/DartTerminalPhase0Pty.app
PTY_BUNDLE_STAMP := $(PTY_BUNDLE)/Contents/.phase0-built
PTY_SOURCE := $(PROJECT_ROOT)/tool/phase0/pty_port.dart
PTY_INFO_PLIST := $(PROJECT_ROOT)/native/macos/phase0/Pty-Info.plist
PTY_NATIVE_DIR := $(PROJECT_ROOT)/native/macos/phase0/pty
PTY_CHILD_OBJECT := $(PTY_BUILD_DIR)/PtyExecChild.o
PTY_SPAWN_OBJECT := $(PTY_BUILD_DIR)/PtySpawn.o
PTY_BRIDGE_OBJECT := $(PTY_BUILD_DIR)/PtyPortBridge.o
PTY_AUDIT_SOURCE := $(PROJECT_ROOT)/tool/phase0/audit_pty_child.dart

METAL_BUILD_DIR := $(BUILD_DIR)/metal
METAL_SNAPSHOT := $(METAL_BUILD_DIR)/metal_instances.aot
METAL_HOST := $(METAL_BUILD_DIR)/dart_terminal_phase0_metal
METAL_BUNDLE := $(METAL_BUILD_DIR)/DartTerminalPhase0Metal.app
METAL_BUNDLE_STAMP := $(METAL_BUNDLE)/Contents/.phase0-built
METAL_SOURCE := $(PROJECT_ROOT)/tool/phase0/metal_instances.dart
METAL_BRIDGE_SOURCE := \
	$(PROJECT_ROOT)/native/macos/phase0/metal/MetalBridge.mm
METAL_BRIDGE_OBJECT := $(METAL_BUILD_DIR)/MetalBridge.o
METAL_INFO_PLIST := $(PROJECT_ROOT)/native/macos/phase0/Metal-Info.plist

CORETEXT_BUILD_DIR := $(BUILD_DIR)/coretext
CORETEXT_SNAPSHOT := $(CORETEXT_BUILD_DIR)/coretext_runs.aot
CORETEXT_HOST := $(CORETEXT_BUILD_DIR)/dart_terminal_phase0_coretext
CORETEXT_BUNDLE := $(CORETEXT_BUILD_DIR)/DartTerminalPhase0CoreText.app
CORETEXT_BUNDLE_STAMP := $(CORETEXT_BUNDLE)/Contents/.phase0-built
CORETEXT_SOURCE := $(PROJECT_ROOT)/tool/phase0/coretext_runs.dart
CORETEXT_BRIDGE_SOURCE := \
	$(PROJECT_ROOT)/native/macos/phase0/coretext/CoreTextBridge.mm
CORETEXT_BRIDGE_OBJECT := $(CORETEXT_BUILD_DIR)/CoreTextBridge.o
CORETEXT_INFO_PLIST := $(PROJECT_ROOT)/native/macos/phase0/CoreText-Info.plist

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
BUNDLE_AUDIT_SOURCE := $(PROJECT_ROOT)/tool/phase0/bundle_audit.dart
PHASE0_BUNDLES := \
	$(AOT_BUNDLE) \
	$(WORKER_BUNDLE) \
	$(PTY_BUNDLE) \
	$(METAL_BUNDLE) \
	$(CORETEXT_BUNDLE) \
	$(IME_BUNDLE)

RUNTIME_BUILD_DIR ?= $(PROJECT_ROOT)/build/runtime
RUNTIME_PACKAGE_CONFIG := $(PROJECT_ROOT)/.dart_tool/package_config.json
RUNTIME_DART_SOURCES := \
	$(wildcard $(PROJECT_ROOT)/bin/*.dart) \
	$(wildcard $(PROJECT_ROOT)/lib/*.dart) \
	$(wildcard $(PROJECT_ROOT)/lib/src/*.dart) \
	$(wildcard $(DART_APPKIT_ROOT)/packages/dart_appkit/lib/*.dart) \
	$(wildcard $(DART_APPKIT_ROOT)/packages/dart_appkit/lib/src/*.dart) \
	$(wildcard $(DART_APPKIT_ROOT)/packages/dart_appkit/lib/src/api/*.dart) \
	$(wildcard $(DART_APPKIT_ROOT)/packages/dart_appkit/lib/src/native/*.dart)
RUNTIME_BRIDGE_HEADERS := \
	$(DART_APPKIT_ROOT)/native/bridge/include/dart_appkit.h \
	$(DART_APPKIT_ROOT)/native/bridge/src/AppKitObjects.h \
	$(DART_APPKIT_ROOT)/native/bridge/src/BridgeInternal.h \
	$(DART_APPKIT_ROOT)/native/bridge/src/ObjectRegistry.h
RUNTIME_BRIDGE_SOURCES := \
	$(DART_APPKIT_ROOT)/native/bridge/src/AppKitBridge.mm \
	$(DART_APPKIT_ROOT)/native/bridge/src/EventSink.mm \
	$(DART_APPKIT_ROOT)/native/bridge/src/ObjectRegistry.mm \
	$(DART_APPKIT_ROOT)/native/bridge/src/TextView.mm
RUNTIME_JIT_RUNNER_HEADERS := \
	$(DART_APPKIT_ROOT)/native/runner/AppDelegate.h \
	$(DART_APPKIT_ROOT)/native/runner/DartHost.h \
	$(DART_APPKIT_ROOT)/native/runner/DartMessagePump.h \
	$(DART_APPKIT_ROOT)/native/runner/RunnerArguments.h \
	$(DART_APPKIT_ROOT)/native/runner/RunnerConfiguration.h
RUNTIME_JIT_RUNNER_SOURCES := \
	$(DART_APPKIT_ROOT)/native/runner/main.mm \
	$(DART_APPKIT_ROOT)/native/runner/AppDelegate.mm \
	$(DART_APPKIT_ROOT)/native/runner/DartHost.mm \
	$(DART_APPKIT_ROOT)/native/runner/DartMessagePump.mm \
	$(DART_APPKIT_ROOT)/native/runner/RunnerArguments.cc
RUNTIME_MESSAGE_PUMP_HEADERS := \
	$(DART_APPKIT_ROOT)/native/runner/DartMessagePump.h
RUNTIME_MESSAGE_PUMP_SOURCE := \
	$(DART_APPKIT_ROOT)/native/runner/DartMessagePump.mm
RUNTIME_AUDIT_SOURCE := $(PROJECT_ROOT)/tool/runtime_bundle_audit.dart
RUNTIME_INTEGRATION_SOURCE := \
	$(PROJECT_ROOT)/tool/runtime_integration_smoke.dart
RUNTIME_ARGUMENTS ?=

DEVELOPER_JIT_BUILD_DIR := $(RUNTIME_BUILD_DIR)/developer-jit
DEVELOPER_JIT_RUNNER_BUILD_DIR := \
	$(DEVELOPER_JIT_BUILD_DIR)/dart-appkit-runner
DEVELOPER_JIT_RUNNER := \
	$(DEVELOPER_JIT_RUNNER_BUILD_DIR)/native/dart_appkit_runner
DEVELOPER_JIT_KERNEL := $(DEVELOPER_JIT_BUILD_DIR)/application.dill
DEVELOPER_JIT_KERNEL_DEPFILE := $(DEVELOPER_JIT_KERNEL).d
DEVELOPER_JIT_BUNDLE := \
	$(DEVELOPER_JIT_BUILD_DIR)/DartTerminalDeveloper.app
DEVELOPER_JIT_EXECUTABLE := \
	$(DEVELOPER_JIT_BUNDLE)/Contents/MacOS/dart_terminal_developer_jit
DEVELOPER_JIT_BUNDLED_KERNEL := \
	$(DEVELOPER_JIT_BUNDLE)/Contents/Resources/application.dill
DEVELOPER_JIT_BUNDLE_STAMP := \
	$(DEVELOPER_JIT_BUILD_DIR)/.developer-jit-built
DEVELOPER_JIT_INFO_PLIST := \
	$(PROJECT_ROOT)/native/macos/runtime/DeveloperJit-Info.plist

RELEASE_AOT_BUILD_DIR := $(RUNTIME_BUILD_DIR)/release-aot
RELEASE_AOT_SNAPSHOT := $(RELEASE_AOT_BUILD_DIR)/application.aot
RELEASE_AOT_HOST := $(RELEASE_AOT_BUILD_DIR)/dart_terminal_release_aot
RELEASE_AOT_BUNDLE := $(RELEASE_AOT_BUILD_DIR)/DartTerminal.app
RELEASE_AOT_EXECUTABLE := \
	$(RELEASE_AOT_BUNDLE)/Contents/MacOS/dart_terminal_release_aot
RELEASE_AOT_BUNDLE_STAMP := \
	$(RELEASE_AOT_BUILD_DIR)/.release-aot-built
RELEASE_AOT_HOST_SOURCE := \
	$(PROJECT_ROOT)/native/macos/runtime/ReleaseAotRunner.mm
RELEASE_AOT_INFO_PLIST := \
	$(PROJECT_ROOT)/native/macos/runtime/ReleaseAot-Info.plist

-include $(DEVELOPER_JIT_KERNEL_DEPFILE)

.PHONY: help dart-engine-worker-support release-aot-engine \
	developer-jit-build developer-jit-run developer-jit-audit \
	developer-jit-integration release-aot-build release-aot-run \
	release-aot-audit release-aot-integration runtime-source-check \
	runtime-bundle-audit runtime-integration runtime-verify \
	phase0-engine-worker-support phase0-aot-engine \
	phase0-aot-build phase0-aot-run \
	phase0-worker-build phase0-worker-run \
	phase0-pty-child-audit phase0-pty-build phase0-pty-run \
	phase0-metal-build phase0-metal-run \
	phase0-coretext-build phase0-coretext-run \
	phase0-ime-build phase0-ime-run \
	phase0-grid-build phase0-grid-run \
	phase0-parser-build phase0-parser-run \
	phase0-benchmark-build phase0-benchmark-run \
	phase0-debug-check phase0-debug-smoke \
	phase0-release-build phase0-release-run \
	phase0-bundle-audit phase0-universal-bundle-audit phase0-verify

help:
	@echo "Dart Terminal product runtime targets:"
	@echo "  make developer-jit-build Build the product developer-JIT app"
	@echo "  make developer-jit-run   Run the product developer-JIT app"
	@echo "  make developer-jit-audit Audit the JIT-only bundle contract"
	@echo "  make release-aot-build   Build the thin release-AOT product app"
	@echo "  make release-aot-run     Run the thin release-AOT product app"
	@echo "  make release-aot-audit   Audit the AOT-only bundle contract"
	@echo "  make runtime-integration Run one common smoke suite in both modes"
	@echo "  make runtime-verify      Check, build, audit, and smoke both modes"
	@echo ""
	@echo "Historical Phase 0 feasibility/regression targets:"
	@echo "  make phase0-engine-worker-support Patch the pinned embedder for workers"
	@echo "  make phase0-aot-engine  Build the revision-matched AOT Dart Engine"
	@echo "  make phase0-aot-build   Build the release AOT AppKit spike bundle"
	@echo "  make phase0-aot-run     Launch, validate, and auto-close the AOT spike"
	@echo "  make phase0-worker-build Build the release AOT worker-isolate spike"
	@echo "  make phase0-worker-run   Validate worker lifecycle and bulk transfer"
	@echo "  make phase0-pty-child-audit Audit post-fork child symbol dependencies"
	@echo "  make phase0-pty-build    Build the PTY/job-control/port-batch spike"
	@echo "  make phase0-pty-run      Run the integrated PTY spike on real hardware"
	@echo "  make phase0-metal-build  Build the 100k packed-instance Metal spike"
	@echo "  make phase0-metal-run    Run and validate continuous MTKView drawing"
	@echo "  make phase0-coretext-build Build the coarse CoreText shaping spike"
	@echo "  make phase0-coretext-run Validate Latin/CJK/emoji/ligature runs"
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
	@echo "  make phase0-release-build Build every release-AOT Phase 0 artifact"
	@echo "  make phase0-release-run   Run every release-AOT Phase 0 hardware gate"
	@echo "  make phase0-bundle-audit Audit thin host-architecture AOT app bundles"
	@echo "  make phase0-universal-bundle-audit Audit UNIVERSAL_BUNDLE arm64+x86_64"
	@echo "  make phase0-verify        Run the complete local Phase 0 acceptance path"

$(RUNTIME_PACKAGE_CONFIG): pubspec.yaml pubspec.lock
	dart pub get

$(DEVELOPER_JIT_RUNNER): $(RUNTIME_BRIDGE_HEADERS) \
		$(RUNTIME_BRIDGE_SOURCES) $(RUNTIME_JIT_RUNNER_HEADERS) \
		$(RUNTIME_JIT_RUNNER_SOURCES) $(DART_APPKIT_ROOT)/Makefile \
		$(DART_ENGINE_JIT_LIBRARY)
	$(MAKE) -C $(DART_APPKIT_ROOT) \
		BUILD_DIR=$(DEVELOPER_JIT_RUNNER_BUILD_DIR) \
		DART_SDK=$(DART_SDK_ROOT) \
		DART_ENGINE_ROOT=$(DART_ENGINE_ROOT) \
		DART_ENGINE_LIBRARY=$(DART_ENGINE_JIT_LIBRARY) runner

$(DEVELOPER_JIT_KERNEL): $(RUNTIME_DART_SOURCES) $(RUNTIME_PACKAGE_CONFIG) \
		$(DART_ENGINE_KERNEL_COMPILER) $(DART_ENGINE_PLATFORM_KERNEL)
	@mkdir -p $(DEVELOPER_JIT_BUILD_DIR)
	$(DART_ENGINE_KERNEL_COMPILER) \
		--platform=$(DART_ENGINE_PLATFORM_KERNEL) \
		--packages=$(RUNTIME_PACKAGE_CONFIG) \
		--no-aot --link-platform --no-embed-sources \
		--output=$@ --depfile=$(DEVELOPER_JIT_KERNEL_DEPFILE) \
		-Dsdk_hash=$(DART_SDK_HASH) \
		-Ddart.vm.product=false -Ddart.vm.asan=false \
		-Ddart.vm.msan=false -Ddart.vm.tsan=false \
		$(PROJECT_ROOT)/bin/main.dart

$(DEVELOPER_JIT_BUNDLE_STAMP): $(DEVELOPER_JIT_RUNNER) \
		$(DEVELOPER_JIT_KERNEL) $(DART_ENGINE_JIT_LIBRARY) \
		$(DEVELOPER_JIT_INFO_PLIST) $(DART_ENGINE_ROOT)/LICENSE Makefile
	@rm -rf $(DEVELOPER_JIT_BUNDLE)
	@mkdir -p $(DEVELOPER_JIT_BUNDLE)/Contents/MacOS
	@mkdir -p $(DEVELOPER_JIT_BUNDLE)/Contents/Frameworks
	@mkdir -p $(DEVELOPER_JIT_BUNDLE)/Contents/Resources
	cp $(DEVELOPER_JIT_RUNNER) $(DEVELOPER_JIT_EXECUTABLE)
	cp $(DART_ENGINE_JIT_LIBRARY) \
		$(DEVELOPER_JIT_BUNDLE)/Contents/Frameworks/libdart_engine_jit_shared.dylib
	cp $(DEVELOPER_JIT_KERNEL) $(DEVELOPER_JIT_BUNDLED_KERNEL)
	cp $(DART_ENGINE_ROOT)/LICENSE \
		$(DEVELOPER_JIT_BUNDLE)/Contents/Resources/DART_SDK_LICENSE.txt
	cp $(DEVELOPER_JIT_INFO_PLIST) \
		$(DEVELOPER_JIT_BUNDLE)/Contents/Info.plist
	chmod 755 $(DEVELOPER_JIT_EXECUTABLE)
	codesign --force --deep --sign - $(DEVELOPER_JIT_BUNDLE)
	touch $@

developer-jit-build: $(DEVELOPER_JIT_BUNDLE_STAMP)

developer-jit-run: developer-jit-build
	$(DEVELOPER_JIT_EXECUTABLE) \
		--kernel $(DEVELOPER_JIT_BUNDLED_KERNEL) \
		--sdk-version $(DART_SDK_VERSION) \
		--sdk-revision $(DART_SDK_REVISION) -- $(RUNTIME_ARGUMENTS)

developer-jit-audit: developer-jit-build
	dart run $(RUNTIME_AUDIT_SOURCE) --mode=developer-jit \
		--expected-architectures=$(HOST_ARCH) \
		--deployment-target=$(MACOSX_DEPLOYMENT_TARGET) \
		$(DEVELOPER_JIT_BUNDLE)

developer-jit-integration: developer-jit-build
	dart run $(RUNTIME_INTEGRATION_SOURCE) --mode=developer-jit \
		$(DEVELOPER_JIT_BUNDLE)

$(RELEASE_AOT_SNAPSHOT): $(RUNTIME_DART_SOURCES) $(RUNTIME_PACKAGE_CONFIG)
	@mkdir -p $(RELEASE_AOT_BUILD_DIR)
	dart compile aot-snapshot --verbosity=warning -o $@ \
		$(PROJECT_ROOT)/bin/main.dart

$(RELEASE_AOT_HOST): $(RELEASE_AOT_HOST_SOURCE) \
		$(RUNTIME_BRIDGE_HEADERS) $(RUNTIME_BRIDGE_SOURCES) \
		$(RUNTIME_MESSAGE_PUMP_HEADERS) $(RUNTIME_MESSAGE_PUMP_SOURCE) \
		$(DART_ENGINE_AOT_LIBRARY)
	@mkdir -p $(RELEASE_AOT_BUILD_DIR)
	$(CLANGXX) $(NATIVE_FLAGS) -fblocks -fvisibility=hidden \
		-DDT_DART_SDK_VERSION=\"$(DART_SDK_VERSION)\" \
		-I$(DART_APPKIT_ROOT)/native/bridge/include \
		-I$(DART_APPKIT_ROOT)/native/bridge/src \
		-I$(DART_APPKIT_ROOT)/native/runner \
		-I$(DART_ENGINE_ROOT)/runtime \
		-I$(DART_ENGINE_ROOT)/runtime/engine \
		$(RUNTIME_BRIDGE_SOURCES) $(RUNTIME_MESSAGE_PUMP_SOURCE) \
		$(RELEASE_AOT_HOST_SOURCE) $(DART_ENGINE_AOT_LIBRARY) \
		-framework AppKit -framework CoreFoundation \
		-Wl,-rpath,@executable_path/../Frameworks \
		-Wl,-export_dynamic -o $@

$(RELEASE_AOT_BUNDLE_STAMP): $(RELEASE_AOT_HOST) \
		$(RELEASE_AOT_SNAPSHOT) $(DART_ENGINE_AOT_LIBRARY) \
		$(RELEASE_AOT_INFO_PLIST) $(DART_ENGINE_ROOT)/LICENSE Makefile
	@rm -rf $(RELEASE_AOT_BUNDLE)
	@mkdir -p $(RELEASE_AOT_BUNDLE)/Contents/MacOS
	@mkdir -p $(RELEASE_AOT_BUNDLE)/Contents/Frameworks
	@mkdir -p $(RELEASE_AOT_BUNDLE)/Contents/Resources
	cp $(RELEASE_AOT_HOST) $(RELEASE_AOT_EXECUTABLE)
	cp $(DART_ENGINE_AOT_LIBRARY) \
		$(RELEASE_AOT_BUNDLE)/Contents/Frameworks/libdart_engine_aot_shared.dylib
	cp $(RELEASE_AOT_SNAPSHOT) \
		$(RELEASE_AOT_BUNDLE)/Contents/Resources/application.aot
	cp $(DART_ENGINE_ROOT)/LICENSE \
		$(RELEASE_AOT_BUNDLE)/Contents/Resources/DART_SDK_LICENSE.txt
	cp $(RELEASE_AOT_INFO_PLIST) \
		$(RELEASE_AOT_BUNDLE)/Contents/Info.plist
	chmod 755 $(RELEASE_AOT_EXECUTABLE)
	codesign --force --deep --sign - $(RELEASE_AOT_BUNDLE)
	touch $@

release-aot-build: $(RELEASE_AOT_BUNDLE_STAMP)

release-aot-run: release-aot-build
	$(RELEASE_AOT_EXECUTABLE) $(RUNTIME_ARGUMENTS)

release-aot-audit: release-aot-build
	dart run $(RUNTIME_AUDIT_SOURCE) --mode=release-aot \
		--expected-architectures=$(HOST_ARCH) \
		--deployment-target=$(MACOSX_DEPLOYMENT_TARGET) \
		$(RELEASE_AOT_BUNDLE)

release-aot-integration: release-aot-build
	dart run $(RUNTIME_INTEGRATION_SOURCE) --mode=release-aot \
		$(RELEASE_AOT_BUNDLE)

runtime-source-check:
	dart format --output=none --set-exit-if-changed \
		bin lib test tool benchmark
	xcrun clang-format --style=file:$(DART_APPKIT_ROOT)/.clang-format \
		--dry-run --Werror $(RELEASE_AOT_HOST_SOURCE)
	plutil -lint $(DEVELOPER_JIT_INFO_PLIST) $(RELEASE_AOT_INFO_PLIST)
	dart analyze
	dart run test/run_tests.dart

runtime-bundle-audit: developer-jit-build release-aot-build
	@$(MAKE) developer-jit-audit
	@$(MAKE) release-aot-audit

runtime-integration: developer-jit-build release-aot-build
	@$(MAKE) developer-jit-integration
	@$(MAKE) release-aot-integration

runtime-verify:
	@$(MAKE) runtime-source-check
	@$(MAKE) runtime-bundle-audit
	@$(MAKE) runtime-integration

$(DART_ENGINE_OUT)/build.ninja:
	$(DART_ENGINE_ROOT)/tools/gn.py --mode=product --arch=$(HOST_ARCH)

dart-engine-worker-support:
	@if git -C $(DART_ENGINE_ROOT) apply --reverse --check \
		$(DART_ENGINE_WORKER_PATCH) >/dev/null 2>&1; then \
		echo "Dart Engine worker-isolate patch already applied"; \
	else \
		git -C $(DART_ENGINE_ROOT) apply --check \
			$(DART_ENGINE_WORKER_PATCH); \
		git -C $(DART_ENGINE_ROOT) apply $(DART_ENGINE_WORKER_PATCH); \
	fi

phase0-engine-worker-support: dart-engine-worker-support

$(DART_ENGINE_AOT_LIBRARY): dart-engine-worker-support \
		$(DART_ENGINE_OUT)/build.ninja
	$(DART_ENGINE_NINJA) -C $(DART_ENGINE_OUT) dart_engine_aot_shared

release-aot-engine: $(DART_ENGINE_AOT_LIBRARY)

phase0-aot-engine: $(DART_ENGINE_AOT_LIBRARY)

$(AOT_SNAPSHOT): $(AOT_SOURCE) pubspec.yaml pubspec.lock
	@mkdir -p $(AOT_BUILD_DIR)
	dart compile aot-snapshot --verbosity=warning -o $@ $(AOT_SOURCE)

$(AOT_HOST): $(AOT_HOST_SOURCE) $(DART_ENGINE_AOT_LIBRARY)
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

$(WORKER_SNAPSHOT): $(WORKER_SOURCE) pubspec.yaml pubspec.lock
	@mkdir -p $(WORKER_BUILD_DIR)
	dart compile aot-snapshot --verbosity=warning -o $@ $(WORKER_SOURCE)

$(WORKER_BUNDLE_STAMP): $(AOT_HOST) $(WORKER_SNAPSHOT) \
		$(WORKER_INFO_PLIST) Makefile
	@mkdir -p $(WORKER_BUNDLE)/Contents/MacOS
	@mkdir -p $(WORKER_BUNDLE)/Contents/Frameworks
	@mkdir -p $(WORKER_BUNDLE)/Contents/Resources
	cp $(AOT_HOST) \
		$(WORKER_BUNDLE)/Contents/MacOS/dart_terminal_phase0_worker
	cp $(DART_ENGINE_AOT_LIBRARY) \
		$(WORKER_BUNDLE)/Contents/Frameworks/libdart_engine_aot_shared.dylib
	cp $(WORKER_SNAPSHOT) \
		$(WORKER_BUNDLE)/Contents/Resources/phase0_app.aot
	cp $(WORKER_INFO_PLIST) $(WORKER_BUNDLE)/Contents/Info.plist
	chmod 755 \
		$(WORKER_BUNDLE)/Contents/MacOS/dart_terminal_phase0_worker
	codesign --force --deep --sign - $(WORKER_BUNDLE)
	touch $@

phase0-worker-build: $(WORKER_BUNDLE_STAMP)

phase0-worker-run: phase0-worker-build
	$(WORKER_BUNDLE)/Contents/MacOS/dart_terminal_phase0_worker

$(PTY_SNAPSHOT): $(PTY_SOURCE) pubspec.yaml pubspec.lock
	@mkdir -p $(PTY_BUILD_DIR)
	dart compile aot-snapshot --verbosity=warning -o $@ $(PTY_SOURCE)

$(PTY_CHILD_OBJECT): $(PTY_NATIVE_DIR)/PtyExecChild.c \
		$(PTY_NATIVE_DIR)/PtySpawn.h
	@mkdir -p $(PTY_BUILD_DIR)
	$(CLANG) $(C_FLAGS) -fno-stack-protector -I$(PTY_NATIVE_DIR) \
		-c $(PTY_NATIVE_DIR)/PtyExecChild.c -o $@

$(PTY_SPAWN_OBJECT): $(PTY_NATIVE_DIR)/PtySpawn.c \
		$(PTY_NATIVE_DIR)/PtySpawn.h
	@mkdir -p $(PTY_BUILD_DIR)
	$(CLANG) $(C_FLAGS) -I$(PTY_NATIVE_DIR) \
		-c $(PTY_NATIVE_DIR)/PtySpawn.c -o $@

$(PTY_BRIDGE_OBJECT): $(PTY_NATIVE_DIR)/PtyPortBridge.cc \
		$(PTY_NATIVE_DIR)/PtySpawn.h
	@mkdir -p $(PTY_BUILD_DIR)
	$(CLANGXX) $(NATIVE_FLAGS) -I$(PTY_NATIVE_DIR) \
		-I$(DART_ENGINE_ROOT)/runtime \
		-c $(PTY_NATIVE_DIR)/PtyPortBridge.cc -o $@

phase0-pty-child-audit: $(PTY_CHILD_OBJECT) $(PTY_AUDIT_SOURCE)
	dart run $(PTY_AUDIT_SOURCE) $(PTY_CHILD_OBJECT)

$(PTY_HOST): $(AOT_HOST_SOURCE) $(PTY_CHILD_OBJECT) $(PTY_SPAWN_OBJECT) \
		$(PTY_BRIDGE_OBJECT) $(DART_ENGINE_AOT_LIBRARY)
	@mkdir -p $(PTY_BUILD_DIR)
	$(CLANGXX) $(NATIVE_FLAGS) \
		-I$(DART_ENGINE_ROOT)/runtime \
		-I$(DART_ENGINE_ROOT)/runtime/engine \
		$(AOT_HOST_SOURCE) $(PTY_CHILD_OBJECT) $(PTY_SPAWN_OBJECT) \
		$(PTY_BRIDGE_OBJECT) $(DART_ENGINE_AOT_LIBRARY) \
		-framework AppKit -framework CoreFoundation \
		-Wl,-rpath,@executable_path/../Frameworks \
		-Wl,-export_dynamic -o $@

$(PTY_BUNDLE_STAMP): $(PTY_HOST) $(PTY_SNAPSHOT) $(PTY_INFO_PLIST) \
		phase0-pty-child-audit Makefile
	@mkdir -p $(PTY_BUNDLE)/Contents/MacOS
	@mkdir -p $(PTY_BUNDLE)/Contents/Frameworks
	@mkdir -p $(PTY_BUNDLE)/Contents/Resources
	cp $(PTY_HOST) $(PTY_BUNDLE)/Contents/MacOS/dart_terminal_phase0_pty
	cp $(DART_ENGINE_AOT_LIBRARY) \
		$(PTY_BUNDLE)/Contents/Frameworks/libdart_engine_aot_shared.dylib
	cp $(PTY_SNAPSHOT) $(PTY_BUNDLE)/Contents/Resources/phase0_app.aot
	cp $(PTY_INFO_PLIST) $(PTY_BUNDLE)/Contents/Info.plist
	chmod 755 $(PTY_BUNDLE)/Contents/MacOS/dart_terminal_phase0_pty
	codesign --force --deep --sign - $(PTY_BUNDLE)
	touch $@

phase0-pty-build: $(PTY_BUNDLE_STAMP)

phase0-pty-run: phase0-pty-build
	$(PTY_BUNDLE)/Contents/MacOS/dart_terminal_phase0_pty

$(METAL_SNAPSHOT): $(METAL_SOURCE) pubspec.yaml pubspec.lock
	@mkdir -p $(METAL_BUILD_DIR)
	dart compile aot-snapshot --verbosity=warning -o $@ $(METAL_SOURCE)

$(METAL_BRIDGE_OBJECT): $(METAL_BRIDGE_SOURCE)
	@mkdir -p $(METAL_BUILD_DIR)
	$(CLANGXX) $(NATIVE_FLAGS) \
		-c $(METAL_BRIDGE_SOURCE) -o $@

$(METAL_HOST): $(AOT_HOST_SOURCE) $(METAL_BRIDGE_OBJECT) \
		$(DART_ENGINE_AOT_LIBRARY)
	@mkdir -p $(METAL_BUILD_DIR)
	$(CLANGXX) $(NATIVE_FLAGS) \
		-I$(DART_ENGINE_ROOT)/runtime \
		-I$(DART_ENGINE_ROOT)/runtime/engine \
		$(AOT_HOST_SOURCE) $(METAL_BRIDGE_OBJECT) \
		$(DART_ENGINE_AOT_LIBRARY) \
		-framework AppKit -framework CoreFoundation \
		-framework Metal -framework MetalKit -framework QuartzCore \
		-Wl,-rpath,@executable_path/../Frameworks \
		-Wl,-export_dynamic -o $@

$(METAL_BUNDLE_STAMP): $(METAL_HOST) $(METAL_SNAPSHOT) \
		$(METAL_INFO_PLIST) Makefile
	@mkdir -p $(METAL_BUNDLE)/Contents/MacOS
	@mkdir -p $(METAL_BUNDLE)/Contents/Frameworks
	@mkdir -p $(METAL_BUNDLE)/Contents/Resources
	cp $(METAL_HOST) \
		$(METAL_BUNDLE)/Contents/MacOS/dart_terminal_phase0_metal
	cp $(DART_ENGINE_AOT_LIBRARY) \
		$(METAL_BUNDLE)/Contents/Frameworks/libdart_engine_aot_shared.dylib
	cp $(METAL_SNAPSHOT) $(METAL_BUNDLE)/Contents/Resources/phase0_app.aot
	cp $(METAL_INFO_PLIST) $(METAL_BUNDLE)/Contents/Info.plist
	chmod 755 $(METAL_BUNDLE)/Contents/MacOS/dart_terminal_phase0_metal
	codesign --force --deep --sign - $(METAL_BUNDLE)
	touch $@

phase0-metal-build: $(METAL_BUNDLE_STAMP)

phase0-metal-run: phase0-metal-build
	$(METAL_BUNDLE)/Contents/MacOS/dart_terminal_phase0_metal

$(CORETEXT_SNAPSHOT): $(CORETEXT_SOURCE) pubspec.yaml pubspec.lock
	@mkdir -p $(CORETEXT_BUILD_DIR)
	dart compile aot-snapshot --verbosity=warning -o $@ $(CORETEXT_SOURCE)

$(CORETEXT_BRIDGE_OBJECT): $(CORETEXT_BRIDGE_SOURCE)
	@mkdir -p $(CORETEXT_BUILD_DIR)
	$(CLANGXX) $(NATIVE_FLAGS) \
		-c $(CORETEXT_BRIDGE_SOURCE) -o $@

$(CORETEXT_HOST): $(AOT_HOST_SOURCE) $(CORETEXT_BRIDGE_OBJECT) \
		$(DART_ENGINE_AOT_LIBRARY)
	@mkdir -p $(CORETEXT_BUILD_DIR)
	$(CLANGXX) $(NATIVE_FLAGS) \
		-I$(DART_ENGINE_ROOT)/runtime \
		-I$(DART_ENGINE_ROOT)/runtime/engine \
		$(AOT_HOST_SOURCE) $(CORETEXT_BRIDGE_OBJECT) \
		$(DART_ENGINE_AOT_LIBRARY) \
		-framework AppKit -framework CoreFoundation -framework CoreText \
		-Wl,-rpath,@executable_path/../Frameworks \
		-Wl,-export_dynamic -o $@

$(CORETEXT_BUNDLE_STAMP): $(CORETEXT_HOST) $(CORETEXT_SNAPSHOT) \
		$(CORETEXT_INFO_PLIST) Makefile
	@mkdir -p $(CORETEXT_BUNDLE)/Contents/MacOS
	@mkdir -p $(CORETEXT_BUNDLE)/Contents/Frameworks
	@mkdir -p $(CORETEXT_BUNDLE)/Contents/Resources
	cp $(CORETEXT_HOST) \
		$(CORETEXT_BUNDLE)/Contents/MacOS/dart_terminal_phase0_coretext
	cp $(DART_ENGINE_AOT_LIBRARY) \
		$(CORETEXT_BUNDLE)/Contents/Frameworks/libdart_engine_aot_shared.dylib
	cp $(CORETEXT_SNAPSHOT) \
		$(CORETEXT_BUNDLE)/Contents/Resources/phase0_app.aot
	cp $(CORETEXT_INFO_PLIST) $(CORETEXT_BUNDLE)/Contents/Info.plist
	chmod 755 \
		$(CORETEXT_BUNDLE)/Contents/MacOS/dart_terminal_phase0_coretext
	codesign --force --deep --sign - $(CORETEXT_BUNDLE)
	touch $@

phase0-coretext-build: $(CORETEXT_BUNDLE_STAMP)

phase0-coretext-run: phase0-coretext-build
	$(CORETEXT_BUNDLE)/Contents/MacOS/dart_terminal_phase0_coretext

$(IME_SNAPSHOT): $(IME_SOURCE) pubspec.yaml pubspec.lock
	@mkdir -p $(IME_BUILD_DIR)
	dart compile aot-snapshot --verbosity=warning -o $@ $(IME_SOURCE)

$(IME_BRIDGE_OBJECT): $(IME_BRIDGE_SOURCE)
	@mkdir -p $(IME_BUILD_DIR)
	$(CLANGXX) $(NATIVE_FLAGS) \
		-c $(IME_BRIDGE_SOURCE) -o $@

$(IME_HOST): $(AOT_HOST_SOURCE) $(IME_BRIDGE_OBJECT) \
		$(DART_ENGINE_AOT_LIBRARY)
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

phase0-release-build: phase0-aot-build phase0-worker-build \
		phase0-pty-build phase0-metal-build phase0-coretext-build \
		phase0-ime-build phase0-grid-build phase0-parser-build \
		phase0-benchmark-build

phase0-release-run:
	@$(MAKE) phase0-aot-run
	@$(MAKE) phase0-worker-run
	@$(MAKE) phase0-pty-run
	@$(MAKE) phase0-metal-run
	@$(MAKE) phase0-coretext-run
	@$(MAKE) phase0-ime-run
	@$(MAKE) phase0-grid-run
	@$(MAKE) phase0-parser-run
	@$(MAKE) phase0-benchmark-run

phase0-bundle-audit: phase0-release-build
	dart run $(BUNDLE_AUDIT_SOURCE) \
		--expected-architectures=$(HOST_ARCH) \
		--deployment-target=$(MACOSX_DEPLOYMENT_TARGET) \
		--signing=adhoc $(PHASE0_BUNDLES)

phase0-universal-bundle-audit:
	@if [[ -z "$(UNIVERSAL_BUNDLE)" || "$(UNIVERSAL_BUNDLE)" != /* ]]; then \
		echo "UNIVERSAL_BUNDLE=/absolute/path/to/Application.app is required" >&2; \
		exit 64; \
	fi
	dart run $(BUNDLE_AUDIT_SOURCE) \
		--expected-architectures=arm64,x86_64 \
		--deployment-target=$(MACOSX_DEPLOYMENT_TARGET) \
		--signing=any $(UNIVERSAL_BUNDLE)

phase0-verify:
	@$(MAKE) phase0-debug-smoke
	@$(MAKE) phase0-release-run
	@$(MAKE) phase0-bundle-audit
