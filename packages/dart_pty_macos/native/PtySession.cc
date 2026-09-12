#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <sys/event.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <deque>
#include <limits>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "PtySpawnInternal.h"
#include "dart_pty_macos.h"

namespace {

constexpr size_t kMaximumStringBytes = 1024 * 1024;
constexpr size_t kMaximumVectorEntries = 16 * 1024;
constexpr size_t kMaximumQueueBytes = 64 * 1024 * 1024;
constexpr size_t kDefaultReadBatchBytes = 64 * 1024;
constexpr size_t kMaximumReadBatchesPerTurn = 8;
constexpr size_t kMaximumWriteBatchesPerTurn = 8;
constexpr size_t kMaximumWriteBytesPerTurn = 512 * 1024;
constexpr uint32_t kMaximumCloseGraceMillis = 60 * 1000;
constexpr uintptr_t kControlEventIdentifier = 1;

thread_local DptyError g_last_error = {};
thread_local std::string g_last_error_message;

int32_t SetError(DptyStatus status, int32_t system_error, const char* message) {
  g_last_error_message = message == nullptr ? "" : message;
  g_last_error.status = status;
  g_last_error.system_error = system_error;
  g_last_error.message =
      g_last_error_message.empty() ? nullptr : g_last_error_message.c_str();
  g_last_error.message_length = g_last_error_message.size();
  return status;
}

void ClearError() { (void)SetError(DPTY_STATUS_OK, 0, nullptr); }

bool CopyString(const char* source, const char* field, std::string* target,
                bool allow_empty = false) {
  if (source == nullptr || target == nullptr) {
    (void)SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL, field);
    return false;
  }
  const size_t length = strnlen(source, kMaximumStringBytes + 1);
  if ((!allow_empty && length == 0) || length > kMaximumStringBytes) {
    (void)SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL, field);
    return false;
  }
  target->assign(source, length);
  return true;
}

struct OwnedConfig {
  std::string executable;
  std::vector<std::string> arguments;
  std::vector<std::string> environment;
  std::optional<std::string> working_directory;
  uint16_t rows = 0;
  uint16_t columns = 0;
  size_t read_high_water = 0;
  size_t read_low_water = 0;
  size_t read_batch = kDefaultReadBatchBytes;
  uint32_t read_batches_per_event_loop_turn = 0;
  size_t write_capacity = 0;
  dpty_event_callback_v1 callback = nullptr;
  void* callback_context = nullptr;
  bool diagnostics_enabled = false;
};

bool CopyConfig(const DptySessionConfigV1* source, OwnedConfig* target) {
  constexpr size_t kMinimumConfigSize =
      offsetof(DptySessionConfigV1, read_batch_bytes);
  constexpr size_t kReadBatchConfigSize =
      offsetof(DptySessionConfigV1, read_batches_per_event_loop_turn);
  const bool has_read_batch =
      source != nullptr && source->struct_size >= kReadBatchConfigSize;
  const bool has_read_turn_limit =
      source != nullptr && source->struct_size >= sizeof(DptySessionConfigV1);
  if (source == nullptr || target == nullptr ||
      source->struct_size < kMinimumConfigSize ||
      source->abi_version != DPTY_ABI_VERSION || source->callback == nullptr ||
      source->arguments == nullptr || source->argument_count == 0 ||
      source->argument_count > kMaximumVectorEntries ||
      source->environment_count > kMaximumVectorEntries ||
      (source->environment_count != 0 && source->environment == nullptr) ||
      source->initial_rows == 0 || source->initial_columns == 0 ||
      source->read_high_water_bytes == 0 ||
      source->read_low_water_bytes >= source->read_high_water_bytes ||
      source->read_high_water_bytes > kMaximumQueueBytes ||
      source->write_capacity_bytes == 0 ||
      source->write_capacity_bytes > kMaximumQueueBytes ||
      source->diagnostics_enabled > 1 ||
      (has_read_batch && source->read_batch_bytes > kDefaultReadBatchBytes) ||
      (has_read_turn_limit &&
       source->read_batches_per_event_loop_turn > kMaximumReadBatchesPerTurn)) {
    (void)SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                   "PTY session configuration is invalid");
    return false;
  }
  if (!CopyString(source->executable, "PTY executable is invalid",
                  &target->executable) ||
      target->executable.front() != '/') {
    (void)SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                   "PTY executable must be an absolute path");
    return false;
  }
  target->arguments.reserve(source->argument_count);
  for (size_t index = 0; index < source->argument_count; ++index) {
    std::string value;
    if (!CopyString(source->arguments[index], "PTY argument is invalid", &value,
                    true)) {
      return false;
    }
    target->arguments.push_back(std::move(value));
  }
  target->environment.reserve(source->environment_count);
  for (size_t index = 0; index < source->environment_count; ++index) {
    std::string value;
    if (!CopyString(source->environment[index],
                    "PTY environment entry is invalid", &value) ||
        value.front() == '=' || value.find('=') == std::string::npos) {
      (void)SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                     "PTY environment entry must be KEY=value");
      return false;
    }
    target->environment.push_back(std::move(value));
  }
  if (source->working_directory != nullptr) {
    std::string directory;
    if (!CopyString(source->working_directory,
                    "PTY working directory is invalid", &directory) ||
        directory.front() != '/') {
      (void)SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                     "PTY working directory must be an absolute path");
      return false;
    }
    target->working_directory = std::move(directory);
  }
  target->rows = source->initial_rows;
  target->columns = source->initial_columns;
  target->read_high_water = source->read_high_water_bytes;
  target->read_low_water = source->read_low_water_bytes;
  target->read_batch = has_read_batch && source->read_batch_bytes != 0
                           ? source->read_batch_bytes
                           : kDefaultReadBatchBytes;
  target->read_batches_per_event_loop_turn =
      has_read_turn_limit ? source->read_batches_per_event_loop_turn : 0;
  target->write_capacity = source->write_capacity_bytes;
  target->callback = source->callback;
  target->callback_context = source->callback_context;
  target->diagnostics_enabled = source->diagnostics_enabled != 0;
  return true;
}

struct OutputBatch {
  uint64_t sequence = 0;
  std::vector<uint8_t> bytes;
};

struct PendingResize {
  uint16_t rows = 0;
  uint16_t columns = 0;
};

struct PendingWrite {
  uint64_t request_id = 0;
  bool diagnostic = false;
  bool dequeue_observed = false;
  std::vector<uint8_t> bytes;
};

class Session final : public std::enable_shared_from_this<Session> {
 public:
  explicit Session(OwnedConfig config) : config_(std::move(config)) {}

