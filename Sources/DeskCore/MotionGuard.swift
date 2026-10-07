import Foundation

/// A motion session never survives a reconnect. Timers use monotonic uptime.
public struct MotionGuard {
    public enum Mode: Equatable {
        case up, down, target(Double)
    }

    public enum Decision: Equatable {
        case keepMoving, arrived, stop(String)
    }

    public let mode: Mode
    private let started: TimeInterval
    private var progressAt: TimeInterval
    private var progressHeight: Double
    private let startingHeight: Double

    public init(mode: Mode, heightCM: Double, now: TimeInterval) {
        self.mode = mode
        started = now
        progressAt = now
        progressHeight = heightCM
        startingHeight = heightCM
    }

    public static func validLimits(min: Double, max: Double) -> Bool {
        min.isFinite && max.isFinite && min >= 40 && max <= 150 && max - min >= 1
    }

    public static func validTarget(_ height: Double, min: Double, max: Double, baseMM: Double) -> Bool {
        validLimits(min: min, max: max) && height.isFinite && (min...max).contains(height)
            && LinakProtocol.encodeTarget(heightCM: height, baseMM: baseMM) != nil
    }

    public mutating func evaluate(heightCM: Double, telemetryAt: TimeInterval,
                                  now: TimeInterval, min: Double, max: Double) -> Decision {
        guard Self.validLimits(min: min, max: max), heightCM.isFinite else {
            return .stop("高度或范围无效")
        }
        guard now >= telemetryAt, now - telemetryAt <= 2 else {
            return .stop("高度数据中断，已停止发送升降指令")
        }
        guard now - started < 45 else { return .stop("本次升降已超时") }
        switch mode {
        case .up:
            if heightCM >= max { return .stop("已到达设定的最高高度") }
        case .down:
            if heightCM <= min { return .stop("已到达设定的最低高度") }
        case .target(let target):
            guard Self.validTarget(target, min: min, max: max, baseMM: 0) else {
                return .stop("目标高度超出设定范围")
            }
            if abs(heightCM - target) <= 0.15
                || (startingHeight < target && heightCM >= target)
                || (startingHeight > target && heightCM <= target) { return .arrived }
            if (startingHeight < target && heightCM >= max)
                || (startingHeight > target && heightCM <= min) {
                return .stop("已到达设定的高度边界")
            }
        }
        if abs(heightCM - progressHeight) >= 0.05 {
            progressHeight = heightCM
            progressAt = now
        }
        if now - progressAt >= 3 { return .stop("桌子未继续移动，请检查控制器") }
        return .keepMoving
    }
}
