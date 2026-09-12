#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#include "TerminalAppleScriptPlugin.h"

#include <dispatch/dispatch.h>
#include <stdio.h>
#include <string.h>

namespace {

int g_failures = 0;

void Expect(bool condition, const char* description) {
  if (!condition) {
    fprintf(stderr, "FAIL %s\n", description);
    ++g_failures;
  }
}

NSData* Data(NSString* value) {
  return [value dataUsingEncoding:NSUTF8StringEncoding];
}

int32_t Publish(NSString* value) {
  NSData* data = Data(value);
  return dtas_publish_snapshot(static_cast<const uint8_t*>(data.bytes),
                               data.length);
}

int32_t Enqueue(NSString* value) {
  NSData* data = Data(value);
  return dtas_enqueue_self_automation_command(
      static_cast<const uint8_t*>(data.bytes), data.length);
}

DtasSummaryV1 Summary() {
  DtasSummaryV1 summary = {};
  summary.struct_size = sizeof(summary);
  summary.version = DTAS_SUMMARY_VERSION;
  Expect(dtas_debug_summary(&summary) == DTAS_STATUS_OK, "summary status");
  return summary;
}

NSString* Command(uint64_t operation, NSString* kind, id target,
                  id direction, id text) {
  NSDictionary* packet = @{
    @"version" : @1,
    @"operationId" : @(operation),
    @"kind" : kind,
    @"target" : target,
    @"direction" : direction,
    @"text" : text,
  };
  NSData* data = [NSJSONSerialization dataWithJSONObject:packet
                                                  options:0
                                                    error:nil];
  return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

const da_native_extension_services_v1 kServices = {
    sizeof(da_native_extension_services_v1),
    DA_NATIVE_EXTENSION_ABI_VERSION,
    nullptr,
    nullptr,
};

const NSString* kEnabledSnapshot =
    @"{\"version\":1,\"generation\":7,\"enabled\":true,\"windows\":[{"
     "\"id\":\"window:1\",\"title\":\"project\",\"index\":1,"
     "\"frontmost\":true,\"selectedTab\":\"tab:2\",\"tabs\":[{"
     "\"id\":\"tab:2\",\"title\":\"shell\",\"index\":1,"
     "\"selected\":true,\"focusedTerminal\":\"terminal:3\","
     "\"terminals\":[{\"id\":\"terminal:3\",\"title\":\"zsh\","
     "\"workingDirectory\":\"/private/tmp\"}]}]}]}";

const NSString* kDisabledSnapshot =
    @"{\"version\":1,\"generation\":8,\"enabled\":false,\"windows\":[]}";

void TestInitializationAndSnapshot() {
  Expect(dtas_abi_version() == DTAS_ABI_VERSION, "ABI version");
  Expect(dtas_session_start(1u, 1000u) == DTAS_STATUS_NOT_INITIALIZED,
         "start before initialize");
  Expect(dtas_initialize(nullptr) == DTAS_STATUS_UNSUPPORTED_VERSION,
         "null services");
  da_native_extension_services_v1 wrong = kServices;
  wrong.abi_version = 99u;
  Expect(dtas_initialize(&wrong) == DTAS_STATUS_UNSUPPORTED_VERSION,
         "wrong service ABI");
  Expect(dtas_initialize(&kServices) == DTAS_STATUS_OK, "initialize");
  Expect(dtas_initialize(&kServices) == DTAS_STATUS_OK,
         "idempotent initialize");
  da_native_extension_services_v1 other = kServices;
  Expect(dtas_initialize(&other) == DTAS_STATUS_INVALID_ARGUMENT,
         "different service table");
  Expect(dtas_session_start(0u, 1000u) == DTAS_STATUS_INVALID_ARGUMENT,
         "zero pending bound");
  Expect(dtas_session_start(17u, 1000u) == DTAS_STATUS_INVALID_ARGUMENT,
         "large pending bound");
  Expect(dtas_session_start(16u, 0u) == DTAS_STATUS_INVALID_ARGUMENT,
         "zero timeout");
  Expect(dtas_session_start(16u, 1000000u) == DTAS_STATUS_OK,
         "session start");
  Expect(dtas_session_start(16u, 1000000u) == DTAS_STATUS_ALREADY_STARTED,
         "duplicate session");

  DtasSummaryV1 initial = Summary();
  Expect(initial.started == 1u && initial.enabled == 0u &&
             initial.window_count == 0u,
         "initial disabled cache");
  Expect(Publish(@"{}") == DTAS_STATUS_INVALID_ARGUMENT,
         "malformed snapshot");
  Expect(Summary().generation == 0u, "invalid snapshot remains atomic");
  Expect(Publish((NSString*)kEnabledSnapshot) == DTAS_STATUS_OK,
         "publish enabled snapshot");
  DtasSummaryV1 published = Summary();
  Expect(published.generation == 7u && published.enabled == 1u &&
             published.window_count == 1u && published.tab_count == 1u &&
             published.terminal_count == 1u,
         "published hierarchy summary");

  NSApplication* application = [NSApplication sharedApplication];
  NSArray* windows = [application valueForKey:@"dtasWindows"];
  id window = windows.firstObject;
  NSArray* tabs = [window valueForKey:@"dtasTabs"];
  id tab = tabs.firstObject;
  NSArray* terminals = [tab valueForKey:@"terminals"];
  id terminal = terminals.firstObject;
  Expect(windows.count == 1u &&
             [[window valueForKey:@"uniqueID"] isEqual:@"window:1"] &&
             [[window valueForKey:@"selectedTab"] isEqual:tab] &&
             [[tab valueForKey:@"focusedTerminal"] isEqual:terminal] &&
             [[terminal valueForKey:@"workingDirectory"]
                 isEqual:@"/private/tmp"],
         "cached KVC object hierarchy");
  for (NSString* name in @[
         @"DTASNewWindowCommand", @"DTASNewTabCommand", @"DTASSplitCommand",
         @"DTASInputTextCommand", @"DTASFocusCommand", @"DTASCloseCommand"
       ]) {
    Expect(NSClassFromString(name) != Nil, "dictionary command class exists");
  }
}

void TestCommandsAndLifecycle() {
  NSArray<NSString*>* commands = @[
    Command(1u, @"newWindow", [NSNull null], [NSNull null], [NSNull null]),
    Command(2u, @"newTab", @"window:1", [NSNull null], [NSNull null]),
    Command(3u, @"split", @"terminal:3", @"right", [NSNull null]),
    Command(4u, @"inputText", @"terminal:3", [NSNull null], @"printf ok\n"),
    Command(5u, @"focus", @"terminal:3", [NSNull null], [NSNull null]),
    Command(6u, @"closeTerminal", @"terminal:3", [NSNull null],
            [NSNull null]),
    Command(7u, @"closeTab", @"tab:2", [NSNull null], [NSNull null]),
    Command(8u, @"closeWindow", @"window:1", [NSNull null], [NSNull null]),
  ];
  for (NSString* command in commands) {
    Expect(Enqueue(command) == DTAS_STATUS_OK, "enqueue typed command");
  }
  Expect(Enqueue(commands.firstObject) == DTAS_STATUS_INVALID_ARGUMENT,
         "duplicate operation");
  DtasSummaryV1 queued = Summary();
  Expect(queued.queued_command_count == 8u &&
             queued.pending_command_count == 8u,
         "queued and pending command counts");

  for (NSUInteger index = 0u; index < commands.count; ++index) {
    size_t length = 0u;
    Expect(dtas_take_command(nullptr, 0u, &length) ==
               DTAS_STATUS_BUFFER_TOO_SMALL &&
               length == Data(commands[index]).length,
           "two-pass command sizing");
    uint8_t* output = new uint8_t[length];
    size_t copied = 0u;
    Expect(dtas_take_command(output, length, &copied) == DTAS_STATUS_OK &&
               copied == length &&
               memcmp(output, Data(commands[index]).bytes, length) == 0,
           "ordered command copy");
    delete[] output;
    const char* object = index == 0u   ? "window:1"
                         : index == 1u ? "tab:2"
                         : index == 2u ? "terminal:3"
                                       : nullptr;
    Expect(dtas_complete_command(index + 1u, DTAS_COMMAND_COMPLETED,
                                 reinterpret_cast<const uint8_t*>(object),
                                 object == nullptr ? 0u : strlen(object)) ==
               DTAS_STATUS_OK,
           "complete command once");
    Expect(dtas_complete_command(index + 1u, DTAS_COMMAND_COMPLETED, nullptr,
                                 0u) == DTAS_STATUS_NOT_FOUND,
           "duplicate completion rejected");
  }
  DtasSummaryV1 completed = Summary();
  Expect(completed.pending_command_count == 0u &&
             completed.queued_command_count == 0u &&
             completed.resumed_command_count == 8u,
         "all commands resolved once");

  NSString* typed_result =
      Command(18u, @"newWindow", [NSNull null], [NSNull null], [NSNull null]);
  Expect(Enqueue(typed_result) == DTAS_STATUS_OK, "typed result command");
  size_t typed_length = 0u;
  Expect(dtas_take_command(nullptr, 0u, &typed_length) ==
             DTAS_STATUS_BUFFER_TOO_SMALL,
         "typed result command sizing");
  NSMutableData* typed_buffer = [NSMutableData dataWithLength:typed_length];
  Expect(dtas_take_command(static_cast<uint8_t*>(typed_buffer.mutableBytes),
                           typed_length, &typed_length) == DTAS_STATUS_OK,
         "typed result command take");
  const char* wrong_result = "terminal:3";
  Expect(dtas_complete_command(
             18u, DTAS_COMMAND_COMPLETED,
             reinterpret_cast<const uint8_t*>(wrong_result),
             strlen(wrong_result)) == DTAS_STATUS_INVALID_ARGUMENT,
         "object-producing command rejects the wrong result kind");
  Expect(dtas_complete_command(18u, DTAS_COMMAND_COMPLETED, nullptr, 0u) ==
             DTAS_STATUS_INVALID_ARGUMENT,
         "object-producing command requires its result object");
  const char* window_result = "window:1";
  Expect(dtas_complete_command(
             18u, DTAS_COMMAND_COMPLETED,
             reinterpret_cast<const uint8_t*>(window_result),
             strlen(window_result)) == DTAS_STATUS_OK,
         "object-producing command accepts the declared result kind");

  NSString* boolean_result =
      Command(19u, @"focus", @"terminal:3", [NSNull null], [NSNull null]);
  Expect(Enqueue(boolean_result) == DTAS_STATUS_OK, "boolean result command");
  size_t boolean_length = 0u;
  Expect(dtas_take_command(nullptr, 0u, &boolean_length) ==
             DTAS_STATUS_BUFFER_TOO_SMALL,
         "boolean result command sizing");
  NSMutableData* boolean_buffer = [NSMutableData dataWithLength:boolean_length];
  Expect(dtas_take_command(static_cast<uint8_t*>(boolean_buffer.mutableBytes),
                           boolean_length, &boolean_length) == DTAS_STATUS_OK,
         "boolean result command take");
  Expect(dtas_complete_command(
             19u, DTAS_COMMAND_COMPLETED,
             reinterpret_cast<const uint8_t*>(window_result),
             strlen(window_result)) == DTAS_STATUS_INVALID_ARGUMENT,
         "boolean command rejects an object result");
  Expect(dtas_complete_command(19u, DTAS_COMMAND_COMPLETED, nullptr, 0u) ==
             DTAS_STATUS_OK,
         "boolean command accepts a boolean completion");

  Expect(Enqueue(Command(20u, @"split", @"terminal:3", @"sideways",
                         [NSNull null])) == DTAS_STATUS_INVALID_ARGUMENT,
         "invalid split direction");
  Expect(Enqueue(Command(21u, @"closeTab", @"terminal:3", [NSNull null],
                         [NSNull null])) == DTAS_STATUS_INVALID_ARGUMENT,
         "wrong-kind command target");

  Expect(Enqueue(Command(22u, @"focus", @"terminal:3", [NSNull null],
                         [NSNull null])) == DTAS_STATUS_OK,
         "pending command before disable");
  Expect(Publish((NSString*)kDisabledSnapshot) == DTAS_STATUS_OK,
         "disable snapshot");
  DtasSummaryV1 disabled = Summary();
  Expect(disabled.enabled == 0u && disabled.pending_command_count == 0u &&
             disabled.resumed_command_count == 11u,
         "disable resolves pending commands");
  Expect(Enqueue(Command(23u, @"newWindow", [NSNull null], [NSNull null],
                         [NSNull null])) == DTAS_STATUS_DISABLED,
         "disabled command rejected");
  Expect(Summary().rejected_command_count == 4u,
         "each invalid or disabled request counted once");
  Expect([[[NSApplication sharedApplication] valueForKey:@"dtasWindows"] count] ==
             0u,
         "disabled hierarchy is empty");
  Expect(dtas_session_shutdown() == DTAS_STATUS_OK, "session shutdown");
  Expect(dtas_session_shutdown() == DTAS_STATUS_NOT_INITIALIZED,
         "duplicate shutdown");
}

void TestBoundsTimeoutAndThread() {
  Expect(dtas_session_start(2u, 1000u) == DTAS_STATUS_OK,
         "bounded session restart");
  Expect(Publish((NSString*)kEnabledSnapshot) == DTAS_STATUS_OK,
         "restart snapshot");
  NSString* first =
      Command(30u, @"focus", @"terminal:3", [NSNull null], [NSNull null]);
  NSString* second =
      Command(31u, @"focus", @"terminal:3", [NSNull null], [NSNull null]);
  NSString* third =
      Command(32u, @"focus", @"terminal:3", [NSNull null], [NSNull null]);
  Expect(Enqueue(first) == DTAS_STATUS_OK && Enqueue(second) == DTAS_STATUS_OK &&
             Enqueue(third) == DTAS_STATUS_RESOURCE_EXHAUSTED,
         "pending cap remains after command take");
  size_t length = 0u;
  Expect(dtas_take_command(nullptr, 0u, &length) ==
             DTAS_STATUS_BUFFER_TOO_SMALL,
         "pending cap sizing");
  NSMutableData* buffer = [NSMutableData dataWithLength:length];
  Expect(dtas_take_command(static_cast<uint8_t*>(buffer.mutableBytes), length,
                           &length) == DTAS_STATUS_OK &&
             Enqueue(third) == DTAS_STATUS_RESOURCE_EXHAUSTED,
         "taken but incomplete command consumes pending capacity");
  Expect(dtas_complete_command(30u, DTAS_COMMAND_REJECTED, nullptr, 0u) ==
             DTAS_STATUS_OK &&
             Enqueue(third) == DTAS_STATUS_OK,
         "completion releases pending capacity");

  [[NSRunLoop currentRunLoop]
      runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
  DtasSummaryV1 expired = Summary();
  Expect(expired.pending_command_count == 0u &&
             expired.resumed_command_count == 3u &&
             expired.rejected_command_count == 2u,
         "native deadline resolves every pending command");

  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
  __block int32_t background_status = DTAS_STATUS_INTERNAL;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
    DtasSummaryV1 summary = {};
    summary.struct_size = sizeof(summary);
    summary.version = DTAS_SUMMARY_VERSION;
    background_status = dtas_debug_summary(&summary);
    dispatch_semaphore_signal(semaphore);
  });
  dispatch_semaphore_wait(semaphore,
                          dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
  Expect(background_status == DTAS_STATUS_WRONG_THREAD,
         "background access rejected");
  Expect(dtas_session_shutdown() == DTAS_STATUS_OK, "final shutdown");
}

}  // namespace

int main() {
  @autoreleasepool {
    [NSApplication sharedApplication];
    TestInitializationAndSnapshot();
    TestCommandsAndLifecycle();
    TestBoundsTimeoutAndThread();
  }
  if (g_failures == 0) {
    printf("terminal AppleScript native capability tests passed\n");
  }
  return g_failures == 0 ? 0 : 1;
}