  ~Session() {
    if (thread_.joinable()) {
      thread_.join();
    }
  }

  void SetHandle(DptySessionHandle handle) { handle_ = handle; }

  int32_t Start() {
    const std::lock_guard<std::mutex> lock(mutex_);
    if (state_ != State::kCreated) {
      return SetError(DPTY_STATUS_WRONG_STATE, 0,
                      "PTY session has already been started");
    }
    state_ = State::kRunning;
    try {
      std::shared_ptr<Session> self = shared_from_this();
      thread_ = std::thread([self] { self->Run(); });
    } catch (...) {
      state_ = State::kFinished;
      return SetError(DPTY_STATUS_SYSTEM_ERROR, EAGAIN,
                      "could not create PTY reactor thread");
    }
    return DPTY_STATUS_OK;
  }

  int32_t Write(const uint8_t* bytes, size_t length) {
    return EnqueueWrite(bytes, length, nullptr);
  }

  int32_t WriteTracked(const uint8_t* bytes, size_t length,
                       uint64_t* out_request_id) {
    if (out_request_id == nullptr) {
      return SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                      "tracked PTY write requires an output request ID");
    }
    *out_request_id = 0;
    return EnqueueWrite(bytes, length, out_request_id);
  }

  int32_t EnqueueWrite(const uint8_t* bytes, size_t length,
                       uint64_t* out_request_id) {
    if (bytes == nullptr || length == 0) {
      return SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                      "PTY write requires non-empty bytes");
    }
    uint64_t request_id = 0;
    size_t queued_bytes = 0;
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      if (state_ != State::kRunning || closing_ || child_completed_) {
        return SetError(DPTY_STATUS_WRONG_STATE, 0,
                        "PTY session does not accept writes");
      }
      if (length > config_.write_capacity ||
          write_queued_bytes_ > config_.write_capacity - length) {
        ++write_backpressure_rejections_;
        return SetError(DPTY_STATUS_BACKPRESSURED, 0,
                        "PTY write queue is full");
      }
      if (out_request_id != nullptr) {
        request_id = next_write_request_id_++;
        if (next_write_request_id_ == 0) {
          next_write_request_id_ = 1;
        }
      }
      PendingWrite write;
      write.request_id = request_id;
      write.diagnostic = out_request_id != nullptr;
      write.bytes.assign(bytes, bytes + length);
      writes_.push_back(std::move(write));
      write_queued_bytes_ += length;
      queued_bytes = write_queued_bytes_;
      max_write_queued_bytes_ =
          std::max(max_write_queued_bytes_, write_queued_bytes_);
      if (out_request_id != nullptr) {
        *out_request_id = request_id;
        emit_waitpid_pending_ = true;
      }
    }
    if (out_request_id != nullptr) {
      EmitDiagnostic(DPTY_EVENT_WRITE_ENQUEUED, request_id, length,
                     static_cast<int64_t>(queued_bytes), 0, 0);
    }
    Wake();
    return DPTY_STATUS_OK;
  }

  int32_t Acknowledge(uint64_t sequence, size_t length) {
    bool should_wake = false;
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      if (outstanding_.empty() || outstanding_.front().sequence != sequence ||
          outstanding_.front().bytes.size() != length) {
        return SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                        "PTY output acknowledgement is out of order");
      }
      read_in_flight_bytes_ -= outstanding_.front().bytes.size();
      outstanding_.pop_front();
      should_wake =
          read_paused_ && read_in_flight_bytes_ <= config_.read_low_water;
    }
    if (should_wake) {
      Wake();
    }
    return DPTY_STATUS_OK;
  }

  int32_t Resize(uint16_t rows, uint16_t columns) {
    if (rows == 0 || columns == 0) {
      return SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                      "PTY size must be nonzero");
    }
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      if (state_ != State::kRunning || closing_ || child_completed_) {
        return SetError(DPTY_STATUS_WRONG_STATE, 0,
                        "PTY session cannot be resized");
      }
      pending_resize_ = PendingResize{rows, columns};
    }
    Wake();
    return DPTY_STATUS_OK;
  }

  int32_t SendSignal(uint32_t signal) {
    const int native_signal = NativeSignal(signal);
    if (native_signal == 0) {
      return SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                      "PTY signal is invalid");
    }
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      if (state_ != State::kRunning || closing_ || child_completed_) {
        return SetError(DPTY_STATUS_WRONG_STATE, 0,
                        "PTY session cannot receive a signal");
      }
      pending_signals_.push_back(native_signal);
    }
    Wake();
    return DPTY_STATUS_OK;
  }

  int32_t Close(uint32_t grace_period_millis) {
    if (grace_period_millis > kMaximumCloseGraceMillis) {
      return SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                      "PTY close grace period exceeds 60 seconds");
    }
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      if (state_ == State::kFinished) {
        return DPTY_STATUS_OK;
      }
      if (state_ != State::kRunning) {
        return SetError(DPTY_STATUS_WRONG_STATE, 0,
                        "PTY session has not started");
      }
      if (!closing_) {
        closing_ = true;
        close_grace_millis_ = grace_period_millis;
      }
    }
    Wake();
    return DPTY_STATUS_OK;
  }

  int32_t ForceClose() {
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      if (state_ == State::kFinished) {
        return DPTY_STATUS_OK;
      }
      if (state_ != State::kRunning) {
        return SetError(DPTY_STATUS_WRONG_STATE, 0,
                        "PTY session has not started");
      }
      closing_ = true;
      force_close_requested_ = true;
    }
    Wake();
    return DPTY_STATUS_OK;
  }

  int32_t GetStats(DptySessionStatsV1* output) const {
    if (output == nullptr || output->struct_size < sizeof(DptySessionStatsV1) ||
        output->abi_version != DPTY_ABI_VERSION) {
      return SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                      "PTY stats buffer is incompatible");
    }
    const std::lock_guard<std::mutex> lock(mutex_);
    output->bytes_read = bytes_read_;
    output->bytes_written = bytes_written_;
    output->read_batches = read_batches_;
    output->write_backpressure_rejections = write_backpressure_rejections_;
    output->max_read_in_flight_bytes = max_read_in_flight_bytes_;
    output->max_write_queued_bytes = max_write_queued_bytes_;
    output->read_pause_count = read_pause_count_;
    output->child_pid = child_pid_;
    output->has_exited = state_ == State::kFinished ? 1 : 0;
    return DPTY_STATUS_OK;
  }

  int32_t GetProcessSnapshot(DptyProcessSnapshotV1* output) const {
    if (output == nullptr ||
        output->struct_size < sizeof(DptyProcessSnapshotV1) ||
        output->abi_version != DPTY_ABI_VERSION) {
      return SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                      "PTY process snapshot buffer is incompatible");
    }
    output->child_pid = 0;
    output->child_process_group = 0;
    output->foreground_process_group = 0;
    output->child_process_group_error = 0;
    output->foreground_process_group_error = 0;
    output->has_exited = 0;
    output->terminal_echo_enabled = 0;
    output->terminal_attributes_error = 0;

    const std::lock_guard<std::mutex> lock(mutex_);
    output->has_exited = state_ == State::kFinished ? 1 : 0;
    const pid_t child = child_pid_;
    const int master = master_fd_;
    if (child <= 0 || master < 0 || state_ != State::kRunning) {
      output->child_pid = child > 0 ? child : 0;
      output->child_process_group_error = ENXIO;
      output->foreground_process_group_error = ENXIO;
      output->terminal_attributes_error = ENXIO;
      return DPTY_STATUS_OK;
    }

    output->child_pid = child;
    errno = 0;
    const pid_t child_group = getpgid(child);
    if (child_group > 0) {
      output->child_process_group = child_group;
    } else {
      output->child_process_group_error = errno == 0 ? ESRCH : errno;
    }
    errno = 0;
    const pid_t foreground = tcgetpgrp(master);
    if (foreground > 0) {
      output->foreground_process_group = foreground;
    } else {
      output->foreground_process_group_error = errno == 0 ? ENOTTY : errno;
    }
    struct termios terminal = {};
    errno = 0;
    if (tcgetattr(master, &terminal) == 0) {
      output->terminal_echo_enabled = (terminal.c_lflag & ECHO) != 0 ? 1 : 0;
    } else {
      output->terminal_attributes_error = errno == 0 ? ENOTTY : errno;
    }
    return DPTY_STATUS_OK;
  }

  bool CanDestroy() const {
    const std::lock_guard<std::mutex> lock(mutex_);
    return state_ == State::kFinished && outstanding_.empty();
  }

  void Join() {
    if (thread_.joinable()) {
      thread_.join();
    }
  }

 private:
  enum class State { kCreated, kRunning, kFinished };

  static int NativeSignal(uint32_t signal) {
    switch (signal) {
      case DPTY_SIGNAL_INTERRUPT:
        return SIGINT;
      case DPTY_SIGNAL_SUSPEND:
        return SIGTSTP;
      case DPTY_SIGNAL_QUIT:
        return SIGQUIT;
      case DPTY_SIGNAL_HANGUP:
        return SIGHUP;
      case DPTY_SIGNAL_TERMINATE:
        return SIGTERM;
      case DPTY_SIGNAL_KILL:
        return SIGKILL;
      default:
        return 0;
    }
  }

  void Wake() const {
    const int descriptor = kqueue_fd_.load(std::memory_order_acquire);
    if (descriptor < 0) {
      return;
    }
    struct kevent trigger = {};
    EV_SET(&trigger, kControlEventIdentifier, EVFILT_USER, 0, NOTE_TRIGGER, 0,
           nullptr);
    (void)kevent(descriptor, &trigger, 1, nullptr, 0, nullptr);
  }

  void Emit(uint32_t type, uint64_t sequence, const uint8_t* bytes,
            size_t length, int64_t value1, int64_t value2,
            int32_t system_error) const {
    config_.callback(handle_, type, sequence, bytes, length, value1, value2,
                     system_error, config_.callback_context);
  }

  void EmitDiagnostic(uint32_t type, uint64_t sequence, size_t length,
                      int64_t value1, int64_t value2,
                      int32_t system_error) const {
    if (!config_.diagnostics_enabled) {
      return;
    }
    Emit(type, sequence, nullptr, length, value1, value2, system_error);
  }

  void EmitStateSnapshot(uint64_t related_write_request_id) const {
    int32_t foreground_error = 0;
    errno = 0;
    const pid_t foreground =
        master_fd_ >= 0 ? tcgetpgrp(master_fd_) : static_cast<pid_t>(-1);
    if (foreground < 0) {
      foreground_error = errno;
    }

    struct termios terminal = {};
    errno = 0;
    const int terminal_result =
        master_fd_ >= 0 ? tcgetattr(master_fd_, &terminal) : -1;
    const int32_t terminal_error = terminal_result == 0 ? 0 : errno;

    size_t queued_bytes = 0;
    uint64_t state_flags = 0;
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      queued_bytes = write_queued_bytes_;
      if (closing_) {
        state_flags |= DPTY_SESSION_STATE_CLOSING;
      }
      if (close_started_) {
        state_flags |= DPTY_SESSION_STATE_CLOSE_STARTED;
      }
      if (child_reaped_by_session_) {
        state_flags |= DPTY_SESSION_STATE_CHILD_REAPED;
      }
      if (master_eof_) {
        state_flags |= DPTY_SESSION_STATE_MASTER_EOF;
      }
      if (read_paused_) {
        state_flags |= DPTY_SESSION_STATE_READ_PAUSED;
      }
      if (read_enabled_) {
        state_flags |= DPTY_SESSION_STATE_READ_ENABLED;
      }
      if (write_enabled_) {
        state_flags |= DPTY_SESSION_STATE_WRITE_ENABLED;
      }
      if (child_completed_) {
        state_flags |= DPTY_SESSION_STATE_CHILD_EXIT_OBSERVED;
      }
      if (child_externally_reaped_) {
        state_flags |= DPTY_SESSION_STATE_CHILD_EXTERNALLY_REAPED;
      }
    }
    EmitDiagnostic(DPTY_EVENT_STATE_SNAPSHOT, related_write_request_id,
                   queued_bytes, static_cast<int64_t>(foreground),
                   static_cast<int64_t>(state_flags), foreground_error);
    EmitDiagnostic(
        DPTY_EVENT_TERMIOS_SNAPSHOT, related_write_request_id,
        terminal_result == 0 ? terminal.c_cc[VEOF] : 0,
        terminal_result == 0 ? static_cast<int64_t>(terminal.c_lflag) : 0,
        terminal_result == 0 ? 1 : 0, terminal_error);
  }

  void ObserveProcessExitReady(pid_t child, int64_t status_hint,
                               bool status_valid) {
    if (status_valid) {
      process_exit_status_ = static_cast<int>(status_hint);
      process_exit_status_valid_ = true;
    }
    if (process_exit_ready_observed_) {
      return;
    }
    process_exit_ready_observed_ = true;
    EmitDiagnostic(DPTY_EVENT_PROCESS_EXIT_READY, 0, status_valid ? 1 : 0,
                   static_cast<int64_t>(child), status_hint, 0);
  }

  void FinishError(DptyStatus status, int32_t system_error) {
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      state_ = State::kFinished;
      child_pid_ = -1;
    }
    Emit(DPTY_EVENT_ERROR, 0, nullptr, 0, status, 0, system_error);
  }

  void Run() {
    std::vector<char*> argv;
    argv.reserve(config_.arguments.size() + 1);
    for (std::string& value : config_.arguments) {
      argv.push_back(value.data());
    }
    argv.push_back(nullptr);
    std::vector<char*> environment;
    environment.reserve(config_.environment.size() + 1);
    for (std::string& value : config_.environment) {
      environment.push_back(value.data());
    }
    environment.push_back(nullptr);

    DptyPreparedSpawnConfig spawn_config = {};
    spawn_config.executable = config_.executable.c_str();
    spawn_config.argv = argv.data();
    spawn_config.envp = environment.data();
    spawn_config.working_directory = config_.working_directory.has_value()
                                         ? config_.working_directory->c_str()
                                         : nullptr;
    spawn_config.initial_size.ws_row = config_.rows;
    spawn_config.initial_size.ws_col = config_.columns;
    DptyPreparedSpawnResult spawn_result = {};
    int32_t system_error = 0;
    const int32_t spawn_status =
        dpty_spawn_prepared(&spawn_config, &spawn_result, &system_error);
    if (spawn_status != DPTY_STATUS_OK) {
      FinishError(static_cast<DptyStatus>(spawn_status), system_error);
      return;
    }
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      master_fd_ = spawn_result.master_fd;
      child_pid_ = spawn_result.child_pid;
    }
    exec_error_fd_ = spawn_result.exec_error_fd;

    if (!CheckExec(&system_error)) {
      TerminateAndReap(SIGKILL);
      CloseDescriptors();
      FinishError(DPTY_STATUS_SYSTEM_ERROR, system_error);
      return;
    }
    if (!ConfigureKqueue(&system_error)) {
      TerminateAndReap(SIGKILL);
      CloseDescriptors();
      FinishError(DPTY_STATUS_SYSTEM_ERROR, system_error);
      return;
    }

    Emit(DPTY_EVENT_STARTED, 0, nullptr, 0, spawn_result.child_pid, 0, 0);
    ProcessControl();
    EventLoop();
    CloseDescriptors();
  }

  bool CheckExec(int32_t* out_error) {
    struct pollfd descriptor = {};
    descriptor.fd = exec_error_fd_;
    descriptor.events = POLLIN | POLLHUP;
    int poll_status = 0;
    do {
      poll_status = poll(&descriptor, 1, 5000);
    } while (poll_status < 0 && errno == EINTR);
    if (poll_status <= 0) {
      *out_error = poll_status == 0 ? ETIMEDOUT : errno;
      return false;
    }
    int child_error = 0;
    ssize_t bytes = 0;
    do {
      bytes = read(exec_error_fd_, &child_error, sizeof(child_error));
    } while (bytes < 0 && errno == EINTR);
    (void)close(exec_error_fd_);
    exec_error_fd_ = -1;
    if (bytes == static_cast<ssize_t>(sizeof(child_error))) {
      *out_error = child_error;
      return false;
    }
    if (bytes < 0) {
      *out_error = errno;
      return false;
    }
    return true;
  }

  bool ConfigureKqueue(int32_t* out_error) {
    const int descriptor = kqueue();
    if (descriptor < 0) {
      *out_error = errno;
      return false;
    }
    struct kevent changes[4] = {};
    EV_SET(&changes[0], static_cast<uintptr_t>(master_fd_), EVFILT_READ,
           EV_ADD | EV_CLEAR, 0, 0, nullptr);
    EV_SET(&changes[1], static_cast<uintptr_t>(master_fd_), EVFILT_WRITE,
           EV_ADD | EV_CLEAR | EV_DISABLE, 0, 0, nullptr);
    EV_SET(&changes[2], static_cast<uintptr_t>(child_pid_), EVFILT_PROC,
           EV_ADD | EV_CLEAR, NOTE_EXIT | NOTE_EXITSTATUS, 0, nullptr);
    EV_SET(&changes[3], kControlEventIdentifier, EVFILT_USER, EV_ADD | EV_CLEAR,
           0, 0, nullptr);
    if (kevent(descriptor, changes, 4, nullptr, 0, nullptr) != 0) {
      *out_error = errno;
      (void)close(descriptor);
      return false;
    }
    kqueue_fd_.store(descriptor, std::memory_order_release);
    return true;
  }

  void EventLoop() {
    while (!finished_reaping_) {
      struct timespec timeout = {};
      timeout.tv_nsec = 100 * 1000 * 1000;
      struct kevent events[8] = {};
      const int count = kevent(kqueue_fd_.load(std::memory_order_acquire),
                               nullptr, 0, events, 8, &timeout);
      if (count < 0 && errno != EINTR) {
        TerminateAndReap(SIGKILL);
        FinishError(DPTY_STATUS_SYSTEM_ERROR, errno);
        return;
      }
      if (count > 0) {
        for (int index = 0; index < count; ++index) {
          if (events[index].filter == EVFILT_READ) {
            ReadAvailable();
          } else if (events[index].filter == EVFILT_WRITE) {
            FlushWrites();
          } else if (events[index].filter == EVFILT_PROC) {
            ObserveProcessExitReady(
                static_cast<pid_t>(events[index].ident),
                static_cast<int64_t>(events[index].data),
                (events[index].fflags & NOTE_EXITSTATUS) != 0);
            ReapChild();
          }
        }
      }
      ProcessControl();
      if (read_retry_requested_) {
        ReadAvailable();
      }
      ReapChild();
      if (child_completed_) {
        ReadAvailable();
        bool outstanding_capacity = false;
        bool outstanding_empty = false;
        {
          const std::lock_guard<std::mutex> lock(mutex_);
          outstanding_capacity =
              read_in_flight_bytes_ < config_.read_high_water;
          outstanding_empty = outstanding_.empty();
        }
        if (master_eof_ || !outstanding_capacity) {
          if (!outstanding_empty) {
            continue;
          }
          FinishExit();
        }
      }
    }
  }

  void ProcessControl() {
    std::optional<PendingResize> resize;
    std::deque<int> signals;
    bool begin_close = false;
    bool force_close = false;
    uint32_t grace_millis = 0;
    bool resume_read = false;
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      resize = pending_resize_;
      pending_resize_.reset();
      signals.swap(pending_signals_);
      force_close = force_close_requested_;
      force_close_requested_ = false;
      if (force_close) {
        close_started_ = true;
      } else if (closing_ && !close_started_) {
        close_started_ = true;
        begin_close = true;
        grace_millis = close_grace_millis_;
      }
      resume_read =
          read_paused_ && read_in_flight_bytes_ <= config_.read_low_water;
    }
    if (resize.has_value() && master_fd_ >= 0) {
      struct winsize size = {};
      size.ws_row = resize->rows;
      size.ws_col = resize->columns;
      (void)ioctl(master_fd_, TIOCSWINSZ, &size);
    }
    for (const int signal : signals) {
      SendToForeground(signal);
    }
    if (force_close && !child_completed_) {
      size_t queued_bytes = 0;
      {
        const std::lock_guard<std::mutex> lock(mutex_);
        queued_bytes = write_queued_bytes_;
        emit_waitpid_pending_ = true;
      }
      EmitDiagnostic(DPTY_EVENT_FORCE_CLOSE_DEQUEUED, 0, 0,
                     static_cast<int64_t>(queued_bytes), 0, 0);
      EmitStateSnapshot(0);
      SendToProcessGroups(SIGKILL);
      close_kill_deadline_ = std::chrono::steady_clock::time_point::max();
    } else if (begin_close) {
      {
        const std::lock_guard<std::mutex> lock(mutex_);
        emit_waitpid_pending_ = true;
      }
      EmitStateSnapshot(0);
      SendToProcessGroups(SIGHUP);
      close_kill_deadline_ = std::chrono::steady_clock::now() +
                             std::chrono::milliseconds(grace_millis);
    }
    if (close_started_ && !child_completed_ &&
        std::chrono::steady_clock::now() >= close_kill_deadline_) {
      SendToProcessGroups(SIGKILL);
      close_kill_deadline_ = std::chrono::steady_clock::time_point::max();
    }
    if (resume_read) {
      SetReadEnabled(true);
      ReadAvailable();
    }
    FlushWrites();
  }

  void ReadAvailable() {
    if (master_fd_ < 0 || master_eof_) {
      read_retry_requested_ = false;
      return;
    }
    read_retry_requested_ = false;
    size_t batches = 0;
    for (;;) {
      size_t available = 0;
      bool pause_read = false;
      {
        const std::lock_guard<std::mutex> lock(mutex_);
        if (read_in_flight_bytes_ >= config_.read_high_water) {
          if (!read_paused_) {
            read_paused_ = true;
            ++read_pause_count_;
          }
          pause_read = true;
        } else {
          available = std::min(config_.read_batch,
                               config_.read_high_water - read_in_flight_bytes_);
        }
      }
      if (pause_read) {
        SetReadEnabled(false);
        return;
      }
      std::vector<uint8_t> bytes(available);
      size_t collected = 0;
      size_t read_attempts = 0;
      bool terminal_read = false;
      for (;;) {
        const ssize_t count = read(master_fd_, bytes.data() + collected,
                                   bytes.size() - collected);
        if (count > 0) {
          collected += static_cast<size_t>(count);
          ++read_attempts;
          if (config_.read_batches_per_event_loop_turn == 0 ||
              collected == bytes.size() ||
              read_attempts >= kMaximumReadBatchesPerTurn) {
            break;
          }
          continue;
        }
        if (count == 0 || (count < 0 && errno == EIO)) {
          terminal_read = true;
          break;
        }
        if (errno == EINTR) {
          continue;
        }
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
          break;
        }
        terminal_read = true;
        break;
      }
      if (terminal_read) {
        master_eof_ = true;
        SetReadEnabled(false);
      }
      if (collected > 0) {
        bytes.resize(collected);
        uint64_t sequence = 0;
        const uint8_t* data = nullptr;
        size_t length = 0;
        bool yield_after_batch = false;
        {
          const std::lock_guard<std::mutex> lock(mutex_);
          sequence = next_sequence_++;
          outstanding_.push_back(OutputBatch{sequence, std::move(bytes)});
          OutputBatch& batch = outstanding_.back();
          data = batch.bytes.data();
          length = batch.bytes.size();
          read_in_flight_bytes_ += length;
          bytes_read_ += length;
          ++read_batches_;
          max_read_in_flight_bytes_ =
              std::max(max_read_in_flight_bytes_, read_in_flight_bytes_);
          if (config_.read_batches_per_event_loop_turn != 0) {
            read_paused_ = true;
            ++read_pause_count_;
            yield_after_batch = true;
          }
        }
        if (yield_after_batch) {
          SetReadEnabled(false);
        }
        Emit(DPTY_EVENT_OUTPUT, sequence, data, length, 0, 0, 0);
        ++batches;
        if (yield_after_batch) {
          return;
        }
        if (terminal_read) {
          return;
        }
        if (batches >= kMaximumReadBatchesPerTurn) {
          read_retry_requested_ = true;
          Wake();
          return;
        }
        continue;
      }
      if (terminal_read) {
        return;
      }
      return;
    }
  }

  void FlushWrites() {
    if (master_fd_ < 0 || child_completed_) {
      return;
    }
    size_t batches = 0;
    size_t bytes_written_this_turn = 0;
    for (;;) {
      const uint8_t* data = nullptr;
      size_t length = 0;
      bool empty = false;
      bool emit_dequeue = false;
      bool diagnostic = false;
      uint64_t request_id = 0;
      size_t queued_bytes = 0;
      {
        const std::lock_guard<std::mutex> lock(mutex_);
        if (writes_.empty()) {
          empty = true;
        } else {
          PendingWrite& write = writes_.front();
          data = write.bytes.data() + write_offset_;
          length = write.bytes.size() - write_offset_;
          diagnostic = write.diagnostic;
          request_id = write.request_id;
          queued_bytes = write_queued_bytes_;
          if (diagnostic && !write.dequeue_observed) {
            write.dequeue_observed = true;
            emit_dequeue = true;
          }
        }
      }
      if (empty) {
        SetWriteEnabled(false);
        return;
      }
      if (emit_dequeue) {
        EmitDiagnostic(DPTY_EVENT_WRITE_DEQUEUED, request_id, length,
                       static_cast<int64_t>(queued_bytes), 0, 0);
        EmitStateSnapshot(request_id);
      }
      const ssize_t count = write(master_fd_, data, length);
      if (count > 0) {
        const size_t consumed = static_cast<size_t>(count);
        bool completed = false;
        size_t request_bytes = 0;
        size_t remaining_queued_bytes = 0;
        {
          const std::lock_guard<std::mutex> lock(mutex_);
          write_offset_ += consumed;
          write_queued_bytes_ -= consumed;
          bytes_written_ += consumed;
          if (write_offset_ == writes_.front().bytes.size()) {
            request_bytes = writes_.front().bytes.size();
            completed = writes_.front().diagnostic;
            request_id = writes_.front().request_id;
            writes_.pop_front();
            write_offset_ = 0;
          }
          remaining_queued_bytes = write_queued_bytes_;
        }
        if (completed) {
          EmitDiagnostic(DPTY_EVENT_WRITE_COMPLETED, request_id, request_bytes,
                         static_cast<int64_t>(remaining_queued_bytes), 0, 0);
        }
        ++batches;
        bytes_written_this_turn += consumed;
        if (batches >= kMaximumWriteBatchesPerTurn ||
            bytes_written_this_turn >= kMaximumWriteBytesPerTurn) {
          Wake();
          return;
        }
        continue;
      }
      if (count < 0 && errno == EINTR) {
        continue;
      }
      if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
        SetWriteEnabled(true);
      } else if (count < 0 && diagnostic) {
        EmitDiagnostic(DPTY_EVENT_WRITE_ERROR, request_id, length,
                       static_cast<int64_t>(queued_bytes), 0, errno);
      }
      return;
    }
  }

  void SetReadEnabled(bool enabled) {
    const int descriptor = kqueue_fd_.load(std::memory_order_acquire);
    if (descriptor < 0 || master_fd_ < 0) {
      return;
    }
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      if (read_enabled_ == enabled) {
        return;
      }
      read_enabled_ = enabled;
      if (enabled) {
        read_paused_ = false;
      }
    }
    struct kevent change = {};
    EV_SET(&change, static_cast<uintptr_t>(master_fd_), EVFILT_READ,
           enabled ? EV_ENABLE : EV_DISABLE, 0, 0, nullptr);
    (void)kevent(descriptor, &change, 1, nullptr, 0, nullptr);
  }

  void SetWriteEnabled(bool enabled) {
    const int descriptor = kqueue_fd_.load(std::memory_order_acquire);
    if (descriptor < 0 || master_fd_ < 0 || write_enabled_ == enabled) {
      return;
    }
    write_enabled_ = enabled;
    struct kevent change = {};
    EV_SET(&change, static_cast<uintptr_t>(master_fd_), EVFILT_WRITE,
           enabled ? EV_ENABLE : EV_DISABLE, 0, 0, nullptr);
    (void)kevent(descriptor, &change, 1, nullptr, 0, nullptr);
  }

  int DeliverSignal(pid_t target, int signal) const {
    errno = 0;
    const int result = kill(target, signal);
    const int32_t system_error = result == 0 ? 0 : errno;
    EmitDiagnostic(DPTY_EVENT_SIGNAL_DELIVERY, 0, static_cast<size_t>(signal),
                   static_cast<int64_t>(target), result, system_error);
    return result;
  }

  void SendToForeground(int signal) {
    errno = 0;
    const pid_t foreground = master_fd_ >= 0 ? tcgetpgrp(master_fd_) : -1;
    if (foreground > 0 && DeliverSignal(-foreground, signal) == 0) {
      return;
    }
    pid_t child = -1;
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      child = child_pid_;
    }
    if (child > 0) {
      (void)DeliverSignal(child, signal);
    } else if (foreground <= 0) {
      EmitDiagnostic(DPTY_EVENT_SIGNAL_DELIVERY, 0, static_cast<size_t>(signal),
                     0, -1, errno == 0 ? ESRCH : errno);
    }
  }

  void SendToProcessGroups(int signal) {
    pid_t child = -1;
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      child = child_pid_;
    }
    const pid_t foreground = master_fd_ >= 0 ? tcgetpgrp(master_fd_) : -1;
    const pid_t child_group = child > 0 ? getpgid(child) : -1;
    bool child_signaled = false;
    if (foreground > 0) {
      const int result = DeliverSignal(-foreground, signal);
      child_signaled = result == 0 && child_group == foreground;
    }
    if (child_group > 0 && child_group != foreground) {
      child_signaled = DeliverSignal(-child_group, signal) == 0;
    }
    if (child > 0 && !child_signaled) {
      (void)DeliverSignal(child, signal);
    }
    if (foreground <= 0 && child <= 0) {
      EmitDiagnostic(DPTY_EVENT_SIGNAL_DELIVERY, 0, static_cast<size_t>(signal),
                     0, -1, ESRCH);
    }
  }

  void ReapChild() {
    if (child_completed_) {
      return;
    }
    pid_t child = -1;
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      child = child_pid_;
    }
    if (child <= 0) {
      return;
    }
    int status = 0;
    errno = 0;
    const pid_t waited = waitpid(child, &status, WNOHANG);
    if (waited == child) {
      ObserveProcessExitReady(waited, status, true);
      {
        const std::lock_guard<std::mutex> lock(mutex_);
        child_completed_ = true;
        child_reaped_by_session_ = true;
        child_status_ = status;
        emit_waitpid_pending_ = false;
        writes_.clear();
        write_offset_ = 0;
        write_queued_bytes_ = 0;
      }
      EmitDiagnostic(DPTY_EVENT_WAITPID_RESULT, 0, 0,
                     static_cast<int64_t>(waited), status, 0);
    } else if (waited == 0) {
      bool emit_pending = false;
      {
        const std::lock_guard<std::mutex> lock(mutex_);
        emit_pending = emit_waitpid_pending_;
        emit_waitpid_pending_ = false;
      }
      if (emit_pending) {
        EmitDiagnostic(DPTY_EVENT_WAITPID_RESULT, 0, 0, 0, 0, 0);
      }
    } else if (errno != EINTR) {
      const int32_t wait_error = errno;
      bool emit_error = false;
      bool external_reap = false;
      int retained_status = 0;
      {
        const std::lock_guard<std::mutex> lock(mutex_);
        emit_error = !waitpid_error_observed_;
        waitpid_error_observed_ = true;
        if (wait_error == ECHILD && process_exit_ready_observed_ &&
            process_exit_status_valid_) {
          child_completed_ = true;
          child_externally_reaped_ = true;
          child_status_ = process_exit_status_;
          emit_waitpid_pending_ = false;
          writes_.clear();
          write_offset_ = 0;
          write_queued_bytes_ = 0;
          external_reap = true;
          retained_status = child_status_;
        }
      }
      if (emit_error) {
        EmitDiagnostic(DPTY_EVENT_WAITPID_RESULT, 0, 0, -1, 0, wait_error);
      }
      if (external_reap) {
        EmitDiagnostic(DPTY_EVENT_EXTERNAL_REAP_OBSERVED, 0, 0,
                       static_cast<int64_t>(child), retained_status,
                       wait_error);
      }
    }
  }

  void FinishExit() {
    int64_t exit_code = 0;
    int64_t signal = 0;
    if (WIFEXITED(child_status_)) {
      exit_code = WEXITSTATUS(child_status_);
    } else if (WIFSIGNALED(child_status_)) {
      signal = WTERMSIG(child_status_);
      exit_code = 128 + signal;
    }
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      state_ = State::kFinished;
    }
    finished_reaping_ = true;
    EmitDiagnostic(DPTY_EVENT_EXIT_PUBLISHED, 0, 0, exit_code, signal, 0);
    Emit(DPTY_EVENT_EXIT, 0, nullptr, 0, exit_code, signal, 0);
  }

  void TerminateAndReap(int signal) {
    SendToProcessGroups(signal);
    pid_t child = -1;
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      child = child_pid_;
    }
    if (child > 0) {
      while (waitpid(child, nullptr, 0) < 0 && errno == EINTR) {
      }
    }
  }

  void CloseDescriptors() {
    const int descriptor = kqueue_fd_.exchange(-1, std::memory_order_acq_rel);
    if (descriptor >= 0) {
      (void)close(descriptor);
    }
    if (exec_error_fd_ >= 0) {
      (void)close(exec_error_fd_);
      exec_error_fd_ = -1;
    }
    int master = -1;
    {
      const std::lock_guard<std::mutex> lock(mutex_);
      master = master_fd_;
      master_fd_ = -1;
    }
    if (master >= 0) {
      (void)close(master);
    }
  }

  OwnedConfig config_;
  DptySessionHandle handle_ = 0;
  mutable std::mutex mutex_;
  std::thread thread_;
  State state_ = State::kCreated;
  std::atomic<int> kqueue_fd_{-1};
  int master_fd_ = -1;
  int exec_error_fd_ = -1;
  pid_t child_pid_ = -1;
  bool child_completed_ = false;
  bool child_reaped_by_session_ = false;
  bool child_externally_reaped_ = false;
  int child_status_ = 0;
  bool master_eof_ = false;
  bool finished_reaping_ = false;
  bool read_retry_requested_ = false;
  bool read_enabled_ = true;
  bool write_enabled_ = false;
  uint64_t next_sequence_ = 0;
  std::deque<OutputBatch> outstanding_;
  size_t read_in_flight_bytes_ = 0;
  bool read_paused_ = false;
  std::deque<PendingWrite> writes_;
  size_t write_offset_ = 0;
  size_t write_queued_bytes_ = 0;
  uint64_t next_write_request_id_ = 1;
  std::optional<PendingResize> pending_resize_;
  std::deque<int> pending_signals_;
  bool closing_ = false;
  bool close_started_ = false;
  bool force_close_requested_ = false;
  bool emit_waitpid_pending_ = false;
  bool waitpid_error_observed_ = false;
  bool process_exit_ready_observed_ = false;
  bool process_exit_status_valid_ = false;
  int process_exit_status_ = 0;
  uint32_t close_grace_millis_ = 0;
  std::chrono::steady_clock::time_point close_kill_deadline_ =
      std::chrono::steady_clock::time_point::max();
  uint64_t bytes_read_ = 0;
  uint64_t bytes_written_ = 0;
  uint64_t read_batches_ = 0;
  uint64_t write_backpressure_rejections_ = 0;
  size_t max_read_in_flight_bytes_ = 0;
  size_t max_write_queued_bytes_ = 0;
  uint64_t read_pause_count_ = 0;
};

