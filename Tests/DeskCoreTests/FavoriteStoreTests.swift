import Foundation
import Testing
@testable import DeskCore

@Suite("收藏位置与本机存储")
struct FavoriteStoreTests {
    @Test func migrateExistingHeightsAndKeepExplicitEmptyCollection() throws {
        try withStore { store, defaults, deskID in
            defaults.set(70.0, forKey: "desk.\(deskID.uuidString).sitCM")
            defaults.set(105.0, forKey: "desk.\(deskID.uuidString).standCM")
            let migrated = store.load(for: deskID)
            #expect(migrated.map(\.heightCM) == [70, 105])
            #expect(migrated.map(\.name) == ["收藏 1", "收藏 2"])
            #expect(store.load(for: deskID) == migrated)
            try store.save([], for: deskID)
            #expect(store.load(for: deskID).isEmpty)
            #expect(FavoriteStore.nextNumber(in: []) == 1)
        }
    }

    @Test func renameRoundTripReuseDeletedNumberAndEnforceFiveLimit() throws {
        try withStore { store, _, deskID in
            var favorites = (1...5).map { DeskFavorite(number: $0, heightCM: Double(60 + $0 * 10)) }
            favorites[0].customName = "  工作  "
            favorites[1].customName = "   "
            try store.save(favorites, for: deskID)
            let saved = store.load(for: deskID)
            #expect(saved[0].name == "工作")
            #expect(saved[1].customName == nil)
            #expect(saved[1].name == "收藏 2")
            #expect(FavoriteStore.nextNumber(in: favorites) == nil)
            favorites.remove(at: 1)
            #expect(FavoriteStore.nextNumber(in: favorites) == 2)
            favorites.append(DeskFavorite(number: 2, heightCM: 85))
            favorites.append(DeskFavorite(number: 3, heightCM: 90))
            #expect(throws: FavoriteStore.SaveError.tooMany) { try store.save(favorites, for: deskID) }
            #expect(store.load(for: deskID) == saved)
        }
    }

    @Test func isolateDesksAndRejectInvalidDataWithoutReplacingSavedFavorites() throws {
        try withStore { store, _, deskID in
            #expect(store.load(for: deskID).isEmpty)
            let favorite = DeskFavorite(number: 1, heightCM: 70)
            try store.save([favorite], for: deskID)
            let otherDesk = UUID()
            #expect(store.load(for: otherDesk).isEmpty)
            try store.save([DeskFavorite(number: 1, customName: "另一张桌子", heightCM: 90)], for: otherDesk)
            #expect(store.load(for: deskID) == [favorite])
            #expect(store.load(for: otherDesk).first?.heightCM == 90)
            #expect(throws: FavoriteStore.SaveError.invalidEntry) {
                try store.save([DeskFavorite(number: 1, heightCM: .nan)], for: deskID)
            }
            #expect(throws: FavoriteStore.SaveError.invalidEntry) {
                try store.save([favorite, DeskFavorite(number: 1, heightCM: 80)], for: deskID)
            }
            #expect(store.load(for: deskID) == [favorite])
        }
    }
}

private func withStore(_ body: (FavoriteStore, UserDefaults, UUID) throws -> Void) throws {
    let suite = "desk-control-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(FavoriteStore(defaults: defaults), defaults, UUID())
}
