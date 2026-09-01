#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>

#include <pthread.h>

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <deque>
#include <memory>
#include <mutex>
#include <string>

#include "include/dart_api.h"
#include "include/dart_engine.h"

extern "C" __attribute__((weak, visibility("default"))) void
dt_phase0_native_finalize(void) {}

namespace {

constexpr size_t kMaxMessagesPerTurn = 64;
constexpr auto kMaxTimePerTurn = std::chrono::microseconds(4000);
constexpr int kSoftwareExitCode = 70;

std::atomic<bool> g_dart_reported_success{false};
std::atomic<uint64_t> g_dart_elapsed_micros{0};
std::atomic<bool> g_worker_reported_success{false};
std::atomic<uint64_t> g_worker_bytes{0};
std::atomic<uint64_t> g_worker_chunks{0};
std::atomic<uint64_t> g_worker_ping_micros{0};
std::atomic<uint64_t> g_worker_heartbeat_gap_micros{0};
NSWindow* g_window = nil;

uint64_t CurrentThreadId() {
  uint64_t thread_id = 0;
  if (pthread_threadid_np(nullptr, &thread_id) != 0) {
    return 0;
  }
  return thread_id;
}

void RequestApplicationStop() {
  dispatch_async(dispatch_get_main_queue(), ^{
    [NSApp stop:nil];
    NSEvent* wake_event = [NSEvent
        otherEventWithType:NSEventTypeApplicationDefined
                   location:NSZeroPoint
              modifierFlags:0
                  timestamp:0
               windowNumber:0
                    context:nil
                    subtype:0
                      data1:0
                      data2:0];
    [NSApp postEvent:wake_event atStart:YES];
  });
}

std::string CopyAndFreeError(char* error) {
  if (error == nullptr) {
    return {};
  }
  std::string result(error);
  std::free(error);
  return result;
}

std::string CopyDartError(Dart_Handle error) {
  if (!Dart_IsError(error)) {
    return {};
  }
  const char* text = Dart_GetError(error);
  return text == nullptr ? "unknown Dart error" : std::string(text);
}

class AotMessagePump final {
 public:
  struct Stats {
    uint64_t handled_messages = 0;
    uint64_t drain_turns = 0;
    uint64_t resignaled_turns = 0;
    int64_t max_elapsed_micros = 0;
  };

  ~AotMessagePump() { Stop(); }

  bool Start(std::string* out_error) {
    if (pthread_main_np() == 0) {
      *out_error = "message pump must start on the process main thread";
      return false;
    }

    CFRunLoopSourceContext context = {};
    context.info = this;
    context.perform = PerformSource;
    CFRunLoopSourceRef source =
        CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context);
    if (source == nullptr) {
      *out_error = "could not create Dart CFRunLoopSource";
      return false;
    }

