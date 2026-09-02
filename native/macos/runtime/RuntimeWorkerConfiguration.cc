#include "RuntimeWorkerConfiguration.h"

#include <unistd.h>

#include <string_view>
#include <system_error>
#include <utility>

namespace dart_terminal {
namespace {

constexpr std::string_view kRuntimeWorkerExecutablePrefix =
    "--runtime-worker-executable=";
constexpr std::string_view kRuntimeWorkerKernelPrefix =
    "--runtime-worker-kernel=";
constexpr std::string_view kRuntimeWorkerModePrefix = "--runtime-worker-mode=";

bool IsInternalWorkerArgument(const std::string& argument) {
  return argument.starts_with(kRuntimeWorkerExecutablePrefix) ||
         argument.starts_with(kRuntimeWorkerKernelPrefix) ||
         argument.starts_with(kRuntimeWorkerModePrefix);
}

bool ResolveExecutable(const std::filesystem::path& input,
                       std::filesystem::path* output, std::string* out_error) {
  if (!input.is_absolute()) {
    *out_error = "runtime worker executable must be absolute";
    return false;
  }
  std::error_code error;
  *output = std::filesystem::canonical(input, error);
  if (error || !std::filesystem::is_regular_file(*output, error) || error ||
      access(output->c_str(), X_OK) != 0) {
    *out_error = "runtime worker executable is not executable";
    return false;
  }
  return true;
}

bool ResolveKernel(const std::filesystem::path& input,
                   std::filesystem::path* output, std::string* out_error) {
  if (!input.is_absolute()) {
    *out_error = "runtime worker Kernel must be absolute";
    return false;
  }
  std::error_code error;
  *output = std::filesystem::canonical(input, error);
  if (error || !std::filesystem::is_regular_file(*output, error) || error) {
    *out_error = "runtime worker Kernel is missing";
    return false;
  }
  return true;
}

}  // namespace

bool PrependRuntimeWorkerConfiguration(
    const std::filesystem::path& executable,
    const std::optional<std::filesystem::path>& kernel,
    std::vector<std::string>* application_arguments, std::string* out_error) {
  if (application_arguments == nullptr || out_error == nullptr) {
    return false;
  }
  for (const std::string& argument : *application_arguments) {
    if (IsInternalWorkerArgument(argument)) {
      *out_error = "runtime worker configuration is host-owned";
      return false;
    }
  }

  std::filesystem::path resolved_executable;
  if (!ResolveExecutable(executable, &resolved_executable, out_error)) {
    return false;
  }
  std::optional<std::filesystem::path> resolved_kernel;
  if (kernel.has_value()) {
    std::filesystem::path value;
    if (!ResolveKernel(*kernel, &value, out_error)) {
      return false;
    }
    resolved_kernel = std::move(value);
  }

  std::vector<std::string> internal_arguments = {
      std::string(kRuntimeWorkerExecutablePrefix) +
          resolved_executable.string(),
      std::string(kRuntimeWorkerModePrefix) +
          (resolved_kernel.has_value() ? "kernel" : "self-contained"),
  };
  if (resolved_kernel.has_value()) {
    internal_arguments.push_back(std::string(kRuntimeWorkerKernelPrefix) +
                                 resolved_kernel->string());
  }
  application_arguments->insert(application_arguments->begin(),
                                internal_arguments.begin(),
                                internal_arguments.end());
  return true;
}

}  // namespace dart_terminal
