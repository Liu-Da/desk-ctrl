import Foundation

public struct DeskFavorite: Codable, Equatable, Identifiable {
    public let id: UUID
    public let number: Int
    public var customName: String?
    public var heightCM: Double

    public init(id: UUID = UUID(), number: Int, customName: String? = nil, heightCM: Double) {
        self.id = id
        self.number = number
        self.customName = customName
        self.heightCM = heightCM
    }

    public var name: String {
        let name = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "收藏 \(number)" : name
    }
}

/// An explicitly saved empty collection must not restore legacy presets on reconnect.
public struct FavoriteStore {
    public static let maximumCount = 5
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public enum SaveError: LocalizedError, Equatable {
        case tooMany, invalidEntry

        public var errorDescription: String? {
            switch self {
            case .tooMany: return "最多保存 5 个收藏位置"
            case .invalidEntry: return "收藏位置的编号或高度无效"
            }
        }
    }

    public static func nextNumber(in favorites: [DeskFavorite]) -> Int? {
        guard favorites.count < maximumCount else { return nil }
        return (1...maximumCount).first { number in !favorites.contains { $0.number == number } }
    }

    public func load(for deskID: UUID) -> [DeskFavorite] {
        let key = storageKey(deskID)
        if defaults.object(forKey: key) != nil {
            guard let data = defaults.data(forKey: key),
                  let favorites = try? JSONDecoder().decode([DeskFavorite].self, from: data),
                  (try? validate(favorites)) != nil else { return [] }
            return favorites
        }

        var migrated: [DeskFavorite] = []
        for legacyName in ["sitCM", "standCM"] {
            let value = defaults.object(forKey: "desk.\(deskID.uuidString).\(legacyName)") as? NSNumber
            if let height = value?.doubleValue, height.isFinite, (40...150).contains(height) {
                migrated.append(DeskFavorite(number: migrated.count + 1, heightCM: height))
            }
        }
        try? save(migrated, for: deskID)
        return migrated
    }

    public func save(_ favorites: [DeskFavorite], for deskID: UUID) throws {
        try validate(favorites)
        var normalized = favorites
        for index in normalized.indices {
            let name = normalized[index].customName?.trimmingCharacters(in: .whitespacesAndNewlines)
            normalized[index].customName = name?.isEmpty == false ? name : nil
        }
        let data = try JSONEncoder().encode(normalized)
        defaults.set(data, forKey: storageKey(deskID))
    }

    private func validate(_ favorites: [DeskFavorite]) throws {
        guard favorites.count <= Self.maximumCount else { throw SaveError.tooMany }
        guard Set(favorites.map(\.id)).count == favorites.count,
              Set(favorites.map(\.number)).count == favorites.count,
              favorites.allSatisfy({ (1...Self.maximumCount).contains($0.number)
                  && $0.heightCM.isFinite && (40...150).contains($0.heightCM) }) else {
            throw SaveError.invalidEntry
        }
    }

    private func storageKey(_ deskID: UUID) -> String { "desk.\(deskID.uuidString).favorites" }
}
