#import <AppKit/AppKit.h>

#include <pthread.h>

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <system_error>
#include <utility>
#include <vector>

#include "BridgeInternal.h"
#include "DartEventEncoder.h"
#include "DartMessagePump.h"
#include "ObjectRegistry.h"
#include "RuntimeLifecycleBridge.h"
#include "RuntimeWorkerConfiguration.h"
#include "TerminalMetalView.h"
#include "include/dart_api.h"
#include "include/dart_engine.h"
#include "include/dart_native_api.h"

#ifndef DT_DART_SDK_VERSION
#define DT_DART_SDK_VERSION "unknown"
#endif

namespace dart_terminal {
namespace {

constexpr std::string_view kRuntimeWorkerExecutableName =
    "dart_terminal_runtime_worker";

bool ConfigureRuntimeWorker(const char* launcher_argument,
                            std::vector<std::string>* application_arguments,
                            std::string* out_error) {
  if (launcher_argument == nullptr || application_arguments == nullptr ||
      out_error == nullptr) {
    return false;
  }
  std::error_code error;
  const std::filesystem::path launcher =
      std::filesystem::canonical(launcher_argument, error);
  if (error) {
    *out_error = "could not resolve the Release launcher";
    return false;
  }
  const std::filesystem::path worker_executable =
      launcher.parent_path().parent_path() / "Helpers" /
      kRuntimeWorkerExecutableName;
  return PrependRuntimeWorkerConfiguration(worker_executable, std::nullopt,
                                           application_arguments, out_error);
}

class EnteredIsolate final {
 public:
  explicit EnteredIsolate(Dart_Isolate isolate) {
    DartEngine_AcquireIsolate(isolate);
    Dart_EnterScope();
  }

  ~EnteredIsolate() {
    Dart_ExitScope();
    DartEngine_ReleaseIsolate();
  }

  EnteredIsolate(const EnteredIsolate&) = delete;
  EnteredIsolate& operator=(const EnteredIsolate&) = delete;
};

std::string CopyDartError(Dart_Handle handle) {
  if (!Dart_IsError(handle)) {
    return {};
  }
  const char* error = Dart_GetError(handle);
  return error == nullptr ? "unknown Dart error" : std::string(error);
}

std::string CopyAndFreeError(char* error) {
  if (error == nullptr) {
    return {};
  }
  std::string result(error);
  std::free(error);
  return result;
}

void RequestApplicationTermination() {
  dispatch_async(dispatch_get_main_queue(), ^{
    [NSApp terminate:nil];
  });
}

class ReleaseAotHost final {
 public:
  explicit ReleaseAotHost(dart_appkit::DartMessagePump* message_pump)
      : message_pump_(message_pump) {}

  ~ReleaseAotHost() { Shutdown(); }

  bool Start(const std::string& snapshot_path,
             const std::vector<std::string>& arguments,
             std::string* out_error) {
    if (pthread_main_np() == 0) {
      *out_error = "release AOT host must start on the process main thread";
      return false;
    }
    if (message_pump_ == nullptr) {
      *out_error = "release AOT host requires a Dart message pump";
      return false;
    }
    if (snapshot_path.empty()) {
      *out_error = "release AOT snapshot path is empty";
      return false;
    }

    const char* runtime_version = Dart_VersionString();
    if (runtime_version == nullptr ||
        std::string_view(runtime_version).find(DT_DART_SDK_VERSION) ==
            std::string_view::npos) {
      *out_error = "Dart Engine runtime version does not match product SDK " +
                   std::string(DT_DART_SDK_VERSION);
      return false;
    }

    char* engine_error = nullptr;
    if (!DartEngine_Init(&engine_error)) {
      *out_error = "could not initialize release AOT Dart Engine";
      const std::string detail = CopyAndFreeError(engine_error);
      if (!detail.empty()) {
        *out_error += ": " + detail;
      }
      return false;
    }
    engine_started_ = true;
    DartEngine_SetDefaultMessageScheduler(message_pump_->scheduler());
    DartEngine_SetHandleMessageErrorCallback(HandleMessageError);

    const DartEngine_SnapshotData snapshot =
        DartEngine_AotSnapshotFromFile(snapshot_path.c_str(), &engine_error);
    if (engine_error != nullptr) {
      *out_error = "could not load release AOT snapshot: " +
                   CopyAndFreeError(engine_error);
      Shutdown();
      return false;
    }

    isolate_ = DartEngine_CreateIsolate(snapshot, &engine_error);
    if (isolate_ == nullptr || engine_error != nullptr) {
      *out_error = "could not create release AOT root isolate: " +
                   CopyAndFreeError(engine_error);
      isolate_ = nullptr;
      Shutdown();
      return false;
    }
    DartEngine_SetMessageScheduler(message_pump_->scheduler(), isolate_);
    active_host_.store(this, std::memory_order_release);
    dart_appkit::InstallEventPoster(PostNativeEvent, this);

    if (!InvokeMain(arguments, out_error)) {
      Shutdown();
      return false;
    }
    return true;
  }

