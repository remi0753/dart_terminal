#ifndef DART_TERMINAL_RUNTIME_RUNTIME_DIAGNOSTICS_H_
#define DART_TERMINAL_RUNTIME_RUNTIME_DIAGNOSTICS_H_

#include <stdint.h>

#define DT_RUNTIME_DIAGNOSTICS_ABI_VERSION 1u

#define DT_RUNTIME_DIAGNOSTIC_PHASE_ROOT_STARTING 1u
#define DT_RUNTIME_DIAGNOSTIC_PHASE_ROOT_READY 2u
#define DT_RUNTIME_DIAGNOSTIC_PHASE_SHUTDOWN_STARTED 3u
#define DT_RUNTIME_DIAGNOSTIC_PHASE_ROOT_STOPPED 4u

#define DT_RUNTIME_DIAGNOSTICS_OK 0
#define DT_RUNTIME_DIAGNOSTICS_NOT_STARTED 1
#define DT_RUNTIME_DIAGNOSTICS_WRONG_THREAD 2
#define DT_RUNTIME_DIAGNOSTICS_INVALID_PHASE 3
#define DT_RUNTIME_DIAGNOSTICS_PHASE_REGRESSION 4
#define DT_RUNTIME_DIAGNOSTICS_ALREADY_FINISHED 5

#if defined(__cplusplus)
extern "C" {
#endif

__attribute__((visibility("default"))) uint32_t
dt_runtime_diagnostics_abi_version(void);

__attribute__((visibility("default"))) int32_t
dt_runtime_diagnostics_record_phase(uint32_t phase);

#if defined(__cplusplus)
}
#endif

#if defined(__cplusplus)

#include <cstddef>
#include <string>

namespace dart_terminal {

inline constexpr const char* kRuntimeDiagnosticsSubsystem = "dev.dart-terminal";
inline constexpr const char* kRuntimeDiagnosticsFormat =
    "dart-terminal-local-run-metadata";
inline constexpr uint32_t kRuntimeDiagnosticsFormatVersion = 1;
inline constexpr size_t kRuntimeDiagnosticsMaximumBytes = 16 * 1024;

enum class RuntimeDiagnosticLogLevel : uint32_t {
  kInfo = 1,
  kError = 2,
  kFault = 3,
};

enum class RuntimeDiagnosticLogEvent : uint32_t {
  kSessionStarted = 1,
  kPhaseChanged = 2,
  kPreviousUncleanRun = 3,
  kInvalidPriorMetadata = 4,
  kPersistenceFailed = 5,
  kSessionFinished = 6,
};

using RuntimeDiagnosticLogObserver = void (*)(RuntimeDiagnosticLogLevel level,
                                              RuntimeDiagnosticLogEvent event,
                                              void* context);

struct RuntimeDiagnosticsOptions {
  std::string runtime_mode;
  std::string architecture;
  std::string bundle_identifier;
  std::string application_version;
  std::string dart_sdk_revision;
  std::string metadata_directory;
  bool strict_persistence = false;
};

class RuntimeDiagnosticsSession final {
 public:
  RuntimeDiagnosticsSession() = default;
  ~RuntimeDiagnosticsSession();

  bool Start(const RuntimeDiagnosticsOptions& options, std::string* out_error);
  int32_t RecordPhase(uint32_t phase);
  bool Finish(int32_t exit_code);

  bool started() const { return started_; }
  bool finished() const { return finished_; }
  bool persistence_healthy() const { return persistence_healthy_; }
  const std::string& metadata_directory() const { return metadata_directory_; }
  const std::string& launch_id() const { return launch_id_; }

  RuntimeDiagnosticsSession(const RuntimeDiagnosticsSession&) = delete;
  RuntimeDiagnosticsSession& operator=(const RuntimeDiagnosticsSession&) =
      delete;

 private:
  bool PersistCurrentRecord();

  std::string runtime_mode_;
  std::string architecture_;
  std::string bundle_identifier_;
  std::string application_version_;
  std::string dart_sdk_revision_;
  std::string metadata_directory_;
  std::string launch_id_;
  std::string started_at_;
  std::string updated_at_;
  std::string outcome_ = "running";
  uint32_t phase_ = 0;
  int32_t exit_code_ = 0;
  bool has_exit_code_ = false;
  bool strict_persistence_ = false;
  bool persistence_healthy_ = true;
  bool started_ = false;
  bool finished_ = false;
};

bool RuntimeDiagnosticsOptionsForCurrentProcess(
    const char* runtime_mode, RuntimeDiagnosticsOptions* out_options,
    std::string* out_error);

bool RuntimeDiagnosticsFinishActiveSession(int32_t exit_code);
int32_t RuntimeDiagnosticsRecordActivePhase(uint32_t phase);

void SetRuntimeDiagnosticsLogObserverForTesting(
    RuntimeDiagnosticLogObserver observer, void* context);

}  // namespace dart_terminal

#endif  // defined(__cplusplus)

#endif  // DART_TERMINAL_RUNTIME_RUNTIME_DIAGNOSTICS_H_
