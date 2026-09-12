#ifndef DART_TERMINAL_APP_INTENTS_MACOS_NATIVE_TERMINAL_APP_INTENTS_H_
#define DART_TERMINAL_APP_INTENTS_MACOS_NATIVE_TERMINAL_APP_INTENTS_H_

#include <stdint.h>

#define DTAI_ABI_VERSION 1u
#define DTAI_MAX_PENDING_COMMANDS 16u
#define DTAI_DEFAULT_TIMEOUT_MICROS (30u * 1000u * 1000u)
#define DTAI_MAX_TIMEOUT_MICROS (300u * 1000u * 1000u)

typedef enum DtaiStatus {
  DTAI_STATUS_OK = 0,
  DTAI_STATUS_INVALID_ARGUMENT = 1,
  DTAI_STATUS_UNSUPPORTED_VERSION = 2,
  DTAI_STATUS_NOT_INITIALIZED = 3,
  DTAI_STATUS_ALREADY_STARTED = 4,
  DTAI_STATUS_NOT_FOUND = 5,
  DTAI_STATUS_RESOURCE_EXHAUSTED = 6,
  DTAI_STATUS_WRONG_THREAD = 7,
  DTAI_STATUS_DISABLED = 8,
  DTAI_STATUS_STALE_GENERATION = 9,
  DTAI_STATUS_INTERNAL = 10,
} DtaiStatus;

typedef enum DtaiAction {
  DTAI_ACTION_NEW_WINDOW = 1,
  DTAI_ACTION_NEW_TAB = 2,
  DTAI_ACTION_TOGGLE_QUICK_TERMINAL = 3,
} DtaiAction;

typedef enum DtaiCommandDisposition {
  DTAI_COMMAND_COMPLETED = 0,
  DTAI_COMMAND_REJECTED = 1,
  DTAI_COMMAND_FAILED = 2,
} DtaiCommandDisposition;

#if defined(__cplusplus)
extern "C" {
#endif

__attribute__((visibility("default"))) uint32_t dtai_abi_version(void);

__attribute__((visibility("default"))) int32_t
dtai_session_start(uint32_t maximum_pending_commands, uint64_t timeout_micros);

__attribute__((visibility("default"))) int32_t
dtai_session_set_enabled(uint32_t enabled);

__attribute__((visibility("default"))) int32_t dtai_take_command(
    uint64_t* operation_id, uint64_t* generation, uint32_t* action);

__attribute__((visibility("default"))) int32_t dtai_complete_command(
    uint64_t operation_id, uint64_t generation, uint32_t disposition);

__attribute__((visibility("default"))) int32_t dtai_session_shutdown(void);

__attribute__((visibility("default"))) int32_t dtai_debug_summary(
    uint64_t* generation, uint64_t* queued_command_count,
    uint64_t* pending_command_count, uint64_t* accepted_command_count,
    uint64_t* resolved_command_count, uint64_t* rejected_command_count,
    uint64_t* timed_out_command_count, uint32_t* started, uint32_t* enabled);

// In-process deterministic acceptance seam. It admits the same closed action
// through the same bounded queue as AppIntent.perform(), without invoking Siri,
// Shortcuts, or any user-owned automation.
__attribute__((visibility("default"))) int32_t
dtai_debug_enqueue_action(uint32_t action);

#if defined(__cplusplus)
}
#endif

#endif  // DART_TERMINAL_APP_INTENTS_MACOS_NATIVE_TERMINAL_APP_INTENTS_H_