    CFRunLoopRef run_loop = CFRunLoopGetMain();
    CFRetain(run_loop);
    CFRunLoopAddSource(run_loop, source, kCFRunLoopCommonModes);
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      source_ = source;
      run_loop_ = run_loop;
      running_ = true;
    }
    return true;
  }

  void Stop() {
    CFRunLoopSourceRef source = nullptr;
    CFRunLoopRef run_loop = nullptr;
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      running_ = false;
      pending_.clear();
      source = source_;
      run_loop = run_loop_;
      source_ = nullptr;
      run_loop_ = nullptr;
    }
    if (source != nullptr) {
      if (run_loop != nullptr) {
        CFRunLoopRemoveSource(run_loop, source, kCFRunLoopCommonModes);
      }
      CFRunLoopSourceInvalidate(source);
      CFRelease(source);
    }
    if (run_loop != nullptr) {
      CFRelease(run_loop);
    }
  }

  DartEngine_MessageScheduler scheduler() {
    return DartEngine_MessageScheduler{ScheduleMessage, this};
  }

  Stats stats() const {
    const std::lock_guard<std::mutex> lock(mutex_);
    return stats_;
  }

 private:
  static void ScheduleMessage(Dart_Isolate isolate, void* context) {
    if (isolate != nullptr && context != nullptr) {
      static_cast<AotMessagePump*>(context)->Enqueue(isolate);
    }
  }

  static void PerformSource(void* context) {
    if (context != nullptr) {
      static_cast<AotMessagePump*>(context)->DrainOneTurn();
    }
  }

  void Enqueue(Dart_Isolate isolate) {
    CFRunLoopSourceRef source = nullptr;
    CFRunLoopRef run_loop = nullptr;
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      if (!running_ || source_ == nullptr || run_loop_ == nullptr) {
        return;
      }
      pending_.push_back(isolate);
      source = source_;
      run_loop = run_loop_;
      CFRetain(source);
      CFRetain(run_loop);
    }
    CFRunLoopSourceSignal(source);
    CFRunLoopWakeUp(run_loop);
    CFRelease(source);
    CFRelease(run_loop);
  }

  void DrainOneTurn() {
    if (pthread_main_np() == 0) {
      return;
    }

    const auto started = std::chrono::steady_clock::now();
    size_t handled = 0;
    while (handled < kMaxMessagesPerTurn) {
      Dart_Isolate isolate = nullptr;
      {
        const std::lock_guard<std::mutex> lock(mutex_);
        if (!running_ || pending_.empty()) {
          break;
        }
        isolate = pending_.front();
        pending_.pop_front();
      }
      DartEngine_HandleMessage(isolate);
      ++handled;
      if (std::chrono::steady_clock::now() - started >= kMaxTimePerTurn) {
        break;
      }
    }

    const int64_t elapsed =
        std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::steady_clock::now() - started)
            .count();
    CFRunLoopSourceRef source = nullptr;
    CFRunLoopRef run_loop = nullptr;
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      if (handled != 0) {
        stats_.handled_messages += handled;
        ++stats_.drain_turns;
        if (elapsed > stats_.max_elapsed_micros) {
          stats_.max_elapsed_micros = elapsed;
        }
      }
      if (running_ && !pending_.empty() && source_ != nullptr &&
          run_loop_ != nullptr) {
        ++stats_.resignaled_turns;
        source = source_;
        run_loop = run_loop_;
        CFRetain(source);
        CFRetain(run_loop);
      }
    }
    if (source != nullptr && run_loop != nullptr) {
      CFRunLoopSourceSignal(source);
      CFRunLoopWakeUp(run_loop);
      CFRelease(source);
      CFRelease(run_loop);
    }
  }

  mutable std::mutex mutex_;
  std::deque<Dart_Isolate> pending_;
  CFRunLoopSourceRef source_ = nullptr;
  CFRunLoopRef run_loop_ = nullptr;
  bool running_ = false;
  Stats stats_;
};

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

class AotHost final {
 public:
  explicit AotHost(AotMessagePump* main_pump) : main_pump_(main_pump) {}
  ~AotHost() { Shutdown(); }

  bool Start(const std::string& snapshot_path, std::string* out_error) {
    if (pthread_main_np() == 0) {
      *out_error = "AOT root isolate must start on the process main thread";
      return false;
    }
    if (main_pump_ == nullptr) {
      *out_error = "AOT host requires a main message pump";
      return false;
    }

    char* engine_error = nullptr;
    if (!DartEngine_Init(&engine_error)) {
      *out_error = "DartEngine_Init failed: " + CopyAndFreeError(engine_error);
      return false;
    }
    engine_started_ = true;
    active_host_.store(this, std::memory_order_release);
    DartEngine_SetDefaultMessageScheduler(main_pump_->scheduler());
    DartEngine_SetHandleMessageErrorCallback(HandleMessageError);

    const DartEngine_SnapshotData snapshot =
        DartEngine_AotSnapshotFromFile(snapshot_path.c_str(), &engine_error);
    if (engine_error != nullptr) {
      *out_error = "could not load AOT snapshot: " +
                   CopyAndFreeError(engine_error);
      Shutdown();
      return false;
    }

    isolate_ = DartEngine_CreateIsolate(snapshot, &engine_error);
    if (isolate_ == nullptr || engine_error != nullptr) {
      *out_error = "could not create AOT root isolate: " +
                   CopyAndFreeError(engine_error);
      isolate_ = nullptr;
      Shutdown();
      return false;
    }
    DartEngine_SetMessageScheduler(main_pump_->scheduler(), isolate_);

    EnteredIsolate entered(isolate_);
    Dart_Handle result = Dart_Invoke(
        Dart_RootLibrary(), Dart_NewStringFromCString("main"), 0, nullptr);
    if (Dart_IsError(result)) {
      *out_error = "Dart AOT main failed: " + CopyDartError(result);
      return false;
    }
    result = DartEngine_DrainMicrotasksQueue();
    if (Dart_IsError(result)) {
      *out_error = "Dart AOT startup microtask failed: " +
                   CopyDartError(result);
      return false;
    }
    return true;
  }

