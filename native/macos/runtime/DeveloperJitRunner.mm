#import <AppKit/AppKit.h>

#include <cstdio>
#include <filesystem>
#include <iostream>
#include <string>
#include <string_view>
#include <system_error>
#include <vector>

#include <unistd.h>

#include "AppDelegate.h"
#include "RunnerArguments.h"
#include "RunnerConfiguration.h"
#include "RuntimeLifecycleBridge.h"

#ifndef DT_RUNTIME_WORKER_EXECUTABLE
#error "DT_RUNTIME_WORKER_EXECUTABLE must identify the trusted Dart executable"
#endif

namespace {

constexpr std::string_view kRuntimeWorkerExecutablePrefix =
    "--runtime-worker-executable=";
constexpr std::string_view kRuntimeWorkerKernelPrefix =
    "--runtime-worker-kernel=";
constexpr std::string_view kRuntimeWorkerKernelName = "runtime_worker.dill";

bool ConfigureRuntimeWorker(const char* launcher_argument,
                            dart_appkit::RunnerConfiguration* configuration,
                            std::string* out_error) {
  if (launcher_argument == nullptr || configuration == nullptr ||
      out_error == nullptr) {
    return false;
  }
  for (const std::string& argument : configuration->application_arguments) {
    if (argument.starts_with(kRuntimeWorkerExecutablePrefix) ||
        argument.starts_with(kRuntimeWorkerKernelPrefix)) {
      *out_error = "runtime worker configuration is host-owned";
      return false;
    }
  }

  const std::filesystem::path configured_executable(
      DT_RUNTIME_WORKER_EXECUTABLE);
  if (!configured_executable.is_absolute()) {
    *out_error = "configured runtime worker executable is not absolute";
    return false;
  }
  std::error_code error;
  const std::filesystem::path worker_executable =
      std::filesystem::canonical(configured_executable, error);
  if (error || !std::filesystem::is_regular_file(worker_executable, error) ||
      error || access(worker_executable.c_str(), X_OK) != 0) {
    *out_error = "configured runtime worker executable is not executable";
    return false;
  }

  const std::filesystem::path launcher =
      std::filesystem::canonical(launcher_argument, error);
  if (error) {
    *out_error = "could not resolve the Developer launcher";
    return false;
  }
  const std::filesystem::path worker_kernel =
      std::filesystem::canonical(launcher.parent_path().parent_path() /
                                     "Resources" / kRuntimeWorkerKernelName,
                                 error);
  if (error || !std::filesystem::is_regular_file(worker_kernel, error) ||
      error) {
    *out_error = "bundled runtime worker Kernel is missing";
    return false;
  }

  const std::vector<std::string> internal_arguments = {
      std::string(kRuntimeWorkerExecutablePrefix) + worker_executable.string(),
      std::string(kRuntimeWorkerKernelPrefix) + worker_kernel.string(),
  };
  configuration->application_arguments.insert(
      configuration->application_arguments.begin(), internal_arguments.begin(),
      internal_arguments.end());
  return true;
}

}  // namespace

@interface DartTerminalDeveloperJitDelegate : DartAppKitAppDelegate
@end

@implementation DartTerminalDeveloperJitDelegate

- (void)applicationWillTerminate:(NSNotification*)notification {
  [super applicationWillTerminate:notification];
  dart_terminal::RuntimeLifecycleCompleteApplicationTermination(self.exitCode);
}

@end

int main(int argc, const char* argv[]) {
  @autoreleasepool {
    dart_appkit::RunnerConfiguration configuration;
    std::string error;
    if (!dart_appkit::ParseRunnerArguments(argc, argv, &configuration,
                                           &error)) {
      std::cerr << "Runner argument error: " << error << '\n';
      std::cerr << dart_appkit::RunnerUsage(argv[0]);
      return dart_appkit::kRunnerUsageExitCode;
    }
    if (!std::filesystem::is_regular_file(configuration.kernel_path)) {
      std::cerr << "Kernel file does not exist: " << configuration.kernel_path
                << '\n';
      return dart_appkit::kRunnerInputExitCode;
    }
    if (!ConfigureRuntimeWorker(argv[0], &configuration, &error)) {
      std::cerr << "Runtime worker configuration error: " << error << '\n';
      return dart_appkit::kRunnerInputExitCode;
    }
    if (dart_terminal::RuntimeLifecycleShouldFailHostStartup()) {
      std::fprintf(stderr,
                   "RUNTIME_LIFECYCLE_FATAL class=host-startup status=70\n");
      return dart_terminal::kRuntimeSoftwareExitCode;
    }

    NSApplication* application = [NSApplication sharedApplication];
    [application setActivationPolicy:NSApplicationActivationPolicyRegular];
    DartTerminalDeveloperJitDelegate* delegate =
        [[DartTerminalDeveloperJitDelegate alloc]
            initWithConfiguration:configuration];
    application.delegate = delegate;
    [application run];
    return dart_terminal::RuntimeLifecycleEffectiveExitCode(delegate.exitCode);
  }
}
