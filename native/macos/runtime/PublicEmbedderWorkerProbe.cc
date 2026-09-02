#include <pthread.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdlib>
#include <deque>
#include <functional>
#include <iostream>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>

#include "include/dart_api.h"
#include "include/dart_engine.h"

namespace {

using Clock = std::chrono::steady_clock;
constexpr auto kProbeTimeout = std::chrono::seconds(20);
constexpr auto kCleanupTimeout = std::chrono::seconds(5);

struct WorkerHandle {
  std::mutex mutex;
  Dart_Isolate isolate = nullptr;
  std::atomic<bool> shutdown{false};
  std::atomic<bool> cleaned{false};
};

struct DartReport {
  bool ready = false;
  int status = 1;
  uint64_t transferred_bytes = 0;
  uint64_t transfer_micros = 0;
  uint64_t normal_observed = 0;
  uint64_t fault_observed = 0;
  uint64_t forced_observed = 0;
  uint64_t replacement_observed = 0;
  uint64_t microtasks_unavailable_observed = 0;
  uint64_t fault_diagnostic_lost_observed = 0;
};

std::mutex g_state_mutex;
std::condition_variable g_state_condition;
std::vector<WorkerHandle*> g_workers;
DartReport g_report;
std::string g_last_native_error;
std::atomic<uint64_t> g_created{0};
std::atomic<uint64_t> g_shutdown{0};
std::atomic<uint64_t> g_cleaned{0};
std::atomic<uint64_t> g_released{0};
std::atomic<bool> g_root_message_error{false};

void SetNativeError(const std::string& message) {
  const std::lock_guard<std::mutex> lock(g_state_mutex);
  g_last_native_error = message;
}

std::string CopyAndFreeError(char* error) {
  if (error == nullptr) {
    return {};
  }
  std::string result(error);
  std::free(error);
  return result;
}

void WorkerShutdown(void* isolate_group_data, void* isolate_data) {
  (void)isolate_group_data;
  auto* worker = static_cast<WorkerHandle*>(isolate_data);
  if (worker != nullptr) {
    worker->shutdown.store(true, std::memory_order_release);
    g_shutdown.fetch_add(1, std::memory_order_acq_rel);
  }
}

void WorkerCleanup(void* isolate_group_data, void* isolate_data) {
  (void)isolate_group_data;
  auto* worker = static_cast<WorkerHandle*>(isolate_data);
  if (worker != nullptr) {
    {
      const std::lock_guard<std::mutex> lock(worker->mutex);
      worker->isolate = nullptr;
    }
    // Publish cleanup only after the callback has finished using worker-owned
    // synchronization. A successful observation authorizes handle deletion.
    worker->cleaned.store(true, std::memory_order_release);
    g_cleaned.fetch_add(1, std::memory_order_acq_rel);
    g_state_condition.notify_all();
  }
}

class MainMessagePump final {
 public:
  DartEngine_MessageScheduler scheduler() {
    return DartEngine_MessageScheduler{Schedule, this};
  }

  bool PumpUntil(const std::function<bool()>& done) {
    const Clock::time_point deadline = Clock::now() + kProbeTimeout;
    while (!done()) {
      Dart_Isolate isolate = nullptr;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        condition_.wait_until(lock, deadline,
                              [this] { return stopped_ || !pending_.empty(); });
        if (stopped_) {
          return done();
        }
        if (pending_.empty()) {
          return done();
        }
        isolate = pending_.front();
        pending_.pop_front();
      }
      DartEngine_HandleMessage(isolate);
      if (Clock::now() >= deadline) {
        return done();
      }
    }
    return true;
  }

  void Stop() {
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      stopped_ = true;
      pending_.clear();
    }
    condition_.notify_all();
  }

 private:
  static void Schedule(Dart_Isolate isolate, void* context) {
    if (isolate != nullptr && context != nullptr) {
      static_cast<MainMessagePump*>(context)->Enqueue(isolate);
    }
  }

  void Enqueue(Dart_Isolate isolate) {
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      if (stopped_) {
        return;
      }
      pending_.push_back(isolate);
    }
    condition_.notify_one();
  }

  std::mutex mutex_;
  std::condition_variable condition_;
  std::deque<Dart_Isolate> pending_;
  bool stopped_ = false;
};

class EnteredEngineIsolate final {
 public:
  explicit EnteredEngineIsolate(Dart_Isolate isolate) : isolate_(isolate) {
    DartEngine_AcquireIsolate(isolate_);
    Dart_EnterScope();
  }