  void Shutdown() {
    AotHost* expected = this;
    active_host_.compare_exchange_strong(expected, nullptr,
                                         std::memory_order_acq_rel);
    if (engine_started_) {
      DartEngine_SetHandleMessageErrorCallback(nullptr);
      DartEngine_Shutdown();
      engine_started_ = false;
      isolate_ = nullptr;
    }
  }

  bool has_fatal_error() const {
    const std::lock_guard<std::mutex> lock(error_mutex_);
    return !fatal_error_.empty();
  }

  std::string fatal_error() const {
    const std::lock_guard<std::mutex> lock(error_mutex_);
    return fatal_error_;
  }

 private:
  static void HandleMessageError(Dart_Handle error, Dart_Isolate isolate) {
    (void)isolate;
    AotHost* host = active_host_.load(std::memory_order_acquire);
    if (host == nullptr) {
      return;
    }
    {
      const std::lock_guard<std::mutex> lock(host->error_mutex_);
      if (host->fatal_error_.empty()) {
        host->fatal_error_ = CopyDartError(error);
      }
    }
    RequestApplicationStop();
  }

  static std::atomic<AotHost*> active_host_;
  AotMessagePump* main_pump_ = nullptr;
  Dart_Isolate isolate_ = nullptr;
  bool engine_started_ = false;
  mutable std::mutex error_mutex_;
  std::string fatal_error_;
};

std::atomic<AotHost*> AotHost::active_host_{nullptr};

}  // namespace

extern "C" __attribute__((visibility("default"))) uint32_t
dt_phase0_aot_abi_version(void) {
  return 1;
}

extern "C" __attribute__((visibility("default"))) int32_t
dt_phase0_aot_is_main_thread(void) {
  return pthread_main_np() != 0 ? 1 : 0;
}

extern "C" __attribute__((visibility("default"))) uint64_t
dt_phase0_aot_thread_id(void) {
  return CurrentThreadId();
}

extern "C" __attribute__((visibility("default"))) int32_t
dt_phase0_aot_show_window(void) {
  if (pthread_main_np() == 0) {
    return 1;
  }
  if (g_window != nil) {
    return 0;
  }

  const NSRect frame = NSMakeRect(160, 160, 680, 320);
  g_window = [[NSWindow alloc]
      initWithContentRect:frame
                styleMask:(NSWindowStyleMaskTitled |
                           NSWindowStyleMaskClosable |
                           NSWindowStyleMaskResizable)
                  backing:NSBackingStoreBuffered
                    defer:NO];
  g_window.releasedWhenClosed = NO;
  g_window.title = @"Dart Terminal — Phase 0 AOT";

  NSTextField* label = [NSTextField labelWithString:
      @"Release AOT Dart root isolate is running on the AppKit main thread."];
  label.alignment = NSTextAlignmentCenter;
  label.font = [NSFont monospacedSystemFontOfSize:16
                                           weight:NSFontWeightRegular];
  label.frame = NSMakeRect(30, 135, 620, 40);
  NSView* content = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 680, 320)];
  [content addSubview:label];
  g_window.contentView = content;
  [g_window makeKeyAndOrderFront:nil];
  return 0;
}

extern "C" __attribute__((visibility("default"))) int32_t
dt_phase0_aot_report_success(uint64_t elapsed_micros) {
  if (pthread_main_np() == 0 || g_window == nil) {
    return 1;
  }
  g_dart_elapsed_micros.store(elapsed_micros, std::memory_order_release);
  g_dart_reported_success.store(true, std::memory_order_release);
  return 0;
}

