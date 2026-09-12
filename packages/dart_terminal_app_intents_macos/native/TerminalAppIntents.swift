import AppIntents
import Foundation

private let statusOK: Int32 = 0
private let statusInvalidArgument: Int32 = 1
private let statusNotInitialized: Int32 = 3
private let statusAlreadyStarted: Int32 = 4
private let statusNotFound: Int32 = 5
private let statusResourceExhausted: Int32 = 6
private let statusWrongThread: Int32 = 7
private let statusDisabled: Int32 = 8
private let statusStaleGeneration: Int32 = 9
private let statusInternal: Int32 = 10
private let maximumPendingCommands: UInt32 = 16
private let maximumTimeoutMicros: UInt64 = 300 * 1_000_000

private enum TerminalIntentAction: UInt32, Sendable {
  case newWindow = 1
  case newTab = 2
  case toggleQuickTerminal = 3
}

private enum TerminalIntentOutcome: UInt32, Sendable {
  case completed = 0
  case rejected = 1
  case failed = 2
  case disabled = 3
  case timedOut = 4
  case disposed = 5
}

private enum TerminalIntentError: LocalizedError {
  case disabled
  case unavailable
  case busy
  case timedOut
  case failed

  var errorDescription: String? {
    switch self {
    case .disabled:
      return "This terminal action is disabled in Settings."
    case .unavailable:
      return "The terminal action is currently unavailable."
    case .busy:
      return "The terminal is busy. Try the action again."
    case .timedOut:
      return "The terminal did not finish the action in time."
    case .failed:
      return "The terminal could not complete the action."
    }
  }
}

private final class PendingCommand: @unchecked Sendable {
  init(
    operationID: UInt64,
    generation: UInt64,
    action: TerminalIntentAction,
    continuation: CheckedContinuation<TerminalIntentOutcome, Never>?
  ) {
    self.operationID = operationID
    self.generation = generation
    self.action = action
    self.continuation = continuation
  }

  let operationID: UInt64
  let generation: UInt64
  let action: TerminalIntentAction
  let continuation: CheckedContinuation<TerminalIntentOutcome, Never>?
  var taken = false
}

private struct Admission {
  let status: Int32
  let command: PendingCommand?
  let immediateOutcome: TerminalIntentOutcome?
}

private final class TerminalIntentCommandQueue: @unchecked Sendable {
  static let shared = TerminalIntentCommandQueue()

  private let lock = NSLock()
  private var generation: UInt64 = 0
  private var nextOperationID: UInt64 = 1
  private var timeoutMicros: UInt64 = 30 * 1_000_000
  private var pendingLimit: UInt32 = maximumPendingCommands
  private var queuedOperationIDs: [UInt64] = []
  private var pending: [UInt64: PendingCommand] = [:]
  private var acceptedCount: UInt64 = 0
  private var resolvedCount: UInt64 = 0
  private var rejectedCount: UInt64 = 0
  private var timedOutCount: UInt64 = 0
  private var started = false
  private var enabled = false

  private init() {}

  func start(maximumPending: UInt32, timeout: UInt64) -> Int32 {
    guard Thread.isMainThread else { return statusWrongThread }
    guard maximumPending > 0, maximumPending <= maximumPendingCommands,
      timeout > 0, timeout <= maximumTimeoutMicros
    else {
      return statusInvalidArgument
    }
    lock.lock()
    defer { lock.unlock() }
    guard !started else { return statusAlreadyStarted }
    guard bumpGenerationLocked() else { return statusInternal }
    pendingLimit = maximumPending
    timeoutMicros = timeout
    queuedOperationIDs.removeAll(keepingCapacity: true)
    pending.removeAll(keepingCapacity: true)
    acceptedCount = 0
    resolvedCount = 0
    rejectedCount = 0
    timedOutCount = 0
    started = true
    enabled = false
    return statusOK
  }

  func setEnabled(_ value: Bool) -> Int32 {
    guard Thread.isMainThread else { return statusWrongThread }
    var resumptions: [PendingCommand] = []
    lock.lock()
    guard started else {
      lock.unlock()
      return statusNotInitialized
    }
    if enabled == value {
      lock.unlock()
      return statusOK
    }
    guard bumpGenerationLocked() else {
      lock.unlock()
      return statusInternal
    }
    enabled = value
    if !value {
      resumptions = drainLocked()
    }
    lock.unlock()
    resume(resumptions, with: .disabled)
    return statusOK
  }

