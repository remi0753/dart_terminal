#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdlib>
#include <deque>
#include <exception>
#include <iomanip>
#include <iostream>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>

#include "include/dart_api.h"
#include "include/dart_engine.h"

namespace {

using Clock = std::chrono::steady_clock;
constexpr auto kObservationTimeout = std::chrono::seconds(5);

std::atomic<int> g_error_count{0};
std::atomic<Dart_Isolate> g_expected_error_isolate{nullptr};
std::mutex g_error_mutex;
std::string g_last_error;

std::string CopyAndFreeError(char *error) {
  if (error == nullptr) {
    return {};
  }
  std::string result(error);
  std::free(error);
  return result;
}

void RequireDartSuccess(Dart_Handle handle, const std::string &operation) {
  if (!Dart_IsError(handle)) {
    return;
  }
  const char *detail = Dart_GetError(handle);
  throw std::runtime_error(operation + ": " +
                           (detail == nullptr ? "unknown Dart error" : detail));
}

class EnteredIsolate final {
public:
  explicit EnteredIsolate(Dart_Isolate isolate) : isolate_(isolate) {
    if (isolate_ == nullptr) {
      throw std::runtime_error("cannot enter a null isolate");
    }
    DartEngine_AcquireIsolate(isolate_);
    Dart_EnterScope();
  }

  ~EnteredIsolate() {
    Dart_ExitScope();
    DartEngine_ReleaseIsolate();
  }

  EnteredIsolate(const EnteredIsolate &) = delete;
  EnteredIsolate &operator=(const EnteredIsolate &) = delete;

private:
  Dart_Isolate isolate_;
};

class MessageLoop final {
public:
  MessageLoop() : main_thread_(std::this_thread::get_id()) {}
  ~MessageLoop() { Stop(); }

  void Start() {
    worker_ = std::thread([this] { Run(); });
  }

  void Stop() {
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      if (stopping_) {
        return;
      }
      stopping_ = true;
      pending_.clear();
    }
    condition_.notify_all();
    if (worker_.joinable()) {
      worker_.join();
    }
  }

  DartEngine_MessageScheduler scheduler() {
    return DartEngine_MessageScheduler{Schedule, this};
  }

  bool handled_off_main_thread() const {
    return handled_off_main_thread_.load(std::memory_order_acquire);
  }

private:
  static void Schedule(Dart_Isolate isolate, void *context) {
    if (isolate != nullptr && context != nullptr) {
      static_cast<MessageLoop *>(context)->Enqueue(isolate);
    }
  }

  void Enqueue(Dart_Isolate isolate) {
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      if (stopping_) {
        return;
      }
      pending_.push_back(isolate);
    }
    condition_.notify_one();
  }

  void Run() {
    while (true) {
      Dart_Isolate isolate = nullptr;
      {
        std::unique_lock<std::mutex> lock(mutex_);
        condition_.wait(lock,
                        [this] { return stopping_ || !pending_.empty(); });
        if (stopping_) {
          return;
        }
        isolate = pending_.front();
        pending_.pop_front();
      }
      if (std::this_thread::get_id() != main_thread_) {
        handled_off_main_thread_.store(true, std::memory_order_release);
      }
      DartEngine_HandleMessage(isolate);
    }
  }

  const std::thread::id main_thread_;
  mutable std::mutex mutex_;
  std::condition_variable condition_;
  std::deque<Dart_Isolate> pending_;
  std::thread worker_;
  bool stopping_ = false;
  std::atomic<bool> handled_off_main_thread_{false};
};

void HandleMessageError(Dart_Handle error, Dart_Isolate destination_isolate) {
  const char *detail = Dart_GetError(error);
  {
    const std::lock_guard<std::mutex> lock(g_error_mutex);
    g_last_error = detail == nullptr ? "unknown Dart error" : detail;
  }
  if (destination_isolate ==
      g_expected_error_isolate.load(std::memory_order_acquire)) {
    g_error_count.fetch_add(1, std::memory_order_acq_rel);
  }
}

Dart_Handle Invoke(Dart_Isolate isolate, const char *function,
                   intptr_t argument_count, Dart_Handle *arguments) {
  (void)isolate;
  Dart_Handle result =
      Dart_Invoke(Dart_RootLibrary(), Dart_NewStringFromCString(function),
                  argument_count, arguments);
  RequireDartSuccess(result, std::string("Dart_Invoke(") + function + ")");
  return result;
}

Dart_Port StartDomain(Dart_Isolate isolate, const std::string &name) {
  EnteredIsolate entered(isolate);
  Dart_Handle arguments[] = {Dart_NewStringFromCString(name.c_str())};
  Dart_Handle send_port = Invoke(isolate, "startDomain", 1, arguments);
  Dart_Port port = 0;
  RequireDartSuccess(Dart_SendPortGetId(send_port, &port),
                     "Dart_SendPortGetId");
  return port;
}

