#include "PtySpawn.h"

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <sys/event.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <limits>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "include/dart_native_api.h"

extern char** environ;

namespace {

constexpr size_t kDeliveryBatchBytes = 64 * 1024;
constexpr size_t kHighWaterBytes = 1024 * 1024;
constexpr size_t kLowWaterBytes = 512 * 1024;
constexpr size_t kBurstBytes = 10 * 1024 * 1024;
constexpr int kExpectedExitCode = 37;
constexpr auto kAckTimeout = std::chrono::seconds(5);
constexpr int64_t kBatchEvent = 1;
constexpr int64_t kSummaryEvent = 2;

struct ScenarioResult {
  int32_t status = 0;
  int32_t failed_step = 0;
  int32_t system_error = 0;
  int32_t exec_error = 0;
  int64_t child_pid = -1;
  int64_t exit_code = -1;
  uint64_t x_bytes = 0;
  uint64_t read_calls = 0;
  uint64_t elapsed_micros = 0;
  bool tty_ok = false;
  bool resize_ok = false;
  bool signal_ok = false;
};

struct OutstandingBatch {
  uint64_t sequence;
  size_t bytes;
};

class BridgeState;
ScenarioResult RunScenario(BridgeState* bridge);

Dart_CObject Int64Object(int64_t value) {
  Dart_CObject object = {};
  object.type = Dart_CObject_kInt64;
  object.value.as_int64 = value;
  return object;
}

class BridgeState final {
 public:
  ~BridgeState() {
    if (thread_.joinable()) {
      thread_.join();
    }
  }

  int32_t Start(Dart_Port port) {
    if (pthread_main_np() != 0 || port == ILLEGAL_PORT) {
      return 1;
    }

    const std::lock_guard<std::mutex> lock(mutex_);
    if (active_ || thread_.joinable()) {
      return 2;
    }

    active_ = true;
    finished_ = false;
    port_ = port;
    next_sequence_ = 0;
    last_acked_sequence_ = std::numeric_limits<uint64_t>::max();
    in_flight_bytes_ = 0;
    max_in_flight_bytes_ = 0;
    total_posted_bytes_ = 0;
    posted_batches_ = 0;
    min_large_batch_bytes_ = 0;
    max_batch_bytes_ = 0;
    backpressure_waits_ = 0;
    max_post_micros_ = 0;
    post_failures_ = 0;
    ack_failures_ = 0;
    outstanding_.clear();

    try {
      thread_ = std::thread([this] { Run(); });
    } catch (...) {
      active_ = false;
      port_ = ILLEGAL_PORT;
      return 3;
    }
    return 0;
  }

  int32_t Acknowledge(uint64_t sequence, uint64_t bytes) {
    const std::lock_guard<std::mutex> lock(mutex_);
    if (!active_ || outstanding_.empty()) {
      ++ack_failures_;
      return 1;
    }
    const OutstandingBatch expected = outstanding_.front();
    if (expected.sequence != sequence || expected.bytes != bytes) {
      ++ack_failures_;
      return 2;
    }
    outstanding_.pop_front();
    in_flight_bytes_ -= expected.bytes;
    last_acked_sequence_ = sequence;
    condition_.notify_all();
    return 0;
  }

  int32_t Join() {
    if (pthread_main_np() != 0) {
      return 1;
    }
    if (!thread_.joinable()) {
      return 2;
    }
    thread_.join();
    const std::lock_guard<std::mutex> lock(mutex_);
    active_ = false;
    port_ = ILLEGAL_PORT;
    return finished_ ? 0 : 3;
  }