  func submit(_ action: TerminalIntentAction) async -> TerminalIntentOutcome {
    await withCheckedContinuation { continuation in
      let admission = admit(action, continuation: continuation)
      if let outcome = admission.immediateOutcome {
        continuation.resume(returning: outcome)
      } else if let command = admission.command {
        scheduleTimeout(for: command)
      } else {
        continuation.resume(returning: .failed)
      }
    }
  }

  func enqueueForDebug(_ action: TerminalIntentAction) -> Int32 {
    let admission = admit(action, continuation: nil)
    if let command = admission.command {
      scheduleTimeout(for: command)
    }
    return admission.status
  }

  private func admit(
    _ action: TerminalIntentAction,
    continuation: CheckedContinuation<TerminalIntentOutcome, Never>?
  ) -> Admission {
    lock.lock()
    defer { lock.unlock() }
    guard started else {
      rejectedCount &+= 1
      return Admission(
        status: statusNotInitialized,
        command: nil,
        immediateOutcome: .disposed
      )
    }
    guard enabled else {
      rejectedCount &+= 1
      return Admission(
        status: statusDisabled,
        command: nil,
        immediateOutcome: .disabled
      )
    }
    guard pending.count < Int(pendingLimit) else {
      rejectedCount &+= 1
      return Admission(
        status: statusResourceExhausted,
        command: nil,
        immediateOutcome: .rejected
      )
    }
    guard nextOperationID < UInt64.max else {
      rejectedCount &+= 1
      return Admission(
        status: statusInternal,
        command: nil,
        immediateOutcome: .failed
      )
    }
    let operationID = nextOperationID
    nextOperationID += 1
    let command = PendingCommand(
      operationID: operationID,
      generation: generation,
      action: action,
      continuation: continuation
    )
    pending[operationID] = command
    queuedOperationIDs.append(operationID)
    acceptedCount &+= 1
    return Admission(status: statusOK, command: command, immediateOutcome: nil)
  }

  private func scheduleTimeout(for command: PendingCommand) {
    lock.lock()
    let delay = timeoutMicros
    lock.unlock()
    let operationID = command.operationID
    let generation = command.generation
    DispatchQueue.global(qos: .utility).asyncAfter(
      deadline: .now() + .nanoseconds(Int(delay * 1_000))
    ) { [weak self, operationID, generation] in
      self?.expire(operationID: operationID, generation: generation)
    }
  }

  private func expire(operationID: UInt64, generation: UInt64) {
    var expired: PendingCommand?
    lock.lock()
    if let command = pending[operationID], command.generation == generation {
      pending.removeValue(forKey: operationID)
      queuedOperationIDs.removeAll { $0 == operationID }
      resolvedCount &+= 1
      timedOutCount &+= 1
      expired = command
    }
    lock.unlock()
    expired?.continuation?.resume(returning: .timedOut)
  }

  func take(
    operationID: UnsafeMutablePointer<UInt64>?,
    generation outputGeneration: UnsafeMutablePointer<UInt64>?,
    action outputAction: UnsafeMutablePointer<UInt32>?
  ) -> Int32 {
    guard Thread.isMainThread else { return statusWrongThread }
    guard let operationID, let outputGeneration, let outputAction else {
      return statusInvalidArgument
    }
    lock.lock()
    defer { lock.unlock() }
    guard started else { return statusNotInitialized }
    while !queuedOperationIDs.isEmpty {
      let candidate = queuedOperationIDs.removeFirst()
      guard let command = pending[candidate] else { continue }
      command.taken = true
      operationID.pointee = command.operationID
      outputGeneration.pointee = command.generation
      outputAction.pointee = command.action.rawValue
      return statusOK
    }
    return statusNotFound
  }

  func complete(
    operationID: UInt64,
    generation commandGeneration: UInt64,
    disposition: UInt32
  ) -> Int32 {
    guard Thread.isMainThread else { return statusWrongThread }
    guard operationID > 0, commandGeneration > 0,
      let outcome = completionOutcome(disposition)
    else {
      return statusInvalidArgument
    }
    var command: PendingCommand?
    lock.lock()
    guard started else {
      lock.unlock()
      return statusNotInitialized
    }
    guard commandGeneration == generation else {
      lock.unlock()
      return statusStaleGeneration
    }
    guard let candidate = pending[operationID] else {
      lock.unlock()
      return statusNotFound
    }
    guard candidate.generation == commandGeneration, candidate.taken else {
      lock.unlock()
      return candidate.generation == commandGeneration
        ? statusInvalidArgument : statusStaleGeneration
    }
    pending.removeValue(forKey: operationID)
    resolvedCount &+= 1
    command = candidate
    lock.unlock()
    command?.continuation?.resume(returning: outcome)
    return statusOK
  }