  ~EnteredEngineIsolate() {
    Dart_ExitScope();
    DartEngine_ReleaseIsolate();
  }

  EnteredEngineIsolate(const EnteredEngineIsolate&) = delete;
  EnteredEngineIsolate& operator=(const EnteredEngineIsolate&) = delete;

 private:
  Dart_Isolate isolate_;
};

bool ReportReady() {
  const std::lock_guard<std::mutex> lock(g_state_mutex);
  return g_report.ready || g_root_message_error.load(std::memory_order_acquire);
}

void HandleRootMessageError(Dart_Handle error,
                            Dart_Isolate destination_isolate) {
  (void)destination_isolate;
  const char* detail = Dart_GetError(error);
  SetNativeError(detail == nullptr ? "unknown root message error" : detail);
  g_root_message_error.store(true, std::memory_order_release);
  g_state_condition.notify_all();
}

bool WaitForAllWorkersCleaned() {
  const Clock::time_point deadline = Clock::now() + kCleanupTimeout;
  std::unique_lock<std::mutex> lock(g_state_mutex);
  return g_state_condition.wait_until(lock, deadline, [] {
    return std::all_of(g_workers.begin(), g_workers.end(),
                       [](WorkerHandle* worker) {
                         return worker->cleaned.load(std::memory_order_acquire);
                       });
  });
}

void KillOutstandingWorkers() {
  std::vector<WorkerHandle*> workers;
  {
    const std::lock_guard<std::mutex> lock(g_state_mutex);
    workers = g_workers;
  }
  for (WorkerHandle* worker : workers) {
    const std::lock_guard<std::mutex> lock(worker->mutex);
    if (worker->isolate != nullptr) {
      Dart_KillIsolate(worker->isolate);
    }
  }
}

void DeleteCleanedWorkers() {
  std::vector<WorkerHandle*> workers;
  {
    const std::lock_guard<std::mutex> lock(g_state_mutex);
    workers.swap(g_workers);
  }
  for (WorkerHandle* worker : workers) {
    if (worker->cleaned.load(std::memory_order_acquire)) {
      delete worker;
      g_released.fetch_add(1, std::memory_order_acq_rel);
    }
  }
}

}  // namespace

DART_EXPORT WorkerHandle* dt_public_embedder_create_worker() {
  Dart_Isolate parent = Dart_CurrentIsolate();
  if (parent == nullptr) {
    SetNativeError("worker creation requires a current parent isolate");
    return nullptr;
  }

  auto* worker = new WorkerHandle();
  Dart_ExitIsolate();
  char* error = nullptr;
  Dart_Isolate child =
      Dart_CreateIsolateInGroup(parent, "dart-terminal-public-worker",
                                WorkerShutdown, WorkerCleanup, worker, &error);
  if (child == nullptr || error != nullptr) {
    SetNativeError("Dart_CreateIsolateInGroup failed: " +
                   CopyAndFreeError(error));
    if (child != nullptr) {
      Dart_ShutdownIsolate();
    }
    Dart_EnterIsolate(parent);
    delete worker;
    return nullptr;
  }

  worker->isolate = child;
  {
    const std::lock_guard<std::mutex> lock(g_state_mutex);
    g_workers.push_back(worker);
  }
  g_created.fetch_add(1, std::memory_order_acq_rel);
  Dart_ExitIsolate();
  Dart_EnterIsolate(parent);
  return worker;
}

