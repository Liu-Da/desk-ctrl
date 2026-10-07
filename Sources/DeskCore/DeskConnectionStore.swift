import Foundation

public struct RememberedDesk: Codable, Equatable {
    public let id: UUID
    public let name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

public struct DeskConnectionStore {
    private let defaults: UserDefaults
    private let key = "lastConnectedDesk"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> RememberedDesk? {
        guard let data = defaults.data(forKey: key),
              let desk = try? JSONDecoder().decode(RememberedDesk.self, from: data),
              !desk.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return desk
    }

    public func save(_ desk: RememberedDesk) throws {
        let data = try JSONEncoder().encode(desk)
        defaults.set(data, forKey: key)
    }
}

/// One cached connection, followed by at most one scan for that exact device.
public struct DeskReconnectAttempt {
    public enum Stage: Equatable { case cachedConnection, scanning, scanConnection, finished }
    public let desk: RememberedDesk
    public private(set) var stage: Stage

    public init(desk: RememberedDesk, hasCachedPeripheral: Bool) {
        self.desk = desk
        stage = hasCachedPeripheral ? .cachedConnection : .scanning
    }

    public mutating func discovered(_ id: UUID) -> Bool {
        guard stage == .scanning, id == desk.id else { return false }
        stage = .scanConnection
        return true
    }

    public mutating func connectionFailed() -> Bool {
        guard stage == .cachedConnection else { stage = .finished; return false }
        stage = .scanning
        return true
    }

    public mutating func cancel() { stage = .finished }
}