class SessionRegistry final {
 public:
  DptySessionHandle Insert(const std::shared_ptr<Session>& session) {
    const std::lock_guard<std::mutex> lock(mutex_);
    uint32_t index = 0;
    if (free_indices_.empty()) {
      if (slots_.size() >= std::numeric_limits<uint32_t>::max()) {
        return 0;
      }
      index = static_cast<uint32_t>(slots_.size());
      slots_.push_back(Slot{});
    } else {
      index = free_indices_.back();
      free_indices_.pop_back();
    }
    Slot& slot = slots_[index];
    slot.session = session;
    ++live_count_;
    return Encode(index, slot.generation);
  }

  std::shared_ptr<Session> Lookup(DptySessionHandle handle) const {
    uint32_t index = 0;
    uint32_t generation = 0;
    if (!Decode(handle, &index, &generation)) {
      return nullptr;
    }
    const std::lock_guard<std::mutex> lock(mutex_);
    if (index >= slots_.size()) {
      return nullptr;
    }
    const Slot& slot = slots_[index];
    if (slot.generation != generation || slot.session == nullptr) {
      return nullptr;
    }
    return slot.session;
  }

  std::shared_ptr<Session> Remove(DptySessionHandle handle) {
    uint32_t index = 0;
    uint32_t generation = 0;
    if (!Decode(handle, &index, &generation)) {
      return nullptr;
    }
    const std::lock_guard<std::mutex> lock(mutex_);
    if (index >= slots_.size()) {
      return nullptr;
    }
    Slot& slot = slots_[index];
    if (slot.generation != generation || slot.session == nullptr) {
      return nullptr;
    }
    std::shared_ptr<Session> session = std::move(slot.session);
    ++slot.generation;
    if (slot.generation == 0) {
      slot.generation = 1;
    }
    free_indices_.push_back(index);
    --live_count_;
    return session;
  }

