#include <dlfcn.h>
#include <errno.h>
#include <signal.h>
#include <sys/wait.h>

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <deque>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "dart_pty_macos.h"

namespace {

using Clock = std::chrono::steady_clock;

int failures = 0;

void Expect(bool condition, const char* description) {
  if (!condition) {
    std::cerr << "PtyCapability expectation failed: " << description << '\n';
    ++failures;
  }
}

template <typename Function>
Function Lookup(void* image, const char* symbol) {
  dlerror();
  Function function = reinterpret_cast<Function>(dlsym(image, symbol));
  const char* error = dlerror();
  if (function == nullptr || error != nullptr) {
    std::cerr << "Could not resolve " << symbol << ": "
              << (error == nullptr ? "unknown" : error) << '\n';
    ++failures;
  }
  return function;
}

struct Api {
  uint32_t (*version)() = nullptr;
  int32_t (*create)(const DptySessionConfigV1*, DptySessionHandle*) = nullptr;
  int32_t (*start)(DptySessionHandle) = nullptr;
  int32_t (*write)(DptySessionHandle, const uint8_t*, size_t) = nullptr;
  int32_t (*write_tracked)(DptySessionHandle, const uint8_t*, size_t,
                           uint64_t*) = nullptr;
  int32_t (*ack)(DptySessionHandle, uint64_t, size_t) = nullptr;
  int32_t (*resize)(DptySessionHandle, uint16_t, uint16_t) = nullptr;
  int32_t (*send_signal)(DptySessionHandle, uint32_t) = nullptr;
  int32_t (*close)(DptySessionHandle, uint32_t) = nullptr;
  int32_t (*force_close)(DptySessionHandle) = nullptr;
  int32_t (*stats)(DptySessionHandle, DptySessionStatsV1*) = nullptr;
  int32_t (*process_snapshot)(DptySessionHandle,
                              DptyProcessSnapshotV1*) = nullptr;
  int32_t (*destroy)(DptySessionHandle) = nullptr;
  uint64_t (*live_count)() = nullptr;
};

struct PendingAck {
  uint64_t sequence;
  size_t length;
};

struct Diagnostic {
  uint32_t type = 0;
  uint64_t sequence = 0;
  size_t length = 0;
  int64_t value1 = 0;
  int64_t value2 = 0;
  int32_t system_error = 0;
};

struct Events {
  Api* api = nullptr;
  std::mutex mutex;
  std::condition_variable condition;
  bool started = false;
  bool exited = false;
  bool failed = false;
  bool auto_ack = true;
  bool retain_output = true;
  int64_t pid = -1;
  int64_t exit_code = -1;
  int64_t exit_signal = 0;
  int32_t system_error = 0;
  uint64_t next_sequence = 0;
  uint64_t x_bytes = 0;
  size_t held_bytes = 0;
  size_t maximum_output_batch = 0;
  std::vector<uint8_t> output;
  std::string recent_output;
  std::deque<PendingAck> pending_acks;
  std::vector<Diagnostic> diagnostics;
};

void EventCallback(DptySessionHandle session, uint32_t event_type,
                   uint64_t sequence, const uint8_t* data, size_t length,
                   int64_t value1, int64_t value2, int32_t system_error,
                   void* context) {
  Events* events = static_cast<Events*>(context);
  bool acknowledge = false;
  {
    const std::lock_guard<std::mutex> lock(events->mutex);
    if (event_type == DPTY_EVENT_STARTED) {
      events->started = true;
      events->pid = value1;
    } else if (event_type == DPTY_EVENT_OUTPUT) {
      if (sequence != events->next_sequence || data == nullptr || length == 0 ||
          length > 64 * 1024) {
        events->failed = true;
      }
      events->maximum_output_batch =
          std::max(events->maximum_output_batch, length);
      ++events->next_sequence;
      if (events->retain_output) {
        events->output.insert(events->output.end(), data, data + length);
        events->recent_output.append(reinterpret_cast<const char*>(data),
                                     length);
        if (events->recent_output.size() > 256 * 1024) {
          events->recent_output.erase(
              0, events->recent_output.size() - 256 * 1024);
        }
      }
      events->x_bytes += static_cast<uint64_t>(
          std::count(data, data + length, static_cast<uint8_t>('x')));
      if (events->auto_ack) {
        acknowledge = true;
      } else {
        events->pending_acks.push_back(PendingAck{sequence, length});
        events->held_bytes += length;
      }
    } else if (event_type == DPTY_EVENT_EXIT) {
      events->exited = true;
      events->exit_code = value1;
      events->exit_signal = value2;
    } else if (event_type == DPTY_EVENT_ERROR) {
      events->failed = true;
      events->system_error = system_error;
    } else if (event_type >= DPTY_EVENT_WRITE_ENQUEUED &&
               event_type <= DPTY_EVENT_EXTERNAL_REAP_OBSERVED) {
      if (data != nullptr) {
        events->failed = true;
      }
      events->diagnostics.push_back(Diagnostic{event_type, sequence, length,
                                               value1, value2, system_error});
    } else {
      events->failed = true;
    }
    events->condition.notify_all();
  }
  if (acknowledge &&
      events->api->ack(session, sequence, length) != DPTY_STATUS_OK) {
    const std::lock_guard<std::mutex> lock(events->mutex);
    events->failed = true;
    events->condition.notify_all();
  }
}

template <typename Predicate>
bool WaitFor(Events* events, std::chrono::milliseconds timeout,
             Predicate predicate) {
  std::unique_lock<std::mutex> lock(events->mutex);
  return events->condition.wait_for(lock, timeout, [&] {
    return predicate(*events) || events->failed;
  }) && predicate(*events);
}

bool ContainsLocked(const Events& events, const std::string& marker) {
  return events.recent_output.find(marker) != std::string::npos;
}

bool WaitForMarker(Events* events, const std::string& marker,
                   std::chrono::milliseconds timeout) {
  return WaitFor(events, timeout, [&](const Events& value) {
    return ContainsLocked(value, marker);
  });
}

bool HasDiagnosticLocked(const Events& events, uint32_t type) {
  return std::any_of(
      events.diagnostics.begin(), events.diagnostics.end(),
      [type](const Diagnostic& value) { return value.type == type; });
}

bool WaitForDiagnostic(Events* events, uint32_t type,
                       std::chrono::milliseconds timeout) {
  return WaitFor(events, timeout, [&](const Events& value) {
    return HasDiagnosticLocked(value, type);
  });
}

int32_t Write(Api* api, DptySessionHandle session, const std::string& value) {
  return api->write(session, reinterpret_cast<const uint8_t*>(value.data()),
                    value.size());
}

DptySessionHandle Create(Api* api, Events* events, const char* executable,
                         const std::vector<const char*>& arguments,
                         size_t high_water = 256 * 1024,
                         size_t low_water = 128 * 1024,
                         size_t write_capacity = 64 * 1024,
                         bool diagnostics = false, size_t read_batch = 0,
                         bool legacy_config_prefix = false,
                         bool previous_config_prefix = false,
                         uint32_t read_batches_per_event_loop_turn = 0) {
  const char* environment[] = {"PATH=/usr/bin:/bin", "TERM=xterm-256color",
                               "HOME=/private/tmp"};
  DptySessionConfigV1 config = {};
  config.struct_size =
      legacy_config_prefix ? offsetof(DptySessionConfigV1, read_batch_bytes)
      : previous_config_prefix
          ? offsetof(DptySessionConfigV1, read_batches_per_event_loop_turn)
          : sizeof(config);
  config.abi_version = DPTY_ABI_VERSION;
  config.executable = executable;
  config.arguments = arguments.data();
  config.argument_count = arguments.size();
  config.environment = environment;
  config.environment_count = sizeof(environment) / sizeof(environment[0]);
  config.working_directory = "/private/tmp";
  config.initial_rows = 24;
  config.initial_columns = 80;
  config.read_high_water_bytes = high_water;
  config.read_low_water_bytes = low_water;
  config.write_capacity_bytes = write_capacity;
  config.callback = EventCallback;
  config.callback_context = events;
  config.diagnostics_enabled = diagnostics ? 1 : 0;
  config.read_batch_bytes = read_batch;
  config.read_batches_per_event_loop_turn = read_batches_per_event_loop_turn;
  DptySessionHandle session = 0;
  Expect(api->create(&config, &session) == DPTY_STATUS_OK,
         "session configuration is copied");
  return session;
}

void TestReadBatchConfiguration(Api* api) {
  Events configured_events;
  configured_events.api = api;
  const std::vector<const char*> configured_arguments = {
      "sh", "-c",
      "head -c 1048576 /dev/zero | tr '\\000' x; "
      "printf __DPTY_BATCH_COMPLETE__"};
  const DptySessionHandle configured =
      Create(api, &configured_events, "/bin/sh", configured_arguments,
             256 * 1024, 128 * 1024, 64 * 1024, false, 4 * 1024, false, true);
  Expect(api->start(configured) == DPTY_STATUS_OK,
         "configured read-batch session starts");
  Expect(WaitForMarker(&configured_events, "__DPTY_BATCH_COMPLETE__",
                       std::chrono::seconds(5)),
         "configured read-batch payload drains");
  Expect(WaitFor(&configured_events, std::chrono::seconds(3),
                 [](const Events& value) { return value.exited; }),
         "configured read-batch child exits");
  {
    const std::lock_guard<std::mutex> lock(configured_events.mutex);
    Expect(configured_events.maximum_output_batch > 0 &&
               configured_events.maximum_output_batch <= 4 * 1024 &&
               configured_events.x_bytes >= 1024 * 1024,
           "previous config prefix preserves its read-batch bound");
  }
  Expect(api->destroy(configured) == DPTY_STATUS_OK,
         "configured read-batch session is destroyed");

  Events legacy_events;
  legacy_events.api = api;
  const std::vector<const char*> legacy_arguments = {"sh", "-c", "exit 0"};
  const DptySessionHandle legacy =
      Create(api, &legacy_events, "/bin/sh", legacy_arguments, 256 * 1024,
             128 * 1024, 64 * 1024, false, 0, true);
  Expect(api->start(legacy) == DPTY_STATUS_OK,
         "legacy config-prefix session starts");
  Expect(WaitFor(&legacy_events, std::chrono::seconds(3),
                 [](const Events& value) { return value.exited; }),
         "legacy config-prefix child exits");
  Expect(api->destroy(legacy) == DPTY_STATUS_OK,
         "legacy config-prefix session is destroyed");
}

void ReleaseHeldOutput(Api* api, Events* events, DptySessionHandle session) {
  for (;;) {
    PendingAck acknowledgement = {};
    {
      const std::lock_guard<std::mutex> lock(events->mutex);
      if (events->pending_acks.empty()) {
        events->auto_ack = true;
        events->held_bytes = 0;
        return;
      }
      acknowledgement = events->pending_acks.front();
      events->pending_acks.pop_front();
      events->held_bytes -= acknowledgement.length;
    }
    Expect(api->ack(session, acknowledgement.sequence,
                    acknowledgement.length) == DPTY_STATUS_OK,
           "held output acknowledgement is accepted in order");
  }
}

void TestInteractiveSession(Api* api) {
  Events events;
  events.api = api;
  const std::vector<const char*> arguments = {"-zsh", "-f", "-i"};
  const DptySessionHandle session = Create(api, &events, "/bin/zsh", arguments);
  Expect(session != 0, "interactive session handle");
  const Clock::time_point start_time = Clock::now();
  Expect(api->start(session) == DPTY_STATUS_OK, "reactor starts");
  Expect(Clock::now() - start_time < std::chrono::milliseconds(50),
         "start does not wait for exec or PTY readiness");
  Expect(WaitFor(&events, std::chrono::seconds(3),
                 [](const Events& value) { return value.started; }),
         "interactive child starts");

  DptyProcessSnapshotV1 shell_snapshot = {};
  shell_snapshot.struct_size = sizeof(shell_snapshot);
  shell_snapshot.abi_version = DPTY_ABI_VERSION;
  Expect(api->process_snapshot(session, &shell_snapshot) == DPTY_STATUS_OK,
         "live shell process snapshot is readable");
  Expect(shell_snapshot.child_pid > 0 &&
             shell_snapshot.child_process_group == shell_snapshot.child_pid &&
             shell_snapshot.foreground_process_group ==
                 shell_snapshot.child_process_group &&
             shell_snapshot.child_process_group_error == 0 &&
             shell_snapshot.foreground_process_group_error == 0 &&
             shell_snapshot.terminal_echo_enabled == 1 &&
             shell_snapshot.terminal_attributes_error == 0 &&
             shell_snapshot.has_exited == 0,
         "idle shell owns its process group and starts with echo enabled");

  std::vector<uint8_t> oversized(64 * 1024 + 1, 'w');
  Expect(api->write(session, oversized.data(), oversized.size()) ==
             DPTY_STATUS_BACKPRESSURED,
         "oversized write is rejected without blocking");

  Expect(Write(api, session, "stty -echo; unsetopt zle; PS1=''; PS2=''\n") ==
             DPTY_STATUS_OK,
         "shell setup write");
  Expect(Write(api, session,
               "print -r -- __DPTY_READY__; "
               "[[ -t 0 && -t 1 && -o interactive ]] && print -r -- "
               "__DPTY_TTY_OK__; [[ -o login ]] && print -r -- "
               "__DPTY_LOGIN_OK__; print -r -- __DPTY_ENV__${TERM}; "
               "print -r -- __DPTY_CWD__${PWD}\n") == DPTY_STATUS_OK,
         "interactive checks are queued");
  Expect(WaitForMarker(&events, "__DPTY_CWD__/private/tmp",
                       std::chrono::seconds(3)),
         "working directory is applied");
  DptyProcessSnapshotV1 no_echo_snapshot = {};
  no_echo_snapshot.struct_size = sizeof(no_echo_snapshot);
  no_echo_snapshot.abi_version = DPTY_ABI_VERSION;
  Expect(api->process_snapshot(session, &no_echo_snapshot) == DPTY_STATUS_OK &&
             no_echo_snapshot.terminal_echo_enabled == 0 &&
             no_echo_snapshot.terminal_attributes_error == 0,
         "live no-echo terminal mode is observable without terminal content");
  {
    const std::lock_guard<std::mutex> lock(events.mutex);
    Expect(ContainsLocked(events, "__DPTY_TTY_OK__"),
           "stdin/stdout are interactive TTYs");
    Expect(ContainsLocked(events, "__DPTY_LOGIN_OK__"),
           "login-shell argv zero is preserved");
    Expect(ContainsLocked(events, "__DPTY_ENV__xterm-256color"),
           "explicit environment is applied");
  }

  Expect(api->resize(session, 43, 132) == DPTY_STATUS_OK, "resize is queued");
  Expect(Write(api, session, "print -r -- __DPTY_SIZE__$(stty size)\n") ==
             DPTY_STATUS_OK,
         "size probe is queued");
  Expect(WaitForMarker(&events, "__DPTY_SIZE__43 132", std::chrono::seconds(3)),
         "TIOCSWINSZ reaches the child");

  Expect(Write(api, session, "sleep 30\n") == DPTY_STATUS_OK,
         "foreground process starts");
  DptyProcessSnapshotV1 foreground_snapshot = {};
  foreground_snapshot.struct_size = sizeof(foreground_snapshot);
  foreground_snapshot.abi_version = DPTY_ABI_VERSION;
  bool observed_distinct_foreground = false;
  const Clock::time_point foreground_deadline =
      Clock::now() + std::chrono::seconds(3);
  while (Clock::now() < foreground_deadline) {
    if (api->process_snapshot(session, &foreground_snapshot) ==
            DPTY_STATUS_OK &&
        foreground_snapshot.child_process_group > 0 &&
        foreground_snapshot.foreground_process_group > 0 &&
        foreground_snapshot.foreground_process_group !=
            foreground_snapshot.child_process_group) {
      observed_distinct_foreground = true;
      break;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  Expect(observed_distinct_foreground,
         "distinct foreground job process group is observed");
  Expect(api->send_signal(session, DPTY_SIGNAL_INTERRUPT) == DPTY_STATUS_OK,
         "foreground interrupt is queued");
  Expect(Write(api, session, "print -r -- __DPTY_SIGINT__${?}\n") ==
             DPTY_STATUS_OK,
         "signal result probe is queued");
  Expect(WaitForMarker(&events, "__DPTY_SIGINT__130", std::chrono::seconds(3)),
         "SIGINT reaches the foreground process group");

  const size_t partial_start = [&] {
    const std::lock_guard<std::mutex> lock(events.mutex);
    return events.output.size();
  }();
  Expect(Write(api, session,
               "printf '\\342'; sleep 0.05; printf '\\202\\254'; "
               "print -r -- __DPTY_UTF8__\n") == DPTY_STATUS_OK,
         "partial UTF-8 producer is queued");
  Expect(WaitForMarker(&events, "__DPTY_UTF8__", std::chrono::seconds(3)),
         "partial UTF-8 output completes");
  {
    const std::lock_guard<std::mutex> lock(events.mutex);
    const std::vector<uint8_t> euro = {0xe2, 0x82, 0xac};
    Expect(std::search(
               events.output.begin() + static_cast<ptrdiff_t>(partial_start),
               events.output.end(), euro.begin(),
               euro.end()) != events.output.end(),
           "native transport preserves split UTF-8 bytes");
    events.auto_ack = false;
  }

  Expect(Write(api, session,
               "print -r -- __DPTY_BURST_BEGIN__; head -c 10485760 "
               "/dev/zero | tr '\\000' x; print -r -- __DPTY_BURST_END__\n") ==
             DPTY_STATUS_OK,
         "10 MiB burst is queued");
  Expect(WaitFor(&events, std::chrono::seconds(4),
                 [](const Events& value) {
                   return value.held_bytes >= 256 * 1024;
                 }),
         "read delivery stops at its high watermark");
  DptySessionStatsV1 paused_stats = {};
  paused_stats.struct_size = sizeof(paused_stats);
  paused_stats.abi_version = DPTY_ABI_VERSION;
  Expect(api->stats(session, &paused_stats) == DPTY_STATUS_OK,
         "paused stats are readable");
  Expect(paused_stats.max_read_in_flight_bytes <= 256 * 1024,
         "read in-flight bytes are bounded");
  Expect(paused_stats.read_pause_count > 0,
         "high watermark paused the read filter");
  ReleaseHeldOutput(api, &events, session);
  const bool burst_finished =
      WaitForMarker(&events, "__DPTY_BURST_END__", std::chrono::seconds(10));
  if (!burst_finished) {
    DptySessionStatsV1 debug_stats = {};
    debug_stats.struct_size = sizeof(debug_stats);
    debug_stats.abi_version = DPTY_ABI_VERSION;
    (void)api->stats(session, &debug_stats);
    const std::lock_guard<std::mutex> lock(events.mutex);
    std::cerr << "DPTY burst debug failed=" << events.failed
              << " errno=" << events.system_error
              << " output=" << events.output.size()
              << " held=" << events.held_bytes
              << " pending=" << events.pending_acks.size()
              << " read=" << debug_stats.bytes_read
              << " batches=" << debug_stats.read_batches
              << " pauses=" << debug_stats.read_pause_count << '\n';
  }
  Expect(burst_finished, "10 MiB burst drains after ACK credits resume");
  {
    const std::lock_guard<std::mutex> lock(events.mutex);
    Expect(events.x_bytes >= 10 * 1024 * 1024,
           "all burst payload bytes are delivered");
    Expect(events.maximum_output_batch > 0 &&
               events.maximum_output_batch <= 64 * 1024,
           "default burst delivery stays within the 64 KiB contract");
  }

  Expect(Write(api, session, "exit 37\n") == DPTY_STATUS_OK,
         "explicit shell exit is queued");
  Expect(WaitFor(&events, std::chrono::seconds(4),
                 [](const Events& value) { return value.exited; }),
         "shell exit event arrives");
  int64_t child_pid = -1;
  {
    const std::lock_guard<std::mutex> lock(events.mutex);
    Expect(!events.failed, "interactive session has no native error");
    Expect(events.exit_code == 37 && events.exit_signal == 0,
           "exit status is preserved");
    Expect(events.diagnostics.empty(),
           "diagnostics remain disabled by default");
    child_pid = events.pid;
  }
  DptySessionStatsV1 final_stats = {};
  final_stats.struct_size = sizeof(final_stats);
  final_stats.abi_version = DPTY_ABI_VERSION;
  Expect(api->stats(session, &final_stats) == DPTY_STATUS_OK,
         "final stats are readable");
  Expect(final_stats.bytes_read >= 10 * 1024 * 1024,
         "final stats include burst output");
  Expect(final_stats.write_backpressure_rejections == 1,
         "write backpressure is counted");
  Expect(final_stats.max_write_queued_bytes <= 64 * 1024,
         "write queue remains bounded");
  Expect(final_stats.has_exited == 1, "stats report exit");
  DptyProcessSnapshotV1 exited_snapshot = {};
  exited_snapshot.struct_size = sizeof(exited_snapshot);
  exited_snapshot.abi_version = DPTY_ABI_VERSION;
  Expect(api->process_snapshot(session, &exited_snapshot) == DPTY_STATUS_OK &&
             exited_snapshot.has_exited == 1 &&
             exited_snapshot.child_process_group == 0 &&
             exited_snapshot.foreground_process_group == 0 &&
             exited_snapshot.child_process_group_error == ENXIO &&
             exited_snapshot.foreground_process_group_error == ENXIO &&
             exited_snapshot.terminal_echo_enabled == 0 &&
             exited_snapshot.terminal_attributes_error == ENXIO,
         "exited snapshot is content-free and unavailable");
  Expect(api->destroy(session) == DPTY_STATUS_OK,
         "finished session is destroyed");
  const uint8_t byte = 0;
  Expect(api->write(session, &byte, 1) == DPTY_STATUS_INVALID_HANDLE,
         "destroyed generation is stale");
  Expect(api->process_snapshot(session, &exited_snapshot) ==
             DPTY_STATUS_INVALID_HANDLE,
         "destroyed process snapshot generation is stale");
  errno = 0;
  Expect(waitpid(static_cast<pid_t>(child_pid), nullptr, WNOHANG) == -1 &&
             errno == ECHILD,
         "child was reaped by its owning session");
}

void TestExecFailure(Api* api) {
  Events events;
  events.api = api;
  const std::vector<const char*> arguments = {"missing"};
  const DptySessionHandle session =
      Create(api, &events, "/definitely/missing/dpty", arguments);
  Expect(api->start(session) == DPTY_STATUS_OK,
         "exec failure remains asynchronous");
  Expect(WaitFor(&events, std::chrono::seconds(3),
                 [](const Events& value) { return value.failed; }),
         "exec failure event arrives");
  {
    const std::lock_guard<std::mutex> lock(events.mutex);
    Expect(events.system_error == ENOENT, "exec errno is preserved");
  }
  Expect(api->destroy(session) == DPTY_STATUS_OK,
         "failed session can be destroyed");
}

void TestGracefulClose(Api* api) {
  Events events;
  events.api = api;
  const std::vector<const char*> arguments = {
      "sh", "-c",
      "trap 'exit 23' HUP; echo __DPTY_HUP_READY__; while :; do sleep 1; "
      "done"};
  const DptySessionHandle session = Create(api, &events, "/bin/sh", arguments);
  Expect(api->start(session) == DPTY_STATUS_OK, "HUP-aware child starts");
  Expect(WaitForMarker(&events, "__DPTY_HUP_READY__", std::chrono::seconds(3)),
         "HUP-aware child installed its trap");
  Expect(api->close(session, 1000) == DPTY_STATUS_OK,
         "graceful close is queued");
  Expect(WaitFor(&events, std::chrono::seconds(3),
                 [](const Events& value) { return value.exited; }),
         "graceful close reaps the child");
  {
    const std::lock_guard<std::mutex> lock(events.mutex);
    Expect(events.exit_code == 23 && events.exit_signal == 0,
           "SIGHUP trap exits before escalation");
  }
  Expect(api->destroy(session) == DPTY_STATUS_OK,
         "gracefully closed session is destroyed");
}

void TestForcedClose(Api* api) {
  Events events;
  events.api = api;
  const std::vector<const char*> arguments = {
      "sh", "-c",
      "trap '' HUP TERM; echo __DPTY_STUBBORN__; while :; do sleep 1; done"};
  const DptySessionHandle session = Create(api, &events, "/bin/sh", arguments);
  Expect(api->start(session) == DPTY_STATUS_OK, "stubborn child starts");
  Expect(WaitFor(&events, std::chrono::seconds(3),
                 [](const Events& value) { return value.started; }),
         "stubborn child started event");
  Expect(WaitForMarker(&events, "__DPTY_STUBBORN__", std::chrono::seconds(3)),
         "stubborn child installed its signal handlers");
  Expect(api->close(session, 50) == DPTY_STATUS_OK, "bounded close is queued");
  Expect(WaitFor(&events, std::chrono::seconds(4),
                 [](const Events& value) { return value.exited; }),
         "forced close reaps stubborn child");
  {
    const std::lock_guard<std::mutex> lock(events.mutex);
    Expect(events.exit_signal == SIGKILL && events.exit_code == 128 + SIGKILL,
           "close escalates to SIGKILL after grace");
  }
  Expect(api->destroy(session) == DPTY_STATUS_OK,
         "forced-close session is destroyed");
}

void TestExplicitForceClose(Api* api) {
  Events events;
  events.api = api;
  const std::vector<const char*> arguments = {
      "sh", "-c",
      "trap '' HUP TERM; echo __DPTY_FORCE_READY__; while :; do sleep 1; "
      "done"};
  const DptySessionHandle session = Create(api, &events, "/bin/sh", arguments);
  Expect(api->start(session) == DPTY_STATUS_OK, "explicit-force child starts");
  Expect(
      WaitForMarker(&events, "__DPTY_FORCE_READY__", std::chrono::seconds(3)),
      "explicit-force child installed its signal handlers");
  Expect(api->close(session, 60000) == DPTY_STATUS_OK,
         "long graceful close is queued");
  const Clock::time_point force_started = Clock::now();
  Expect(api->force_close(session) == DPTY_STATUS_OK,
         "force close is accepted while closing");
  Expect(api->force_close(session) == DPTY_STATUS_OK,
         "force close is idempotent while closing");
  Expect(WaitFor(&events, std::chrono::seconds(3),
                 [](const Events& value) { return value.exited; }),
         "explicit force close reaps stubborn child");
  Expect(Clock::now() - force_started < std::chrono::seconds(2),
         "explicit force bypasses the graceful deadline");
  {
    const std::lock_guard<std::mutex> lock(events.mutex);
    Expect(events.exit_signal == SIGKILL && events.exit_code == 128 + SIGKILL,
           "explicit force close reports SIGKILL");
  }
  Expect(api->force_close(session) == DPTY_STATUS_OK,
         "force close accepts an already-finished session");
  Expect(api->destroy(session) == DPTY_STATUS_OK,
         "explicit-force session is destroyed");
}

void TestDirectForceClose(Api* api) {
  Events events;
  events.api = api;
  const std::vector<const char*> arguments = {"sh", "-c",
                                              "while :; do sleep 1; done"};
  const DptySessionHandle session = Create(api, &events, "/bin/sh", arguments);
  Expect(api->start(session) == DPTY_STATUS_OK, "direct-force child starts");
  Expect(WaitFor(&events, std::chrono::seconds(3),
                 [](const Events& value) { return value.started; }),
         "direct-force child started event");
  Expect(api->force_close(session) == DPTY_STATUS_OK,
         "force close is accepted before graceful close");
  Expect(WaitFor(&events, std::chrono::seconds(3),
                 [](const Events& value) { return value.exited; }),
         "direct force close reaps child");
  {
    const std::lock_guard<std::mutex> lock(events.mutex);
    Expect(events.exit_signal == SIGKILL && events.exit_code == 128 + SIGKILL,
           "direct force close reports SIGKILL");
  }
  Expect(api->destroy(session) == DPTY_STATUS_OK,
         "direct-force session is destroyed");
}

void TestTrackedWriteDiagnostics(Api* api) {
  Events events;
  events.api = api;
  const std::vector<const char*> arguments = {"cat"};
  const DptySessionHandle session =
      Create(api, &events, "/bin/cat", arguments, 256 * 1024, 128 * 1024,
             64 * 1024, true);
  Expect(api->start(session) == DPTY_STATUS_OK, "diagnostic child starts");
  Expect(WaitFor(&events, std::chrono::seconds(3),
                 [](const Events& value) { return value.started; }),
         "diagnostic child reports start");

  const uint8_t byte = 'd';
  Expect(api->write_tracked(session, &byte, 1, nullptr) ==
             DPTY_STATUS_INVALID_ARGUMENT,
         "tracked write requires an output ID");
  std::vector<uint8_t> oversized(64 * 1024 + 1, 'd');
  uint64_t rejected_request_id = 99;
  Expect(
      api->write_tracked(session, oversized.data(), oversized.size(),
                         &rejected_request_id) == DPTY_STATUS_BACKPRESSURED &&
          rejected_request_id == 0,
      "rejected tracked write clears its request ID");

  uint64_t request_id = 0;
  Expect(api->write_tracked(session, &byte, 1, &request_id) == DPTY_STATUS_OK &&
             request_id != 0,
         "tracked write returns an opaque request ID");
  Expect(WaitForDiagnostic(&events, DPTY_EVENT_WRITE_COMPLETED,
                           std::chrono::seconds(3)),
         "tracked write reaches native completion");
  Expect(api->force_close(session) == DPTY_STATUS_OK,
         "diagnostic force close is accepted");
  Expect(WaitFor(&events, std::chrono::seconds(3),
                 [](const Events& value) { return value.exited; }),
         "diagnostic force close exits");
  {
    const std::lock_guard<std::mutex> lock(events.mutex);
    for (const uint32_t type : {
             DPTY_EVENT_WRITE_ENQUEUED,
             DPTY_EVENT_WRITE_DEQUEUED,
             DPTY_EVENT_WRITE_COMPLETED,
             DPTY_EVENT_STATE_SNAPSHOT,
             DPTY_EVENT_TERMIOS_SNAPSHOT,
             DPTY_EVENT_FORCE_CLOSE_DEQUEUED,
             DPTY_EVENT_SIGNAL_DELIVERY,
             DPTY_EVENT_WAITPID_RESULT,
             DPTY_EVENT_PROCESS_EXIT_READY,
             DPTY_EVENT_EXIT_PUBLISHED,
         }) {
      Expect(HasDiagnosticLocked(events, type),
             "required privacy-safe diagnostic stage is emitted");
    }
    for (const Diagnostic& diagnostic : events.diagnostics) {
      if (diagnostic.type == DPTY_EVENT_WRITE_ENQUEUED ||
          diagnostic.type == DPTY_EVENT_WRITE_DEQUEUED ||
          diagnostic.type == DPTY_EVENT_WRITE_COMPLETED) {
        Expect(diagnostic.sequence == request_id,
               "tracked write diagnostic preserves request identity");
      }
    }
    const auto termios =
        std::find_if(events.diagnostics.begin(), events.diagnostics.end(),
                     [](const Diagnostic& value) {
                       return value.type == DPTY_EVENT_TERMIOS_SNAPSHOT;
                     });
    Expect(termios != events.diagnostics.end() && termios->value2 == 1 &&
               termios->length == 4,
           "termios snapshot records the default VEOF identity");
    const auto signal =
        std::find_if(events.diagnostics.begin(), events.diagnostics.end(),
                     [](const Diagnostic& value) {
                       return value.type == DPTY_EVENT_SIGNAL_DELIVERY &&
                              value.length == SIGKILL;
                     });
    Expect(signal != events.diagnostics.end() && signal->value1 != 0 &&
               signal->value2 == 0 && signal->system_error == 0,
           "signal diagnostic records the successful kill target");
  }
  Expect(api->destroy(session) == DPTY_STATUS_OK,
         "diagnostic session is destroyed");
}

void TestForceCloseFairnessUnderOutputFlood(Api* api) {
  Events events;
  events.api = api;
  events.retain_output = false;
  const std::vector<const char*> arguments = {"yes", "x"};
  const DptySessionHandle session =
      Create(api, &events, "/usr/bin/yes", arguments, 1024 * 1024, 512 * 1024,
             64 * 1024, true);
  Expect(api->start(session) == DPTY_STATUS_OK, "output-flood child starts");
  Expect(WaitFor(&events, std::chrono::seconds(3),
                 [](const Events& value) { return value.started; }),
         "output-flood child reports start");
  std::this_thread::sleep_for(std::chrono::milliseconds(100));

  const uint8_t control_d = 0x04;
  uint64_t request_id = 0;
  Expect(api->write_tracked(session, &control_d, 1, &request_id) ==
                 DPTY_STATUS_OK &&
             request_id != 0,
         "tracked Control-D is accepted during an output flood");
  const Clock::time_point force_started = Clock::now();
  Expect(api->force_close(session) == DPTY_STATUS_OK,
         "force close is accepted during an output flood");
  const bool exited = WaitFor(&events, std::chrono::seconds(2),
                              [](const Events& value) { return value.exited; });
  if (!exited) {
    pid_t pid = -1;
    {
      const std::lock_guard<std::mutex> lock(events.mutex);
      pid = static_cast<pid_t>(events.pid);
    }
    if (pid > 0) {
      (void)kill(-pid, SIGKILL);
      (void)kill(pid, SIGKILL);
    }
    (void)WaitFor(&events, std::chrono::seconds(2),
                  [](const Events& value) { return value.exited; });
  }
  Expect(exited && Clock::now() - force_started < std::chrono::seconds(2),
         "bounded read turns preserve force-close fairness under output flood");
  Expect(WaitForDiagnostic(&events, DPTY_EVENT_FORCE_CLOSE_DEQUEUED,
                           std::chrono::seconds(1)),
         "reactor dequeues force close during output flood");
  Expect(api->destroy(session) == DPTY_STATUS_OK,
         "output-flood session is destroyed");
}

void TestExternalReapCompletion(Api* api) {
  Events events;
  events.api = api;
  const std::vector<const char*> arguments = {
      "sh", "-c",
      "printf __DPTY_EXTERNAL_REAP_READY__; read value; sleep 0.2; exit 37"};
  const DptySessionHandle session =
      Create(api, &events, "/bin/sh", arguments, 256 * 1024, 128 * 1024,
             64 * 1024, true);
  Expect(api->start(session) == DPTY_STATUS_OK, "external-reap child starts");
  Expect(WaitForMarker(&events, "__DPTY_EXTERNAL_REAP_READY__",
                       std::chrono::seconds(3)),
         "external-reap child is ready");
  pid_t child = -1;
  {
    const std::lock_guard<std::mutex> lock(events.mutex);
    child = static_cast<pid_t>(events.pid);
  }
  pid_t externally_reaped_pid = -1;
  int externally_reaped_status = 0;
  int external_reap_error = 0;
  std::thread external_reaper([&] {
    errno = 0;
    externally_reaped_pid = waitpid(child, &externally_reaped_status, 0);
    external_reap_error = externally_reaped_pid < 0 ? errno : 0;
  });
  const uint8_t newline = '\n';
  Expect(api->write(session, &newline, 1) == DPTY_STATUS_OK,
         "external-reap child exit is released");
  const bool exited = WaitFor(&events, std::chrono::seconds(3),
                              [](const Events& value) { return value.exited; });
  external_reaper.join();
  Expect(exited, "external reap still publishes child exit");
  {
    const std::lock_guard<std::mutex> lock(events.mutex);
    Expect(externally_reaped_pid == events.pid && external_reap_error == 0,
           "test competitor reaps the exact PTY child");
    Expect(events.exit_code == 37 && events.exit_signal == 0,
           "kernel exit status preserves external normal exit");
    const auto ready =
        std::find_if(events.diagnostics.begin(), events.diagnostics.end(),
                     [](const Diagnostic& value) {
                       return value.type == DPTY_EVENT_PROCESS_EXIT_READY;
                     });
    Expect(ready != events.diagnostics.end() && ready->length == 1 &&
               ready->value2 == externally_reaped_status,
           "NOTE_EXITSTATUS matches the externally reaped wait status");
    const auto external =
        std::find_if(events.diagnostics.begin(), events.diagnostics.end(),
                     [](const Diagnostic& value) {
                       return value.type == DPTY_EVENT_EXTERNAL_REAP_OBSERVED;
                     });
    Expect(external != events.diagnostics.end() &&
               external->value1 == events.pid &&
               external->value2 == externally_reaped_status &&
               external->system_error == ECHILD,
           "external reap is explicitly classified from matching kernel data");
  }
  Expect(api->destroy(session) == DPTY_STATUS_OK,
         "externally reaped session is destroyed");
}

void TestExternalReapSignalCompletion(Api* api) {
  Events events;
  events.api = api;
  const std::vector<const char*> arguments = {
      "sh", "-c",
      "printf __DPTY_EXTERNAL_SIGNAL_READY__; read value; sleep 0.2; "
      "kill -TERM $$"};
  const DptySessionHandle session =
      Create(api, &events, "/bin/sh", arguments, 256 * 1024, 128 * 1024,
             64 * 1024, true);
  Expect(api->start(session) == DPTY_STATUS_OK,
         "external-reap signal child starts");
  Expect(WaitForMarker(&events, "__DPTY_EXTERNAL_SIGNAL_READY__",
                       std::chrono::seconds(3)),
         "external-reap signal child is ready");
  pid_t child = -1;
  {
    const std::lock_guard<std::mutex> lock(events.mutex);
    child = static_cast<pid_t>(events.pid);
  }
  pid_t externally_reaped_pid = -1;
  int externally_reaped_status = 0;
  int external_reap_error = 0;
  std::thread external_reaper([&] {
    errno = 0;
    externally_reaped_pid = waitpid(child, &externally_reaped_status, 0);
    external_reap_error = externally_reaped_pid < 0 ? errno : 0;
  });
  const uint8_t newline = '\n';
  Expect(api->write(session, &newline, 1) == DPTY_STATUS_OK,
         "external-reap signal exit is released");
  const bool exited = WaitFor(&events, std::chrono::seconds(3),
                              [](const Events& value) { return value.exited; });
  external_reaper.join();
  Expect(exited, "external signal reap still publishes child exit");
  {
    const std::lock_guard<std::mutex> lock(events.mutex);
    Expect(externally_reaped_pid == events.pid && external_reap_error == 0,
           "test competitor reaps the signaled PTY child");
    Expect(WIFSIGNALED(externally_reaped_status) &&
               WTERMSIG(externally_reaped_status) == SIGTERM,
           "external waiter observes the expected terminating signal");
    Expect(events.exit_code == 128 + SIGTERM && events.exit_signal == SIGTERM,
           "kernel exit status preserves external signal exit");
    const auto external =
        std::find_if(events.diagnostics.begin(), events.diagnostics.end(),
                     [](const Diagnostic& value) {
                       return value.type == DPTY_EVENT_EXTERNAL_REAP_OBSERVED;
                     });
    Expect(external != events.diagnostics.end() &&
               external->value2 == externally_reaped_status &&
               external->system_error == ECHILD,
           "external signal reap retains matching kernel status");
  }
  Expect(api->destroy(session) == DPTY_STATUS_OK,
         "externally reaped signal session is destroyed");
}

}  // namespace

int main(int argc, const char* argv[]) {
  if (argc != 2) {
    std::cerr << "usage: pty_capability_tests <libdart_pty_macos.dylib>\n";
    return 64;
  }
  void* image = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (image == nullptr) {
    std::cerr << "Could not load PTY capability: " << dlerror() << '\n';
    return 1;
  }
  Api api;
  api.version = Lookup<decltype(api.version)>(image, "dpty_abi_version");
  api.create = Lookup<decltype(api.create)>(image, "dpty_session_create");
  api.start = Lookup<decltype(api.start)>(image, "dpty_session_start");
  api.write = Lookup<decltype(api.write)>(image, "dpty_session_write");
  api.write_tracked =
      Lookup<decltype(api.write_tracked)>(image, "dpty_session_write_tracked");
  api.ack = Lookup<decltype(api.ack)>(image, "dpty_session_ack_output");
  api.resize = Lookup<decltype(api.resize)>(image, "dpty_session_resize");
  api.send_signal =
      Lookup<decltype(api.send_signal)>(image, "dpty_session_send_signal");
  api.close = Lookup<decltype(api.close)>(image, "dpty_session_close");
  api.force_close =
      Lookup<decltype(api.force_close)>(image, "dpty_session_force_close");
  api.stats = Lookup<decltype(api.stats)>(image, "dpty_session_get_stats");
  api.process_snapshot = Lookup<decltype(api.process_snapshot)>(
      image, "dpty_session_get_process_snapshot");
  api.destroy = Lookup<decltype(api.destroy)>(image, "dpty_session_destroy");
  api.live_count =
      Lookup<decltype(api.live_count)>(image, "dpty_debug_live_session_count");
  Expect(api.version() == DPTY_ABI_VERSION, "PTY ABI version");

  DptySessionConfigV1 invalid = {};
  DptySessionHandle invalid_handle = 99;
  Expect(
      api.create(&invalid, &invalid_handle) == DPTY_STATUS_INVALID_ARGUMENT &&
          invalid_handle == 0,
      "invalid configuration is rejected before allocation");
  TestInteractiveSession(&api);
  TestReadBatchConfiguration(&api);
  TestExecFailure(&api);
  TestGracefulClose(&api);
  TestForcedClose(&api);
  TestExplicitForceClose(&api);
  TestDirectForceClose(&api);
  TestTrackedWriteDiagnostics(&api);
  TestForceCloseFairnessUnderOutputFlood(&api);
  TestExternalReapCompletion(&api);
  TestExternalReapSignalCompletion(&api);
  Expect(api.live_count() == 0, "all native sessions are released");
  dlclose(image);
  if (failures != 0) {
    return 1;
  }
  std::cout << "macOS PTY capability contract passed\n";
  return 0;
}