void SetPeer(Dart_Isolate isolate, Dart_Port port) {
  EnteredIsolate entered(isolate);
  Dart_Handle arguments[] = {Dart_NewSendPort(port)};
  RequireDartSuccess(arguments[0], "Dart_NewSendPort");
  Invoke(isolate, "setPeer", 1, arguments);
}

void SendToPeer(Dart_Isolate isolate, const std::string &command,
                int64_t sequence) {
  EnteredIsolate entered(isolate);
  Dart_Handle arguments[] = {Dart_NewStringFromCString(command.c_str()),
                             Dart_NewInteger(sequence)};
  Invoke(isolate, "sendToPeer", 2, arguments);
}

void StartBulkTransfer(Dart_Isolate isolate, int64_t chunk_count,
                       int64_t chunk_bytes) {
  EnteredIsolate entered(isolate);
  Dart_Handle arguments[] = {Dart_NewInteger(chunk_count),
                             Dart_NewInteger(chunk_bytes)};
  Invoke(isolate, "startBulkTransfer", 2, arguments);
}

bool BooleanResult(Dart_Isolate isolate, const char *function) {
  EnteredIsolate entered(isolate);
  Dart_Handle result = Invoke(isolate, function, 0, nullptr);
  bool value = false;
  RequireDartSuccess(Dart_BooleanValue(result, &value),
                     std::string("Dart_BooleanValue(") + function + ")");
  return value;
}

int64_t IntegerResult(Dart_Isolate isolate, const char *function) {
  EnteredIsolate entered(isolate);
  Dart_Handle result = Invoke(isolate, function, 0, nullptr);
  int64_t value = 0;
  RequireDartSuccess(Dart_IntegerToInt64(result, &value),
                     std::string("Dart_IntegerToInt64(") + function + ")");
  return value;
}

void CloseDomain(Dart_Isolate isolate) {
  EnteredIsolate entered(isolate);
  Invoke(isolate, "closeDomain", 0, nullptr);
}

std::string EventLog(Dart_Isolate isolate) {
  EnteredIsolate entered(isolate);
  Dart_Handle result = Invoke(isolate, "eventLog", 0, nullptr);
  if (!Dart_IsString(result)) {
    throw std::runtime_error("eventLog did not return a String");
  }
  const char *value = nullptr;
  RequireDartSuccess(Dart_StringToCString(result, &value),
                     "Dart_StringToCString(eventLog)");
  return value == nullptr ? std::string() : std::string(value);
}

bool HasLivePorts(Dart_Isolate isolate) {
  EnteredIsolate entered(isolate);
  return Dart_HasLivePorts();
}

template <typename Predicate>
void WaitUntil(Predicate predicate, const std::string &description) {
  const Clock::time_point deadline = Clock::now() + kObservationTimeout;
  while (Clock::now() < deadline) {
    if (predicate()) {
      return;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(2));
  }
  throw std::runtime_error("timed out waiting for " + description);
}

Dart_Isolate CreateIsolate(const DartEngine_SnapshotData &snapshot,
                           const std::string &label, int64_t *elapsed_micros) {
  const Clock::time_point started = Clock::now();
  char *error = nullptr;
  Dart_Isolate isolate = DartEngine_CreateIsolate(snapshot, &error);
  *elapsed_micros = std::chrono::duration_cast<std::chrono::microseconds>(
                        Clock::now() - started)
                        .count();
  if (isolate == nullptr || error != nullptr) {
    throw std::runtime_error("could not create " + label + ": " +
                             CopyAndFreeError(error));
  }
  return isolate;
}

void PrintBoolean(const std::string &name, bool value) {
  std::cout << name << '=' << (value ? "true" : "false") << '\n';
}

} // namespace

