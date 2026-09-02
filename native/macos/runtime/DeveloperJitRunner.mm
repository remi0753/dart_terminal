#import <AppKit/AppKit.h>

#include <cstdio>
#include <filesystem>
#include <iostream>
#include <string>

#include "AppDelegate.h"
#include "RunnerArguments.h"
#include "RunnerConfiguration.h"
#include "RuntimeLifecycleBridge.h"

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
