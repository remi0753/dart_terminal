import AppKit
import CoreGraphics
import Darwin
import Foundation
import ScreenCaptureKit

private let expectedBundleIdentifier = "com.mitchellh.ghostty"
private let inputSampleCount = 7
private let idleWindowMicroseconds = 2_000_000
private let memoryOutputBytes = 22_048

private enum CaptureFailure: String, Error {
    case arguments
    case existingApplication
    case fixture
    case launch
    case applicationIdentity
    case visibility
    case screenPermission
    case window
    case screenshot
    case pixelObservation
    case appleEvent
    case processResource
    case termination
}

private struct ProcessResourceSnapshot {
    let cpuNanoseconds: UInt64
    let residentBytes: UInt64
}

private struct PixelSignature {
    let red: Double
    let green: Double
    let blue: Double

    func distance(from other: PixelSignature) -> Double {
        let redDelta = red - other.red
        let greenDelta = green - other.green
        let blueDelta = blue - other.blue
        return (redDelta * redDelta + greenDelta * greenDelta + blueDelta * blueDelta).squareRoot()
    }
}

private struct ResourceWindow {
    let elapsedMicroseconds: UInt64
    let cpuMicroseconds: UInt64
    let residentBytes: UInt64
}

@main
@MainActor
private struct GhosttyPerformanceCapture {
    static func main() async {
        do {
            let appURL = try parseArguments()
            let result = try await capture(appURL: appURL)
            print(result)
        } catch let failure as CaptureFailure {
            fputs("GHOSTTY_COMPARATOR_CAPTURE_FAIL reason=\(failure.rawValue)\n", stderr)
            exit(1)
        } catch {
            fputs("GHOSTTY_COMPARATOR_CAPTURE_FAIL reason=unexpected\n", stderr)
            exit(1)
        }
    }