extern "C" __attribute__((visibility("default"))) int32_t
dt_phase0_worker_report_success(
    uint64_t bytes, uint64_t elapsed_micros, uint64_t chunks,
    uint64_t root_thread_id, uint64_t worker_thread_id,
    uint64_t ping_micros, uint64_t heartbeat_gap_micros,
    uint64_t worker_exit_seen, uint64_t fault_thread_id,
    uint64_t fault_error_seen, uint64_t fault_exit_seen) {
  g_dart_elapsed_micros.store(elapsed_micros, std::memory_order_release);
  g_worker_bytes.store(bytes, std::memory_order_release);
  g_worker_chunks.store(chunks, std::memory_order_release);
  g_worker_ping_micros.store(ping_micros, std::memory_order_release);
  g_worker_heartbeat_gap_micros.store(heartbeat_gap_micros,
                                      std::memory_order_release);

  const uint64_t current_thread_id = CurrentThreadId();
  const uint64_t minimum_bytes = 64ULL * 1024ULL * 1024ULL;
  const uint64_t minimum_bytes_per_second = 100ULL * 1024ULL * 1024ULL;
  const uint64_t bytes_per_second =
      elapsed_micros == 0 ? 0 : (bytes * 1000000ULL) / elapsed_micros;

  uint32_t failures = 0;
  failures |= pthread_main_np() == 0 ? 1U << 0 : 0;
  failures |= g_window == nil ? 1U << 1 : 0;
  failures |= bytes < minimum_bytes ? 1U << 2 : 0;
  failures |= chunks < 128 ? 1U << 3 : 0;
  failures |= root_thread_id == 0 || root_thread_id != current_thread_id
                  ? 1U << 4
                  : 0;
  failures |= worker_thread_id == 0 || worker_thread_id == root_thread_id
                  ? 1U << 5
                  : 0;
  failures |= fault_thread_id == 0 || fault_thread_id == root_thread_id
                  ? 1U << 6
                  : 0;
  failures |= worker_exit_seen != 1 ? 1U << 7 : 0;
  failures |= fault_error_seen != 1 ? 1U << 8 : 0;
  failures |= fault_exit_seen != 1 ? 1U << 9 : 0;
  failures |= bytes_per_second < minimum_bytes_per_second ? 1U << 10 : 0;
  failures |= ping_micros > 50000 ? 1U << 11 : 0;
  failures |= heartbeat_gap_micros > 50000 ? 1U << 12 : 0;

  if (failures != 0) {
    std::fprintf(stderr,
                 "PHASE0_WORKER_REPORT_REJECT failures=0x%x "
                 "bytes_per_second=%llu\n",
                 failures,
                 static_cast<unsigned long long>(bytes_per_second));
    return static_cast<int32_t>(failures);
  }

  g_worker_reported_success.store(true, std::memory_order_release);
  g_dart_reported_success.store(true, std::memory_order_release);
  return 0;
}

extern "C" __attribute__((visibility("default"))) int32_t
dt_phase0_aot_terminate(void) {
  if (pthread_main_np() == 0) {
    return 1;
  }
  RequestApplicationStop();
  return 0;
}

@interface Phase0AotDelegate : NSObject <NSApplicationDelegate> {
 @private
  std::string snapshot_path_;
  std::unique_ptr<AotMessagePump> pump_;
  std::unique_ptr<AotHost> host_;
  int exit_code_;
}

- (instancetype)initWithSnapshotPath:(const std::string&)snapshotPath;
- (int)exitCode;
- (void)finalizeRun;

@end

@implementation Phase0AotDelegate

- (instancetype)initWithSnapshotPath:(const std::string&)snapshotPath {
  self = [super init];
  if (self != nil) {
    snapshot_path_ = snapshotPath;
    exit_code_ = kSoftwareExitCode;
  }
  return self;
}

- (int)exitCode {
  return exit_code_;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
  (void)notification;
  pump_ = std::make_unique<AotMessagePump>();
  std::string error;
  if (!pump_->Start(&error)) {
    std::fprintf(stderr, "PHASE0_AOT_FAIL %s\n", error.c_str());
    RequestApplicationStop();
    return;
  }

  host_ = std::make_unique<AotHost>(pump_.get());
  if (!host_->Start(snapshot_path_, &error)) {
    std::fprintf(stderr, "PHASE0_AOT_FAIL %s\n", error.c_str());
    RequestApplicationStop();
    return;
  }

  [NSApp activateIgnoringOtherApps:YES];
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC),
      dispatch_get_main_queue(), ^{
        if (!g_dart_reported_success.load(std::memory_order_acquire)) {
          std::fprintf(stderr, "PHASE0_AOT_FAIL timeout\n");
          RequestApplicationStop();
        }
      });
}