  uint64_t live_count() const {
    const std::lock_guard<std::mutex> lock(mutex_);
    return live_count_;
  }

 private:
  struct Slot {
    uint32_t generation = 1;
    std::shared_ptr<Session> session;
  };

  static DptySessionHandle Encode(uint32_t index, uint32_t generation) {
    return (static_cast<uint64_t>(generation) << 32) |
           (static_cast<uint64_t>(index) + 1);
  }

  static bool Decode(DptySessionHandle handle, uint32_t* index,
                     uint32_t* generation) {
    const uint32_t encoded_index = static_cast<uint32_t>(handle);
    const uint32_t encoded_generation = static_cast<uint32_t>(handle >> 32);
    if (encoded_index == 0 || encoded_generation == 0) {
      return false;
    }
    *index = encoded_index - 1;
    *generation = encoded_generation;
    return true;
  }

  mutable std::mutex mutex_;
  std::deque<Slot> slots_;
  std::vector<uint32_t> free_indices_;
  uint64_t live_count_ = 0;
};

SessionRegistry g_registry;

std::shared_ptr<Session> LookupSession(DptySessionHandle handle) {
  std::shared_ptr<Session> session = g_registry.Lookup(handle);
  if (session == nullptr) {
    (void)SetError(DPTY_STATUS_INVALID_HANDLE, 0,
                   "PTY session handle is stale or invalid");
  }
  return session;
}

}  // namespace

