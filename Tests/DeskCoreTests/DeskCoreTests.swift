import Foundation
import Testing
@testable import DeskCore

@Suite("LINAK 协议与停止处理")
struct DeskCoreTests {
    @Test
    func testHeightAndSignedSpeedUseLittleEndianAndCorrectUnits() throws {
        let sample = try #require(LinakProtocol.decodeTelemetry(Data([0x20, 0x03, 0x9c, 0xff])))
        checkEqual(sample.travel, 800)
        checkEqual(sample.speed, -100)
        checkEqual(sample.heightCM(baseMM: 620), 70)
        checkEqual(LinakProtocol.encodeTarget(heightCM: 70, baseMM: 620), Data([0x20, 0x03]))
        checkNil(LinakProtocol.decodeTelemetry(Data([0, 0])))
        checkNil(LinakProtocol.decodeTelemetry(Data([0, 0, 0, 0, 0])))
    }

    @Test func testRejectInvalidHeightRatherThanWrappingInteger() {
        checkNil(LinakProtocol.encodeTarget(heightCM: 60, baseMM: 620))
        checkNil(LinakProtocol.encodeTarget(heightCM: .nan, baseMM: 620))
        checkNil(LinakProtocol.encodeTarget(heightCM: .infinity, baseMM: 620))
        checkNil(LinakProtocol.encodeTarget(heightCM: 1000, baseMM: 620))
    }

    @Test func testAnonymousDevicesAreNotMistakenForDesks() {
        checkFalse(LinakProtocol.isDesk(name: nil, serviceUUIDs: []))
        checkFalse(LinakProtocol.isDesk(name: "Desktop speaker", serviceUUIDs: []))
        checkFalse(LinakProtocol.isDesk(name: "Headphones", serviceUUIDs: ["180F"]))
        checkEqual(LinakProtocol.isDesk(name: "DESK 5348", serviceUUIDs: []), true)
        checkEqual(LinakProtocol.isDesk(name: "Desk6296", serviceUUIDs: []), true)
        checkEqual(LinakProtocol.isDesk(name: nil, serviceUUIDs: [LinakProtocol.controlService]), true)
    }

    @Test func testBaseOffsetAndDPGFraming() {
        checkEqual(LinakProtocol.decodeBaseMM(Data([1, 3, 1, 0x38, 0x18])), 620)
        checkNil(LinakProtocol.decodeBaseMM(Data([1, 2, 0x38, 0x18])))
        checkNil(LinakProtocol.decodeBaseMM(Data([0, 3, 1, 0x38, 0x18])))
        checkNil(LinakProtocol.decodeBaseMM(Data([1, 3, 1, 0, 0])))
        checkEqual(LinakProtocol.dpgPayload(Data([1, 3, 0, 2, 3])), Data([0, 2, 3]))
        checkNil(LinakProtocol.dpgPayload(Data([0, 3, 0, 2, 3])))
        checkNil(LinakProtocol.dpgPayload(Data([1, 0, 0, 2, 3])))
        checkEqual(LinakProtocol.Command.stop.data, Data([0xff, 0]))
        checkEqual(LinakProtocol.readDPG(0x81), Data([0x7f, 0x81, 0]))
    }

    @Test func testFreshTelemetryAndProgressRequired() {
        var motion = MotionGuard(mode: .up, heightCM: 70, now: 10)
        checkEqual(motion.evaluate(heightCM: 70.1, telemetryAt: 10.4, now: 10.4, min: 60, max: 130), .keepMoving)
        checkEqual(motion.evaluate(heightCM: 70.1, telemetryAt: 10.4, now: 12.5, min: 60, max: 130),
                       .stop("高度数据中断，已停止发送升降指令"))
        checkEqual(motion.evaluate(heightCM: 70.1, telemetryAt: 14, now: 14, min: 60, max: 130),
                       .stop("桌子未继续移动，请检查控制器"))
    }

    @Test func testTargetStopsOnArrivalAndCrossingInBothDirections() {
        var up = MotionGuard(mode: .target(80), heightCM: 70, now: 0)
        checkEqual(up.evaluate(heightCM: 80.3, telemetryAt: 0.4, now: 0.4, min: 60, max: 130), .arrived)
        var down = MotionGuard(mode: .target(70), heightCM: 80, now: 0)
        checkEqual(down.evaluate(heightCM: 69.8, telemetryAt: 0.4, now: 0.4, min: 60, max: 130), .arrived)
    }

    @Test func testLimitsAndTimeout() {
        var up = MotionGuard(mode: .up, heightCM: 129, now: 0)
        checkEqual(up.evaluate(heightCM: 130, telemetryAt: 1, now: 1, min: 60, max: 130),
                       .stop("已到达设定的最高高度"))
        var down = MotionGuard(mode: .down, heightCM: 61, now: 0)
        checkEqual(down.evaluate(heightCM: 60, telemetryAt: 1, now: 1, min: 60, max: 130),
                       .stop("已到达设定的最低高度"))
        var timeout = MotionGuard(mode: .up, heightCM: 70, now: 0)
        checkEqual(timeout.evaluate(heightCM: 90, telemetryAt: 46, now: 46, min: 60, max: 130),
                       .stop("本次升降已超时"))
        checkFalse(MotionGuard.validLimits(min: 130, max: 60))
        checkFalse(MotionGuard.validTarget(50, min: 60, max: 130, baseMM: 620))
    }
}

private func checkEqual<T: Equatable>(_ actual: T, _ expected: T) { #expect(actual == expected) }
private func checkNil<T>(_ actual: T?) { #expect(actual == nil) }
private func checkFalse(_ actual: Bool) { #expect(!actual) }