  bool PostBatch(const uint8_t* bytes, size_t length) {
    if (bytes == nullptr || length == 0 || length > kDeliveryBatchBytes) {
      return false;
    }

    uint64_t sequence = 0;
    Dart_Port port = ILLEGAL_PORT;
    {
      std::unique_lock<std::mutex> lock(mutex_);
      if (!active_) {
        return false;
      }
      if (in_flight_bytes_ + length > kHighWaterBytes) {
        ++backpressure_waits_;
        const bool resumed = condition_.wait_for(lock, kAckTimeout, [this] {
          return !active_ || in_flight_bytes_ <= kLowWaterBytes;
        });
        if (!resumed || !active_) {
          ++post_failures_;
          return false;
        }
      }

      sequence = next_sequence_++;
      port = port_;
      outstanding_.push_back(OutstandingBatch{sequence, length});
      in_flight_bytes_ += length;
      max_in_flight_bytes_ =
          std::max(max_in_flight_bytes_, in_flight_bytes_);
    }

    Dart_CObject kind = Int64Object(kBatchEvent);
    Dart_CObject sequence_object =
        Int64Object(static_cast<int64_t>(sequence));
    Dart_CObject payload = {};
    payload.type = Dart_CObject_kTypedData;
    payload.value.as_typed_data.type = Dart_TypedData_kUint8;
    payload.value.as_typed_data.length = static_cast<intptr_t>(length);
    payload.value.as_typed_data.values = const_cast<uint8_t*>(bytes);
    Dart_CObject* values[] = {&kind, &sequence_object, &payload};
    Dart_CObject message = {};
    message.type = Dart_CObject_kArray;
    message.value.as_array.length = 3;
    message.value.as_array.values = values;

    const auto started = std::chrono::steady_clock::now();
    const bool posted = Dart_PostCObject(port, &message);
    const uint64_t post_micros = static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::steady_clock::now() - started)
            .count());

    const std::lock_guard<std::mutex> lock(mutex_);
    max_post_micros_ = std::max(max_post_micros_, post_micros);
    if (!posted) {
      ++post_failures_;
      if (!outstanding_.empty() &&
          outstanding_.back().sequence == sequence) {
        in_flight_bytes_ -= outstanding_.back().bytes;
        outstanding_.pop_back();
      }
      condition_.notify_all();
      return false;
    }