extern "C" __attribute__((visibility("default"))) uint32_t
dpty_abi_version(void) {
  return DPTY_ABI_VERSION;
}

extern "C" __attribute__((visibility("default"))) int32_t dpty_session_create(
    const DptySessionConfigV1* config, DptySessionHandle* out_session) {
  ClearError();
  if (out_session == nullptr) {
    return SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                    "PTY output session pointer is null");
  }
  *out_session = 0;
  try {
    OwnedConfig copied;
    if (!CopyConfig(config, &copied)) {
      return g_last_error.status;
    }
    std::shared_ptr<Session> session =
        std::make_shared<Session>(std::move(copied));
    const DptySessionHandle handle = g_registry.Insert(session);
    if (handle == 0) {
      return SetError(DPTY_STATUS_SYSTEM_ERROR, ENOMEM,
                      "PTY session registry is exhausted");
    }
    session->SetHandle(handle);
    *out_session = handle;
    return DPTY_STATUS_OK;
  } catch (...) {
    return SetError(DPTY_STATUS_SYSTEM_ERROR, ENOMEM,
                    "could not allocate PTY session");
  }
}

extern "C" __attribute__((visibility("default"))) int32_t
dpty_session_start(DptySessionHandle session) {
  ClearError();
  const std::shared_ptr<Session> value = LookupSession(session);
  return value == nullptr ? DPTY_STATUS_INVALID_HANDLE : value->Start();
}

