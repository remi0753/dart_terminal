#ifndef DART_TERMINAL_RUNTIME_RUNTIME_LIFECYCLE_BRIDGE_H_
#define DART_TERMINAL_RUNTIME_RUNTIME_LIFECYCLE_BRIDGE_H_

#include <stdint.h>

#if defined(__cplusplus)
extern "C" {
#endif

__attribute__((visibility("default"))) uint32_t
dt_runtime_lifecycle_abi_version(void);

__attribute__((visibility("default"))) int32_t
dt_runtime_lifecycle_set_exit_code(int32_t exit_code);

__attribute__((visibility("default"))) int32_t
dt_runtime_lifecycle_request_termination(int32_t exit_code);

#if defined(__cplusplus)
}
#endif

#if defined(__cplusplus)

namespace dart_terminal {

inline constexpr uint32_t kRuntimeLifecycleAbiVersion = 1;
inline constexpr int kRuntimeUsageExitCode = 64;
inline constexpr int kRuntimeInputExitCode = 66;
inline constexpr int kRuntimeSoftwareExitCode = 70;
inline constexpr int kRuntimeTemporaryFailureExitCode = 75;

bool RuntimeLifecycleShouldFailHostStartup();
int RuntimeLifecycleEffectiveExitCode(int delegate_exit_code);
void RuntimeLifecycleCompleteApplicationTermination(int delegate_exit_code);

}  // namespace dart_terminal

#endif  // defined(__cplusplus)

#endif  // DART_TERMINAL_RUNTIME_RUNTIME_LIFECYCLE_BRIDGE_H_
