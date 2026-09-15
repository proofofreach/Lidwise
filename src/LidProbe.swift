import Foundation
import IOKit
import IOKit.pwr_mgt
import Darwin

private final class LidMeasurementRecorder {
    private var timebase = mach_timebase_info_data_t()
    private let root: io_service_t
    private var port: IONotificationPortRef?
    private var notification: io_object_t = 0
    private(set) var samples: [LidMeasurementSample] = []
    private(set) var notificationsAvailable = false

    init() {
        mach_timebase_info(&timebase)
        root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0, let notificationPort = IONotificationPortCreate(kIOMainPortDefault) else { return }
        port = notificationPort
        let callback: IOServiceInterestCallback = { context, _, message, argument in
            // IOPM.h's function-like C macro is not imported into Swift.
            // iokit_family_msg(err_sub(13), 0x100), checked against the SDK in tests.
            let clamshellStateChanged: UInt32 = 0xe0034100
            guard message == clamshellStateChanged, let context else { return }
            let recorder = Unmanaged<LidMeasurementRecorder>.fromOpaque(context).takeUnretainedValue()
            let bits = UInt(bitPattern: argument)
            recorder.capture(lidEvent: (bits & UInt(kClamshellStateBit)) != 0)
        }
        let result = IOServiceAddInterestNotification(notificationPort, root, kIOGeneralInterest,
            callback, Unmanaged.passUnretained(self).toOpaque(), &notification)
        if result == KERN_SUCCESS, let source = IONotificationPortGetRunLoopSource(notificationPort) {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source.takeUnretainedValue(), .defaultMode)
            notificationsAvailable = true
        }
    }

    deinit {
        if notification != 0 { IOObjectRelease(notification) }
        if let port { IONotificationPortDestroy(port) }
        if root != 0 { IOObjectRelease(root) }
    }

    var continuousSeconds: Double { seconds(mach_continuous_time()) }

    private func seconds(_ ticks: UInt64) -> Double {
        Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }

    func capture(lidEvent: Bool? = nil) {
        // Limit storage even if the notification source is unexpectedly noisy.
        guard samples.count < 1024 else { return }
        let awake = seconds(mach_absolute_time())
        let continuous = continuousSeconds
        let lid: Bool?
        if let lidEvent { lid = lidEvent }
        else if root != 0,
                let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString,
                    kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber {
            lid = value.boolValue
        } else { lid = nil }
        samples.append(LidMeasurementSample(continuousSeconds: continuous,
            awakeSeconds: awake, lidClosed: lid, isLidEvent: lidEvent != nil))
    }
}

@main
private enum LidProbeMain {
    static func main() {
        guard let options = LidProbeOptions.parse(Array(CommandLine.arguments.dropFirst())) else {
            fputs("usage: lidwise verify --expect awake|sleep [--seconds 15..120] [--json]\n", stderr)
            exit(2)
        }
        let recorder = LidMeasurementRecorder()
        recorder.capture()
        let deadline = recorder.continuousSeconds + Double(options.seconds)
        if !options.json {
            fputs("Measuring only; no power settings will change. Close and reopen the lid during the test. Keep the Mac on a hard, ventilated surface.\n", stderr)
        }
        while recorder.continuousSeconds < deadline {
            // An actual system sleep suspends us. On wake, the continuous clock
            // ends an expired test immediately; no system wake is scheduled.
            let interval = min(0.5, max(0, deadline - recorder.continuousSeconds))
            if recorder.notificationsAvailable {
                CFRunLoopRunInMode(.defaultMode, interval, false)
            } else {
                // A run loop with no registered source returns immediately.
                Thread.sleep(forTimeInterval: interval)
            }
            recorder.capture()
        }
        let report = LidMeasurementReport.evaluate(recorder.samples,
            expectation: options.expectation, model: machineModel(),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            notificationsAvailable: recorder.notificationsAvailable)
        if options.json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            do {
                let data = try encoder.encode(report)
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data([10]))
            } catch { fputs("Could not encode the measurement result.\n", stderr); exit(1) }
        } else {
            print("Lidwise verification: \(report.result)")
            print(report.summary)
            print(String(format: "Measured %.1fs; sampled closed lid %.1fs; sleep %.2fs; maximum sample gap %.2fs.",
                report.durationSeconds, report.closedLidSeconds, report.sleepSeconds, report.maxSampleGap))
            print("Mac: \(report.model); \(report.osVersion)")
        }
    }

    private static func machineModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0, size < 512 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: buffer)
    }
}
