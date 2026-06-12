import Testing
@testable import OrefSwiftCLI

@Suite("LoadJS")
struct LoadJSTests {
    @Test("compact patch identifiers are normalized to directory names")
    func compactPatchIdentifiers() throws {
        #expect(try loadSourceAlgorithm(false, false, false, "P12") == "Sources/JSAlgorithmP1P2")
        #expect(try loadSourceAlgorithm(false, false, false, "123") == "Sources/JSAlgorithmP1P2P3")
    }

    @Test("explicit patch directory names remain stable")
    func explicitPatchIdentifiers() throws {
        #expect(try loadSourceAlgorithm(false, false, false, "P1P3") == "Sources/JSAlgorithmP1P3")
        #expect(try loadSourceAlgorithm(false, false, false, "p2p3") == "Sources/JSAlgorithmP2P3")
    }

    @Test("invalid patch identifiers are rejected")
    func invalidPatchIdentifiers() throws {
        do {
            _ = try loadSourceAlgorithm(false, false, false, "P4")
            Issue.record("Expected P4 to be rejected")
        } catch let error as JSErrors {
            guard case .invalidPatchIdentifier("P4") = error else {
                Issue.record("Unexpected error for P4: \(error)")
                return
            }
        }

        do {
            _ = try loadSourceAlgorithm(false, false, false, "P11")
            Issue.record("Expected P11 to be rejected")
        } catch let error as JSErrors {
            guard case .invalidPatchIdentifier("P11") = error else {
                Issue.record("Unexpected error for P11: \(error)")
                return
            }
        }
    }
}
