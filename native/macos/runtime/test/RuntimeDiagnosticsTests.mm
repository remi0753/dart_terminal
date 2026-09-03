#import <Foundation/Foundation.h>

#include "RuntimeDiagnostics.h"

#include <sys/stat.h>
#include <unistd.h>

#include <cstdint>
#include <iostream>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace {

using LogRecord = std::pair<dart_terminal::RuntimeDiagnosticLogLevel,
                            dart_terminal::RuntimeDiagnosticLogEvent>;

int failures = 0;

void Expect(bool condition, const char* description) {
  if (!condition) {
    std::cerr << "RuntimeDiagnostics expectation failed: " << description
              << '\n';
    ++failures;
  }
}

std::string CopyString(NSString* value) {
  if (value == nil || value.UTF8String == nullptr) {
    return {};
  }
  return value.UTF8String;
}

NSString* CopyNSString(const std::string& value) {
  return [[NSString alloc] initWithBytes:value.data()
                                  length:value.size()
                                encoding:NSUTF8StringEncoding];
}

NSDictionary<NSString*, id>* ReadRecord(NSString* directory,
                                        NSString* filename) {
  NSString* path = [directory stringByAppendingPathComponent:filename];
  NSData* data = [NSData dataWithContentsOfFile:path];
  if (data == nil) {
    return nil;
  }
  id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  return [object isKindOfClass:[NSDictionary class]] ? object : nil;
}

void ExpectRecordShape(NSDictionary<NSString*, id>* record,
                       const dart_terminal::RuntimeDiagnosticsOptions& options,
                       NSString* outcome, NSString* phase,
                       NSNumber* exit_code) {
  NSSet<NSString*>* expected_keys = [NSSet setWithArray:@[
    @"format",
    @"version",
    @"launch_id",
    @"bundle_identifier",
    @"application_version",
    @"runtime_mode",
    @"architecture",
    @"dart_sdk_revision",
    @"process_id",
    @"started_at",
    @"updated_at",
    @"phase",
    @"outcome",
    @"exit_code",
  ]];
  Expect(record != nil, "metadata record is readable JSON");
  if (record == nil) {
    return;
  }
  Expect([[NSSet setWithArray:record.allKeys] isEqualToSet:expected_keys],
         "metadata uses the exact privacy allowlist");
  Expect([record[@"format"]
             isEqualToString:[NSString
                                 stringWithUTF8String:
                                     dart_terminal::kRuntimeDiagnosticsFormat]],
         "metadata format");
  Expect([record[@"version"] unsignedIntValue] ==
             dart_terminal::kRuntimeDiagnosticsFormatVersion,
         "metadata version");
  Expect([[NSUUID alloc] initWithUUIDString:record[@"launch_id"]] != nil,
         "metadata launch ID");
  Expect([record[@"bundle_identifier"]
             isEqualToString:CopyNSString(options.bundle_identifier)],
         "metadata bundle identifier");
  Expect([record[@"application_version"]
             isEqualToString:CopyNSString(options.application_version)],
         "metadata application version");
  Expect([record[@"runtime_mode"]
             isEqualToString:CopyNSString(options.runtime_mode)],
         "metadata runtime mode");
  Expect([record[@"architecture"]
             isEqualToString:CopyNSString(options.architecture)],
         "metadata architecture");
  Expect([record[@"dart_sdk_revision"]
             isEqualToString:CopyNSString(options.dart_sdk_revision)],
         "metadata Dart SDK revision");
  Expect([record[@"process_id"] intValue] == getpid(), "metadata process ID");
  NSISO8601DateFormatter* formatter = [[NSISO8601DateFormatter alloc] init];
  formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime |
                            NSISO8601DateFormatWithFractionalSeconds;
  Expect([formatter dateFromString:record[@"started_at"]] != nil,
         "metadata start timestamp");
  Expect([formatter dateFromString:record[@"updated_at"]] != nil,
         "metadata update timestamp");
  Expect([record[@"phase"] isEqualToString:phase], "metadata phase");
  Expect([record[@"outcome"] isEqualToString:outcome], "metadata outcome");
  if (exit_code == nil) {
    Expect([record[@"exit_code"] isKindOfClass:[NSNull class]],
           "running metadata has no exit status");
  } else {
    Expect([record[@"exit_code"] isEqualToNumber:exit_code],
           "finished metadata exit status");
  }
}

