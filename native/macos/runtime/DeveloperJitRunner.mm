#import <AppKit/AppKit.h>

#include <cstdio>
#include <filesystem>
#include <iostream>
#include <optional>
#include <string>
#include <string_view>
#include <system_error>
#include <vector>

#include "AppDelegate.h"
#include "RunnerArguments.h"
#include "RunnerConfiguration.h"
#include "RuntimeDiagnostics.h"
#include "RuntimeLifecycleBridge.h"
#include "RuntimeWorkerConfiguration.h"
#include "TerminalMetalView.h"

#ifndef DT_RUNTIME_WORKER_EXECUTABLE
#error "DT_RUNTIME_WORKER_EXECUTABLE must identify the trusted Dart executable"
#endif

namespace {

constexpr std::string_view kRuntimeWorkerKernelName = "runtime_worker.dill";

bool ConfigureRuntimeWorker(const char* launcher_argument,
                            dart_appkit::RunnerConfiguration* configuration,
                            std::string* out_error) {
  if (launcher_argument == nullptr || configuration == nullptr ||
      out_error == nullptr) {
    return false;
  }
  std::error_code error;
  const std::filesystem::path launcher =
      std::filesystem::canonical(launcher_argument, error);
  if (error) {
    *out_error = "could not resolve the Developer launcher";
    return false;
  }
  const std::filesystem::path worker_kernel =
      launcher.parent_path().parent_path() / "Resources" /
      kRuntimeWorkerKernelName;
  return dart_terminal::PrependRuntimeWorkerConfiguration(
      DT_RUNTIME_WORKER_EXECUTABLE, worker_kernel,
      &configuration->application_arguments, out_error);
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
    dart_terminal::RuntimeDiagnosticsOptions diagnostics_options;
    std::string error;
    if (!dart_terminal::RuntimeDiagnosticsOptionsForCurrentProcess(
            "developer-jit", &diagnostics_options, &error)) {
      std::cerr << "Runtime diagnostics startup failed: " << error << '\n';
      return dart_terminal::kRuntimeSoftwareExitCode;
    }
    dart_terminal::RuntimeDiagnosticsSession diagnostics;
    if (!diagnostics.Start(diagnostics_options, &error)) {
      std::cerr << "Runtime diagnostics startup failed: " << error << '\n';
      return dart_terminal::kRuntimeSoftwareExitCode;
    }
    const auto finish = [&diagnostics](int exit_code) {
      diagnostics.Finish(exit_code);
      return exit_code;
    };

    dart_appkit::RunnerConfiguration configuration;
    if (!dart_appkit::ParseRunnerArguments(argc, argv, &configuration,
                                           &error)) {
      std::cerr << "Runner argument error: " << error << '\n';
      std::cerr << dart_appkit::RunnerUsage(argv[0]);
      return finish(dart_appkit::kRunnerUsageExitCode);
    }
    if (!std::filesystem::is_regular_file(configuration.kernel_path)) {
      std::cerr << "Kernel file does not exist: " << configuration.kernel_path
                << '\n';
      return finish(dart_appkit::kRunnerInputExitCode);
    }
    if (!ConfigureRuntimeWorker(argv[0], &configuration, &error)) {
      std::cerr << "Runtime worker configuration error: " << error << '\n';
      return finish(dart_appkit::kRunnerInputExitCode);
    }
    if (dart_terminal::RuntimeLifecycleShouldFailHostStartup()) {
      std::fprintf(stderr,
                   "RUNTIME_LIFECYCLE_FATAL class=host-startup status=70\n");
      return finish(dart_terminal::kRuntimeSoftwareExitCode);
    }

    NSApplication* application = [NSApplication sharedApplication];
    [application setActivationPolicy:NSApplicationActivationPolicyRegular];
    std::string registration_error;
    if (!dart_terminal::RegisterTerminalMetalView(&registration_error)) {
      std::cerr << "TerminalMetalView registration failed: "
                << registration_error << '\n';
      return finish(dart_terminal::kRuntimeSoftwareExitCode);
    }
    DartTerminalDeveloperJitDelegate* delegate =
        [[DartTerminalDeveloperJitDelegate alloc]
            initWithConfiguration:configuration];
    application.delegate = delegate;
    [application run];
    return finish(
        dart_terminal::RuntimeLifecycleEffectiveExitCode(delegate.exitCode));
  }
}