DART_EXPORT int32_t dt_public_embedder_start_worker(WorkerHandle* worker,
                                                    int64_t root_port,
                                                    int64_t error_port,
                                                    int64_t exit_port) {
  if (worker == nullptr) {
    SetNativeError("cannot start a null worker");
    return 1;
  }
  Dart_Isolate parent = Dart_CurrentIsolate();
  if (parent == nullptr) {
    SetNativeError("worker start requires a current parent isolate");
    return 2;
  }

  Dart_Isolate child = nullptr;
  {
    const std::lock_guard<std::mutex> lock(worker->mutex);
    child = worker->isolate;
  }
  if (child == nullptr) {
    SetNativeError("worker was cleaned before start");
    return 3;
  }

  Dart_ExitIsolate();
  Dart_EnterIsolate(child);
  Dart_EnterScope();
  Dart_Handle argument = Dart_NewSendPort(static_cast<Dart_Port>(root_port));
  Dart_Handle result = argument;
  if (!Dart_IsError(argument)) {
    Dart_Handle arguments[] = {argument};
    result = Dart_Invoke(Dart_RootLibrary(),
                         Dart_NewStringFromCString("publicEmbedderWorkerMain"),
                         1, arguments);
  }
  std::string invoke_error;
  if (Dart_IsError(result)) {
    const char* detail = Dart_GetError(result);
    invoke_error = detail == nullptr ? "unknown worker invocation error"
                                     : std::string(detail);
  }
  Dart_ExitScope();
  if (!invoke_error.empty()) {
    SetNativeError("worker entrypoint failed: " + invoke_error);
    Dart_ShutdownIsolate();
    Dart_EnterIsolate(parent);
    return 4;
  }

  char* error = nullptr;
  const bool started =
      Dart_RunLoopAsync(true, static_cast<Dart_Port>(error_port),
                        static_cast<Dart_Port>(exit_port), &error);
  if (!started) {
    SetNativeError("Dart_RunLoopAsync failed: " + CopyAndFreeError(error));
    Dart_ShutdownIsolate();
    Dart_EnterIsolate(parent);
    return 5;
  }
  Dart_EnterIsolate(parent);
  return 0;
}

DART_EXPORT void dt_public_embedder_kill_worker(WorkerHandle* worker) {
  if (worker == nullptr) {
    return;
  }
  const std::lock_guard<std::mutex> lock(worker->mutex);
  if (worker->isolate != nullptr) {
    Dart_KillIsolate(worker->isolate);
  }
}

DART_EXPORT int32_t dt_public_embedder_worker_cleaned(WorkerHandle* worker) {
  return worker != nullptr && worker->cleaned.load(std::memory_order_acquire)
             ? 1
             : 0;
}

DART_EXPORT int32_t dt_public_embedder_release_worker(WorkerHandle* worker) {
  if (worker == nullptr || !worker->cleaned.load(std::memory_order_acquire)) {
    return 1;
  }
  {
    const std::lock_guard<std::mutex> lock(g_state_mutex);
    const auto position = std::find(g_workers.begin(), g_workers.end(), worker);
    if (position == g_workers.end()) {
      return 2;
    }
    g_workers.erase(position);
  }
  delete worker;
  g_released.fetch_add(1, std::memory_order_acq_rel);
  return 0;
}

DART_EXPORT int32_t dt_public_embedder_is_main_thread() {
  return pthread_main_np() == 0 ? 0 : 1;
}

DART_EXPORT void dt_public_embedder_report(
    int32_t status, uint64_t transferred_bytes, uint64_t transfer_micros,
    uint64_t normal_observed, uint64_t fault_observed, uint64_t forced_observed,
    uint64_t replacement_observed, uint64_t microtasks_unavailable_observed,
    uint64_t fault_diagnostic_lost_observed) {
  {
    const std::lock_guard<std::mutex> lock(g_state_mutex);
    g_report = DartReport{
        true,
        status,
        transferred_bytes,
        transfer_micros,
        normal_observed,
        fault_observed,
        forced_observed,
        replacement_observed,
        microtasks_unavailable_observed,
        fault_diagnostic_lost_observed,
    };
  }
  g_state_condition.notify_all();
}

