#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#include "TerminalAppleScriptPlugin.h"

#include <dispatch/dispatch.h>
#include <limits.h>
#include <math.h>
#include <stdatomic.h>
#include <string.h>

static const NSUInteger kMaximumTitleBytes = 1024u;
static const NSUInteger kMaximumWorkingDirectoryBytes = 4096u;

@class DTASScriptWindow;
@class DTASScriptTab;
@class DTASScriptTerminal;

@interface DTASScriptTerminal : NSObject
@property(nonatomic, copy, readonly) NSString* uniqueID;
@property(nonatomic, copy, readonly) NSString* title;
@property(nonatomic, copy, readonly) NSString* workingDirectory;
@property(nonatomic, weak) DTASScriptTab* parentTab;
- (instancetype)initWithIdentifier:(NSString*)identifier
                             title:(NSString*)title
                  workingDirectory:(NSString*)workingDirectory;
- (NSScriptObjectSpecifier*)objectSpecifier;
@end

@interface DTASScriptTab : NSObject
@property(nonatomic, copy, readonly) NSString* uniqueID;
@property(nonatomic, copy, readonly) NSString* title;
@property(nonatomic, readonly) NSInteger index;
@property(nonatomic, readonly, getter=isSelected) BOOL selected;
@property(nonatomic, copy, readonly) NSArray<DTASScriptTerminal*>* terminals;
@property(nonatomic, strong) DTASScriptTerminal* focusedTerminal;
@property(nonatomic, weak) DTASScriptWindow* parentWindow;
- (instancetype)initWithIdentifier:(NSString*)identifier
                             title:(NSString*)title
                             index:(NSInteger)index
                          selected:(BOOL)selected
                         terminals:(NSArray<DTASScriptTerminal*>*)terminals;
- (NSScriptObjectSpecifier*)objectSpecifier;
@end

@interface DTASScriptWindow : NSObject
@property(nonatomic, copy, readonly) NSString* uniqueID;
@property(nonatomic, copy, readonly) NSString* title;
@property(nonatomic, readonly) NSInteger orderedIndex;
@property(nonatomic, readonly, getter=isFrontmost) BOOL frontmost;
@property(nonatomic, copy, readonly) NSArray<DTASScriptTab*>* dtasTabs;
@property(nonatomic, strong) DTASScriptTab* selectedTab;
- (instancetype)initWithIdentifier:(NSString*)identifier
                             title:(NSString*)title
                             index:(NSInteger)index
                         frontmost:(BOOL)frontmost
                              tabs:(NSArray<DTASScriptTab*>*)tabs;
- (NSScriptObjectSpecifier*)objectSpecifier;
@end

@interface DTASPendingCommand : NSObject
@property(nonatomic, readonly) uint64_t operationID;
@property(nonatomic, copy, readonly) NSData* packet;
@property(nonatomic, strong, readonly, nullable) NSScriptCommand* command;
- (instancetype)initWithOperationID:(uint64_t)operationID
                              packet:(NSData*)packet
                             command:(nullable NSScriptCommand*)command;
@end

static const da_native_extension_services_v1* g_services = NULL;
static BOOL g_started = NO;
static BOOL g_enabled = NO;
static uint64_t g_generation = 0u;
static uint64_t g_next_operation_id = 1u;
static uint64_t g_timeout_micros = DTAS_DEFAULT_TIMEOUT_MICROS;
static NSUInteger g_maximum_pending = DTAS_MAX_PENDING_COMMANDS;
static NSArray<DTASScriptWindow*>* g_windows = nil;
static NSDictionary<NSString*, id>* g_objects_by_id = nil;
static NSMutableArray<DTASPendingCommand*>* g_command_queue = nil;
static NSMutableDictionary<NSNumber*, DTASPendingCommand*>* g_pending = nil;
static _Atomic uint64_t g_resumed_count = 0u;
static _Atomic uint64_t g_rejected_count = 0u;

static BOOL DtasIsMainThread(void) { return [NSThread isMainThread]; }

static BOOL DtasExactKeys(NSDictionary* value, NSArray<NSString*>* keys) {
  if (value.count != keys.count) return NO;
  for (NSString* key in keys) {
    if (value[key] == nil) return NO;
  }
  return YES;
}

