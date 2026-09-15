import Foundation

// Measurement logic is independent of IOKit so fixture tests never change power.
struct LidMeasurementSample {
    let continuousSeconds: Double
    let awakeSeconds: Double
    let lidClosed: Bool?
    var isLidEvent = false
}

struct LidMeasurementReport: Codable {
    let schemaVersion = 1
    let expectation: String
    let result: String
    let summary: String
    let durationSeconds: Double
    let closedLidSeconds: Double
    let sleepSeconds: Double
    let maxSampleGap: Double
    let model: String
    let osVersion: String
    let lidClosedObserved: Bool
    let lidNotificationsAvailable: Bool
    let sampleCount: Int

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", expectation, result, summary, model
        case durationSeconds = "duration_seconds", closedLidSeconds = "closed_lid_seconds"
        case sleepSeconds = "sleep_seconds", maxSampleGap = "max_sample_gap"
        case osVersion = "os_version", lidClosedObserved = "lid_closed_observed"
        case lidNotificationsAvailable = "lid_notifications_available", sampleCount = "sample_count"
    }

    static func evaluate(_ samples: [LidMeasurementSample], expectation: String,
                         model: String, osVersion: String,
                         notificationsAvailable: Bool) -> LidMeasurementReport {
        var duration = 0.0, closed = 0.0, slept = 0.0, gap = 0.0
        var invalid = samples.count < 2 || samples.count >= 1024
        var missingLid = false
        var closedSleepObserved = false
        let sawClosed = samples.contains { $0.lidClosed == true }
        if let first = samples.first, let last = samples.last {
            duration = last.continuousSeconds - first.continuousSeconds
            let awakeDuration = last.awakeSeconds - first.awakeSeconds
            if duration.isFinite, awakeDuration.isFinite {
                slept = max(0, duration - awakeDuration)
            }
        }
        for sample in samples {
            if !sample.continuousSeconds.isFinite || !sample.awakeSeconds.isFinite { invalid = true }
            if sample.lidClosed == nil { missingLid = true }
        }
        for (previous, current) in zip(samples, samples.dropFirst()) {
            let elapsed = current.continuousSeconds - previous.continuousSeconds
            let awake = current.awakeSeconds - previous.awakeSeconds
            guard elapsed.isFinite, awake.isFinite, elapsed >= 0, awake >= 0,
                  awake <= elapsed + 0.05 else { invalid = true; continue }
            gap = max(gap, elapsed)
            // Sleep is computed across the whole run above. Summing positive
            // per-sample differences would turn clock-read jitter into sleep.
            if previous.lidClosed == true && (current.lidClosed == true || current.isLidEvent) {
                closed += elapsed
                // A sleep result requires a pause in an interval that started
                // closed. Sleep elsewhere in the run is not lid-sleep evidence.
                if elapsed - awake >= 1 { closedSleepObserved = true }
            }
        }
        let result: String
        let summary: String
        if invalid || !duration.isFinite || duration <= 0 {
            result = "inconclusive"; summary = "The clock samples were incomplete or inconsistent. Repeat the test."
        } else if !sawClosed {
            result = "inconclusive"; summary = "No closed-lid signal was observed. Close and reopen the lid during the test."
        } else if expectation == "sleep" && slept >= 1 && closedSleepObserved {
            result = "passed"; summary = "Sleep was observed in an interval that began with the lid closed. This does not prove uninterrupted sleep."
        } else if expectation == "sleep" && slept >= 1 {
            result = "inconclusive"; summary = "Sleep was observed, but it could not be linked to a closed-lid interval. Repeat the test."
        } else if expectation == "awake" && slept > 0.5 && closedSleepObserved {
            result = "failed"; summary = "Sleep was observed during the test. Review the session deadline, power policy and setup."
        } else if expectation == "awake" && slept > 0.5 {
            result = "inconclusive"; summary = "Sleep was observed, but it could not be linked to a closed-lid interval. Repeat the test."
        } else if missingLid || closed < 10 || (expectation == "awake" && gap > 2) {
            result = "inconclusive"; summary = "Closed-lid coverage was too short or sampling was interrupted. Repeat with the lid closed for at least 10 seconds."
        } else if expectation == "awake" {
            result = "passed"; summary = "No measurable sleep was observed during this closed-lid test. This is evidence for this run only."
        } else {
            result = "failed"; summary = "No measurable sleep was observed. Another sleep hold or macOS activity may be keeping the Mac awake."
        }
        return LidMeasurementReport(expectation: expectation, result: result, summary: summary,
            durationSeconds: duration.isFinite ? max(0, duration) : 0,
            closedLidSeconds: closed, sleepSeconds: slept, maxSampleGap: gap,
            model: model, osVersion: osVersion, lidClosedObserved: sawClosed,
            lidNotificationsAvailable: notificationsAvailable, sampleCount: samples.count)
    }
}

struct LidProbeOptions {
    var expectation = "awake"
    var seconds = 60
    var json = false

    static func parse(_ arguments: [String]) -> LidProbeOptions? {
        var result = LidProbeOptions(), index = 0
        var seen = Set<String>()
        while index < arguments.count {
            let flag = arguments[index]
            guard seen.insert(flag).inserted else { return nil }
            switch flag {
            case "--expect":
                index += 1
                guard index < arguments.count, ["awake", "sleep"].contains(arguments[index]) else { return nil }
                result.expectation = arguments[index]
            case "--seconds":
                index += 1
                guard index < arguments.count, !arguments[index].isEmpty,
                      arguments[index].utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
                      let value = Int(arguments[index]), (15...120).contains(value) else { return nil }
                result.seconds = value
            case "--json": result.json = true
            default: return nil
            }
            index += 1
        }
        return seen.contains("--expect") ? result : nil
    }
}
