import Foundation

@main
enum LidProbeTests {
    static func main() throws {
        func report(_ samples: [LidMeasurementSample], _ expectation: String = "awake") -> LidMeasurementReport {
            LidMeasurementReport.evaluate(samples, expectation: expectation, model: "fixture",
                osVersion: "fixture", notificationsAvailable: true)
        }
        func sample(_ continuous: Double, _ awake: Double, _ lid: Bool?, event: Bool = false) -> LidMeasurementSample {
            LidMeasurementSample(continuousSeconds: continuous, awakeSeconds: awake,
                lidClosed: lid, isLidEvent: event)
        }
        let closed = (0...30).map { sample(Double($0) / 2, Double($0) / 2, true) }
        precondition(report(closed).result == "passed")
        precondition(report(closed, "sleep").result == "failed")
        precondition(report((0...30).map { sample(Double($0), Double($0), false) }).result == "inconclusive")
        precondition(report([sample(0, 0, true), sample(4, 4, true)]).result == "inconclusive")
        precondition(report([sample(0, 0, true), sample(60, 1, false, event: true)]).result == "failed")
        precondition(report([sample(0, 0, true), sample(60, 1, false, event: true)], "sleep").result == "passed")
        precondition(report([sample(0, 0, false), sample(60, 1, false)], "sleep").result == "inconclusive")
        precondition(report([sample(0, 0, false), sample(60, 1, false),
            sample(61, 2, true, event: true), sample(72, 13, true)], "sleep").result == "inconclusive")
        precondition(report([sample(0, 0, false), sample(60, 1, false),
            sample(61, 2, true, event: true), sample(72, 13, true)]).result == "inconclusive")
        precondition(report([sample(0, 0, true), sample(60, 60, true)]).result == "inconclusive")
        precondition(report([sample(1, 1, true), sample(0, 2, true)]).result == "inconclusive")
        precondition(report([sample(0, 0, true), sample(.infinity, 2, true)]).result == "inconclusive")
        precondition(report([]).result == "inconclusive")
        var unknown = closed; unknown[10] = sample(5, 5, nil)
        precondition(report(unknown).result == "inconclusive")
        let encoded = try JSONEncoder().encode(report(closed))
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        precondition(json["schema_version"] as? Int == 1)
        precondition(json["closed_lid_seconds"] as? Double == 15)
        precondition(LidProbeOptions.parse([]) == nil)
        precondition(LidProbeOptions.parse(["--expect", "awake"])?.seconds == 60)
        precondition(LidProbeOptions.parse(["--expect", "sleep", "--seconds", "120", "--json"])?.json == true)
        for invalid in [["--seconds", "14"], ["--seconds", "121"], ["--seconds", "-1"],
                        ["--seconds", "999999999999999999999"], ["--expect", "maybe"],
                        ["--json", "--json"], ["--seconds"], ["--unknown"],
                        ["--seconds", "1.5"], ["--seconds", "+15"]] {
            precondition(LidProbeOptions.parse(invalid) == nil)
        }
        print("Lid measurement outcomes, missing evidence, clock discontinuity and bounded arguments: ok")
    }
}
