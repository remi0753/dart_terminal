#ifndef DART_PTY_MACOS_NATIVE_DART_PTY_MACOS_H_
#define DART_PTY_MACOS_NATIVE_DART_PTY_MACOS_H_

#include <stddef.h>
#include <stdint.h>

#define DPTY_ABI_VERSION 6u

#if defined(__cplusplus)
extern "C" {
#endif

typedef uint64_t DptySessionHandle;

typedef enum DptyStatus {
  DPTY_STATUS_OK = 0,
  DPTY_STATUS_INVALID_ARGUMENT = 1,
  DPTY_STATUS_INVALID_HANDLE = 2,
  DPTY_STATUS_WRONG_STATE = 3,
  DPTY_STATUS_BACKPRESSURED = 4,
  DPTY_STATUS_SYSTEM_ERROR = 5,
  DPTY_STATUS_TIMED_OUT = 6,
} DptyStatus;

typedef enum DptyEventType {
  DPTY_EVENT_STARTED = 1,
  DPTY_EVENT_OUTPUT = 2,
  DPTY_EVENT_EXIT = 3,
  DPTY_EVENT_ERROR = 4,
  DPTY_EVENT_WRITE_ENQUEUED = 5,
  DPTY_EVENT_WRITE_DEQUEUED = 6,
  DPTY_EVENT_WRITE_COMPLETED = 7,
  DPTY_EVENT_WRITE_ERROR = 8,
  DPTY_EVENT_FORCE_CLOSE_DEQUEUED = 9,
  DPTY_EVENT_SIGNAL_DELIVERY = 10,
  DPTY_EVENT_WAITPID_RESULT = 11,
  DPTY_EVENT_EXIT_PUBLISHED = 12,
  DPTY_EVENT_STATE_SNAPSHOT = 13,
  DPTY_EVENT_TERMIOS_SNAPSHOT = 14,
  DPTY_EVENT_PROCESS_EXIT_READY = 15,
  DPTY_EVENT_EXTERNAL_REAP_OBSERVED = 16,
} DptyEventType;

typedef enum DptySessionStateFlag {
  DPTY_SESSION_STATE_CLOSING = 1u << 0,
  DPTY_SESSION_STATE_CLOSE_STARTED = 1u << 1,
  DPTY_SESSION_STATE_CHILD_REAPED = 1u << 2,
  DPTY_SESSION_STATE_MASTER_EOF = 1u << 3,
  DPTY_SESSION_STATE_READ_PAUSED = 1u << 4,
  DPTY_SESSION_STATE_READ_ENABLED = 1u << 5,
  DPTY_SESSION_STATE_WRITE_ENABLED = 1u << 6,
  DPTY_SESSION_STATE_CHILD_EXIT_OBSERVED = 1u << 7,
  DPTY_SESSION_STATE_CHILD_EXTERNALLY_REAPED = 1u << 8,
} DptySessionStateFlag;

typedef enum DptySignal {
  DPTY_SIGNAL_INTERRUPT = 1,
  DPTY_SIGNAL_SUSPEND = 2,
  DPTY_SIGNAL_QUIT = 3,
  DPTY_SIGNAL_HANGUP = 4,
  DPTY_SIGNAL_TERMINATE = 5,
  DPTY_SIGNAL_KILL = 6,
} DptySignal;

// OUTPUT data remains valid until its exact sequence/length pair is
// acknowledged. Other events have data=null. Diagnostic events are emitted
// only when DptySessionConfigV1.diagnostics_enabled is nonzero and never carry
// terminal content.
// STARTED: value1=child pid.
// EXIT: value1=portable exit code, value2=terminating signal or 0.
// ERROR: value1=DptyStatus, system_error=errno or 0.
// WRITE_ENQUEUED: sequence=request id, length=request bytes,
//   value1=total queued bytes.
// WRITE_DEQUEUED: sequence=request id, length=pending request bytes,
//   value1=total queued bytes.
// WRITE_COMPLETED: sequence=request id, length=request bytes,
//   value1=remaining queued bytes.
// WRITE_ERROR: sequence=request id, length=pending request bytes,
//   value1=total queued bytes, system_error=errno.
// FORCE_CLOSE_DEQUEUED: value1=total queued bytes.
// SIGNAL_DELIVERY: length=signal, value1=kill(2) target (negative for a process
//   group), value2=kill result, system_error=errno on failure.
// WAITPID_RESULT: value1=waitpid result, value2=child status when reaped,
//   system_error=errno on failure. A pending result is coalesced per trigger.
// EXIT_PUBLISHED: value1=portable exit code, value2=signal or 0.
// STATE_SNAPSHOT: sequence=related write request id or 0, length=queued bytes,
//   value1=foreground process group or -1, value2=DptySessionStateFlag bits,
//   system_error=tcgetpgrp errno on failure.
// TERMIOS_SNAPSHOT: sequence=related write request id or 0,
//   length=VEOF character value, value1=termios c_lflag, value2=1 when valid,
//   system_error=tcgetattr errno on failure.
// PROCESS_EXIT_READY: length=1 when value2 contains a valid kernel exit
//   status, value1=child pid, value2=kqueue NOTE_EXITSTATUS data.
// EXTERNAL_REAP_OBSERVED: value1=child pid, value2=the retained kernel exit
//   status used after waitpid returned ECHILD.
typedef void (*dpty_event_callback_v1)(DptySessionHandle session,
                                       uint32_t event_type, uint64_t sequence,
                                       const uint8_t* data, size_t length,
                                       int64_t value1, int64_t value2,
                                       int32_t system_error, void* context);

typedef struct DptySessionConfigV1 {
  size_t struct_size;
  uint32_t abi_version;
  const char* executable;
  const char* const* arguments;
  size_t argument_count;
  const char* const* environment;
  size_t environment_count;
  const char* working_directory;
  uint16_t initial_rows;
  uint16_t initial_columns;
  size_t read_high_water_bytes;
  size_t read_low_water_bytes;
  size_t write_capacity_bytes;
  dpty_event_callback_v1 callback;
  void* callback_context;
  uint32_t diagnostics_enabled;
  // Zero preserves the 64 KiB default. Nonzero values cap one OUTPUT event
  // without changing the aggregate read watermarks or ordered ACK contract.
  size_t read_batch_bytes;
  // Zero preserves existing delivery. Values 1..8 serialize native OUTPUT
  // batches and let the Dart facade yield after this many consumer callbacks.
  uint32_t read_batches_per_event_loop_turn;
} DptySessionConfigV1;

typedef struct DptySessionStatsV1 {
  size_t struct_size;
  uint32_t abi_version;
  uint64_t bytes_read;
  uint64_t bytes_written;
  uint64_t read_batches;
  uint64_t write_backpressure_rejections;
  uint64_t max_read_in_flight_bytes;
  uint64_t max_write_queued_bytes;
  uint64_t read_pause_count;
  int64_t child_pid;
  int32_t has_exited;
} DptySessionStatsV1;

// Content-free, same-call snapshot used for close/quit policy. Process names,
// arguments, environment, working directories, and terminal bytes are never
// inspected or returned. A nonzero per-field error leaves that process-group
// value or terminal attribute unavailable without failing the whole snapshot.
typedef struct DptyProcessSnapshotV1 {
  size_t struct_size;
  uint32_t abi_version;
  int64_t child_pid;
  int64_t child_process_group;
  int64_t foreground_process_group;
  int32_t child_process_group_error;
  int32_t foreground_process_group_error;
  int32_t has_exited;
  int32_t terminal_echo_enabled;
  int32_t terminal_attributes_error;
} DptyProcessSnapshotV1;

typedef struct DptyError {
  int32_t status;
  int32_t system_error;
  const char* message;
  size_t message_length;
} DptyError;

__attribute__((visibility("default"))) uint32_t dpty_abi_version(void);

__attribute__((visibility("default"))) int32_t dpty_session_create(
    const DptySessionConfigV1* config, DptySessionHandle* out_session);

// Starts the reactor and returns without waiting for fork, exec, or I/O.
__attribute__((visibility("default"))) int32_t
dpty_session_start(DptySessionHandle session);

// Copies accepted bytes into a bounded queue. Never waits for FD readiness.
__attribute__((visibility("default"))) int32_t dpty_session_write(
    DptySessionHandle session, const uint8_t* bytes, size_t length);

// The tracked variant also returns an opaque request ID which correlates the
// write diagnostic events. The ID is zero when the write is rejected.
__attribute__((visibility("default"))) int32_t
dpty_session_write_tracked(DptySessionHandle session, const uint8_t* bytes,
                           size_t length, uint64_t* out_request_id);

__attribute__((visibility("default"))) int32_t dpty_session_ack_output(
    DptySessionHandle session, uint64_t sequence, size_t length);

__attribute__((visibility("default"))) int32_t
dpty_session_resize(DptySessionHandle session, uint16_t rows, uint16_t columns);

// Sends the selected signal to the PTY foreground process group when known.
__attribute__((visibility("default"))) int32_t
dpty_session_send_signal(DptySessionHandle session, uint32_t signal);

// Requests SIGHUP immediately and SIGKILL after grace_period_millis.
__attribute__((visibility("default"))) int32_t
dpty_session_close(DptySessionHandle session, uint32_t grace_period_millis);

// Requests immediate SIGKILL escalation. Valid before or during graceful close,
// idempotent, and returns without waiting for process exit or reaping.
__attribute__((visibility("default"))) int32_t
dpty_session_force_close(DptySessionHandle session);

__attribute__((visibility("default"))) int32_t dpty_session_get_stats(
    DptySessionHandle session, DptySessionStatsV1* out_stats);

__attribute__((visibility("default"))) int32_t
dpty_session_get_process_snapshot(DptySessionHandle session,
                                  DptyProcessSnapshotV1* out_snapshot);

// Valid only after EXIT or ERROR and after all OUTPUT records are acknowledged.
__attribute__((visibility("default"))) int32_t
dpty_session_destroy(DptySessionHandle session);

__attribute__((visibility("default"))) int32_t
dpty_get_last_error(DptyError* out_error);

__attribute__((visibility("default"))) uint64_t
dpty_debug_live_session_count(void);

#if defined(__cplusplus)
}
#endif

#endif  // DART_PTY_MACOS_NATIVE_DART_PTY_MACOS_H_