    total_posted_bytes_ += length;
    ++posted_batches_;
    max_batch_bytes_ = std::max(max_batch_bytes_, length);
    if (length >= kDeliveryBatchBytes &&
        (min_large_batch_bytes_ == 0 || length < min_large_batch_bytes_)) {
      min_large_batch_bytes_ = length;
    }
    return true;
  }

 private:
  bool WaitForAllAcknowledgements() {
    std::unique_lock<std::mutex> lock(mutex_);
    return condition_.wait_for(lock, kAckTimeout,
                               [this] { return outstanding_.empty(); });
  }

  bool PostSummary(const ScenarioResult& result) {
    Dart_Port port = ILLEGAL_PORT;
    uint64_t total_posted_bytes = 0;
    uint64_t posted_batches = 0;
    uint64_t min_large_batch_bytes = 0;
    uint64_t max_batch_bytes = 0;
    uint64_t max_in_flight_bytes = 0;
    uint64_t backpressure_waits = 0;
    uint64_t max_post_micros = 0;
    uint64_t post_failures = 0;
    uint64_t ack_failures = 0;
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      port = port_;
      total_posted_bytes = total_posted_bytes_;
      posted_batches = posted_batches_;
      min_large_batch_bytes = min_large_batch_bytes_;
      max_batch_bytes = max_batch_bytes_;
      max_in_flight_bytes = max_in_flight_bytes_;
      backpressure_waits = backpressure_waits_;
      max_post_micros = max_post_micros_;
      post_failures = post_failures_;
      ack_failures = ack_failures_;
    }

    Dart_CObject fields[] = {
        Int64Object(kSummaryEvent),
        Int64Object(result.status),
        Int64Object(result.failed_step),
        Int64Object(result.system_error),
        Int64Object(result.exec_error),
        Int64Object(result.child_pid),
        Int64Object(static_cast<int64_t>(total_posted_bytes)),
        Int64Object(static_cast<int64_t>(posted_batches)),
        Int64Object(static_cast<int64_t>(min_large_batch_bytes)),
        Int64Object(static_cast<int64_t>(max_batch_bytes)),
        Int64Object(static_cast<int64_t>(max_in_flight_bytes)),
        Int64Object(static_cast<int64_t>(backpressure_waits)),
        Int64Object(static_cast<int64_t>(result.x_bytes)),
        Int64Object(result.tty_ok ? 1 : 0),
        Int64Object(result.resize_ok ? 1 : 0),
        Int64Object(result.signal_ok ? 1 : 0),
        Int64Object(result.exit_code),
        Int64Object(static_cast<int64_t>(result.read_calls)),
        Int64Object(static_cast<int64_t>(result.elapsed_micros)),
        Int64Object(static_cast<int64_t>(max_post_micros)),
        Int64Object(static_cast<int64_t>(post_failures)),
        Int64Object(static_cast<int64_t>(ack_failures)),
    };
    Dart_CObject* values[sizeof(fields) / sizeof(fields[0])] = {};
    for (size_t index = 0; index < sizeof(values) / sizeof(values[0]);
         ++index) {
      values[index] = &fields[index];
    }
    Dart_CObject message = {};
    message.type = Dart_CObject_kArray;
    message.value.as_array.length =
        static_cast<intptr_t>(sizeof(values) / sizeof(values[0]));
    message.value.as_array.values = values;
    return Dart_PostCObject(port, &message);
  }

  void Run() {
    ScenarioResult result = RunScenario(this);
    if (!WaitForAllAcknowledgements() && result.status == 0) {
      result.status = 90;
      result.failed_step = 90;
    }

    uint64_t total_posted_bytes = 0;
    uint64_t posted_batches = 0;
    uint64_t min_large_batch_bytes = 0;
    uint64_t max_in_flight_bytes = 0;
    uint64_t backpressure_waits = 0;
    uint64_t post_failures = 0;
    uint64_t ack_failures = 0;
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      total_posted_bytes = total_posted_bytes_;
      posted_batches = posted_batches_;
      min_large_batch_bytes = min_large_batch_bytes_;
      max_in_flight_bytes = max_in_flight_bytes_;
      backpressure_waits = backpressure_waits_;
      post_failures = post_failures_;
      ack_failures = ack_failures_;
    }

    if (result.status == 0 &&
        (total_posted_bytes < kBurstBytes || posted_batches == 0 ||
         min_large_batch_bytes < kDeliveryBatchBytes ||
         max_in_flight_bytes > kHighWaterBytes ||
         result.x_bytes < kBurstBytes || !result.tty_ok ||
         !result.resize_ok || !result.signal_ok ||
         result.exit_code != kExpectedExitCode || post_failures != 0 ||
         ack_failures != 0)) {
      result.status = 91;
      result.failed_step = 91;
    }

    const bool summary_posted = PostSummary(result);
    std::fprintf(
        result.status == 0 && summary_posted ? stdout : stderr,
        "PHASE0_PTY_NATIVE_%s status=%d step=%d errno=%d exec_errno=%d "
        "pid=%lld bytes=%llu batches=%llu min_large_batch=%llu "
        "max_in_flight=%llu waits=%llu x_bytes=%llu tty=%d resize=%d "
        "sigint=%d exit=%lld reads=%llu elapsed_us=%llu post_failures=%llu "
        "ack_failures=%llu summary_posted=%d\n",
        result.status == 0 && summary_posted ? "PASS" : "FAIL",
        result.status, result.failed_step, result.system_error,
        result.exec_error, static_cast<long long>(result.child_pid),
        static_cast<unsigned long long>(total_posted_bytes),
        static_cast<unsigned long long>(posted_batches),
        static_cast<unsigned long long>(min_large_batch_bytes),
        static_cast<unsigned long long>(max_in_flight_bytes),
        static_cast<unsigned long long>(backpressure_waits),
        static_cast<unsigned long long>(result.x_bytes), result.tty_ok ? 1 : 0,
        result.resize_ok ? 1 : 0, result.signal_ok ? 1 : 0,
        static_cast<long long>(result.exit_code),
        static_cast<unsigned long long>(result.read_calls),
        static_cast<unsigned long long>(result.elapsed_micros),
        static_cast<unsigned long long>(post_failures),
        static_cast<unsigned long long>(ack_failures), summary_posted ? 1 : 0);

    const std::lock_guard<std::mutex> lock(mutex_);
    finished_ = true;
  }

  std::mutex mutex_;
  std::condition_variable condition_;
  std::thread thread_;
  bool active_ = false;
  bool finished_ = false;
  Dart_Port port_ = ILLEGAL_PORT;
  uint64_t next_sequence_ = 0;
  uint64_t last_acked_sequence_ = std::numeric_limits<uint64_t>::max();
  size_t in_flight_bytes_ = 0;
  size_t max_in_flight_bytes_ = 0;
  uint64_t total_posted_bytes_ = 0;
  uint64_t posted_batches_ = 0;
  size_t min_large_batch_bytes_ = 0;
  size_t max_batch_bytes_ = 0;
  uint64_t backpressure_waits_ = 0;
  uint64_t max_post_micros_ = 0;
  uint64_t post_failures_ = 0;
  uint64_t ack_failures_ = 0;
  std::deque<OutstandingBatch> outstanding_;
};

