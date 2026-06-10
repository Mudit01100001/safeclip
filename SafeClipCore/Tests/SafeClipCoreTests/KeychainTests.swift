import Foundation
import Testing

@testable import SafeClipCore

/// Exercises the real login Keychain. The test runner creates its own items
/// under a unique service name and removes them afterwards; creator access is
/// silent, so this runs without prompts on a normal developer machine.
@Suite("Keychain", .serialized)
struct KeychainTests {
    @Test func createLoadDeleteRoundTrip() throws {
        let manager = KeychainManager(service: "SafeClip.tests.\(UUID().uuidString)")
        defer { try? manager.deleteMasterKey() }

        #expect(try manager.loadMasterKey() == nil, "fresh service has no key")

        let created = try manager.loadOrCreateMasterKey()
        #expect(created.count == 32)

        let loaded = try manager.loadOrCreateMasterKey()
        #expect(loaded == created, "second call loads the same key, not a new one")

        try manager.deleteMasterKey()
        #expect(try manager.loadMasterKey() == nil, "deleted key is gone — history becomes unreadable (F1)")
    }

    @Test func deleteIsIdempotent() throws {
        let manager = KeychainManager(service: "SafeClip.tests.\(UUID().uuidString)")
        try manager.deleteMasterKey() // nothing exists — must not throw
    }
}