mode_t Permissions(NSString* path) {
  struct stat status = {};
  if (lstat(path.fileSystemRepresentation, &status) != 0) {
    return 0;
  }
  return status.st_mode & 0777;
}

void ObserveLog(dart_terminal::RuntimeDiagnosticLogLevel level,
                dart_terminal::RuntimeDiagnosticLogEvent event, void* context) {
  static_cast<std::vector<LogRecord>*>(context)->emplace_back(level, event);
}

bool HasLog(const std::vector<LogRecord>& records,
            dart_terminal::RuntimeDiagnosticLogLevel level,
            dart_terminal::RuntimeDiagnosticLogEvent event) {
  for (const LogRecord& record : records) {
    if (record.first == level && record.second == event) {
      return true;
    }
  }
  return false;
}

dart_terminal::RuntimeDiagnosticsOptions ValidOptions(NSString* directory) {
  dart_terminal::RuntimeDiagnosticsOptions options;
  options.runtime_mode = "developer-jit";
#if defined(__arm64__)
  options.architecture = "arm64";
#else
  options.architecture = "x86_64";
#endif
  options.bundle_identifier = "dev.dart-terminal.diagnostics-test";
  options.application_version = "0.1.0-test";
  options.dart_sdk_revision = "60a57cd42d64dc03e9f07aa60a2e250755c1ef28";
  options.metadata_directory = CopyString(directory);
  options.strict_persistence = true;
  return options;
}

}  // namespace

