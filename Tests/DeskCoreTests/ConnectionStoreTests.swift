import Foundation
import Testing
@testable import DeskCore

@Suite("记住桌子与自动重连")
struct ConnectionStoreTests {
    @Test func rememberLastSuccessfulDeskAcrossStoreInstances() throws {
        try withConnectionStore { store, defaults in
            #expect(store.load() == nil)
            let first = RememberedDesk(id: UUID(), name: "DESK 5348")
            let second = RememberedDesk(id: UUID(), name: "DESK 6296")
            try store.save(first)
            #expect(DeskConnectionStore(defaults: defaults).load() == first)
            try store.save(second)
            #expect(DeskConnectionStore(defaults: defaults).load() == second)
        }
    }

    @Test func invalidStoredIdentityCannotBecomeReconnectTarget() throws {
        try withConnectionStore { store, defaults in
            defaults.set(Data("{\"id\":\"not-a-uuid\",\"name\":\"DESK 5348\"}".utf8), forKey: "lastConnectedDesk")
            #expect(store.load() == nil)
            defaults.set(Data("broken JSON".utf8), forKey: "lastConnectedDesk")
            #expect(store.load() == nil)
            try store.save(RememberedDesk(id: UUID(), name: " \n "))
            #expect(store.load() == nil)
        }
    }

    @Test func fallbackConnectsOnlyMatchingUUIDAndStopsAfterSecondFailure() {
        let desk = RememberedDesk(id: UUID(), name: "DESK 5348")
        var attempt = DeskReconnectAttempt(desk: desk, hasCachedPeripheral: true)
        #expect(attempt.stage == .cachedConnection)
        let discoveryDuringCachedConnection = attempt.discovered(desk.id)
        #expect(!discoveryDuringCachedConnection)
        let shouldScan = attempt.connectionFailed()
        #expect(shouldScan)
        #expect(attempt.stage == .scanning)
        let wrongDeskDiscovered = attempt.discovered(UUID())
        #expect(!wrongDeskDiscovered)
        #expect(attempt.stage == .scanning)
        let matchingDeskDiscovered = attempt.discovered(desk.id)
        #expect(matchingDeskDiscovered)
        #expect(attempt.stage == .scanConnection)
        let duplicateDiscovery = attempt.discovered(desk.id)
        #expect(!duplicateDiscovery)
        let shouldRetryAgain = attempt.connectionFailed()
        #expect(!shouldRetryAgain)
        #expect(attempt.stage == .finished)
        let discoveryAfterFailure = attempt.discovered(desk.id)
        #expect(!discoveryAfterFailure)
    }

    @Test func unavailableCacheStartsScanAndCancellationIgnoresLaterDiscovery() {
        let desk = RememberedDesk(id: UUID(), name: "DESK 5348")
        var attempt = DeskReconnectAttempt(desk: desk, hasCachedPeripheral: false)
        #expect(attempt.stage == .scanning)
        attempt.cancel()
        let discoveryAfterCancellation = attempt.discovered(desk.id)
        #expect(!discoveryAfterCancellation)
        let retryAfterCancellation = attempt.connectionFailed()
        #expect(!retryAfterCancellation)
        #expect(attempt.stage == .finished)
        var scannedAttempt = DeskReconnectAttempt(desk: desk, hasCachedPeripheral: false)
        let matchingDeskDiscovered = scannedAttempt.discovered(desk.id)
        #expect(matchingDeskDiscovered)
        let shouldRetryAgain = scannedAttempt.connectionFailed()
        #expect(!shouldRetryAgain)
        #expect(scannedAttempt.stage == .finished)
    }
}

private func withConnectionStore(_ body: (DeskConnectionStore, UserDefaults) throws -> Void) throws {
    let suite = "desk-control-connection-tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try body(DeskConnectionStore(defaults: defaults), defaults)
}