class OutputCollector final {
 public:
  explicit OutputCollector(BridgeState* bridge) : bridge_(bridge) {
    pending_.reserve(kDeliveryBatchBytes * 2);
    recent_.reserve(kDeliveryBatchBytes);
  }

  bool Accept(const uint8_t* bytes, size_t length) {
    if (failed_ || bytes == nullptr) {
      return false;
    }
    for (size_t index = 0; index < length; ++index) {
      if (bytes[index] == static_cast<uint8_t>('x')) {
        ++x_bytes_;
      }
    }

    recent_.append(reinterpret_cast<const char*>(bytes), length);
    if (recent_.size() > kDeliveryBatchBytes) {
      recent_.erase(0, recent_.size() - kDeliveryBatchBytes);
    }

    pending_.insert(pending_.end(), bytes, bytes + length);
    while (pending_.size() - pending_offset_ >= kDeliveryBatchBytes) {
      if (!bridge_->PostBatch(pending_.data() + pending_offset_,
                              kDeliveryBatchBytes)) {
        failed_ = true;
        return false;
      }
      pending_offset_ += kDeliveryBatchBytes;
    }
    if (pending_offset_ != 0 && pending_offset_ * 2 >= pending_.size()) {
      pending_.erase(pending_.begin(),
                     pending_.begin() + static_cast<ptrdiff_t>(pending_offset_));
      pending_offset_ = 0;
    }
    return true;
  }

  bool Flush() {
    if (failed_) {
      return false;
    }
    const size_t remaining = pending_.size() - pending_offset_;
    if (remaining != 0 &&
        !bridge_->PostBatch(pending_.data() + pending_offset_, remaining)) {
      failed_ = true;
      return false;
    }
    pending_.clear();
    pending_offset_ = 0;
    return true;
  }

  bool Contains(const char* marker) const {
    return recent_.find(marker) != std::string::npos;
  }

  uint64_t x_bytes() const { return x_bytes_; }
  bool failed() const { return failed_; }

 private:
  BridgeState* bridge_;
  std::vector<uint8_t> pending_;
  size_t pending_offset_ = 0;
  std::string recent_;
  uint64_t x_bytes_ = 0;
  bool failed_ = false;
};

class PtyScenario final {
 public:
  explicit PtyScenario(BridgeState* bridge) : collector_(bridge) {}
  ~PtyScenario() { Cleanup(); }

  ScenarioResult Run() {
    const auto started = std::chrono::steady_clock::now();
    Spawn();
    if (result_.status == 0) {
      ConfigureEvents();
    }
    if (result_.status == 0) {
      CheckExec();
    }
    if (result_.status == 0) {
      RunInteractiveChecks();
    }
    if (result_.status == 0) {
      RunBurst();
    }
    if (result_.status == 0) {
      ExitShell();
    }

    if (master_fd_ >= 0) {
      (void)PumpFor(std::chrono::milliseconds(100));
    }
    if (!collector_.Flush() && result_.status == 0) {
      Fail(80, EIO);
    }
    result_.x_bytes = collector_.x_bytes();
    result_.elapsed_micros = static_cast<uint64_t>(
        std::chrono::duration_cast<std::chrono::microseconds>(
            std::chrono::steady_clock::now() - started)
            .count());
    return result_;
  }

 private:
  void Fail(int32_t step, int32_t system_error) {
    if (result_.status == 0) {
      result_.status = step;
      result_.failed_step = step;
      result_.system_error = system_error;
    }
  }

