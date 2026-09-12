#ifndef DART_TERMINAL_APPLESCRIPT_MACOS_NATIVE_TERMINAL_APPLE_SCRIPT_PLUGIN_H_
#define DART_TERMINAL_APPLESCRIPT_MACOS_NATIVE_TERMINAL_APPLE_SCRIPT_PLUGIN_H_

#include <stddef.h>
#include <stdint.h>

#include "dart_appkit_native_extension.h"

#define DTAS_ABI_VERSION 1u
#define DTAS_SNAPSHOT_VERSION 1u
#define DTAS_COMMAND_VERSION 1u
#define DTAS_SUMMARY_VERSION 1u
#define DTAS_MAX_WINDOWS 32u
#define DTAS_MAX_TABS_PER_WINDOW 64u
#define DTAS_MAX_TERMINALS 64u
#define DTAS_MAX_PENDING_COMMANDS 16u
#define DTAS_MAX_SNAPSHOT_BYTES (4u * 1024u * 1024u)
#define DTAS_MAX_COMMAND_BYTES (64u * 1024u * 1024u + 4096u)
#define DTAS_MAX_OBJECT_ID_BYTES 63u
#define DTAS_DEFAULT_TIMEOUT_MICROS (30u * 1000u * 1000u)
#define DTAS_MAX_TIMEOUT_MICROS (300u * 1000u * 1000u)

typedef enum DtasStatus {
  DTAS_STATUS_OK = 0,
  DTAS_STATUS_INVALID_ARGUMENT = 1,
  DTAS_STATUS_UNSUPPORTED_VERSION = 2,
  DTAS_STATUS_NOT_INITIALIZED = 3,
  DTAS_STATUS_ALREADY_STARTED = 4,
  DTAS_STATUS_NOT_FOUND = 5,
  DTAS_STATUS_RESOURCE_EXHAUSTED = 6,
  DTAS_STATUS_BUFFER_TOO_SMALL = 7,
  DTAS_STATUS_WRONG_THREAD = 8,
  DTAS_STATUS_DISABLED = 9,
  DTAS_STATUS_INTERNAL = 10,
} DtasStatus;

typedef enum DtasCommandDisposition {
  DTAS_COMMAND_COMPLETED = 0,
  DTAS_COMMAND_CONFIRMATION_REQUIRED = 1,
  DTAS_COMMAND_DISABLED = 2,
  DTAS_COMMAND_NOT_FOUND = 3,
  DTAS_COMMAND_BUSY = 4,
  DTAS_COMMAND_REJECTED = 5,
  DTAS_COMMAND_FAILED = 6,
  DTAS_COMMAND_TIMED_OUT = 7,
  DTAS_COMMAND_DISPOSED = 8,
} DtasCommandDisposition;

typedef struct DtasSummaryV1 {
  uint32_t struct_size;
  uint32_t version;
  uint64_t generation;
  uint64_t window_count;
  uint64_t tab_count;
  uint64_t terminal_count;
  uint64_t queued_command_count;
  uint64_t pending_command_count;
  uint64_t resumed_command_count;
  uint64_t rejected_command_count;
  uint32_t started;
  uint32_t enabled;
  uint32_t reserved[4];
} DtasSummaryV1;

#if defined(__cplusplus)
extern "C" {
#endif

__attribute__((visibility("default"))) uint32_t dtas_abi_version(void);

__attribute__((visibility("default"))) int32_t dtas_initialize(
    const da_native_extension_services_v1* services);

__attribute__((visibility("default"))) int32_t dtas_session_start(
    uint32_t maximum_pending_commands, uint64_t timeout_micros);

__attribute__((visibility("default"))) int32_t dtas_publish_snapshot(
    const uint8_t* bytes, size_t length);

__attribute__((visibility("default"))) int32_t dtas_take_command(
    uint8_t* output, size_t capacity, size_t* output_length);

__attribute__((visibility("default"))) int32_t dtas_complete_command(
    uint64_t operation_id, uint32_t disposition, const uint8_t* object_id,
    size_t object_id_length);

__attribute__((visibility("default"))) int32_t dtas_session_shutdown(void);

__attribute__((visibility("default"))) int32_t dtas_debug_summary(
    DtasSummaryV1* summary);

__attribute__((visibility("default"))) int32_t
dtas_enqueue_self_automation_command(
    const uint8_t* bytes, size_t length);

#if defined(__cplusplus)
}
#endif

#endif
