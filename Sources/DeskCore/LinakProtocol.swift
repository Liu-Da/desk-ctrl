import Foundation

public enum LinakProtocol {
    public static let controlService = "99fa0001-338a-1024-8a49-009c0215f78a"
    public static let control = "99fa0002-338a-1024-8a49-009c0215f78a"
    public static let error = "99fa0003-338a-1024-8a49-009c0215f78a"
    public static let dpgService = "99fa0010-338a-1024-8a49-009c0215f78a"
    public static let dpg = "99fa0011-338a-1024-8a49-009c0215f78a"
    public static let heightService = "99fa0020-338a-1024-8a49-009c0215f78a"
    public static let height = "99fa0021-338a-1024-8a49-009c0215f78a"
    public static let targetService = "99fa0030-338a-1024-8a49-009c0215f78a"
    public static let target = "99fa0031-338a-1024-8a49-009c0215f78a"
    public static let services = [controlService, dpgService, heightService, targetService]

    public static func isDesk(name: String?, serviceUUIDs: [String]) -> Bool {
        if serviceUUIDs.contains(where: { $0.uppercased().hasPrefix("99FA") }) { return true }
        guard let name else { return false }
        let upper = name.uppercased()
        return upper.hasPrefix("LINAK")
            || upper.range(of: "^DESK[ _-]*[0-9]{4}$", options: .regularExpression) != nil
    }

    public enum Command: UInt8 {
        case down = 0x46, up = 0x47, wake = 0xfe, stop = 0xff
        public var data: Data { Data([rawValue, 0]) }
    }

    public struct Telemetry: Equatable {
        /// LINAK reports travel above its configured base in 0.1 mm units.
        public let travel: UInt16
        public let speed: Int16
        public func heightCM(baseMM: Double) -> Double {
            (Double(travel) / 10 + baseMM) / 10
        }
    }

    public static func decodeTelemetry(_ data: Data) -> Telemetry? {
        let bytes = Array(data)
        guard bytes.count == 4 else { return nil }
        return Telemetry(
            travel: UInt16(bytes[0]) | UInt16(bytes[1]) << 8,
            speed: Int16(bitPattern: UInt16(bytes[2]) | UInt16(bytes[3]) << 8)
        )
    }

    public static func encodeTarget(heightCM: Double, baseMM: Double) -> Data? {
        let travel = (heightCM * 10 - baseMM) * 10
        guard travel.isFinite, travel >= 0, travel <= Double(UInt16.max) else { return nil }
        let value = UInt16(travel.rounded())
        return Data([UInt8(value & 0xff), UInt8(value >> 8)])
    }

    public static func readDPG(_ command: UInt8) -> Data { Data([0x7f, command, 0]) }
    public static func writeDPG(_ command: UInt8, payload: Data) -> Data {
        Data([0x7f, command, 0x80]) + payload
    }

    public static func decodeBaseMM(_ data: Data) -> Double? {
        let bytes = Array(data)
        guard bytes.count == 5, bytes[0] == 1, bytes[1] != 0 else { return nil }
        let millimeters = Double(UInt16(bytes[3]) | UInt16(bytes[4]) << 8) / 10
        guard (100...1500).contains(millimeters) else { return nil }
        return millimeters
    }

    public static func dpgPayload(_ data: Data) -> Data? {
        let bytes = Array(data)
        guard bytes.count >= 3, bytes[0] == 1, bytes[1] != 0 else { return nil }
        return Data(bytes.dropFirst(2))
    }
}