extern "C" __attribute__((visibility("default"))) int32_t dpty_session_write(
    DptySessionHandle session, const uint8_t* bytes, size_t length) {
  ClearError();
  const std::shared_ptr<Session> value = LookupSession(session);
  return value == nullptr ? DPTY_STATUS_INVALID_HANDLE
                          : value->Write(bytes, length);
}

extern "C" __attribute__((visibility("default"))) int32_t
dpty_session_write_tracked(DptySessionHandle session, const uint8_t* bytes,
                           size_t length, uint64_t* out_request_id) {
  ClearError();
  if (out_request_id == nullptr) {
    return SetError(DPTY_STATUS_INVALID_ARGUMENT, EINVAL,
                    "tracked PTY write output request ID is null");
  }
  *out_request_id = 0;
  const std::shared_ptr<Session> value = LookupSession(session);
  return value == nullptr ? DPTY_STATUS_INVALID_HANDLE
                          : value->WriteTracked(bytes, length, out_request_id);
}

extern "C" __attribute__((visibility("default"))) int32_t
dpty_session_ack_output(DptySessionHandle session, uint64_t sequence,
                        size_t length) {
  ClearError();
  const std::shared_ptr<Session> value = LookupSession(session);
  return value == nullptr ? DPTY_STATUS_INVALID_HANDLE
                          : value->Acknowledge(sequence, length);
}