  void Shutdown() {
    ReleaseAotHost* expected = this;
    active_host_.compare_exchange_strong(expected, nullptr,
                                         std::memory_order_acq_rel);
    dart_appkit::DisableEventPoster();
    if (engine_started_) {
      DartEngine_SetHandleMessageErrorCallback(nullptr);
      DartEngine_Shutdown();
      engine_started_ = false;
      isolate_ = nullptr;
    }
  }

  bool has_fatal_error() const {
    const std::lock_guard<std::mutex> lock(fatal_error_mutex_);
    return !fatal_error_.empty();
  }

  std::string fatal_error() const {
    const std::lock_guard<std::mutex> lock(fatal_error_mutex_);
    return fatal_error_;
  }

  ReleaseAotHost(const ReleaseAotHost&) = delete;
  ReleaseAotHost& operator=(const ReleaseAotHost&) = delete;

 private:
  bool InvokeMain(const std::vector<std::string>& arguments,
                  std::string* out_error) {
    EnteredIsolate entered(isolate_);

    Dart_Handle core_library =
        Dart_LookupLibrary(Dart_NewStringFromCString("dart:core"));
    if (Dart_IsError(core_library)) {
      *out_error = CopyDartError(core_library);
      return false;
    }
    Dart_Handle string_type = Dart_GetNonNullableType(
        core_library, Dart_NewStringFromCString("String"), 0, nullptr);
    if (Dart_IsError(string_type)) {
      *out_error = CopyDartError(string_type);
      return false;
    }

    Dart_Handle dart_arguments = Dart_NewListOfTypeFilled(
        string_type, Dart_NewStringFromCString(""), arguments.size());
    if (Dart_IsError(dart_arguments)) {
      *out_error = CopyDartError(dart_arguments);
      return false;
    }
    for (size_t index = 0; index < arguments.size(); ++index) {
      Dart_Handle result =
          Dart_ListSetAt(dart_arguments, index,
                         Dart_NewStringFromCString(arguments[index].c_str()));
      if (Dart_IsError(result)) {
        *out_error = CopyDartError(result);
        return false;
      }
    }

    Dart_Handle invocation_arguments[] = {dart_arguments};
    Dart_Handle result =
        Dart_Invoke(Dart_RootLibrary(), Dart_NewStringFromCString("main"), 1,
                    invocation_arguments);
    if (Dart_IsError(result)) {
      *out_error = "Dart main failed: " + CopyDartError(result);
      return false;
    }

    result = DartEngine_DrainMicrotasksQueue();
    if (Dart_IsError(result)) {
      *out_error = "Dart startup microtask failed: " + CopyDartError(result);
      return false;
    }
    return true;
  }

  void RecordFatalError(std::string message) {
    {
      const std::lock_guard<std::mutex> lock(fatal_error_mutex_);
      if (!fatal_error_.empty()) {
        return;
      }
      fatal_error_ = std::move(message);
    }
    std::fprintf(stderr, "Unhandled Dart message error: %s\n",
                 fatal_error().c_str());
    RequestApplicationTermination();
  }

  static void HandleMessageError(Dart_Handle error,
                                 Dart_Isolate destination_isolate) {
    (void)destination_isolate;
    ReleaseAotHost* host = active_host_.load(std::memory_order_acquire);
    if (host != nullptr) {
      host->RecordFatalError(CopyDartError(error));
    }
  }

  static bool PostNativeEvent(int64_t dart_port,
                              uint32_t event_protocol_version,
                              const dart_appkit::NativeEvent& event,
                              void* context) {
    (void)context;
    return dart_appkit::PostNativeEventToDartPort(
        dart_port, event_protocol_version, event);
  }

  dart_appkit::DartMessagePump* message_pump_;
  Dart_Isolate isolate_ = nullptr;
  bool engine_started_ = false;
  mutable std::mutex fatal_error_mutex_;
  std::string fatal_error_;

  static std::atomic<ReleaseAotHost*> active_host_;
};

std::atomic<ReleaseAotHost*> ReleaseAotHost::active_host_{nullptr};

}  // namespace
}  // namespace dart_terminal

@interface DartTerminalReleaseAotDelegate : NSObject <NSApplicationDelegate> {
 @private
  std::string snapshot_path_;
  std::vector<std::string> application_arguments_;
  std::unique_ptr<dart_appkit::DartMessagePump> message_pump_;
  std::unique_ptr<dart_terminal::ReleaseAotHost> dart_host_;
  int exit_code_;
  BOOL did_shutdown_;
}

@property(nonatomic, readonly) int exitCode;

- (instancetype)initWithSnapshotPath:(const std::string&)snapshotPath
                applicationArguments:
                    (const std::vector<std::string>&)applicationArguments;

@end

@implementation DartTerminalReleaseAotDelegate

- (instancetype)initWithSnapshotPath:(const std::string&)snapshotPath
                applicationArguments:
                    (const std::vector<std::string>&)applicationArguments {
  self = [super init];
  if (self != nil) {
    snapshot_path_ = snapshotPath;
    application_arguments_ = applicationArguments;
    exit_code_ = 0;
    did_shutdown_ = NO;
  }
  return self;
}

