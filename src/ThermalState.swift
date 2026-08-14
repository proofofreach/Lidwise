import Foundation

let state: String
switch ProcessInfo.processInfo.thermalState {
case .nominal: state = "nominal"
case .fair: state = "fair"
case .serious: state = "serious"
case .critical: state = "critical"
@unknown default: state = "unknown"
}

print(state)