extern "C" __attribute__((visibility("default"))) int32_t dpty_session_resize(
    DptySessionHandle session, uint16_t rows, uint16_t columns) {
  ClearError();
  const std::shared_ptr<Session> value = LookupSession(session);
  return value == nullptr ? DPTY_STATUS_INVALID_HANDLE
                          : value->Resize(rows, columns);
}

extern "C" __attribute__((visibility("default"))) int32_t
dpty_session_send_signal(DptySessionHandle session, uint32_t signal) {
  ClearError();
  const std::shared_ptr<Session> value = LookupSession(session);
  return value == nullptr ? DPTY_STATUS_INVALID_HANDLE
                          : value->SendSignal(signal);
}

extern "C" __attribute__((visibility("default"))) int32_t
dpty_session_close(DptySessionHandle session, uint32_t grace_period_millis) {
  ClearError();
  const std::shared_ptr<Session> value = LookupSession(session);
  return value == nullptr ? DPTY_STATUS_INVALID_HANDLE
                          : value->Close(grace_period_millis);
}

extern "C" __attribute__((visibility("default"))) int32_t
dpty_session_force_close(DptySessionHandle session) {
  ClearError();
  const std::shared_ptr<Session> value = LookupSession(session);
  return value == nullptr ? DPTY_STATUS_INVALID_HANDLE : value->ForceClose();
}

