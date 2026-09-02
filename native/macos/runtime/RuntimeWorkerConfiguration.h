#ifndef DART_TERMINAL_NATIVE_MACOS_RUNTIME_RUNTIME_WORKER_CONFIGURATION_H_
#define DART_TERMINAL_NATIVE_MACOS_RUNTIME_RUNTIME_WORKER_CONFIGURATION_H_

#include <filesystem>
#include <optional>
#include <string>
#include <vector>

namespace dart_terminal {

// Validates a host-selected worker command and prepends its internal Dart
// application arguments. A kernel selects the SDK-executable launch mode;
// nullopt selects a self-contained worker executable.
bool PrependRuntimeWorkerConfiguration(
    const std::filesystem::path& executable,
    const std::optional<std::filesystem::path>& kernel,
    std::vector<std::string>* application_arguments, std::string* out_error);

}  // namespace dart_terminal

#endif  // DART_TERMINAL_NATIVE_MACOS_RUNTIME_RUNTIME_WORKER_CONFIGURATION_H_