static BOOL DtasIsBoolean(id value) {
  return [value isKindOfClass:[NSNumber class]] &&
         CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

static BOOL DtasUnsignedInteger(id value, uint64_t maximum,
                                uint64_t* output) {
  if (![value isKindOfClass:[NSNumber class]] || DtasIsBoolean(value)) {
    return NO;
  }
  NSNumber* number = (NSNumber*)value;
  const double decimal = number.doubleValue;
  const uint64_t integer = number.unsignedLongLongValue;
  if (!isfinite(decimal) || decimal < 0.0 || decimal != (double)integer ||
      integer > maximum) {
    return NO;
  }
  if (output != NULL) *output = integer;
  return YES;
}

static BOOL DtasSafeText(NSString* value, NSUInteger maximum_bytes) {
  if (![value isKindOfClass:[NSString class]] ||
      [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > maximum_bytes) {
    return NO;
  }
  __block BOOL safe = YES;
  [value enumerateSubstringsInRange:NSMakeRange(0, value.length)
                            options:NSStringEnumerationByComposedCharacterSequences
                         usingBlock:^(NSString* substring, NSRange range,
                                      NSRange enclosingRange, BOOL* stop) {
                           (void)range;
                           (void)enclosingRange;
                           for (NSUInteger index = 0; index < substring.length;
                                ++index) {
                             const unichar scalar =
                                 [substring characterAtIndex:index];
                             if (scalar <= 0x1fu ||
                                 (scalar >= 0x7fu && scalar <= 0x9fu) ||
                                 scalar == 0x061cu || scalar == 0x200eu ||
                                 scalar == 0x200fu || scalar == 0x2028u ||
                                 scalar == 0x2029u ||
                                 (scalar >= 0x202au && scalar <= 0x202eu) ||
                                 (scalar >= 0x2066u && scalar <= 0x2069u) ||
                                 (scalar >= 0xd800u && scalar <= 0xdfffu)) {
                               safe = NO;
                               *stop = YES;
                               return;
                             }
                           }
                         }];
  return safe;
}

static BOOL DtasValidIdentifier(NSString* value, NSString* prefix) {
  if (![value isKindOfClass:[NSString class]] ||
      [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >
          DTAS_MAX_OBJECT_ID_BYTES ||
      ![value hasPrefix:[prefix stringByAppendingString:@":"]]) {
    return NO;
  }
  NSString* digits = [value substringFromIndex:prefix.length + 1u];
  if (digits.length == 0u ||
      (digits.length > 1u && [digits hasPrefix:@"0"]) || digits.length > 19u) {
    return NO;
  }
  for (NSUInteger index = 0; index < digits.length; ++index) {
    const unichar unit = [digits characterAtIndex:index];
    if (unit < '0' || unit > '9') return NO;
  }
  unsigned long long parsed = 0u;
  NSScanner* scanner = [NSScanner scannerWithString:digits];
  if (![scanner scanUnsignedLongLong:&parsed] || !scanner.isAtEnd ||
      parsed == 0u || parsed > INT64_MAX) {
    return NO;
  }
  return YES;
}

static id DtasSingleObject(id value) {
  if ([value isKindOfClass:[NSArray class]]) {
    NSArray* values = (NSArray*)value;
    return values.count == 1u ? values.firstObject : nil;
  }
  return value;
}

static NSString* DtasIdentifierForObject(id value, Class expected_class) {
  id object = DtasSingleObject(value);
  if (![object isKindOfClass:expected_class]) return nil;
  return [object valueForKey:@"uniqueID"];
}

@implementation DTASScriptTerminal

- (instancetype)initWithIdentifier:(NSString*)identifier
                             title:(NSString*)title
                  workingDirectory:(NSString*)workingDirectory {
  self = [super init];
  if (self != nil) {
    _uniqueID = [identifier copy];
    _title = [title copy];
    _workingDirectory = [workingDirectory copy];
  }
  return self;
}

- (NSScriptObjectSpecifier*)objectSpecifier {
  DTASScriptTab* parent = self.parentTab;
  if (parent == nil) return nil;
  NSScriptClassDescription* description =
      (NSScriptClassDescription*)parent.classDescription;
  return [[NSUniqueIDSpecifier alloc]
      initWithContainerClassDescription:description
                      containerSpecifier:parent.objectSpecifier
                                     key:@"terminals"
                                uniqueID:self.uniqueID];
}

@end

@implementation DTASScriptTab

- (instancetype)initWithIdentifier:(NSString*)identifier
                             title:(NSString*)title
                             index:(NSInteger)index
                          selected:(BOOL)selected
                         terminals:(NSArray<DTASScriptTerminal*>*)terminals {
  self = [super init];
  if (self != nil) {
    _uniqueID = [identifier copy];
    _title = [title copy];
    _index = index;
    _selected = selected;
    _terminals = [terminals copy];
    for (DTASScriptTerminal* terminal in _terminals) {
      terminal.parentTab = self;
    }
  }
  return self;
}

- (NSScriptObjectSpecifier*)objectSpecifier {
  DTASScriptWindow* parent = self.parentWindow;
  if (parent == nil) return nil;
  NSScriptClassDescription* description =
      (NSScriptClassDescription*)parent.classDescription;
  return [[NSUniqueIDSpecifier alloc]
      initWithContainerClassDescription:description
                      containerSpecifier:parent.objectSpecifier
                                     key:@"dtasTabs"
                                uniqueID:self.uniqueID];
}

@end

@implementation DTASScriptWindow

- (instancetype)initWithIdentifier:(NSString*)identifier
                             title:(NSString*)title
                             index:(NSInteger)index
                         frontmost:(BOOL)frontmost
                              tabs:(NSArray<DTASScriptTab*>*)tabs {
  self = [super init];
  if (self != nil) {
    _uniqueID = [identifier copy];
    _title = [title copy];
    _orderedIndex = index;
    _frontmost = frontmost;
    _dtasTabs = [tabs copy];
    for (DTASScriptTab* tab in _dtasTabs) {
      tab.parentWindow = self;
    }
  }
  return self;
}

- (NSScriptObjectSpecifier*)objectSpecifier {
  NSScriptClassDescription* description =
      (NSScriptClassDescription*)NSApp.classDescription;
  return [[NSUniqueIDSpecifier alloc]
      initWithContainerClassDescription:description
                      containerSpecifier:nil
                                     key:@"dtasWindows"
                                uniqueID:self.uniqueID];
}

@end

@implementation DTASPendingCommand

- (instancetype)initWithOperationID:(uint64_t)operationID
                              packet:(NSData*)packet
                             command:(NSScriptCommand*)command {
  self = [super init];
  if (self != nil) {
    _operationID = operationID;
    _packet = [packet copy];
    _command = command;
  }
  return self;
}

@end


@interface NSApplication (DTASApplicationScripting)
- (NSArray<DTASScriptWindow*>*)dtasWindows;
- (BOOL)dtasScriptingEnabled;
@end

@implementation NSApplication (DTASApplicationScripting)

- (NSArray<DTASScriptWindow*>*)dtasWindows {
  return DtasIsMainThread() && g_started && g_enabled
             ? (g_windows != nil ? g_windows : @[])
             : @[];
}

- (BOOL)dtasScriptingEnabled {
  return DtasIsMainThread() && g_started && g_enabled;
}

@end

static NSInteger DtasErrorNumber(uint32_t disposition) {
  switch (disposition) {
    case DTAS_COMMAND_NOT_FOUND:
      return NSReceiverEvaluationScriptError;
    case DTAS_COMMAND_REJECTED:
      return NSArgumentsWrongScriptError;
    case DTAS_COMMAND_CONFIRMATION_REQUIRED:
    case DTAS_COMMAND_DISABLED:
    case DTAS_COMMAND_BUSY:
      return NSOperationNotSupportedForKeyScriptError;
    case DTAS_COMMAND_TIMED_OUT:
    case DTAS_COMMAND_DISPOSED:
    case DTAS_COMMAND_FAILED:
    default:
      return NSInternalScriptError;
  }
}

static NSString* DtasErrorMessage(uint32_t disposition) {
  switch (disposition) {
    case DTAS_COMMAND_CONFIRMATION_REQUIRED:
      return @"Terminal input confirmation is required; repeat the command to approve.";
    case DTAS_COMMAND_DISABLED:
      return @"Terminal AppleScript automation is disabled.";
    case DTAS_COMMAND_NOT_FOUND:
      return @"The target terminal object no longer exists.";
    case DTAS_COMMAND_BUSY:
      return @"The terminal automation queue is busy.";
    case DTAS_COMMAND_REJECTED:
      return @"The terminal automation command was rejected.";
    case DTAS_COMMAND_TIMED_OUT:
      return @"The terminal automation command timed out.";
    case DTAS_COMMAND_DISPOSED:
      return @"The terminal automation session was disposed.";
    default:
      return @"The terminal automation command failed.";
  }
}

static id DtasFindObject(NSString* identifier) {
  return identifier == nil ? nil : g_objects_by_id[identifier];
}

static NSString* DtasPendingCommandKind(DTASPendingCommand* pending) {
  NSError* error = nil;
  id decoded = [NSJSONSerialization JSONObjectWithData:pending.packet
                                                options:0
                                                  error:&error];
  if (error != nil || ![decoded isKindOfClass:[NSDictionary class]]) return nil;
  id kind = [(NSDictionary*)decoded objectForKey:@"kind"];
  return [kind isKindOfClass:[NSString class]] ? kind : nil;
}

static NSString* DtasCompletedObjectPrefix(NSString* command_kind) {
  if ([command_kind isEqualToString:@"newWindow"]) return @"window";
  if ([command_kind isEqualToString:@"newTab"]) return @"tab";
  if ([command_kind isEqualToString:@"split"]) return @"terminal";
  return nil;
}

static void DtasCompletePending(DTASPendingCommand* pending,
                                uint32_t disposition, NSString* object_id) {
  NSNumber* key = @(pending.operationID);
  if (g_pending[key] != pending) return;
  [g_pending removeObjectForKey:key];
  [g_command_queue removeObjectIdenticalTo:pending];
  NSScriptCommand* command = pending.command;
  if (command != nil) {
    if (disposition == DTAS_COMMAND_COMPLETED) {
      id result = object_id == nil ? @YES : DtasFindObject(object_id);
      if (result == nil) {
        command.scriptErrorNumber = NSReceiverEvaluationScriptError;
        command.scriptErrorString = @"The resulting terminal object is unavailable.";
        [command resumeExecutionWithResult:nil];
      } else {
        [command resumeExecutionWithResult:result];
      }
    } else {
      command.scriptErrorNumber = DtasErrorNumber(disposition);
      command.scriptErrorString = DtasErrorMessage(disposition);
      [command resumeExecutionWithResult:nil];
    }
  }
  atomic_fetch_add_explicit(&g_resumed_count, 1u, memory_order_relaxed);
}

static BOOL DtasCommandPacket(NSDictionary* packet, uint64_t* operation_id) {
  if (!DtasExactKeys(packet, @[
        @"version", @"operationId", @"kind", @"target", @"direction", @"text"
      ]) ||
      ![packet[@"kind"] isKindOfClass:[NSString class]]) {
    return NO;
  }
  uint64_t version = 0u;
  uint64_t operation = 0u;
  if (!DtasUnsignedInteger(packet[@"version"], DTAS_COMMAND_VERSION, &version) ||
      version != DTAS_COMMAND_VERSION ||
      !DtasUnsignedInteger(packet[@"operationId"], INT64_MAX, &operation) ||
      operation == 0u) {
    return NO;
  }
  NSString* kind = packet[@"kind"];
  id target = packet[@"target"];
  id direction = packet[@"direction"];
  id text = packet[@"text"];
  const BOOL null_target = target == [NSNull null];
  const BOOL null_direction = direction == [NSNull null];
  const BOOL null_text = text == [NSNull null];
  BOOL shape = NO;
  if ([kind isEqualToString:@"newWindow"]) {
    shape = null_target && null_direction && null_text;
  } else if ([kind isEqualToString:@"newTab"] ||
             [kind isEqualToString:@"closeWindow"]) {
    shape = DtasValidIdentifier(target, @"window") && null_direction && null_text;
  } else if ([kind isEqualToString:@"closeTab"]) {
    shape = DtasValidIdentifier(target, @"tab") && null_direction && null_text;
  } else if ([kind isEqualToString:@"focus"] ||
             [kind isEqualToString:@"closeTerminal"]) {
    shape = DtasValidIdentifier(target, @"terminal") && null_direction && null_text;
  } else if ([kind isEqualToString:@"split"]) {
    shape = DtasValidIdentifier(target, @"terminal") &&
            [direction isKindOfClass:[NSString class]] &&
            ([(NSString*)direction isEqualToString:@"right"] ||
             [(NSString*)direction isEqualToString:@"left"] ||
             [(NSString*)direction isEqualToString:@"down"] ||
             [(NSString*)direction isEqualToString:@"up"]) &&
            null_text;
  } else if ([kind isEqualToString:@"inputText"]) {
    shape = DtasValidIdentifier(target, @"terminal") && null_direction &&
            [text isKindOfClass:[NSString class]] &&
            [(NSString*)text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 0u &&
            [(NSString*)text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <=
                64u * 1024u * 1024u;
  }
  if (!shape) return NO;
  if (operation_id != NULL) *operation_id = operation;
  return YES;
}

static int32_t DtasEnqueuePacket(NSData* packet, NSScriptCommand* command) {
  if (!g_started) return DTAS_STATUS_NOT_INITIALIZED;
  if (!g_enabled) return DTAS_STATUS_DISABLED;
  if (g_pending.count >= g_maximum_pending) {
    return DTAS_STATUS_RESOURCE_EXHAUSTED;
  }
  NSError* error = nil;
  id decoded = [NSJSONSerialization JSONObjectWithData:packet options:0 error:&error];
  uint64_t operation_id = 0u;
  if (error != nil || ![decoded isKindOfClass:[NSDictionary class]] ||
      !DtasCommandPacket((NSDictionary*)decoded, &operation_id) ||
      g_pending[@(operation_id)] != nil) {
    return DTAS_STATUS_INVALID_ARGUMENT;
  }
  if (command != nil) [command suspendExecution];
  DTASPendingCommand* pending =
      [[DTASPendingCommand alloc] initWithOperationID:operation_id
                                               packet:packet
                                              command:command];
  g_pending[@(operation_id)] = pending;
  [g_command_queue addObject:pending];
  const uint64_t timeout = g_timeout_micros;
  dispatch_after(
      dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * 1000u)),
      dispatch_get_main_queue(), ^{
        DTASPendingCommand* current = g_pending[@(operation_id)];
        if (current == pending) {
          DtasCompletePending(current, DTAS_COMMAND_TIMED_OUT, nil);
        }
      });
  return DTAS_STATUS_OK;
}

static NSData* DtasCreateCommandPacket(NSString* kind, NSString* target,
                                      NSString* direction, NSString* text,
                                      uint64_t* operation_id) {
  if (g_next_operation_id == 0u || g_next_operation_id > INT64_MAX) return nil;
  const uint64_t assigned = g_next_operation_id++;
  NSDictionary* object = @{
    @"version" : @(DTAS_COMMAND_VERSION),
    @"operationId" : @(assigned),
    @"kind" : kind,
    @"target" : target != nil ? target : [NSNull null],
    @"direction" : direction != nil ? direction : [NSNull null],
    @"text" : text != nil ? text : [NSNull null],
  };
  NSError* error = nil;
  NSData* data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
  if (error != nil || data.length == 0u || data.length > DTAS_MAX_COMMAND_BYTES) {
    return nil;
  }
  if (operation_id != NULL) *operation_id = assigned;
  return data;
}

static id DtasRejectCommand(NSScriptCommand* command, int32_t status) {
  atomic_fetch_add_explicit(&g_rejected_count, 1u, memory_order_relaxed);
  command.scriptErrorNumber =
      status == DTAS_STATUS_DISABLED ? NSOperationNotSupportedForKeyScriptError
                                     : NSArgumentsWrongScriptError;
  command.scriptErrorString =
      status == DTAS_STATUS_DISABLED
          ? @"Terminal AppleScript automation is disabled."
          : @"The terminal automation command is invalid or busy.";
  return nil;
}

static id DtasSubmitCommand(NSScriptCommand* command, NSString* kind,
                            NSString* target, NSString* direction,
                            NSString* text) {
  uint64_t operation_id = 0u;
  NSData* packet =
      DtasCreateCommandPacket(kind, target, direction, text, &operation_id);
  (void)operation_id;
  if (packet == nil) return DtasRejectCommand(command, DTAS_STATUS_INTERNAL);
  const int32_t status = DtasEnqueuePacket(packet, command);
  return status == DTAS_STATUS_OK ? nil : DtasRejectCommand(command, status);
}

static id DtasEvaluatedTargetArgument(NSScriptCommand* command) {
  return DtasSingleObject(command.evaluatedArguments[@"Target"]);
}

static NSString* DtasDirection(NSScriptCommand* command) {
  id value = command.evaluatedArguments[@"Direction"];
  if ([value isKindOfClass:[NSString class]]) {
    NSString* text = [(NSString*)value lowercaseString];
    if ([text isEqualToString:@"right"] || [text isEqualToString:@"left"] ||
        [text isEqualToString:@"down"] || [text isEqualToString:@"up"]) {
      return text;
    }
  }
  if ([value isKindOfClass:[NSNumber class]]) {
    switch ([(NSNumber*)value unsignedIntValue]) {
      case 0x72676874u:
        return @"right";
      case 0x6c656674u:
        return @"left";
      case 0x646f776eu:
        return @"down";
      case 0x75702020u:
        return @"up";
      default:
        break;
    }
  }
  return nil;
}

@interface DTASNewWindowCommand : NSScriptCommand
@end
@implementation DTASNewWindowCommand
- (id)performDefaultImplementation {
  return DtasSubmitCommand(self, @"newWindow", nil, nil, nil);
}
@end

@interface DTASNewTabCommand : NSScriptCommand
@end
@implementation DTASNewTabCommand
- (id)performDefaultImplementation {
  NSString* target = DtasIdentifierForObject(
      DtasEvaluatedTargetArgument(self), [DTASScriptWindow class]);
  return target == nil ? DtasRejectCommand(self, DTAS_STATUS_INVALID_ARGUMENT)
                       : DtasSubmitCommand(self, @"newTab", target, nil, nil);
}
@end

@interface DTASSplitCommand : NSScriptCommand
@end
@implementation DTASSplitCommand
- (id)performDefaultImplementation {
  NSString* target = DtasIdentifierForObject(self.evaluatedReceivers,
                                              [DTASScriptTerminal class]);
  NSString* direction = DtasDirection(self);
  return target == nil || direction == nil
             ? DtasRejectCommand(self, DTAS_STATUS_INVALID_ARGUMENT)
             : DtasSubmitCommand(self, @"split", target, direction, nil);
}
@end

@interface DTASInputTextCommand : NSScriptCommand
@end
@implementation DTASInputTextCommand
- (id)performDefaultImplementation {
  NSString* target = DtasIdentifierForObject(
      DtasEvaluatedTargetArgument(self), [DTASScriptTerminal class]);
  id direct = self.directParameter;
  if (![direct isKindOfClass:[NSString class]] || [(NSString*)direct length] == 0u ||
      [(NSString*)direct lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >
          64u * 1024u * 1024u || target == nil) {
    return DtasRejectCommand(self, DTAS_STATUS_INVALID_ARGUMENT);
  }
  return DtasSubmitCommand(self, @"inputText", target, nil, direct);
}
@end

@interface DTASFocusCommand : NSScriptCommand
@end
@implementation DTASFocusCommand
- (id)performDefaultImplementation {
  NSString* target = DtasIdentifierForObject(self.evaluatedReceivers,
                                              [DTASScriptTerminal class]);
  return target == nil ? DtasRejectCommand(self, DTAS_STATUS_INVALID_ARGUMENT)
                       : DtasSubmitCommand(self, @"focus", target, nil, nil);
}
@end

@interface DTASCloseCommand : NSScriptCommand
@end
@implementation DTASCloseCommand
- (id)performDefaultImplementation {
  id receiver = DtasSingleObject(self.evaluatedReceivers);
  NSString* kind = nil;
  if ([receiver isKindOfClass:[DTASScriptTerminal class]]) {
    kind = @"closeTerminal";
  } else if ([receiver isKindOfClass:[DTASScriptTab class]]) {
    kind = @"closeTab";
  } else if ([receiver isKindOfClass:[DTASScriptWindow class]]) {
    kind = @"closeWindow";
  }
  NSString* target =
      kind == nil ? nil : [receiver valueForKey:@"uniqueID"];
  return target == nil ? DtasRejectCommand(self, DTAS_STATUS_INVALID_ARGUMENT)
                       : DtasSubmitCommand(self, kind, target, nil, nil);
}
@end

static BOOL DtasBuildSnapshot(NSDictionary* root,
                              NSArray<DTASScriptWindow*>** windows_output,
                              NSDictionary<NSString*, id>** objects_output,
                              uint64_t* generation_output,
                              BOOL* enabled_output) {
  if (!DtasExactKeys(root, @[@"version", @"generation", @"enabled", @"windows"]) ||
      !DtasIsBoolean(root[@"enabled"]) ||
      ![root[@"windows"] isKindOfClass:[NSArray class]]) {
    return NO;
  }
  uint64_t version = 0u;
  uint64_t generation = 0u;
  if (!DtasUnsignedInteger(root[@"version"], DTAS_SNAPSHOT_VERSION, &version) ||
      version != DTAS_SNAPSHOT_VERSION ||
      !DtasUnsignedInteger(root[@"generation"], INT64_MAX, &generation)) {
    return NO;
  }
  const BOOL enabled = [root[@"enabled"] boolValue];
  NSArray* window_values = root[@"windows"];
  if (window_values.count > DTAS_MAX_WINDOWS ||
      (!enabled && window_values.count != 0u)) {
    return NO;
  }
  NSMutableArray<DTASScriptWindow*>* windows = [NSMutableArray array];
  NSMutableDictionary<NSString*, id>* objects = [NSMutableDictionary dictionary];
  NSUInteger total_terminals = 0u;
  NSUInteger frontmost_count = 0u;
  for (NSUInteger window_position = 0u; window_position < window_values.count;
       ++window_position) {
    id raw_window = window_values[window_position];
    if (![raw_window isKindOfClass:[NSDictionary class]]) return NO;
    NSDictionary* window = raw_window;
    if (!DtasExactKeys(window, @[
          @"id", @"title", @"index", @"frontmost", @"selectedTab", @"tabs"
        ]) ||
        !DtasValidIdentifier(window[@"id"], @"window") ||
        !DtasSafeText(window[@"title"], kMaximumTitleBytes) ||
        !DtasIsBoolean(window[@"frontmost"]) ||
        !DtasValidIdentifier(window[@"selectedTab"], @"tab") ||
        ![window[@"tabs"] isKindOfClass:[NSArray class]]) {
      return NO;
    }
    uint64_t window_index = 0u;
    if (!DtasUnsignedInteger(window[@"index"], DTAS_MAX_WINDOWS,
                             &window_index) ||
        window_index != window_position + 1u ||
        objects[window[@"id"]] != nil) {
      return NO;
    }
    if ([window[@"frontmost"] boolValue]) ++frontmost_count;
    if (frontmost_count > 1u) return NO;
    NSArray* tab_values = window[@"tabs"];
    if (tab_values.count == 0u ||
        tab_values.count > DTAS_MAX_TABS_PER_WINDOW) {
      return NO;
    }
    NSMutableArray<DTASScriptTab*>* tabs = [NSMutableArray array];
    DTASScriptTab* selected_tab = nil;
    for (NSUInteger tab_position = 0u; tab_position < tab_values.count;
         ++tab_position) {
      id raw_tab = tab_values[tab_position];
      if (![raw_tab isKindOfClass:[NSDictionary class]]) return NO;
      NSDictionary* tab = raw_tab;
      if (!DtasExactKeys(tab, @[
            @"id", @"title", @"index", @"selected", @"focusedTerminal",
            @"terminals"
          ]) ||
          !DtasValidIdentifier(tab[@"id"], @"tab") ||
          !DtasSafeText(tab[@"title"], kMaximumTitleBytes) ||
          !DtasIsBoolean(tab[@"selected"]) ||
          !DtasValidIdentifier(tab[@"focusedTerminal"], @"terminal") ||
          ![tab[@"terminals"] isKindOfClass:[NSArray class]]) {
        return NO;
      }
      uint64_t tab_index = 0u;
      if (!DtasUnsignedInteger(tab[@"index"], DTAS_MAX_TABS_PER_WINDOW,
                               &tab_index) ||
          tab_index != tab_position + 1u || objects[tab[@"id"]] != nil) {
        return NO;
      }
      NSArray* terminal_values = tab[@"terminals"];
      if (terminal_values.count == 0u ||
          total_terminals + terminal_values.count > DTAS_MAX_TERMINALS) {
        return NO;
      }
      NSMutableArray<DTASScriptTerminal*>* terminals = [NSMutableArray array];
      DTASScriptTerminal* focused_terminal = nil;
      for (id raw_terminal in terminal_values) {
        if (![raw_terminal isKindOfClass:[NSDictionary class]]) return NO;
        NSDictionary* terminal = raw_terminal;
        if (!DtasExactKeys(terminal,
                           @[@"id", @"title", @"workingDirectory"]) ||
            !DtasValidIdentifier(terminal[@"id"], @"terminal") ||
            !DtasSafeText(terminal[@"title"], kMaximumTitleBytes) ||
            objects[terminal[@"id"]] != nil) {
          return NO;
        }
        id cwd_value = terminal[@"workingDirectory"];
        NSString* cwd = @"";
        if (cwd_value != [NSNull null]) {
          if (!DtasSafeText(cwd_value, kMaximumWorkingDirectoryBytes) ||
              ![(NSString*)cwd_value hasPrefix:@"/"]) {
            return NO;
          }
          cwd = cwd_value;
        }
        DTASScriptTerminal* terminal_object =
            [[DTASScriptTerminal alloc] initWithIdentifier:terminal[@"id"]
                                                    title:terminal[@"title"]
                                         workingDirectory:cwd];
        objects[terminal_object.uniqueID] = terminal_object;
        [terminals addObject:terminal_object];
        if ([terminal_object.uniqueID
                isEqualToString:tab[@"focusedTerminal"]]) {
          focused_terminal = terminal_object;
        }
      }
      total_terminals += terminal_values.count;
      if (focused_terminal == nil) return NO;
      DTASScriptTab* tab_object =
          [[DTASScriptTab alloc] initWithIdentifier:tab[@"id"]
                                             title:tab[@"title"]
                                             index:(NSInteger)tab_index
                                          selected:[tab[@"selected"] boolValue]
                                         terminals:terminals];
      tab_object.focusedTerminal = focused_terminal;
      objects[tab_object.uniqueID] = tab_object;
      [tabs addObject:tab_object];
      if ([tab_object.uniqueID isEqualToString:window[@"selectedTab"]]) {
        if (!tab_object.isSelected || selected_tab != nil) return NO;
        selected_tab = tab_object;
      } else if (tab_object.isSelected) {
        return NO;
      }
    }
    if (selected_tab == nil) return NO;
    DTASScriptWindow* window_object =
        [[DTASScriptWindow alloc] initWithIdentifier:window[@"id"]
                                              title:window[@"title"]
                                              index:(NSInteger)window_index
                                          frontmost:[window[@"frontmost"] boolValue]
                                               tabs:tabs];
    window_object.selectedTab = selected_tab;
    objects[window_object.uniqueID] = window_object;
    [windows addObject:window_object];
  }
  *windows_output = [windows copy];
  *objects_output = [objects copy];
  *generation_output = generation;
  *enabled_output = enabled;
  return YES;
}

uint32_t dtas_abi_version(void) { return DTAS_ABI_VERSION; }

int32_t dtas_initialize(const da_native_extension_services_v1* services) {
  if (!DtasIsMainThread()) return DTAS_STATUS_WRONG_THREAD;
  if (services == NULL ||
      services->struct_size <
          offsetof(da_native_extension_services_v1,
                   register_custom_view_provider) +
              sizeof(services->register_custom_view_provider) ||
      services->abi_version != DA_NATIVE_EXTENSION_ABI_VERSION) {
    return DTAS_STATUS_UNSUPPORTED_VERSION;
  }
  if (g_services != NULL) {
    return g_services == services ? DTAS_STATUS_OK : DTAS_STATUS_INVALID_ARGUMENT;
  }
  g_services = services;
  return DTAS_STATUS_OK;
}

int32_t dtas_session_start(uint32_t maximum_pending_commands,
                           uint64_t timeout_micros) {
  if (!DtasIsMainThread()) return DTAS_STATUS_WRONG_THREAD;
  if (g_services == NULL) return DTAS_STATUS_NOT_INITIALIZED;
  if (g_started) return DTAS_STATUS_ALREADY_STARTED;
  if (maximum_pending_commands == 0u ||
      maximum_pending_commands > DTAS_MAX_PENDING_COMMANDS ||
      timeout_micros == 0u || timeout_micros > DTAS_MAX_TIMEOUT_MICROS) {
    return DTAS_STATUS_INVALID_ARGUMENT;
  }
  g_started = YES;
  g_enabled = NO;
  g_generation = 0u;
  g_next_operation_id = 1u;
  g_timeout_micros = timeout_micros;
  g_maximum_pending = maximum_pending_commands;
  g_windows = @[];
  g_objects_by_id = @{};
  g_command_queue = [NSMutableArray array];
  g_pending = [NSMutableDictionary dictionary];
  atomic_store_explicit(&g_resumed_count, 0u, memory_order_relaxed);
  atomic_store_explicit(&g_rejected_count, 0u, memory_order_relaxed);
  return DTAS_STATUS_OK;
}

int32_t dtas_publish_snapshot(const uint8_t* bytes, size_t length) {
  if (!DtasIsMainThread()) return DTAS_STATUS_WRONG_THREAD;
  if (!g_started) return DTAS_STATUS_NOT_INITIALIZED;
  if (bytes == NULL || length == 0u || length > DTAS_MAX_SNAPSHOT_BYTES) {
    return DTAS_STATUS_INVALID_ARGUMENT;
  }
  NSData* data = [NSData dataWithBytes:bytes length:length];
  NSError* error = nil;
  id decoded = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  NSArray<DTASScriptWindow*>* windows = nil;
  NSDictionary<NSString*, id>* objects = nil;
  uint64_t generation = 0u;
  BOOL enabled = NO;
  if (error != nil || ![decoded isKindOfClass:[NSDictionary class]] ||
      !DtasBuildSnapshot((NSDictionary*)decoded, &windows, &objects,
                         &generation, &enabled)) {
    return DTAS_STATUS_INVALID_ARGUMENT;
  }
  g_windows = windows;
  g_objects_by_id = objects;
  g_generation = generation;
  g_enabled = enabled;
  if (!enabled && g_pending.count != 0u) {
    NSArray<DTASPendingCommand*>* pending = g_pending.allValues;
    for (DTASPendingCommand* command in pending) {
      DtasCompletePending(command, DTAS_COMMAND_DISABLED, nil);
    }
  }
  return DTAS_STATUS_OK;
}

int32_t dtas_take_command(uint8_t* output, size_t capacity,
                          size_t* output_length) {
  if (!DtasIsMainThread()) return DTAS_STATUS_WRONG_THREAD;
  if (!g_started) return DTAS_STATUS_NOT_INITIALIZED;
  if (output_length == NULL) return DTAS_STATUS_INVALID_ARGUMENT;
  if (g_command_queue.count == 0u) {
    *output_length = 0u;
    return DTAS_STATUS_NOT_FOUND;
  }
  DTASPendingCommand* pending = g_command_queue.firstObject;
  *output_length = pending.packet.length;
  if (output == NULL || capacity < pending.packet.length) {
    return DTAS_STATUS_BUFFER_TOO_SMALL;
  }
  memcpy(output, pending.packet.bytes, pending.packet.length);
  [g_command_queue removeObjectAtIndex:0u];
  return DTAS_STATUS_OK;
}

int32_t dtas_complete_command(uint64_t operation_id, uint32_t disposition,
                              const uint8_t* object_id,
                              size_t object_id_length) {
  if (!DtasIsMainThread()) return DTAS_STATUS_WRONG_THREAD;
  if (!g_started) return DTAS_STATUS_NOT_INITIALIZED;
  if (operation_id == 0u || disposition > DTAS_COMMAND_DISPOSED ||
      (object_id == NULL) != (object_id_length == 0u) ||
      object_id_length > DTAS_MAX_OBJECT_ID_BYTES ||
      (disposition != DTAS_COMMAND_COMPLETED && object_id_length != 0u)) {
    return DTAS_STATUS_INVALID_ARGUMENT;
  }
  DTASPendingCommand* pending = g_pending[@(operation_id)];
  if (pending == nil) return DTAS_STATUS_NOT_FOUND;
  NSString* identifier = nil;
  NSString* command_kind = DtasPendingCommandKind(pending);
  if (command_kind == nil) return DTAS_STATUS_INTERNAL;
  NSString* expected_prefix = DtasCompletedObjectPrefix(command_kind);
  if (disposition == DTAS_COMMAND_COMPLETED &&
      ((expected_prefix != nil) != (object_id_length != 0u))) {
    return DTAS_STATUS_INVALID_ARGUMENT;
  }
  if (object_id_length != 0u) {
    identifier = [[NSString alloc] initWithBytes:object_id
                                         length:object_id_length
                                       encoding:NSASCIIStringEncoding];
    if (identifier == nil ||
        !DtasValidIdentifier(identifier, expected_prefix)) {
      return DTAS_STATUS_INVALID_ARGUMENT;
    }
    if (DtasFindObject(identifier) == nil) {
      return DTAS_STATUS_NOT_FOUND;
    }
  }
  DtasCompletePending(pending, disposition, identifier);
  return DTAS_STATUS_OK;
}

int32_t dtas_session_shutdown(void) {
  if (!DtasIsMainThread()) return DTAS_STATUS_WRONG_THREAD;
  if (!g_started) return DTAS_STATUS_NOT_INITIALIZED;
  NSArray<DTASPendingCommand*>* pending = g_pending.allValues;
  for (DTASPendingCommand* command in pending) {
    DtasCompletePending(command, DTAS_COMMAND_DISPOSED, nil);
  }
  g_started = NO;
  g_enabled = NO;
  g_generation = 0u;
  g_windows = nil;
  g_objects_by_id = nil;
  g_command_queue = nil;
  g_pending = nil;
  return DTAS_STATUS_OK;
}

int32_t dtas_debug_summary(DtasSummaryV1* summary) {
  if (!DtasIsMainThread()) return DTAS_STATUS_WRONG_THREAD;
  if (summary == NULL || summary->struct_size < sizeof(DtasSummaryV1) ||
      summary->version != DTAS_SUMMARY_VERSION) {
    return DTAS_STATUS_INVALID_ARGUMENT;
  }
  uint64_t tab_count = 0u;
  uint64_t terminal_count = 0u;
  for (DTASScriptWindow* window in
       (g_windows != nil ? g_windows : @[])) {
    tab_count += window.dtasTabs.count;
    for (DTASScriptTab* tab in window.dtasTabs) {
      terminal_count += tab.terminals.count;
    }
  }
  summary->generation = g_generation;
  summary->window_count = g_windows.count;
  summary->tab_count = tab_count;
  summary->terminal_count = terminal_count;
  summary->queued_command_count = g_command_queue.count;
  summary->pending_command_count = g_pending.count;
  summary->resumed_command_count =
      atomic_load_explicit(&g_resumed_count, memory_order_relaxed);
  summary->rejected_command_count =
      atomic_load_explicit(&g_rejected_count, memory_order_relaxed);
  summary->started = g_started ? 1u : 0u;
  summary->enabled = g_enabled ? 1u : 0u;
  memset(summary->reserved, 0, sizeof(summary->reserved));
  return DTAS_STATUS_OK;
}

int32_t dtas_enqueue_self_automation_command(const uint8_t* bytes,
                                             size_t length) {
  if (!DtasIsMainThread()) return DTAS_STATUS_WRONG_THREAD;
  if (bytes == NULL || length == 0u || length > DTAS_MAX_COMMAND_BYTES) {
    return DTAS_STATUS_INVALID_ARGUMENT;
  }
  const int32_t status =
      DtasEnqueuePacket([NSData dataWithBytes:bytes length:length], nil);
  if (status != DTAS_STATUS_OK) {
    atomic_fetch_add_explicit(&g_rejected_count, 1u, memory_order_relaxed);
  }
  return status;
}
