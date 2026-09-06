import AppKit
import Foundation

guard CommandLine.arguments.count == 2,
      let processIdentifier = Int32(CommandLine.arguments[1]),
      processIdentifier > 0,
      let application = NSRunningApplication(
        processIdentifier: processIdentifier
      ) else {
  exit(64)
}

let activated = application.activate(options: [.activateAllWindows])
guard activated else {
  exit(1)
}

let deadline = Date().addingTimeInterval(2)
while !application.isActive && Date() < deadline {
  RunLoop.current.run(until: Date().addingTimeInterval(0.02))
}
exit(application.isActive ? 0 : 75)