- (int)exitCode {
  return exit_code_;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
  (void)notification;
  message_pump_ = std::make_unique<dart_appkit::DartMessagePump>();
  std::string error;
  if (!message_pump_->Start(&error)) {
    std::fprintf(stderr, "Release AOT startup failed: %s\n", error.c_str());
    exit_code_ = dart_terminal::kRuntimeSoftwareExitCode;
    dart_terminal::RequestApplicationTermination();
    return;
  }

  dart_host_ =
      std::make_unique<dart_terminal::ReleaseAotHost>(message_pump_.get());
  if (!dart_host_->Start(snapshot_path_, application_arguments_, &error)) {
    std::fprintf(stderr, "Release AOT startup failed: %s\n", error.c_str());
    exit_code_ = dart_terminal::kRuntimeSoftwareExitCode;
    dart_terminal::RequestApplicationTermination();
    return;
  }
  [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
  (void)sender;
  return NO;
}

- (void)applicationDidBecomeActive:(NSNotification*)notification {
  (void)notification;
  dart_appkit::PostApplicationActiveChanged(true);
}

- (void)applicationDidResignActive:(NSNotification*)notification {
  (void)notification;
  dart_appkit::PostApplicationActiveChanged(false);
}

- (BOOL)applicationShouldHandleReopen:(NSApplication*)sender
                    hasVisibleWindows:(BOOL)hasVisibleWindows {
  (void)sender;
  dart_appkit::PostApplicationReopenRequested(hasVisibleWindows);
  return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:
    (NSApplication*)sender {
  (void)sender;
  switch (dart_appkit::HandleApplicationShouldTerminate()) {
    case dart_appkit::ApplicationTerminationDecision::kTerminateNow:
      return NSTerminateNow;
    case dart_appkit::ApplicationTerminationDecision::kTerminateLater:
      return NSTerminateLater;
  }
  return NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification*)notification {
  (void)notification;
  if (did_shutdown_) {
    return;
  }
  did_shutdown_ = YES;

  if (dart_host_ != nullptr && dart_host_->has_fatal_error()) {
    std::fprintf(stderr, "Dart isolate terminated with an error: %s\n",
                 dart_host_->fatal_error().c_str());
    exit_code_ = dart_terminal::kRuntimeSoftwareExitCode;
  }

  const size_t leaked_handles =
      dart_appkit::ObjectRegistry::Shared().live_count();
  if (leaked_handles != 0) {
    std::fprintf(
        stderr,
        "Dart Terminal release shutdown releasing %zu live native handle(s)\n",
        leaked_handles);
    exit_code_ = dart_terminal::kRuntimeSoftwareExitCode;
  }

  dart_appkit::ShutdownBridge();
  if (message_pump_ != nullptr) {
    message_pump_->Stop();
  }
  if (dart_host_ != nullptr) {
    dart_host_->Shutdown();
  }
  dart_terminal::RuntimeLifecycleCompleteApplicationTermination(exit_code_);
}

@end

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    if (dart_terminal::RuntimeLifecycleShouldFailHostStartup()) {
      std::fprintf(stderr,
                   "RUNTIME_LIFECYCLE_FATAL class=host-startup status=70\n");
      return dart_terminal::kRuntimeSoftwareExitCode;
    }
    NSString* snapshot = [[NSBundle mainBundle] pathForResource:@"application"
                                                         ofType:@"aot"];
    if (snapshot == nil ||
        !std::filesystem::is_regular_file(snapshot.fileSystemRepresentation)) {
      std::fprintf(stderr, "Release AOT snapshot not found in app bundle\n");
      return dart_terminal::kRuntimeInputExitCode;
    }

    std::vector<std::string> application_arguments;
    application_arguments.reserve(argc > 1 ? static_cast<size_t>(argc - 1) : 0);
    for (int index = 1; index < argc; ++index) {
      application_arguments.emplace_back(argv[index]);
    }
    std::string worker_error;
    if (!dart_terminal::ConfigureRuntimeWorker(argv[0], &application_arguments,
                                               &worker_error)) {
      std::fprintf(stderr, "Runtime worker configuration error: %s\n",
                   worker_error.c_str());
      return dart_terminal::kRuntimeInputExitCode;
    }

    NSApplication* application = [NSApplication sharedApplication];
    application.activationPolicy = NSApplicationActivationPolicyRegular;
    std::string registration_error;
    if (!dart_terminal::RegisterTerminalMetalView(&registration_error)) {
      std::fprintf(stderr, "TerminalMetalView registration failed: %s\n",
                   registration_error.c_str());
      return dart_terminal::kRuntimeSoftwareExitCode;
    }
    DartTerminalReleaseAotDelegate* delegate =
        [[DartTerminalReleaseAotDelegate alloc]
            initWithSnapshotPath:std::string(snapshot.fileSystemRepresentation)
            applicationArguments:application_arguments];
    application.delegate = delegate;
    [application run];
    return dart_terminal::RuntimeLifecycleEffectiveExitCode(delegate.exitCode);
  }
}
