import Foundation

struct ScrollInterpolation {
    static let duration: TimeInterval = 0.1
    private(set) var startValue: Double
    private(set) var targetValue: Double
    private(set) var startTime: TimeInterval

    init(value: Double, time: TimeInterval) {
        startValue = value
        targetValue = value
        startTime = time
    }

    func value(at time: TimeInterval) -> Double {
        let progress = min(1, max(0, (time - startTime) / Self.duration))
        let eased = 1 - pow(1 - progress, 3)
        return startValue + (targetValue - startValue) * eased
    }

    func isComplete(at time: TimeInterval) -> Bool {
        time >= startTime + Self.duration
    }

    mutating func retarget(by delta: Double, at time: TimeInterval, lowerBound: Double, upperBound: Double) {
        let current = value(at: time)
        let pending = targetValue - current
        let reverses = pending * delta < 0
        startValue = current
        targetValue = min(upperBound, max(lowerBound, (reverses ? current : targetValue) + delta))
        startTime = time
    }
}