  func shutdown() -> Int32 {
    guard Thread.isMainThread else { return statusWrongThread }
    var resumptions: [PendingCommand] = []
    lock.lock()
    guard started else {
      lock.unlock()
      return statusOK
    }
    guard bumpGenerationLocked() else {
      lock.unlock()
      return statusInternal
    }
    started = false
    enabled = false
    resumptions = drainLocked()
    lock.unlock()
    resume(resumptions, with: .disposed)
    return statusOK
  }

  func summary(
    generation outputGeneration: UnsafeMutablePointer<UInt64>?,
    queuedCount: UnsafeMutablePointer<UInt64>?,
    pendingCount: UnsafeMutablePointer<UInt64>?,
    acceptedCount outputAccepted: UnsafeMutablePointer<UInt64>?,
    resolvedCount outputResolved: UnsafeMutablePointer<UInt64>?,
    rejectedCount outputRejected: UnsafeMutablePointer<UInt64>?,
    timedOutCount outputTimedOut: UnsafeMutablePointer<UInt64>?,
    started outputStarted: UnsafeMutablePointer<UInt32>?,
    enabled outputEnabled: UnsafeMutablePointer<UInt32>?
  ) -> Int32 {
    guard Thread.isMainThread else { return statusWrongThread }
    guard let outputGeneration, let queuedCount, let pendingCount,
      let outputAccepted, let outputResolved, let outputRejected,
      let outputTimedOut, let outputStarted, let outputEnabled
    else {
      return statusInvalidArgument
    }
    lock.lock()
    defer { lock.unlock() }
    outputGeneration.pointee = generation
    queuedCount.pointee = UInt64(queuedOperationIDs.count)
    pendingCount.pointee = UInt64(pending.count)
    outputAccepted.pointee = acceptedCount
    outputResolved.pointee = resolvedCount
    outputRejected.pointee = rejectedCount
    outputTimedOut.pointee = timedOutCount
    outputStarted.pointee = started ? 1 : 0
    outputEnabled.pointee = enabled ? 1 : 0
    return statusOK
  }

  private func drainLocked() -> [PendingCommand] {
    let commands = Array(pending.values)
    pending.removeAll(keepingCapacity: true)
    queuedOperationIDs.removeAll(keepingCapacity: true)
    resolvedCount &+= UInt64(commands.count)
    return commands
  }

  private func resume(
    _ commands: [PendingCommand],
    with outcome: TerminalIntentOutcome
  ) {
    for command in commands {
      command.continuation?.resume(returning: outcome)
    }
  }

  private func bumpGenerationLocked() -> Bool {
    guard generation < UInt64.max else { return false }
    generation += 1
    return true
  }

  private func completionOutcome(_ value: UInt32) -> TerminalIntentOutcome? {
    switch value {
    case 0: return .completed
    case 1: return .rejected
    case 2: return .failed
    default: return nil
    }
  }
}

private func performTerminalAction(_ action: TerminalIntentAction) async throws {
  switch await TerminalIntentCommandQueue.shared.submit(action) {
  case .completed:
    return
  case .disabled:
    throw TerminalIntentError.disabled
  case .rejected:
    throw TerminalIntentError.busy
  case .timedOut:
    throw TerminalIntentError.timedOut
  case .disposed:
    throw TerminalIntentError.unavailable
  case .failed:
    throw TerminalIntentError.failed
  }
}

@available(macOS 14.0, *)
struct NewTerminalWindowIntent: AppIntent {
  static let title: LocalizedStringResource = "New Terminal Window"
  static let description = IntentDescription("Open a new terminal window.")
  static let openAppWhenRun = true

  func perform() async throws -> some IntentResult {
    try await performTerminalAction(.newWindow)
    return .result()
  }
}

@available(macOS 14.0, *)
struct NewTerminalTabIntent: AppIntent {
  static let title: LocalizedStringResource = "New Terminal Tab"
  static let description = IntentDescription("Open a new terminal tab.")
  static let openAppWhenRun = true