  void Spawn() {
    char executable[] = "/bin/zsh";
    char arg0[] = "zsh";
    char arg1[] = "-f";
    char arg2[] = "-i";
    char* argv[] = {arg0, arg1, arg2, nullptr};

    std::vector<char*> environment;
    for (char** entry = environ; entry != nullptr && *entry != nullptr;
         ++entry) {
      if (std::strncmp(*entry, "TERM=", 5) != 0) {
        environment.push_back(*entry);
      }
    }
    char term[] = "TERM=xterm-256color";
    environment.push_back(term);
    environment.push_back(nullptr);

    DtPtySpawnConfig config = {};
    config.executable = executable;
    config.argv = argv;
    config.envp = environment.data();
    config.initial_size.ws_row = 24;
    config.initial_size.ws_col = 80;
    config.initial_size.ws_xpixel = 0;
    config.initial_size.ws_ypixel = 0;

    DtPtySpawnResult spawn_result = {};
    int32_t error_number = 0;
    const int32_t status =
        dt_pty_spawn(&config, &spawn_result, &error_number);
    if (status != 0) {
      Fail(10 + status, error_number);
      return;
    }
    child_pid_ = spawn_result.child_pid;
    master_fd_ = spawn_result.master_fd;
    exec_error_fd_ = spawn_result.exec_error_fd;
    result_.child_pid = child_pid_;

    const int current_flags = fcntl(master_fd_, F_GETFL);
    if (current_flags < 0 ||
        fcntl(master_fd_, F_SETFL, current_flags | O_NONBLOCK) != 0) {
      Fail(15, errno);
    }
  }

  void ConfigureEvents() {
    kqueue_fd_ = kqueue();
    if (kqueue_fd_ < 0) {
      Fail(20, errno);
      return;
    }
    struct kevent changes[2] = {};
    EV_SET(&changes[0], static_cast<uintptr_t>(master_fd_), EVFILT_READ,
           EV_ADD | EV_CLEAR, 0, 0, nullptr);
    EV_SET(&changes[1], static_cast<uintptr_t>(child_pid_), EVFILT_PROC,
           EV_ADD | EV_CLEAR, NOTE_EXIT, 0, nullptr);
    if (kevent(kqueue_fd_, changes, 2, nullptr, 0, nullptr) != 0) {
      Fail(21, errno);
    }
  }

  void CheckExec() {
    struct pollfd descriptor = {};
    descriptor.fd = exec_error_fd_;
    descriptor.events = POLLIN | POLLHUP;
    const int poll_status = poll(&descriptor, 1, 2000);
    if (poll_status <= 0) {
      Fail(25, poll_status == 0 ? ETIMEDOUT : errno);
      return;
    }
    int child_error = 0;
    const ssize_t bytes = read(exec_error_fd_, &child_error,
                               static_cast<size_t>(sizeof(child_error)));
    if (bytes == static_cast<ssize_t>(sizeof(child_error))) {
      result_.exec_error = child_error;
      Fail(26, child_error);
      return;
    }
    if (bytes < 0) {
      Fail(27, errno);
      return;
    }
    (void)close(exec_error_fd_);
    exec_error_fd_ = -1;
  }

