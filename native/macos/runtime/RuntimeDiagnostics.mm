#import <Foundation/Foundation.h>

#include "RuntimeDiagnostics.h"

#include <fcntl.h>
#include <limits.h>
#include <os/log.h>
#include <pthread.h>
#include <sys/stat.h>
#include <unistd.h>

#include <atomic>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <string>
#include <string_view>
#include <utility>

namespace dart_terminal {
namespace {

constexpr std::string_view kCurrentRunFilename = "current-run.json";
constexpr std::string_view kPreviousUncleanRunFilename =
    "previous-unclean-run.json";

std::atomic<RuntimeDiagnosticsSession*> active_session{nullptr};
std::atomic<RuntimeDiagnosticLogObserver> test_log_observer{nullptr};
std::atomic<void*> test_log_context{nullptr};

os_log_t RuntimeLog() {
  static os_log_t log = os_log_create(kRuntimeDiagnosticsSubsystem, "runtime");
  return log;
}

os_log_t CrashLog() {
  static os_log_t log = os_log_create(kRuntimeDiagnosticsSubsystem, "crash");
  return log;
}

void NotifyTestObserver(RuntimeDiagnosticLogLevel level,
                        RuntimeDiagnosticLogEvent event) {
  RuntimeDiagnosticLogObserver observer =
      test_log_observer.load(std::memory_order_acquire);
  if (observer != nullptr) {
    observer(level, event, test_log_context.load(std::memory_order_acquire));
  }
}

void LogPersistenceFailure() {
  os_log_with_type(CrashLog(), OS_LOG_TYPE_ERROR,
                   "event=metadata-persistence-failed");
  NotifyTestObserver(RuntimeDiagnosticLogLevel::kError,
                     RuntimeDiagnosticLogEvent::kPersistenceFailed);
}

void SetError(std::string* out_error, std::string_view message) {
  if (out_error != nullptr) {
    *out_error = message;
  }
}

bool HasOnlyTokenCharacters(std::string_view value,
                            std::string_view extra_characters) {
  if (value.empty()) {
    return false;
  }
  for (const unsigned char character : value) {
    const bool alpha_numeric = (character >= 'a' && character <= 'z') ||
                               (character >= 'A' && character <= 'Z') ||
                               (character >= '0' && character <= '9');
    if (!alpha_numeric && extra_characters.find(static_cast<char>(character)) ==
                              std::string_view::npos) {
      return false;
    }
  }
  return true;
}

bool IsHexRevision(std::string_view value) {
  if (value.size() != 40) {
    return false;
  }
  for (const char character : value) {
    if (!((character >= '0' && character <= '9') ||
          (character >= 'a' && character <= 'f'))) {
      return false;
    }
  }
  return true;
}

bool ValidateOptions(const RuntimeDiagnosticsOptions& options,
                     std::string* out_error) {
  if (options.runtime_mode != "developer-jit" &&
      options.runtime_mode != "release-aot") {
    SetError(out_error, "invalid diagnostics runtime mode");
    return false;
  }
  if (options.architecture != "arm64" && options.architecture != "x86_64") {
    SetError(out_error, "invalid diagnostics architecture");
    return false;
  }
  if (options.bundle_identifier.size() > 128 ||
      !HasOnlyTokenCharacters(options.bundle_identifier, ".-")) {
    SetError(out_error, "invalid diagnostics bundle identifier");
    return false;
  }
  if (options.application_version.size() > 64 ||
      !HasOnlyTokenCharacters(options.application_version, ".+-")) {
    SetError(out_error, "invalid diagnostics application version");
    return false;
  }
  if (!IsHexRevision(options.dart_sdk_revision)) {
    SetError(out_error, "invalid diagnostics Dart SDK revision");
    return false;
  }
  if (options.metadata_directory.empty() ||
      options.metadata_directory.size() >= PATH_MAX ||
      options.metadata_directory.find('\0') != std::string::npos ||
      !std::filesystem::path(options.metadata_directory).is_absolute()) {
    SetError(out_error, "diagnostics metadata directory must be absolute");
    return false;
  }
  return true;
}

std::string JoinPath(std::string_view directory, std::string_view filename) {
  return (std::filesystem::path(directory) / filename).string();
}

bool EnsurePrivateDirectory(std::string_view directory) {
  NSString* path = [[NSString alloc] initWithBytes:directory.data()
                                            length:directory.size()
                                          encoding:NSUTF8StringEncoding];
  if (path == nil) {
    return false;
  }
  NSError* error = nil;
  NSDictionary<NSFileAttributeKey, id>* attributes = @{
    NSFilePosixPermissions : @0700,
  };
  if (![[NSFileManager defaultManager] createDirectoryAtPath:path
                                 withIntermediateDirectories:YES
                                                  attributes:attributes
                                                       error:&error]) {
    return false;
  }
  struct stat status = {};
  const std::string copied_directory(directory);
  if (lstat(copied_directory.c_str(), &status) != 0 ||
      !S_ISDIR(status.st_mode) || S_ISLNK(status.st_mode) ||
      chmod(copied_directory.c_str(), 0700) != 0) {
    return false;
  }
  return true;
}

bool WriteBytes(int descriptor, const uint8_t* bytes, size_t length) {
  size_t offset = 0;
  while (offset < length) {
    const ssize_t written =
        write(descriptor, bytes + offset, static_cast<size_t>(length - offset));
    if (written > 0) {
      offset += static_cast<size_t>(written);
      continue;
    }
    if (written < 0 && errno == EINTR) {
      continue;
    }
    return false;
  }
  return true;
}

bool WriteDataAtomically(std::string_view directory, std::string_view filename,
                         NSData* data) {
  if (data == nil || data.length == 0 ||
      data.length > kRuntimeDiagnosticsMaximumBytes) {
    return false;
  }
  const std::string destination = JoinPath(directory, filename);
  const std::string temporary = destination + ".tmp";
  unlink(temporary.c_str());
  const int descriptor =
      open(temporary.c_str(),
           O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
  if (descriptor < 0) {
    return false;
  }
  bool success = WriteBytes(descriptor, static_cast<const uint8_t*>(data.bytes),
                            data.length);
  if (success && fsync(descriptor) != 0) {
    success = false;
  }
  if (close(descriptor) != 0) {
    success = false;
  }
  if (success && rename(temporary.c_str(), destination.c_str()) != 0) {
    success = false;
  }
  if (success && chmod(destination.c_str(), 0600) != 0) {
    success = false;
  }
  if (!success) {
    unlink(temporary.c_str());
    return false;
  }
  const std::string copied_directory(directory);
  const int directory_descriptor =
      open(copied_directory.c_str(), O_RDONLY | O_CLOEXEC | O_DIRECTORY);
  if (directory_descriptor >= 0) {
    const bool directory_synced = fsync(directory_descriptor) == 0;
    close(directory_descriptor);
    if (!directory_synced) {
      return false;
    }
  }
  return true;
}

NSString* CopyNSString(std::string_view value) {
  return [[NSString alloc] initWithBytes:value.data()
                                  length:value.size()
                                encoding:NSUTF8StringEncoding];
}

std::string CopyString(NSString* value) {
  if (value == nil || value.UTF8String == nullptr) {
    return {};
  }
  return value.UTF8String;
}

std::string CurrentTimestamp() {
  NSISO8601DateFormatter* formatter = [[NSISO8601DateFormatter alloc] init];
  formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime |
                            NSISO8601DateFormatWithFractionalSeconds;
  formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
  return CopyString([formatter stringFromDate:[NSDate date]]);
}

const char* PhaseName(uint32_t phase) {
  switch (phase) {
    case 0:
      return "host-starting";
    case DT_RUNTIME_DIAGNOSTIC_PHASE_ROOT_STARTING:
      return "root-starting";
    case DT_RUNTIME_DIAGNOSTIC_PHASE_ROOT_READY:
      return "root-ready";
    case DT_RUNTIME_DIAGNOSTIC_PHASE_SHUTDOWN_STARTED:
      return "shutdown-started";
    case DT_RUNTIME_DIAGNOSTIC_PHASE_ROOT_STOPPED:
      return "root-stopped";
    default:
      return nullptr;
  }
}

NSSet<NSString*>* MetadataKeys() {
  static NSSet<NSString*>* keys = [NSSet setWithArray:@[
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
  return keys;
}

bool IsString(id value) { return [value isKindOfClass:[NSString class]]; }

bool IsNumber(id value) { return [value isKindOfClass:[NSNumber class]]; }

bool IsValidTimestamp(NSString* value) {
  if (!IsString(value)) {
    return false;
  }
  NSISO8601DateFormatter* formatter = [[NSISO8601DateFormatter alloc] init];
  formatter.formatOptions = NSISO8601DateFormatWithInternetDateTime |
                            NSISO8601DateFormatWithFractionalSeconds;
  return [formatter dateFromString:value] != nil;
}

bool IsValidPriorRecord(NSDictionary<NSString*, id>* record) {
  if (record == nil ||
      ![[NSSet setWithArray:record.allKeys] isEqualToSet:MetadataKeys()]) {
    return false;
  }
  if (![record[@"format"] isEqualToString:@(kRuntimeDiagnosticsFormat)] ||
      !IsNumber(record[@"version"]) ||
      [record[@"version"] unsignedIntValue] !=
          kRuntimeDiagnosticsFormatVersion ||
      !IsString(record[@"launch_id"]) ||
      [[NSUUID alloc] initWithUUIDString:record[@"launch_id"]] == nil ||
      !IsString(record[@"bundle_identifier"]) ||
      !IsString(record[@"application_version"]) ||
      !IsString(record[@"runtime_mode"]) ||
      !IsString(record[@"architecture"]) ||
      !IsString(record[@"dart_sdk_revision"]) ||
      !IsNumber(record[@"process_id"]) ||
      [record[@"process_id"] longLongValue] <= 0 ||
      !IsValidTimestamp(record[@"started_at"]) ||
      !IsValidTimestamp(record[@"updated_at"]) || !IsString(record[@"phase"]) ||
      ![record[@"outcome"] isEqualToString:@"running"] ||
      ![record[@"exit_code"] isKindOfClass:[NSNull class]]) {
    return false;
  }
  RuntimeDiagnosticsOptions options;
  options.runtime_mode = CopyString(record[@"runtime_mode"]);
  options.architecture = CopyString(record[@"architecture"]);
  options.bundle_identifier = CopyString(record[@"bundle_identifier"]);
  options.application_version = CopyString(record[@"application_version"]);
  options.dart_sdk_revision = CopyString(record[@"dart_sdk_revision"]);
  options.metadata_directory = "/valid/prior/path";
  if (!ValidateOptions(options, nullptr)) {
    return false;
  }
  const std::string phase = CopyString(record[@"phase"]);
  for (uint32_t value = 0; value <= DT_RUNTIME_DIAGNOSTIC_PHASE_ROOT_STOPPED;
       ++value) {
    if (phase == PhaseName(value)) {
      return true;
    }
  }
  return false;
}

bool PriorRecordMatchesOptions(NSDictionary<NSString*, id>* record,
                               const RuntimeDiagnosticsOptions& options) {
  return [record[@"runtime_mode"]
             isEqualToString:CopyNSString(options.runtime_mode)] &&
         [record[@"architecture"]
             isEqualToString:CopyNSString(options.architecture)] &&
         [record[@"bundle_identifier"]
             isEqualToString:CopyNSString(options.bundle_identifier)];
}

enum class PriorRecordStatus { kMissing, kValidRunning, kInvalid };

PriorRecordStatus ReadPriorRecord(std::string_view path,
                                  NSDictionary<NSString*, id>** out_record) {
  const std::string copied_path(path);
  struct stat status = {};
  if (lstat(copied_path.c_str(), &status) != 0) {
    return errno == ENOENT ? PriorRecordStatus::kMissing
                           : PriorRecordStatus::kInvalid;
  }
  if (!S_ISREG(status.st_mode) || S_ISLNK(status.st_mode) ||
      (status.st_mode & 0077) != 0 || status.st_size <= 0 ||
      status.st_size > static_cast<off_t>(kRuntimeDiagnosticsMaximumBytes)) {
    return PriorRecordStatus::kInvalid;
  }
  NSData* data = [NSData dataWithContentsOfFile:CopyNSString(path)
                                        options:0
                                          error:nil];
  if (data == nil || data.length == 0 ||
      data.length > kRuntimeDiagnosticsMaximumBytes) {
    return PriorRecordStatus::kInvalid;
  }
  id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  if (![object isKindOfClass:[NSDictionary class]]) {
    return PriorRecordStatus::kInvalid;
  }
  NSDictionary<NSString*, id>* record = object;
  if (!IsValidPriorRecord(record)) {
    return PriorRecordStatus::kInvalid;
  }
  *out_record = record;
  return PriorRecordStatus::kValidRunning;
}

bool WriteRecord(std::string_view directory, std::string_view filename,
                 NSDictionary<NSString*, id>* record) {
  NSError* error = nil;
  NSData* data = [NSJSONSerialization dataWithJSONObject:record
                                                 options:NSJSONWritingSortedKeys
                                                   error:&error];
  return error == nil && WriteDataAtomically(directory, filename, data);
}

NSString* BundleString(NSBundle* bundle, NSString* key) {
  id value = [bundle objectForInfoDictionaryKey:key];
  return IsString(value) ? value : nil;
}

const char* CompiledArchitecture() {
#if defined(__arm64__)
  return "arm64";
#elif defined(__x86_64__)
  return "x86_64";
#else
  return "unsupported";
#endif
}

bool IsEnabledEnvironmentGate(const char* name) {
  const char* value = std::getenv(name);
  return value != nullptr && std::strcmp(value, "1") == 0;
}

}  // namespace

RuntimeDiagnosticsSession::~RuntimeDiagnosticsSession() {
  RuntimeDiagnosticsSession* expected = this;
  active_session.compare_exchange_strong(expected, nullptr,
                                         std::memory_order_acq_rel);
}

bool RuntimeDiagnosticsSession::Start(const RuntimeDiagnosticsOptions& options,
                                      std::string* out_error) {
  if (pthread_main_np() == 0) {
    SetError(out_error, "diagnostics must start on the process main thread");
    return false;
  }
  if (started_) {
    SetError(out_error, "diagnostics session already started");
    return false;
  }
  if (!ValidateOptions(options, out_error)) {
    return false;
  }
  RuntimeDiagnosticsSession* expected = nullptr;
  if (!active_session.compare_exchange_strong(expected, this,
                                              std::memory_order_acq_rel)) {
    SetError(out_error, "another diagnostics session is active");
    return false;
  }

  runtime_mode_ = options.runtime_mode;
  architecture_ = options.architecture;
  bundle_identifier_ = options.bundle_identifier;
  application_version_ = options.application_version;
  dart_sdk_revision_ = options.dart_sdk_revision;
  metadata_directory_ = std::filesystem::path(options.metadata_directory)
                            .lexically_normal()
                            .string();
  strict_persistence_ = options.strict_persistence;
  launch_id_ = CopyString([NSUUID UUID].UUIDString);
  started_at_ = CurrentTimestamp();
  updated_at_ = started_at_;
  started_ = true;

  const bool directory_ready = EnsurePrivateDirectory(metadata_directory_);
  bool persisted = directory_ready;
  if (directory_ready) {
    unlink(
        JoinPath(metadata_directory_, std::string(kCurrentRunFilename) + ".tmp")
            .c_str());
    unlink(JoinPath(metadata_directory_,
                    std::string(kPreviousUncleanRunFilename) + ".tmp")
               .c_str());
    NSDictionary<NSString*, id>* prior_record = nil;
    const PriorRecordStatus prior_status = ReadPriorRecord(
        JoinPath(metadata_directory_, kCurrentRunFilename), &prior_record);
    if (prior_status == PriorRecordStatus::kValidRunning &&
        PriorRecordMatchesOptions(prior_record, options)) {
      if (!WriteRecord(metadata_directory_, kPreviousUncleanRunFilename,
                       prior_record)) {
        persisted = false;
      } else {
        os_log_with_type(CrashLog(), OS_LOG_TYPE_FAULT,
                         "event=previous-unclean-run");
        NotifyTestObserver(RuntimeDiagnosticLogLevel::kFault,
                           RuntimeDiagnosticLogEvent::kPreviousUncleanRun);
      }
    } else if (prior_status != PriorRecordStatus::kMissing) {
      os_log_with_type(CrashLog(), OS_LOG_TYPE_ERROR,
                       "event=invalid-prior-metadata");
      NotifyTestObserver(RuntimeDiagnosticLogLevel::kError,
                         RuntimeDiagnosticLogEvent::kInvalidPriorMetadata);
    }
  }
  if (directory_ready && !PersistCurrentRecord()) {
    persisted = false;
  }
  persistence_healthy_ = persisted;
  if (!persisted && strict_persistence_) {
    started_ = false;
    RuntimeDiagnosticsSession* active = this;
    active_session.compare_exchange_strong(active, nullptr,
                                           std::memory_order_acq_rel);
    SetError(out_error, "could not persist strict diagnostics metadata");
    return false;
  }
  if (!persisted) {
    LogPersistenceFailure();
  }
  os_log_with_type(RuntimeLog(), OS_LOG_TYPE_INFO,
                   "event=session-started mode=%{public}s "
                   "architecture=%{public}s launch_id=%{public}s",
                   runtime_mode_.c_str(), architecture_.c_str(),
                   launch_id_.c_str());
  NotifyTestObserver(RuntimeDiagnosticLogLevel::kInfo,
                     RuntimeDiagnosticLogEvent::kSessionStarted);
  return true;
}

int32_t RuntimeDiagnosticsSession::RecordPhase(uint32_t phase) {
  if (!started_) {
    return DT_RUNTIME_DIAGNOSTICS_NOT_STARTED;
  }
  if (pthread_main_np() == 0) {
    return DT_RUNTIME_DIAGNOSTICS_WRONG_THREAD;
  }
  if (PhaseName(phase) == nullptr || phase == 0) {
    return DT_RUNTIME_DIAGNOSTICS_INVALID_PHASE;
  }
  if (finished_) {
    return DT_RUNTIME_DIAGNOSTICS_ALREADY_FINISHED;
  }
  if (phase < phase_) {
    return DT_RUNTIME_DIAGNOSTICS_PHASE_REGRESSION;
  }
  if (phase == phase_) {
    return DT_RUNTIME_DIAGNOSTICS_OK;
  }
  phase_ = phase;
  updated_at_ = CurrentTimestamp();
  if (persistence_healthy_ && !PersistCurrentRecord()) {
    persistence_healthy_ = false;
    LogPersistenceFailure();
  }
  os_log_with_type(RuntimeLog(), OS_LOG_TYPE_INFO,
                   "event=phase-changed phase=%{public}s", PhaseName(phase));
  NotifyTestObserver(RuntimeDiagnosticLogLevel::kInfo,
                     RuntimeDiagnosticLogEvent::kPhaseChanged);
  return DT_RUNTIME_DIAGNOSTICS_OK;
}

bool RuntimeDiagnosticsSession::Finish(int32_t exit_code) {
  if (!started_ || pthread_main_np() == 0) {
    return false;
  }
  if (finished_) {
    return persistence_healthy_;
  }
  finished_ = true;
  has_exit_code_ = true;
  exit_code_ = exit_code;
  outcome_ = exit_code == 0 ? "clean" : "failure";
  updated_at_ = CurrentTimestamp();
  if (persistence_healthy_ && !PersistCurrentRecord()) {
    persistence_healthy_ = false;
    LogPersistenceFailure();
  }
  os_log_type_t log_type =
      exit_code == 0 ? OS_LOG_TYPE_INFO : OS_LOG_TYPE_ERROR;
  os_log_with_type(RuntimeLog(), log_type,
                   "event=session-finished outcome=%{public}s exit_code=%d",
                   outcome_.c_str(), exit_code_);
  NotifyTestObserver(exit_code == 0 ? RuntimeDiagnosticLogLevel::kInfo
                                    : RuntimeDiagnosticLogLevel::kError,
                     RuntimeDiagnosticLogEvent::kSessionFinished);
  RuntimeDiagnosticsSession* active = this;
  active_session.compare_exchange_strong(active, nullptr,
                                         std::memory_order_acq_rel);
  return persistence_healthy_;
}

bool RuntimeDiagnosticsSession::PersistCurrentRecord() {
  NSString* format = CopyNSString(kRuntimeDiagnosticsFormat);
  NSString* launch_id = CopyNSString(launch_id_);
  NSString* bundle_identifier = CopyNSString(bundle_identifier_);
  NSString* application_version = CopyNSString(application_version_);
  NSString* runtime_mode = CopyNSString(runtime_mode_);
  NSString* architecture = CopyNSString(architecture_);
  NSString* dart_sdk_revision = CopyNSString(dart_sdk_revision_);
  NSString* started_at = CopyNSString(started_at_);
  NSString* updated_at = CopyNSString(updated_at_);
  NSString* phase = @(PhaseName(phase_));
  NSString* outcome = CopyNSString(outcome_);
  if (launch_id == nil || bundle_identifier == nil ||
      application_version == nil || runtime_mode == nil ||
      architecture == nil || dart_sdk_revision == nil || started_at == nil ||
      updated_at == nil || phase == nil || outcome == nil) {
    return false;
  }
  NSDictionary<NSString*, id>* record = @{
    @"format" : format,
    @"version" : @(kRuntimeDiagnosticsFormatVersion),
    @"launch_id" : launch_id,
    @"bundle_identifier" : bundle_identifier,
    @"application_version" : application_version,
    @"runtime_mode" : runtime_mode,
    @"architecture" : architecture,
    @"dart_sdk_revision" : dart_sdk_revision,
    @"process_id" : @(getpid()),
    @"started_at" : started_at,
    @"updated_at" : updated_at,
    @"phase" : phase,
    @"outcome" : outcome,
    @"exit_code" : has_exit_code_ ? @(exit_code_) : [NSNull null],
  };
  return WriteRecord(metadata_directory_, kCurrentRunFilename, record);
}

bool RuntimeDiagnosticsOptionsForCurrentProcess(
    const char* runtime_mode, RuntimeDiagnosticsOptions* out_options,
    std::string* out_error) {
  if (pthread_main_np() == 0) {
    SetError(out_error, "diagnostics options require the process main thread");
    return false;
  }
  if (runtime_mode == nullptr || out_options == nullptr) {
    SetError(out_error, "diagnostics options are incomplete");
    return false;
  }
  NSBundle* bundle = [NSBundle mainBundle];
  NSString* bundle_identifier = bundle.bundleIdentifier;
  NSString* application_version =
      BundleString(bundle, @"CFBundleShortVersionString");
  NSString* dart_sdk_revision = BundleString(bundle, @"DTDartSDKRevision");
  if (bundle_identifier == nil || application_version == nil ||
      dart_sdk_revision == nil) {
    SetError(out_error, "diagnostics bundle metadata is incomplete");
    return false;
  }

  std::string metadata_directory;
  const bool strict = IsEnabledEnvironmentGate("DT_RUNTIME_DIAGNOSTICS_TEST");
  if (strict) {
    const char* override_directory =
        std::getenv("DT_RUNTIME_DIAGNOSTICS_DIRECTORY");
    if (override_directory == nullptr || override_directory[0] == '\0') {
      SetError(out_error, "strict diagnostics directory is missing");
      return false;
    }
    metadata_directory = override_directory;
  } else {
    NSArray<NSURL*>* urls = [[NSFileManager defaultManager]
        URLsForDirectory:NSApplicationSupportDirectory
               inDomains:NSUserDomainMask];
    NSURL* base = urls.firstObject;
    if (base == nil) {
      SetError(out_error, "Application Support directory is unavailable");
      return false;
    }
    NSURL* directory = [[[base URLByAppendingPathComponent:@"Dart Terminal"
                                               isDirectory:YES]
        URLByAppendingPathComponent:@"Diagnostics"
                        isDirectory:YES]
        URLByAppendingPathComponent:CopyNSString(runtime_mode)
                        isDirectory:YES];
    metadata_directory = CopyString(directory.path);
  }

  RuntimeDiagnosticsOptions options;
  options.runtime_mode = runtime_mode;
  options.architecture = CompiledArchitecture();
  options.bundle_identifier = CopyString(bundle_identifier);
  options.application_version = CopyString(application_version);
  options.dart_sdk_revision = CopyString(dart_sdk_revision);
  options.metadata_directory =
      std::filesystem::path(metadata_directory).lexically_normal().string();
  options.strict_persistence = strict;
  if (!ValidateOptions(options, out_error)) {
    return false;
  }
  *out_options = std::move(options);
  return true;
}

bool RuntimeDiagnosticsFinishActiveSession(int32_t exit_code) {
  RuntimeDiagnosticsSession* session =
      active_session.load(std::memory_order_acquire);
  return session != nullptr && session->Finish(exit_code);
}

int32_t RuntimeDiagnosticsRecordActivePhase(uint32_t phase) {
  RuntimeDiagnosticsSession* session =
      active_session.load(std::memory_order_acquire);
  if (session == nullptr) {
    return DT_RUNTIME_DIAGNOSTICS_NOT_STARTED;
  }
  return session->RecordPhase(phase);
}

void SetRuntimeDiagnosticsLogObserverForTesting(
    RuntimeDiagnosticLogObserver observer, void* context) {
  test_log_context.store(context, std::memory_order_release);
  test_log_observer.store(observer, std::memory_order_release);
}

}  // namespace dart_terminal

extern "C" uint32_t dt_runtime_diagnostics_abi_version(void) {
  return DT_RUNTIME_DIAGNOSTICS_ABI_VERSION;
}

extern "C" int32_t dt_runtime_diagnostics_record_phase(uint32_t phase) {
  return dart_terminal::RuntimeDiagnosticsRecordActivePhase(phase);
}