  func perform() async throws -> some IntentResult {
    try await performTerminalAction(.newTab)
    return .result()
  }
}

@available(macOS 14.0, *)
struct ToggleQuickTerminalIntent: AppIntent {
  static let title: LocalizedStringResource = "Toggle Quick Terminal"
  static let description = IntentDescription("Show or hide Quick Terminal.")
  static let openAppWhenRun = true

  func perform() async throws -> some IntentResult {
    try await performTerminalAction(.toggleQuickTerminal)
    return .result()
  }
}

@available(macOS 14.0, *)
struct DartTerminalShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: NewTerminalWindowIntent(),
      phrases: ["New window in \(.applicationName)"],
      shortTitle: "New Window",
      systemImageName: "macwindow.badge.plus"
    )
    AppShortcut(
      intent: NewTerminalTabIntent(),
      phrases: ["New tab in \(.applicationName)"],
      shortTitle: "New Tab",
      systemImageName: "plus.rectangle.on.rectangle"
    )
    AppShortcut(
      intent: ToggleQuickTerminalIntent(),
      phrases: ["Toggle Quick Terminal in \(.applicationName)"],
      shortTitle: "Quick Terminal",
      systemImageName: "terminal"
    )
  }
}

@_cdecl("dtai_abi_version")
public func dtaiABIVersion() -> UInt32 { 1 }

@_cdecl("dtai_session_start")
public func dtaiSessionStart(
  _ maximumPending: UInt32,
  _ timeoutMicros: UInt64
) -> Int32 {
  TerminalIntentCommandQueue.shared.start(
    maximumPending: maximumPending,
    timeout: timeoutMicros
  )
}

@_cdecl("dtai_session_set_enabled")
public func dtaiSessionSetEnabled(_ enabled: UInt32) -> Int32 {
  guard enabled <= 1 else { return statusInvalidArgument }
  return TerminalIntentCommandQueue.shared.setEnabled(enabled == 1)
}

@_cdecl("dtai_take_command")
public func dtaiTakeCommand(
  _ operationID: UnsafeMutablePointer<UInt64>?,
  _ generation: UnsafeMutablePointer<UInt64>?,
  _ action: UnsafeMutablePointer<UInt32>?
) -> Int32 {
  TerminalIntentCommandQueue.shared.take(
    operationID: operationID,
    generation: generation,
    action: action
  )
}

@_cdecl("dtai_complete_command")
public func dtaiCompleteCommand(
  _ operationID: UInt64,
  _ generation: UInt64,
  _ disposition: UInt32
) -> Int32 {
  TerminalIntentCommandQueue.shared.complete(
    operationID: operationID,
    generation: generation,
    disposition: disposition
  )
}

@_cdecl("dtai_session_shutdown")
public func dtaiSessionShutdown() -> Int32 {
  TerminalIntentCommandQueue.shared.shutdown()
}

@_cdecl("dtai_debug_summary")
public func dtaiDebugSummary(
  _ generation: UnsafeMutablePointer<UInt64>?,
  _ queuedCount: UnsafeMutablePointer<UInt64>?,
  _ pendingCount: UnsafeMutablePointer<UInt64>?,
  _ acceptedCount: UnsafeMutablePointer<UInt64>?,
  _ resolvedCount: UnsafeMutablePointer<UInt64>?,
  _ rejectedCount: UnsafeMutablePointer<UInt64>?,
  _ timedOutCount: UnsafeMutablePointer<UInt64>?,
  _ started: UnsafeMutablePointer<UInt32>?,
  _ enabled: UnsafeMutablePointer<UInt32>?
) -> Int32 {
  TerminalIntentCommandQueue.shared.summary(
    generation: generation,
    queuedCount: queuedCount,
    pendingCount: pendingCount,
    acceptedCount: acceptedCount,
    resolvedCount: resolvedCount,
    rejectedCount: rejectedCount,
    timedOutCount: timedOutCount,
    started: started,
    enabled: enabled
  )
}

@_cdecl("dtai_debug_enqueue_action")
public func dtaiDebugEnqueueAction(_ action: UInt32) -> Int32 {
  guard let value = TerminalIntentAction(rawValue: action) else {
    return statusInvalidArgument
  }
  return TerminalIntentCommandQueue.shared.enqueueForDebug(value)
}