int main(int argc, char** argv) {
  if (argc != 2) {
    std::cerr << "usage: public_embedder_worker_probe SNAPSHOT\n";
    return 64;
  }

  MainMessagePump message_pump;
  bool engine_started = false;
  int result_status = 70;
  try {
    char* error = nullptr;
    if (!DartEngine_Init(&error)) {
      throw std::runtime_error("DartEngine_Init failed: " +
                               CopyAndFreeError(error));
    }
    engine_started = true;
    DartEngine_SetDefaultMessageScheduler(message_pump.scheduler());
    DartEngine_SetHandleMessageErrorCallback(HandleRootMessageError);

    const DartEngine_SnapshotData snapshot =
        Dart_IsPrecompiledRuntime()
            ? DartEngine_AotSnapshotFromFile(argv[1], &error)
            : DartEngine_KernelFromFile(argv[1], &error);
    if (error != nullptr) {
      throw std::runtime_error("snapshot load failed: " +
                               CopyAndFreeError(error));
    }
    Dart_Isolate root = DartEngine_CreateIsolate(snapshot, &error);
    if (root == nullptr || error != nullptr) {
      throw std::runtime_error("root creation failed: " +
                               CopyAndFreeError(error));
    }
    DartEngine_SetMessageScheduler(message_pump.scheduler(), root);

    {
      EnteredEngineIsolate entered(root);
      Dart_Handle result = Dart_Invoke(
          Dart_RootLibrary(),
          Dart_NewStringFromCString("startPublicEmbedderWorkerProbe"), 0,
          nullptr);
      if (Dart_IsError(result)) {
        throw std::runtime_error(std::string("probe entrypoint failed: ") +
                                 Dart_GetError(result));
      }
      result = DartEngine_DrainMicrotasksQueue();
      if (Dart_IsError(result)) {
        throw std::runtime_error(std::string("startup microtask failed: ") +
                                 Dart_GetError(result));
      }
    }

    if (!message_pump.PumpUntil(ReportReady)) {
      throw std::runtime_error("probe did not complete before its deadline");
    }

    DartReport report;
    std::string native_error;
    size_t outstanding_workers = 0;
    {
      const std::lock_guard<std::mutex> lock(g_state_mutex);
      report = g_report;
      native_error = g_last_native_error;
      outstanding_workers = g_workers.size();
    }
    const uint64_t created = g_created.load(std::memory_order_acquire);
    const uint64_t shutdown = g_shutdown.load(std::memory_order_acquire);
    const uint64_t cleaned = g_cleaned.load(std::memory_order_acquire);
    const uint64_t released = g_released.load(std::memory_order_acquire);
    const bool root_error =
        g_root_message_error.load(std::memory_order_acquire);

    std::cout << "probe.report_status=" << report.status << '\n';
    std::cout << "probe.transferred_bytes=" << report.transferred_bytes << '\n';
    std::cout << "probe.transfer_micros=" << report.transfer_micros << '\n';
    std::cout << "probe.normal_observed=" << report.normal_observed << '\n';
    std::cout << "probe.fault_observed=" << report.fault_observed << '\n';
    std::cout << "probe.forced_observed=" << report.forced_observed << '\n';
    std::cout << "probe.replacement_observed=" << report.replacement_observed
              << '\n';
    std::cout << "probe.microtasks_unavailable_observed="
              << report.microtasks_unavailable_observed << '\n';
    std::cout << "probe.fault_diagnostic_lost_observed="
              << report.fault_diagnostic_lost_observed << '\n';
    std::cout << "probe.native_created=" << created << '\n';
    std::cout << "probe.native_shutdown=" << shutdown << '\n';
    std::cout << "probe.native_cleaned=" << cleaned << '\n';
    std::cout << "probe.native_released=" << released << '\n';
    std::cout << "probe.outstanding_workers=" << outstanding_workers << '\n';
    std::cout << "probe.root_message_error=" << (root_error ? "true" : "false")
              << '\n';
    std::cout << "probe.native_error=" << native_error << '\n';

    const bool passed =
        report.ready && report.status == 0 &&
        report.transferred_bytes == 128ULL * 1024ULL * 1024ULL &&
        report.transfer_micros > 0 && report.normal_observed == 1 &&
        report.fault_observed == 1 && report.forced_observed == 1 &&
        report.replacement_observed == 1 &&
        report.microtasks_unavailable_observed == 1 && created == 4 &&
        report.fault_diagnostic_lost_observed == 1 && shutdown == 4 &&
        cleaned == 4 && released == 4 && outstanding_workers == 0 &&
        !root_error && native_error.empty();
    result_status = passed ? 0 : 70;
  } catch (const std::exception& exception) {
    std::cerr << "PUBLIC_EMBEDDER_WORKER_HOST_FAIL " << exception.what()
              << '\n';
    result_status = 70;
  }

  message_pump.Stop();
  KillOutstandingWorkers();
  const bool all_workers_cleaned = WaitForAllWorkersCleaned();
  if (!all_workers_cleaned) {
    std::cerr << "PUBLIC_EMBEDDER_WORKER_HOST_FAIL cleanup timeout\n";
    result_status = 70;
  }
  DeleteCleanedWorkers();
  if (engine_started && all_workers_cleaned) {
    const Clock::time_point shutdown_started = Clock::now();
    DartEngine_Shutdown();
    const int64_t shutdown_micros =
        std::chrono::duration_cast<std::chrono::microseconds>(Clock::now() -
                                                              shutdown_started)
            .count();
    std::cout << "probe.engine_shutdown_micros=" << shutdown_micros << '\n';
  }
  return result_status;
}