  void RunInteractiveChecks() {
    (void)PumpFor(std::chrono::milliseconds(150));
    if (!WriteText("stty -echo; unsetopt zle; PS1=''; PS2=''\n")) {
      Fail(30, errno);
      return;
    }
    (void)PumpFor(std::chrono::milliseconds(150));
    if (!WriteText("print -r -- __DT_READY__\n") ||
        !WaitForMarker("__DT_READY__", std::chrono::seconds(2))) {
      Fail(31, ETIMEDOUT);
      return;
    }

    if (!WriteText(
            "if [[ -t 0 && -t 1 && -o interactive ]]; then print -r -- "
            "__DT_TTY_OK__; else print -r -- __DT_TTY_FAIL__; fi\n") ||
        !WaitForMarker("__DT_TTY_OK__", std::chrono::seconds(2)) ||
        collector_.Contains("__DT_TTY_FAIL__")) {
      Fail(32, EPROTO);
      return;
    }
    result_.tty_ok = true;

    struct winsize resized = {};
    resized.ws_row = 43;
    resized.ws_col = 132;
    if (ioctl(master_fd_, TIOCSWINSZ, &resized) != 0) {
      Fail(33, errno);
      return;
    }
    if (!WriteText("print -r -- \"__DT_SIZE__$(stty size)\"\n") ||
        !WaitForMarker("__DT_SIZE__43 132", std::chrono::seconds(2))) {
      Fail(34, EPROTO);
      return;
    }
    result_.resize_ok = true;

    if (!WriteText("sleep 30\n")) {
      Fail(35, errno);
      return;
    }
    (void)PumpFor(std::chrono::milliseconds(150));
    const uint8_t interrupt = 0x03;
    if (!WriteBytes(&interrupt, 1)) {
      Fail(36, errno);
      return;
    }
    (void)PumpFor(std::chrono::milliseconds(150));
    if (!WriteText("print -r -- \"__DT_SIGINT__${?}\"\n") ||
        !WaitForMarker("__DT_SIGINT__130", std::chrono::seconds(2))) {
      Fail(37, EPROTO);
      return;
    }
    result_.signal_ok = true;
  }

  void RunBurst() {
    if (!WriteText(
            "print -r -- __DT_BURST_BEGIN__; /usr/bin/head -c 10485760 "
            "/dev/zero | /usr/bin/tr '\\000' x; print -r -- "
            "__DT_BURST_END__\n") ||
        !WaitForMarker("__DT_BURST_END__", std::chrono::seconds(8))) {
      Fail(40, ETIMEDOUT);
    }
  }

  void ExitShell() {
    if (!WriteText("exit 37\n")) {
      Fail(50, errno);
      return;
    }
    const auto deadline =
        std::chrono::steady_clock::now() + std::chrono::seconds(3);
    while (!child_exited_ && std::chrono::steady_clock::now() < deadline) {
      if (!PumpOnce(std::chrono::milliseconds(100))) {
        break;
      }
    }
    if (!child_exited_) {
      Fail(51, ETIMEDOUT);
      return;
    }
    if (WIFEXITED(child_status_)) {
      result_.exit_code = WEXITSTATUS(child_status_);
    } else if (WIFSIGNALED(child_status_)) {
      result_.exit_code = 128 + WTERMSIG(child_status_);
    }
    if (result_.exit_code != kExpectedExitCode) {
      Fail(52, ECHILD);
    }
  }

  bool WriteText(const char* text) {
    return WriteBytes(reinterpret_cast<const uint8_t*>(text),
                      std::strlen(text));
  }

  bool WriteBytes(const uint8_t* bytes, size_t length) {
    size_t offset = 0;
    const auto deadline =
        std::chrono::steady_clock::now() + std::chrono::seconds(2);
    while (offset < length && std::chrono::steady_clock::now() < deadline) {
      const ssize_t written = write(master_fd_, bytes + offset, length - offset);
      if (written > 0) {
        offset += static_cast<size_t>(written);
        continue;
      }
      if (written < 0 && errno == EINTR) {
        continue;
      }
      if (written < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
        struct pollfd descriptor = {};
        descriptor.fd = master_fd_;
        descriptor.events = POLLOUT;
        if (poll(&descriptor, 1, 100) < 0 && errno != EINTR) {
          return false;
        }
        continue;
      }
      return false;
    }
    return offset == length;
  }

  bool WaitForMarker(const char* marker,
                     std::chrono::steady_clock::duration timeout) {
    const auto deadline = std::chrono::steady_clock::now() + timeout;
    while (!collector_.Contains(marker) &&
           std::chrono::steady_clock::now() < deadline && !child_exited_) {
      if (!PumpOnce(std::chrono::milliseconds(100))) {
        return false;
      }
    }
    return collector_.Contains(marker);
  }

  bool PumpFor(std::chrono::steady_clock::duration duration) {
    const auto deadline = std::chrono::steady_clock::now() + duration;
    while (std::chrono::steady_clock::now() < deadline && !child_exited_) {
      const auto remaining = deadline - std::chrono::steady_clock::now();
      const auto maximum_wait =
          std::chrono::duration_cast<std::chrono::steady_clock::duration>(
              std::chrono::milliseconds(100));
      if (!PumpOnce(remaining < maximum_wait ? remaining : maximum_wait)) {
        return false;
      }
    }
    return true;
  }