- (void)finalizeRun {
  if (pump_ != nullptr) {
    pump_->Stop();
  }
  const AotMessagePump::Stats stats =
      pump_ == nullptr ? AotMessagePump::Stats{} : pump_->stats();
  const bool fatal = host_ != nullptr && host_->has_fatal_error();
  const bool worker_reported =
      g_worker_reported_success.load(std::memory_order_acquire);
  const bool forced_failure = std::getenv("DT_PHASE0_FORCE_FAIL") != nullptr;
  const bool passed =
      g_dart_reported_success.load(std::memory_order_acquire) && !fatal &&
      !forced_failure &&
      stats.max_elapsed_micros <
          std::chrono::duration_cast<std::chrono::microseconds>(
              kMaxTimePerTurn)
              .count();

  const uint64_t worker_bytes =
      g_worker_bytes.load(std::memory_order_acquire);
  const uint64_t worker_elapsed =
      g_dart_elapsed_micros.load(std::memory_order_acquire);
  const double worker_mib_per_second =
      worker_elapsed == 0
          ? 0.0
          : (static_cast<double>(worker_bytes) * 1000000.0 /
             static_cast<double>(worker_elapsed)) /
                (1024.0 * 1024.0);

  std::fprintf(
      passed ? stdout : stderr,
      "PHASE0_AOT_NATIVE_%s main_thread=%d dart_elapsed_us=%llu "
      "messages=%llu turns=%llu resignaled=%llu max_turn_us=%lld "
      "worker_mode=%d worker_mib_s=%.2f chunks=%llu ping_us=%llu "
      "heartbeat_gap_us=%llu forced_failure=%d\n",
      passed ? "PASS" : "FAIL", pthread_main_np() != 0 ? 1 : 0,
      static_cast<unsigned long long>(
          g_dart_elapsed_micros.load(std::memory_order_acquire)),
      static_cast<unsigned long long>(stats.handled_messages),
      static_cast<unsigned long long>(stats.drain_turns),
      static_cast<unsigned long long>(stats.resignaled_turns),
      static_cast<long long>(stats.max_elapsed_micros), worker_reported ? 1 : 0,
      worker_mib_per_second,
      static_cast<unsigned long long>(
          g_worker_chunks.load(std::memory_order_acquire)),
      static_cast<unsigned long long>(
          g_worker_ping_micros.load(std::memory_order_acquire)),
      static_cast<unsigned long long>(
          g_worker_heartbeat_gap_micros.load(std::memory_order_acquire)),
      forced_failure ? 1 : 0);
  if (fatal) {
    std::fprintf(stderr, "PHASE0_AOT_FAIL Dart error: %s\n",
                 host_->fatal_error().c_str());
  }
  exit_code_ = passed ? 0 : kSoftwareExitCode;

  dt_phase0_native_finalize();
  if (host_ != nullptr) {
    host_->Shutdown();
  }
  g_window = nil;
}

@end

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    NSString* snapshot = nil;
    if (argc == 2) {
      snapshot = [NSString stringWithUTF8String:argv[1]];
    } else {
      snapshot = [[NSBundle mainBundle] pathForResource:@"phase0_app"
                                                 ofType:@"aot"];
    }
    if (snapshot == nil ||
        ![[NSFileManager defaultManager] fileExistsAtPath:snapshot]) {
      std::fprintf(stderr, "PHASE0_AOT_FAIL snapshot not found\n");
      return 66;
    }

    NSApplication* application = [NSApplication sharedApplication];
    application.activationPolicy = NSApplicationActivationPolicyRegular;
    Phase0AotDelegate* delegate = [[Phase0AotDelegate alloc]
        initWithSnapshotPath:std::string(snapshot.fileSystemRepresentation)];
    application.delegate = delegate;
    [application run];
    [delegate finalizeRun];
    return delegate.exitCode;
  }
}