extern "C" __attribute__((visibility("default"))) int32_t
dpty_session_get_stats(DptySessionHandle session,
                       DptySessionStatsV1* out_stats) {
  ClearError();
  const std::shared_ptr<Session> value = LookupSession(session);
  return value == nullptr ? DPTY_STATUS_INVALID_HANDLE
                          : value->GetStats(out_stats);
}

extern "C" __attribute__((visibility("default"))) int32_t
dpty_session_get_process_snapshot(DptySessionHandle session,
                                  DptyProcessSnapshotV1* out_snapshot) {
  ClearError();
  const std::shared_ptr<Session> value = LookupSession(session);
  return value == nullptr ? DPTY_STATUS_INVALID_HANDLE
                          : value->GetProcessSnapshot(out_snapshot);
}

extern "C" __attribute__((visibility("default"))) int32_t
dpty_session_destroy(DptySessionHandle session) {
  ClearError();
  const std::shared_ptr<Session> value = LookupSession(session);
  if (value == nullptr) {
    return DPTY_STATUS_INVALID_HANDLE;
  }
  if (!value->CanDestroy()) {
    return SetError(
        DPTY_STATUS_WRONG_STATE, 0,
        "PTY session has not finished or has unacknowledged output");
  }
  std::shared_ptr<Session> removed = g_registry.Remove(session);
  if (removed == nullptr) {
    return SetError(DPTY_STATUS_INVALID_HANDLE, 0,
                    "PTY session handle became stale");
  }
  removed->Join();
  return DPTY_STATUS_OK;
}

extern "C" __attribute__((visibility("default"))) int32_t
dpty_get_last_error(DptyError* out_error) {
  if (out_error == nullptr) {
    return DPTY_STATUS_INVALID_ARGUMENT;
  }
  *out_error = g_last_error;
  return DPTY_STATUS_OK;
}

extern "C" __attribute__((visibility("default"))) uint64_t
dpty_debug_live_session_count(void) {
  return g_registry.live_count();
}