int main(int argc, char **argv) {
  if (argc != 2) {
    std::cerr << "usage: unmodified_engine_multiple_root_probe SNAPSHOT\n";
    return 64;
  }

  MessageLoop message_loop;
  bool engine_initialized = false;
  try {
    char *error = nullptr;
    if (!DartEngine_Init(&error)) {
      throw std::runtime_error("DartEngine_Init failed: " +
                               CopyAndFreeError(error));
    }
    engine_initialized = true;
    message_loop.Start();
    DartEngine_SetDefaultMessageScheduler(message_loop.scheduler());
    DartEngine_SetHandleMessageErrorCallback(HandleMessageError);

    const DartEngine_SnapshotData snapshot =
        Dart_IsPrecompiledRuntime()
            ? DartEngine_AotSnapshotFromFile(argv[1], &error)
            : DartEngine_KernelFromFile(argv[1], &error);
    if (error != nullptr) {
      throw std::runtime_error("snapshot load failed: " +
                               CopyAndFreeError(error));
    }

    int64_t ui_create_micros = 0;
    int64_t worker_create_micros = 0;
    int64_t replacement_create_micros = 0;
    Dart_Isolate ui = CreateIsolate(snapshot, "UI root", &ui_create_micros);
    Dart_Isolate worker =
        CreateIsolate(snapshot, "worker root", &worker_create_micros);

    const Dart_Port ui_port = StartDomain(ui, "ui");
    const Dart_Port worker_port = StartDomain(worker, "worker");
    SetPeer(ui, worker_port);
    SetPeer(worker, ui_port);

    SendToPeer(ui, "ping", 1);
    WaitUntil(
        [&ui] { return EventLog(ui).find("ui:pong:1") != std::string::npos; },
        "cross-group pong");

    g_expected_error_isolate.store(worker, std::memory_order_release);
    SendToPeer(ui, "fail", 2);
    WaitUntil([] { return g_error_count.load(std::memory_order_acquire) == 1; },
              "worker-root error callback");

    SendToPeer(ui, "ping", 3);
    WaitUntil(
        [&ui] { return EventLog(ui).find("ui:pong:3") != std::string::npos; },
        "post-error worker-root pong");

    constexpr int64_t kBulkChunkCount = 512;
    constexpr int64_t kBulkChunkBytes = 256 * 1024;
    constexpr int64_t kExpectedBulkBytes = kBulkChunkCount * kBulkChunkBytes;
    StartBulkTransfer(ui, kBulkChunkCount, kBulkChunkBytes);
    WaitUntil([&ui] { return BooleanResult(ui, "bulkTransferDone"); },
              "cross-group bulk transfer");
    const int64_t bulk_bytes = IntegerResult(ui, "bulkTransferredBytes");
    const int64_t bulk_micros = IntegerResult(ui, "bulkElapsedMicros");
    if (bulk_bytes != kExpectedBulkBytes || bulk_micros <= 0) {
      throw std::runtime_error("bulk transfer metrics are invalid");
    }
    const double bulk_mib_per_second =
        (static_cast<double>(bulk_bytes) * 1000000.0) /
        (static_cast<double>(bulk_micros) * 1024.0 * 1024.0);

    CloseDomain(worker);
    const bool retired_root_has_live_ports = HasLivePorts(worker);

    Dart_Isolate replacement =
        CreateIsolate(snapshot, "replacement root", &replacement_create_micros);
    const Dart_Port replacement_port = StartDomain(replacement, "replacement");
    SetPeer(ui, replacement_port);
    SetPeer(replacement, ui_port);
    SendToPeer(ui, "ping", 4);
    WaitUntil(
        [&ui] { return EventLog(ui).find("ui:pong:4") != std::string::npos; },
        "replacement-root pong");

    std::string captured_error;
    {
      const std::lock_guard<std::mutex> lock(g_error_mutex);
      captured_error = g_last_error;
    }

    std::cout << "probe.created_roots=3\n";
    PrintBoolean("probe.cross_group_reply",
                 EventLog(ui).find("ui:pong:1") != std::string::npos);
    std::cout << "probe.worker_error_callbacks="
              << g_error_count.load(std::memory_order_acquire) << '\n';
    PrintBoolean("probe.worker_survived_error",
                 EventLog(ui).find("ui:pong:3") != std::string::npos);
    PrintBoolean("probe.retired_root_has_live_ports",
                 retired_root_has_live_ports);
    PrintBoolean("probe.replacement_reply",
                 EventLog(ui).find("ui:pong:4") != std::string::npos);
    PrintBoolean("probe.scheduler_off_main_thread",
                 message_loop.handled_off_main_thread());
    PrintBoolean("probe.intentional_error_observed",
                 captured_error.find("intentional worker failure 2") !=
                     std::string::npos);
    std::cout << "probe.bulk_bytes=" << bulk_bytes << '\n';
    std::cout << "probe.bulk_micros=" << bulk_micros << '\n';
    std::cout << std::fixed << std::setprecision(2)
              << "probe.bulk_mib_per_second=" << bulk_mib_per_second << '\n';
    std::cout << "probe.ui_create_micros=" << ui_create_micros << '\n';
    std::cout << "probe.worker_create_micros=" << worker_create_micros << '\n';
    std::cout << "probe.replacement_create_micros=" << replacement_create_micros
              << '\n';

    message_loop.Stop();
    const Clock::time_point shutdown_started = Clock::now();
    DartEngine_Shutdown();
    engine_initialized = false;
    const int64_t shutdown_micros =
        std::chrono::duration_cast<std::chrono::microseconds>(Clock::now() -
                                                              shutdown_started)
            .count();
    std::cout << "probe.global_shutdown_micros=" << shutdown_micros << '\n';
    return 0;
  } catch (const std::exception &exception) {
    message_loop.Stop();
    if (engine_initialized) {
      DartEngine_Shutdown();
    }
    std::cerr << "UNMODIFIED_ENGINE_PROBE_FAIL " << exception.what() << '\n';
    return 70;
  }
}