  bool PumpOnce(std::chrono::steady_clock::duration timeout) {
    const int64_t timeout_nanos =
        std::chrono::duration_cast<std::chrono::nanoseconds>(timeout).count();
    struct timespec wait = {};
    wait.tv_sec = static_cast<time_t>(timeout_nanos / 1000000000LL);
    wait.tv_nsec = static_cast<long>(timeout_nanos % 1000000000LL);
    struct kevent events[4] = {};
    const int count = kevent(kqueue_fd_, nullptr, 0, events, 4, &wait);
    if (count < 0) {
      if (errno == EINTR) {
        ReapChild();
        return true;
      }
      Fail(60, errno);
      return false;
    }
    for (int index = 0; index < count; ++index) {
      if (events[index].filter == EVFILT_READ) {
        if (!ReadAvailable()) {
          return false;
        }
      }
    }
    ReapChild();
    return !collector_.failed();
  }

  bool ReadAvailable() {
    uint8_t buffer[16 * 1024];
    for (;;) {
      const ssize_t bytes = read(master_fd_, buffer, sizeof(buffer));
      if (bytes > 0) {
        ++result_.read_calls;
        if (!collector_.Accept(buffer, static_cast<size_t>(bytes))) {
          Fail(61, EIO);
          return false;
        }
        continue;
      }
      if (bytes == 0) {
        master_eof_ = true;
        return true;
      }
      if (errno == EINTR) {
        continue;
      }
      if (errno == EAGAIN || errno == EWOULDBLOCK) {
        return true;
      }
      if (errno == EIO) {
        master_eof_ = true;
        return true;
      }
      Fail(62, errno);
      return false;
    }
  }

  void ReapChild() {
    if (child_pid_ <= 0 || child_exited_) {
      return;
    }
    int status = 0;
    const pid_t waited = waitpid(child_pid_, &status, WNOHANG);
    if (waited == child_pid_) {
      child_exited_ = true;
      child_status_ = status;
    } else if (waited < 0 && errno != EINTR) {
      Fail(63, errno);
    }
  }

  void Cleanup() {
    if (child_pid_ > 0 && !child_exited_) {
      (void)kill(-child_pid_, SIGHUP);
      for (int attempt = 0; attempt < 20 && !child_exited_; ++attempt) {
        ReapChild();
        if (!child_exited_) {
          (void)usleep(10000);
        }
      }
      if (!child_exited_) {
        (void)kill(-child_pid_, SIGKILL);
        (void)kill(child_pid_, SIGKILL);
        while (waitpid(child_pid_, nullptr, 0) < 0 && errno == EINTR) {
        }
        child_exited_ = true;
      }
    }
    if (exec_error_fd_ >= 0) {
      (void)close(exec_error_fd_);
      exec_error_fd_ = -1;
    }
    if (master_fd_ >= 0) {
      (void)close(master_fd_);
      master_fd_ = -1;
    }
    if (kqueue_fd_ >= 0) {
      (void)close(kqueue_fd_);
      kqueue_fd_ = -1;
    }
  }

  OutputCollector collector_;
  ScenarioResult result_;
  pid_t child_pid_ = -1;
  int master_fd_ = -1;
  int exec_error_fd_ = -1;
  int kqueue_fd_ = -1;
  int child_status_ = 0;
  bool child_exited_ = false;
  bool master_eof_ = false;
};

ScenarioResult RunScenario(BridgeState* bridge) {
  PtyScenario scenario(bridge);
  return scenario.Run();
}

BridgeState g_bridge;

}  // namespace

extern "C" __attribute__((visibility("default"))) int32_t
dt_phase0_pty_start(int64_t dart_port) {
  return g_bridge.Start(static_cast<Dart_Port>(dart_port));
}

extern "C" __attribute__((visibility("default"))) int32_t
dt_phase0_pty_ack(uint64_t sequence, uint64_t bytes) {
  return g_bridge.Acknowledge(sequence, bytes);
}

extern "C" __attribute__((visibility("default"))) int32_t
dt_phase0_pty_join(void) {
  return g_bridge.Join();
}
