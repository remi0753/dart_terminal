#import <AppKit/AppKit.h>

#include "RuntimeLifecycleBridge.h"

#include <pthread.h>

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace dart_terminal {
namespace {

std::atomic<int32_t> requested_exit_code{0};
std::atomic<bool> termination_requested{false};

bool IsAllowedExitCode(int32_t exit_code) {
  switch (exit_code) {
    case kRuntimeUsageExitCode:
    case kRuntimeSoftwareExitCode:
    case kRuntimeTemporaryFailureExitCode:
      return true;
    default:
      return false;
  }
}

int32_t RecordExitCode(int32_t exit_code) {
  if (pthread_main_np() == 0) {
    return 1;
  }
  if (!IsAllowedExitCode(exit_code)) {
    return 2;
  }
  int32_t expected = 0;
  if (requested_exit_code.compare_exchange_strong(expected, exit_code,
                                                  std::memory_order_acq_rel)) {
    return 0;
  }
  return expected == exit_code ? 0 : 3;
}

}  // namespace

bool RuntimeLifecycleShouldFailHostStartup() {
  const char* value = std::getenv("DT_RUNTIME_TEST_HOST_STARTUP_FAILURE");
  return value != nullptr && std::strcmp(value, "1") == 0;
}

int RuntimeLifecycleEffectiveExitCode(int delegate_exit_code) {
  if (delegate_exit_code != 0) {
    return delegate_exit_code;
  }
  return requested_exit_code.load(std::memory_order_acquire);
}

void RuntimeLifecycleCompleteApplicationTermination(int delegate_exit_code) {
  const int exit_code = RuntimeLifecycleEffectiveExitCode(delegate_exit_code);
  if (exit_code != 0) {
    std::fflush(nullptr);
    std::_Exit(exit_code);
  }
}

}  // namespace dart_terminal

extern "C" uint32_t dt_runtime_lifecycle_abi_version(void) {
  return dart_terminal::kRuntimeLifecycleAbiVersion;
}

extern "C" int32_t dt_runtime_lifecycle_set_exit_code(int32_t exit_code) {
  return dart_terminal::RecordExitCode(exit_code);
}

extern "C" int32_t dt_runtime_lifecycle_request_termination(int32_t exit_code) {
  const int32_t result = dart_terminal::RecordExitCode(exit_code);
  if (result != 0) {
    return result;
  }
  bool expected = false;
  if (dart_terminal::termination_requested.compare_exchange_strong(
          expected, true, std::memory_order_acq_rel)) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [NSApp terminate:nil];
    });
  }
  return 0;
}