int main() {
  @autoreleasepool {
    NSString* root = [NSTemporaryDirectory()
        stringByAppendingPathComponent:
            [NSString stringWithFormat:@"dart-terminal-diagnostics-%@",
                                       [NSUUID UUID].UUIDString]];
    NSString* records = [root stringByAppendingPathComponent:@"records"];
    dart_terminal::RuntimeDiagnosticsOptions options = ValidOptions(records);
    std::vector<LogRecord> logs;
    dart_terminal::SetRuntimeDiagnosticsLogObserverForTesting(ObserveLog,
                                                              &logs);

    Expect(dt_runtime_diagnostics_abi_version() ==
               DT_RUNTIME_DIAGNOSTICS_ABI_VERSION,
           "diagnostics ABI version");
    Expect(dt_runtime_diagnostics_record_phase(
               DT_RUNTIME_DIAGNOSTIC_PHASE_ROOT_STARTING) ==
               DT_RUNTIME_DIAGNOSTICS_NOT_STARTED,
           "phase without a session is rejected");

    {
      dart_terminal::RuntimeDiagnosticsSession invalid;
      dart_terminal::RuntimeDiagnosticsOptions invalid_options = options;
      invalid_options.runtime_mode = "terminal-content-is-not-a-mode";
      std::string error;
      Expect(!invalid.Start(invalid_options, &error) && !error.empty(),
             "free-form runtime metadata is rejected");
    }
    {
      dart_terminal::RuntimeDiagnosticsSession relative;
      dart_terminal::RuntimeDiagnosticsOptions relative_options = options;
      relative_options.metadata_directory = "relative/diagnostics";
      std::string error;
      Expect(!relative.Start(relative_options, &error) && !error.empty(),
             "relative metadata directory is rejected");
    }
    {
      dart_terminal::RuntimeDiagnosticsSession off_main;
      std::string error;
      bool started = true;
      std::thread thread([&] { started = off_main.Start(options, &error); });
      thread.join();
      Expect(!started && !error.empty(), "off-main start is rejected");
    }

    [[NSFileManager defaultManager] createDirectoryAtPath:root
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString* blocked = [root stringByAppendingPathComponent:@"blocked"];
    [@"not-a-directory" writeToFile:blocked
                         atomically:YES
                           encoding:NSUTF8StringEncoding
                              error:nil];
    {
      dart_terminal::RuntimeDiagnosticsSession strict_failure;
      dart_terminal::RuntimeDiagnosticsOptions blocked_options = options;
      blocked_options.metadata_directory = CopyString(blocked);
      std::string error;
      Expect(!strict_failure.Start(blocked_options, &error) && !error.empty(),
             "strict persistence failure is observable");
    }
    {
      dart_terminal::RuntimeDiagnosticsSession best_effort;
      dart_terminal::RuntimeDiagnosticsOptions blocked_options = options;
      blocked_options.metadata_directory = CopyString(blocked);
      blocked_options.strict_persistence = false;
      std::string error;
      Expect(best_effort.Start(blocked_options, &error),
             "production persistence failure is best-effort");
      Expect(!best_effort.persistence_healthy(),
             "best-effort failure remains observable to native tests");
      Expect(!best_effort.Finish(0),
             "best-effort finish reports unhealthy persistence");
    }

    std::string first_launch_id;
    {
      dart_terminal::RuntimeDiagnosticsSession first;
      std::string error;
      Expect(first.Start(options, &error), "first diagnostics session starts");
      Expect(first.persistence_healthy(), "first metadata write succeeds");
      first_launch_id = first.launch_id();
      NSDictionary<NSString*, id>* current =
          ReadRecord(records, @"current-run.json");
      ExpectRecordShape(current, options, @"running", @"host-starting", nil);
      NSData* json = [NSJSONSerialization dataWithJSONObject:current
                                                     options:0
                                                       error:nil];
      NSString* json_text =
          [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
      Expect(
          [json_text rangeOfString:@"terminal-secret"].location == NSNotFound,
          "metadata does not contain unrelated content");
      Expect(Permissions(records) == 0700, "metadata directory is owner-only");
      Expect(Permissions([records
                 stringByAppendingPathComponent:@"current-run.json"]) == 0600,
             "metadata file is owner-only");

      int32_t off_main_result = -1;
      std::thread thread([&] {
        off_main_result = dt_runtime_diagnostics_record_phase(
            DT_RUNTIME_DIAGNOSTIC_PHASE_ROOT_STARTING);
      });
      thread.join();
      Expect(off_main_result == DT_RUNTIME_DIAGNOSTICS_WRONG_THREAD,
             "off-main phase is rejected");
      Expect(dt_runtime_diagnostics_record_phase(0) ==
                 DT_RUNTIME_DIAGNOSTICS_INVALID_PHASE,
             "host-only phase is rejected through the C ABI");
      Expect(dt_runtime_diagnostics_record_phase(99) ==
                 DT_RUNTIME_DIAGNOSTICS_INVALID_PHASE,
             "unknown phase is rejected");
      Expect(dt_runtime_diagnostics_record_phase(
                 DT_RUNTIME_DIAGNOSTIC_PHASE_ROOT_STARTING) ==
                 DT_RUNTIME_DIAGNOSTICS_OK,
             "root-starting phase");
      Expect(dt_runtime_diagnostics_record_phase(
                 DT_RUNTIME_DIAGNOSTIC_PHASE_ROOT_STARTING) ==
                 DT_RUNTIME_DIAGNOSTICS_OK,
             "duplicate phase is idempotent");
      Expect(dt_runtime_diagnostics_record_phase(
                 DT_RUNTIME_DIAGNOSTIC_PHASE_ROOT_READY) ==
                 DT_RUNTIME_DIAGNOSTICS_OK,
             "root-ready phase");
      Expect(dt_runtime_diagnostics_record_phase(
                 DT_RUNTIME_DIAGNOSTIC_PHASE_ROOT_STARTING) ==
                 DT_RUNTIME_DIAGNOSTICS_PHASE_REGRESSION,
             "phase regression is rejected");
      Expect(dt_runtime_diagnostics_record_phase(
                 DT_RUNTIME_DIAGNOSTIC_PHASE_SHUTDOWN_STARTED) ==
                 DT_RUNTIME_DIAGNOSTICS_OK,
             "shutdown-started phase");
      Expect(dt_runtime_diagnostics_record_phase(
                 DT_RUNTIME_DIAGNOSTIC_PHASE_ROOT_STOPPED) ==
                 DT_RUNTIME_DIAGNOSTICS_OK,
             "root-stopped phase");
      current = ReadRecord(records, @"current-run.json");
      ExpectRecordShape(current, options, @"running", @"root-stopped", nil);
    }

    {
      dart_terminal::RuntimeDiagnosticsSession second;
      std::string error;
      Expect(second.Start(options, &error),
             "second diagnostics session starts");
      NSDictionary<NSString*, id>* previous =
          ReadRecord(records, @"previous-unclean-run.json");
      ExpectRecordShape(previous, options, @"running", @"root-stopped", nil);
      Expect(CopyString(previous[@"launch_id"]) == first_launch_id,
             "prior unclean launch ID is retained");
      NSDictionary<NSString*, id>* current =
          ReadRecord(records, @"current-run.json");
      Expect(CopyString(current[@"launch_id"]) != first_launch_id,
             "new launch receives a fresh ID");
      Expect(second.Finish(0), "clean finish persists");
      Expect(second.Finish(70), "finish is idempotent");
      Expect(dt_runtime_diagnostics_record_phase(
                 DT_RUNTIME_DIAGNOSTIC_PHASE_ROOT_STARTING) ==
                 DT_RUNTIME_DIAGNOSTICS_NOT_STARTED,
             "finished session is removed from the C ABI");
      current = ReadRecord(records, @"current-run.json");
      ExpectRecordShape(current, options, @"clean", @"host-starting", @0);
    }

    NSString* current_path =
        [records stringByAppendingPathComponent:@"current-run.json"];
    [@"not-json" writeToFile:current_path
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:nil];
    chmod(current_path.fileSystemRepresentation, 0600);
    {
      dart_terminal::RuntimeDiagnosticsSession third;
      std::string error;
      Expect(third.Start(options, &error),
             "malformed prior metadata does not block startup");
      Expect(third.Finish(70), "classified failure persists");
      NSDictionary<NSString*, id>* current =
          ReadRecord(records, @"current-run.json");
      ExpectRecordShape(current, options, @"failure", @"host-starting", @70);
      NSDictionary<NSString*, id>* previous =
          ReadRecord(records, @"previous-unclean-run.json");
      Expect(CopyString(previous[@"launch_id"]) == first_launch_id,
             "malformed current data does not replace unclean evidence");
    }

    NSArray<NSString*>* record_files =
        [[NSFileManager defaultManager] contentsOfDirectoryAtPath:records
                                                            error:nil];
    Expect(record_files.count == 2 &&
               [record_files containsObject:@"current-run.json"] &&
               [record_files containsObject:@"previous-unclean-run.json"],
           "metadata retention is bounded to two records");
    Expect(HasLog(logs, dart_terminal::RuntimeDiagnosticLogLevel::kInfo,
                  dart_terminal::RuntimeDiagnosticLogEvent::kSessionStarted),
           "session start reaches Unified Logging path");
    Expect(HasLog(logs, dart_terminal::RuntimeDiagnosticLogLevel::kInfo,
                  dart_terminal::RuntimeDiagnosticLogEvent::kPhaseChanged),
           "phase change reaches Unified Logging path");
    Expect(
        HasLog(logs, dart_terminal::RuntimeDiagnosticLogLevel::kFault,
               dart_terminal::RuntimeDiagnosticLogEvent::kPreviousUncleanRun),
        "previous unclean run reaches crash log path");
    Expect(
        HasLog(logs, dart_terminal::RuntimeDiagnosticLogLevel::kError,
               dart_terminal::RuntimeDiagnosticLogEvent::kInvalidPriorMetadata),
        "invalid prior metadata reaches crash log path");
    Expect(HasLog(logs, dart_terminal::RuntimeDiagnosticLogLevel::kError,
                  dart_terminal::RuntimeDiagnosticLogEvent::kPersistenceFailed),
           "persistence failure reaches crash log path");
    Expect(HasLog(logs, dart_terminal::RuntimeDiagnosticLogLevel::kError,
                  dart_terminal::RuntimeDiagnosticLogEvent::kSessionFinished),
           "nonzero finish reaches error log path");

    dart_terminal::SetRuntimeDiagnosticsLogObserverForTesting(nullptr, nullptr);
    [[NSFileManager defaultManager] removeItemAtPath:root error:nil];
  }
  if (failures != 0) {
    return 1;
  }
  std::cout << "RuntimeDiagnostics native contract passed\n";
  return 0;
}