    private static func parseArguments() throws -> URL {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 1, arguments[0].hasPrefix("--app=") else {
            throw CaptureFailure.arguments
        }
        let path = String(arguments[0].dropFirst("--app=".count))
        guard path.hasPrefix("/"), path.hasSuffix(".app") else {
            throw CaptureFailure.arguments
        }
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw CaptureFailure.arguments
        }
        return url
    }

    private static func capture(appURL: URL) async throws -> String {
        _ = NSApplication.shared
        guard CGPreflightScreenCaptureAccess() else {
            throw CaptureFailure.screenPermission
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: expectedBundleIdentifier).isEmpty else {
            throw CaptureFailure.existingApplication
        }

        let fixtureDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dart-terminal-comparator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: fixtureDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: fixtureDirectory) }
        let fixtureURL = fixtureDirectory.appendingPathComponent("fixture.zsh")
        try writeFixture(to: fixtureURL)

        let application = try await launch(appURL: appURL, fixtureURL: fixtureURL, isolatedDirectory: fixtureDirectory)
        defer {
            if !application.isTerminated {
                _ = application.forceTerminate()
            }
        }
        guard application.bundleIdentifier == expectedBundleIdentifier else {
            throw CaptureFailure.applicationIdentity
        }

        let window = try await waitForWindow(processIdentifier: application.processIdentifier)
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.width = 32
        configuration.height = 32
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true

        application.activate(options: [.activateAllWindows])
        try await Task.sleep(for: .milliseconds(750))
        var signature = try await pixelSignature(filter: filter, configuration: configuration)
        var inputLatencies = [UInt64]()
        inputLatencies.reserveCapacity(inputSampleCount)
        for sample in 0..<inputSampleCount {
            let start = DispatchTime.now().uptimeNanoseconds
            try sendInput("phase11-input-\(sample)")
            let changed = try await waitForPixelChange(
                from: signature,
                filter: filter,
                configuration: configuration
            )
            let end = DispatchTime.now().uptimeNanoseconds
            guard end > start else { throw CaptureFailure.pixelObservation }
            inputLatencies.append((end - start) / 1_000)
            signature = changed
            try await Task.sleep(for: .milliseconds(100))
        }

        let visibleWindow = try await measureResourceWindow(processIdentifier: application.processIdentifier)
        try sendInput("phase11-memory")
        try await waitForMemoryReady()
        _ = application.hide()
        try await waitForHidden(application)
        let occludedWindow = try await measureResourceWindow(processIdentifier: application.processIdentifier)

        let sortedLatencies = inputLatencies.sorted()
        let p95Index = max(0, (sortedLatencies.count * 95 + 99) / 100 - 1)
        let inputP95 = sortedLatencies[p95Index]
        let totalElapsed = visibleWindow.elapsedMicroseconds + occludedWindow.elapsedMicroseconds
        let totalCPU = visibleWindow.cpuMicroseconds + occludedWindow.cpuMicroseconds
        guard totalElapsed > 0 else { throw CaptureFailure.processResource }
        let aggregateBasisPoints = totalCPU * 10_000 / totalElapsed
        let refreshTier = currentRefreshTier()

        try sendInput("phase11-exit")
        try await Task.sleep(for: .milliseconds(250))
        _ = application.terminate()
        try await waitForTermination(application)

        return "GHOSTTY_COMPARATOR_CAPTURE_PASS input_samples=\(inputSampleCount) "
            + "input_visible_p95_us=\(inputP95) idle_window_count=2 "
            + "idle_window_us=\(visibleWindow.elapsedMicroseconds) "
            + "idle_cpu_us=\(visibleWindow.cpuMicroseconds) "
            + "idle_rss_bytes=\(visibleWindow.residentBytes) "
            + "occluded_window_us=\(occludedWindow.elapsedMicroseconds) "
            + "occluded_cpu_us=\(occludedWindow.cpuMicroseconds) "
            + "aggregate_cpu_basis_points=\(aggregateBasisPoints) "
            + "memory_output_bytes=\(memoryOutputBytes) refresh_tier_hz=\(refreshTier) "
            + "screen_api=screencapturekit apple_event=true "
            + "raw_samples_retained=false content_free=true"
    }

    private static func writeFixture(to url: URL) throws {
        let source = """
        #!/bin/zsh -f
        export LC_ALL=C
        stty -echo
        printf '\\033[?25l\\033[48;2;8;8;8m\\033[2J\\033[H'
        while IFS= read -r line; do
          case "$line" in
            phase11-input-0) printf '\\033[48;2;180;20;20m\\033[2J\\033[H' ;;
            phase11-input-1) printf '\\033[48;2;20;180;20m\\033[2J\\033[H' ;;
            phase11-input-2) printf '\\033[48;2;20;20;180m\\033[2J\\033[H' ;;
            phase11-input-3) printf '\\033[48;2;160;20;160m\\033[2J\\033[H' ;;
            phase11-input-4) printf '\\033[48;2;180;160;20m\\033[2J\\033[H' ;;
            phase11-input-5) printf '\\033[48;2;20;160;160m\\033[2J\\033[H' ;;
            phase11-input-6) printf '\\033[48;2;180;80;20m\\033[2J\\033[H' ;;
            phase11-memory)
              repeat 11024 printf 'x\\n'
              printf '\\033]2;phase11-memory-ready\\007'
              ;;
            phase11-exit) exit 0 ;;
            *) exit 64 ;;
          esac
        done
        """
        do {
            try Data(source.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            throw CaptureFailure.fixture
        }
    }

    private static func launch(
        appURL: URL,
        fixtureURL: URL,
        isolatedDirectory: URL
    ) async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [
            "--config-default-files=false",
            "--auto-update=off",
            "--shell-integration=none",
            "--cursor-style-blink=false",
            "--window-save-state=never",
            "--window-width=80",
            "--window-height=24",
            "--font-family=Menlo",
            "--font-size=14",
            "--background=080808",
            "--foreground=ffffff",
            "--working-directory=\(isolatedDirectory.path)",
            "-e",
            fixtureURL.path,
        ]
        configuration.environment = [
            "HOME": isolatedDirectory.path,
            "XDG_CACHE_HOME": isolatedDirectory.path,
            "XDG_CONFIG_HOME": isolatedDirectory.path,
        ]
        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { application, _ in
                guard let application else {
                    continuation.resume(throwing: CaptureFailure.launch)
                    return
                }
                continuation.resume(returning: application)
            }
        }
    }

    private static func waitForWindow(processIdentifier: pid_t) async throws -> SCWindow {
        let deadline = DispatchTime.now().uptimeNanoseconds + 10_000_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            let content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: true
            )
            if let window = content.windows.first(where: {
                $0.owningApplication?.processID == processIdentifier && $0.frame.width >= 100 && $0.frame.height >= 100
            }) {
                return window
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw CaptureFailure.window
    }

    private static func pixelSignature(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async throws -> PixelSignature {
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
        } catch {
            throw CaptureFailure.screenshot
        }
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        guard let context = CGContext(
            data: &pixels,
            width: 32,
            height: 32,
            bitsPerComponent: 8,
            bytesPerRow: 32 * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CaptureFailure.screenshot
        }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        var red = 0
        var green = 0
        var blue = 0
        var count = 0
        for y in 2..<27 {
            for x in 2..<30 {
                let offset = (y * 32 + x) * 4
                red += Int(pixels[offset])
                green += Int(pixels[offset + 1])
                blue += Int(pixels[offset + 2])
                count += 1
            }
        }
        guard count > 0 else { throw CaptureFailure.pixelObservation }
        return PixelSignature(
            red: Double(red) / Double(count),
            green: Double(green) / Double(count),
            blue: Double(blue) / Double(count)
        )
    }

    private static func waitForPixelChange(
        from baseline: PixelSignature,
        filter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async throws -> PixelSignature {
        let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            let current = try await pixelSignature(filter: filter, configuration: configuration)
            if current.distance(from: baseline) >= 30 {
                return current
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        throw CaptureFailure.pixelObservation
    }

    private static func sendInput(_ value: String) throws {
        guard value.range(of: #"^[A-Za-z0-9-]+$"#, options: .regularExpression) != nil else {
            throw CaptureFailure.appleEvent
        }
        let source = """
        tell application id "\(expectedBundleIdentifier)"
          input text ("\(value)" & return) to terminal 1
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw CaptureFailure.appleEvent
        }
        _ = script.executeAndReturnError(&error)
        guard error == nil else { throw CaptureFailure.appleEvent }
    }

    private static func waitForMemoryReady() async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
        while DispatchTime.now().uptimeNanoseconds < deadline {
            let source = """
            tell application id "\(expectedBundleIdentifier)"
              name of terminal 1
            end tell
            """
            var error: NSDictionary?
            guard let script = NSAppleScript(source: source) else {
                throw CaptureFailure.appleEvent
            }
            let result = script.executeAndReturnError(&error)
            guard error == nil else { throw CaptureFailure.appleEvent }
            if result.stringValue == "phase11-memory-ready" { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CaptureFailure.fixture
    }

    private static func processResourceSnapshot(processIdentifier: pid_t) throws -> ProcessResourceSnapshot {
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(processIdentifier, RUSAGE_INFO_V4, $0)
            }
        }
        guard status == 0, info.ri_resident_size > 0 else {
            throw CaptureFailure.processResource
        }
        return ProcessResourceSnapshot(
            cpuNanoseconds: info.ri_user_time + info.ri_system_time,
            residentBytes: info.ri_resident_size
        )
    }

    private static func measureResourceWindow(processIdentifier: pid_t) async throws -> ResourceWindow {
        let before = try processResourceSnapshot(processIdentifier: processIdentifier)
        let start = DispatchTime.now().uptimeNanoseconds
        try await Task.sleep(for: .seconds(2))
        let end = DispatchTime.now().uptimeNanoseconds
        let after = try processResourceSnapshot(processIdentifier: processIdentifier)
        guard end > start, after.cpuNanoseconds >= before.cpuNanoseconds else {
            throw CaptureFailure.processResource
        }
        return ResourceWindow(
            elapsedMicroseconds: (end - start) / 1_000,
            cpuMicroseconds: (after.cpuNanoseconds - before.cpuNanoseconds) / 1_000,
            residentBytes: after.residentBytes
        )
    }

    private static func currentRefreshTier() -> Int {
        guard let mode = CGDisplayCopyDisplayMode(CGMainDisplayID()) else { return 60 }
        let refreshRate = mode.refreshRate
        return refreshRate > 90 ? 120 : 60
    }

    private static func waitForTermination(_ application: NSRunningApplication) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
        while !application.isTerminated && DispatchTime.now().uptimeNanoseconds < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        guard application.isTerminated else { throw CaptureFailure.termination }
    }

    private static func waitForHidden(_ application: NSRunningApplication) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
        while !application.isHidden && DispatchTime.now().uptimeNanoseconds < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        guard application.isHidden else { throw CaptureFailure.visibility }
    }
}
