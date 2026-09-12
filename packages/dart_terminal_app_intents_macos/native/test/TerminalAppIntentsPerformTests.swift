import AppIntents
import Foundation

@main
struct TerminalAppIntentsPerformTests {
  @MainActor
  static func main() async throws {
    precondition(dtaiSessionStart(1, 1_000_000) == 0)
    precondition(dtaiSessionSetEnabled(1) == 0)

    let completed = Task {
      _ = try await NewTerminalWindowIntent().perform()
    }
    let first = await takeCommand()
    precondition(first.action == 1)
    precondition(dtaiCompleteCommand(first.operation, first.generation, 0) == 0)
    try await completed.value

    let held = Task {
      _ = try await NewTerminalWindowIntent().perform()
    }
    let heldCommand = await takeCommand()
    do {
      _ = try await NewTerminalTabIntent().perform()
      preconditionFailure("overflowing App Intent unexpectedly succeeded")
    } catch {
      precondition(error.localizedDescription.contains("busy"))
    }
    precondition(
      dtaiCompleteCommand(heldCommand.operation, heldCommand.generation, 0) == 0
    )
    try await held.value

    let failed = Task {
      _ = try await ToggleQuickTerminalIntent().perform()
    }
    let failedCommand = await takeCommand()
    precondition(
      dtaiCompleteCommand(failedCommand.operation, failedCommand.generation, 2)
        == 0
    )
    do {
      try await failed.value
      preconditionFailure("failed App Intent unexpectedly succeeded")
    } catch {
      precondition(error.localizedDescription.contains("could not complete"))
    }

    precondition(dtaiSessionSetEnabled(0) == 0)
    do {
      _ = try await NewTerminalTabIntent().perform()
      preconditionFailure("disabled App Intent unexpectedly succeeded")
    } catch {
      precondition(error.localizedDescription.contains("disabled"))
    }
    precondition(dtaiSessionShutdown() == 0)

    precondition(dtaiSessionStart(1, 1_000) == 0)
    precondition(dtaiSessionSetEnabled(1) == 0)
    do {
      _ = try await ToggleQuickTerminalIntent().perform()
      preconditionFailure("timed-out App Intent unexpectedly succeeded")
    } catch {
      precondition(error.localizedDescription.contains("in time"))
    }
    precondition(dtaiSessionShutdown() == 0)

    precondition(dtaiSessionStart(1, 1_000_000) == 0)
    precondition(dtaiSessionSetEnabled(1) == 0)
    let disposed = Task {
      _ = try await NewTerminalTabIntent().perform()
    }
    _ = await takeCommand()
    precondition(dtaiSessionShutdown() == 0)
    do {
      try await disposed.value
      preconditionFailure("disposed App Intent unexpectedly succeeded")
    } catch {
      precondition(error.localizedDescription.contains("unavailable"))
    }

    print("terminal App Intents perform lifecycle tests passed")
  }

  @MainActor
  private static func takeCommand() async -> (
    operation: UInt64,
    generation: UInt64,
    action: UInt32
  ) {
    for _ in 0..<100 {
      var operation: UInt64 = 0
      var generation: UInt64 = 0
      var action: UInt32 = 0
      let status = dtaiTakeCommand(&operation, &generation, &action)
      if status == 0 {
        return (operation, generation, action)
      }
      precondition(status == 5)
      try? await Task.sleep(for: .milliseconds(1))
    }
    preconditionFailure("App Intent command was not admitted")
  }
}
