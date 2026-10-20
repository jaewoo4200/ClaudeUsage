import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ClaudeUsage

final class CodexPetTests: XCTestCase {
    func testSelectionReadsOnlyDesktopSectionAndQuotedValues() {
        XCTAssertEqual(CodexPetReader.selectedID(config: """
        selected-avatar-id = "wrong"
        [desktop]
        "selected-avatar-id" = "custom:demo" # chosen
        [other]
        selected-avatar-id = "wrong-again"
        """), "custom:demo")
        XCTAssertEqual(CodexPetReader.selectedID(config: "[desktop]\nselected-avatar-id = 'custom:local'"), "custom:local")
        XCTAssertNil(CodexPetReader.selectedID(config: "[unrelated]\nselected-avatar-id = 'codex'"))
        XCTAssertNil(CodexPetReader.selectedID(config: "[desktop]\nselected-avatar-id = invalid"))
    }

    func testLegacySelectionAndConfigPrecedence() throws {
        let home = try directory()
        defer { try? FileManager.default.removeItem(at: home) }
        try Data(#"{"electron-persisted-atom-state":{"selected-avatar-id":"custom:legacy"}}"#.utf8)
            .write(to: home.appendingPathComponent(".codex-global-state.json"))
        XCTAssertEqual(CodexPetReader.selectedID(home: home), "custom:legacy")
        try Data("[desktop]\nselected-avatar-id = 'custom:new'".utf8).write(to: home.appendingPathComponent("config.toml"))
        XCTAssertEqual(CodexPetReader.selectedID(home: home), "custom:new")
    }

    func testBothManifestVersionsDecodeAndRespectDimensions() throws {
        for version in [1, 2] {
            let root = try directory()
            defer { try? FileManager.default.removeItem(at: root) }
            let rows = version == 1 ? 9 : 11
            try pet(root: root, id: "demo", version: version, path: "spritesheet.png", bytes: sheet(rows: rows))
            let source = try XCTUnwrap(CodexPetReader.localSource(root: root, id: "demo", manifest: "pet.json"))
            XCTAssertEqual(source.rows, rows)
            let decoded = try XCTUnwrap(CodexPetSheet.load(source))
            XCTAssertEqual(decoded.name, "Fixture Pet")
            XCTAssertEqual(decoded.rows, rows)
            XCTAssertEqual(decoded.image.width, 96)
            XCTAssertEqual(decoded.image.height, rows * 13)
        }
        XCTAssertNil(CodexPetReader.rows(width: 96, height: 117, expected: 11))
        XCTAssertNil(CodexPetReader.rows(width: 97, height: 117, expected: 9))
        XCTAssertNil(CodexPetReader.rows(width: 8192, height: 8192, expected: nil))
        XCTAssertNil(CodexPetReader.rows(width: 0, height: 0, expected: nil))
    }

    func testRejectsTraversalAbsolutePathsAndSymlinkEscapes() throws {
        let root = try directory()
        let outside = try directory()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        for id in ["", "..", ".", "../outside", "a/b", "a\\b", "a:b"] { XCTAssertFalse(CodexPetReader.safeID(id)) }
        for path in ["../outside.png", "/tmp/image.png", "nested/../../outside.png", "C:\\outside.png"] {
            try pet(root: root, id: "unsafe", version: 1, path: path, bytes: nil)
            XCTAssertNil(CodexPetReader.localSource(root: root, id: "unsafe", manifest: "pet.json"))
        }
        try pet(root: outside, id: "linked", version: 1, path: "spritesheet.png", bytes: sheet(rows: 9))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: outside.appendingPathComponent("linked"))
        XCTAssertNil(CodexPetReader.localSource(root: root, id: "linked", manifest: "pet.json"))
        try pet(root: root, id: "filelink", version: 1, path: "spritesheet.png", bytes: nil)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("filelink/spritesheet.png"),
                                                withDestinationURL: outside.appendingPathComponent("linked/spritesheet.png"))
        XCTAssertNil(CodexPetReader.localSource(root: root, id: "filelink", manifest: "pet.json"))
    }

    func testRejectsUnknownVersionsCorruptSheetsAndUnknownBuiltIns() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try pet(root: root, id: "future", version: 3, path: "spritesheet.png", bytes: Data([0]))
        XCTAssertNil(CodexPetReader.localSource(root: root, id: "future", manifest: "pet.json"))
        try pet(root: root, id: "broken", version: 1, path: "spritesheet.png", bytes: Data([0]))
        let source = try XCTUnwrap(CodexPetReader.localSource(root: root, id: "broken", manifest: "pet.json"))
        XCTAssertNil(CodexPetSheet.load(source))
        try Data("[desktop]\nselected-avatar-id = 'unrecognized'".utf8).write(to: root.appendingPathComponent("config.toml"))
        XCTAssertNil(CodexPetReader.source(home: root, archives: []))
    }

    func testSourceFindsCustomPetWithoutInstalledCodexArchive() throws {
        let home = try directory()
        defer { try? FileManager.default.removeItem(at: home) }
        try pet(root: home.appendingPathComponent("pets"), id: "demo", version: 2, path: "spritesheet.png", bytes: sheet(rows: 11))
        try Data("[desktop]\nselected-avatar-id = 'custom:demo'".utf8).write(to: home.appendingPathComponent("config.toml"))
        XCTAssertEqual(CodexPetReader.source(home: home, archives: [])?.name, "Fixture Pet")
    }

    func testCloudMigrationResolvesOnlyAnExactUnambiguousLocalCopy() throws {
        let home = try directory()
        defer { try? FileManager.default.removeItem(at: home) }
        try pet(root: home.appendingPathComponent("pets"), id: "demo", version: 2, path: "spritesheet.png", bytes: sheet(rows: 11))
        let state: [String: Any] = ["electron-persisted-atom-state": ["migrated-cloud-pet-ids-v1": [
            "account-fixture": ["custom:demo": "pet_fixture"]
        ]]]
        try JSONSerialization.data(withJSONObject: state).write(to: home.appendingPathComponent(".codex-global-state.json"))
        try Data("[desktop]\nselected-avatar-id = 'pet_fixture'".utf8).write(to: home.appendingPathComponent("config.toml"))
        XCTAssertEqual(CodexPetReader.source(home: home, archives: [])?.rows, 11)
        XCTAssertNil(CodexPetReader.localID(for: "pet_other", state: state))
        XCTAssertNil(CodexPetReader.localID(for: "pet_fixture", state: ["migrated-cloud-pet-ids-v1": [
            "a": ["custom:one": "pet_fixture"], "b": ["custom:two": "pet_fixture"]
        ]]))
    }

    @MainActor
    func testSpritePosesStayInsideValidFramesAndStillIsStable() {
        for mood in PetMood.allCases {
            for time in stride(from: 0.0, through: 3, by: 0.08) {
                let pose = CodexPetStore.pose(mood: mood, time: time)
                XCTAssertTrue((0..<9).contains(pose.row))
                XCTAssertTrue((0..<8).contains(pose.column))
            }
            XCTAssertEqual(CodexPetStore.pose(mood: mood, time: 0).column, 0)
        }
        XCTAssertEqual(CodexPetStore.pose(mood: .focused, time: 0).row, 7)
    }

    func testBundledSheetIsReadAtBoundedAsarOffsetWithoutExecutingApp() throws {
        let home = try directory()
        defer { try? FileManager.default.removeItem(at: home) }
        let png = try sheet(rows: 9)
        let archive = home.appendingPathComponent("app.asar")
        let json = try JSONSerialization.data(withJSONObject: ["files": ["webview": ["files": ["assets": ["files": [
            "codex-spritesheet-fixture.png": ["offset": "0", "size": png.count]
        ]]]]]])
        var bytes = Data()
        for number in [4, json.count + 8, json.count + 4, json.count] {
            var value = UInt32(number).littleEndian
            withUnsafeBytes(of: &value) { bytes.append(contentsOf: $0) }
        }
        bytes.append(json)
        bytes.append(png)
        try bytes.write(to: archive)
        let source = try XCTUnwrap(CodexPetReader.source(home: home, archives: [archive]))
        XCTAssertEqual(try source.data(), png)
        XCTAssertEqual(CodexPetSheet.load(source)?.rows, 9)
        XCTAssertEqual(CodexPetReader.source(home: home, archives: [archive], previous: source)?.revision, source.revision)
        try bytes.dropLast(png.count).write(to: archive)
        XCTAssertNil(CodexPetReader.source(home: home, archives: [archive]))
    }

    @MainActor
    func testInstalledSelectedPetWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["CLAUDEUSAGE_LIVE_PET_TEST"] == "1" else {
            throw XCTSkip("Opt in to read the selected local Codex pet; no selection or settings are changed.")
        }
        let source = try XCTUnwrap(CodexPetReader.source(home: CodexPetReader.home, archives: CodexPetReader.archives))
        let sheet = try XCTUnwrap(CodexPetSheet.load(source))
        print("[Codex pet live check] Decoded \(sheet.image.width)x\(sheet.image.height), \(sheet.rows) rows")
        await CodexPetStore.shared.refresh()
        let first = try XCTUnwrap(CodexPetStore.shared.frame(mood: .focused, time: 0))
        let next = try XCTUnwrap(CodexPetStore.shared.frame(mood: .focused, time: 0.17))
        XCTAssertEqual(first.width, next.width)
        XCTAssertFalse(first === next)
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, first, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        try (data as Data).write(to: URL(fileURLWithPath: "/private/tmp/ClaudeUsage-selected-codex-pet-preview.png"))
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeUsage-pet-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func pet(root: URL, id: String, version: Int, path: String, bytes: Data?) throws {
        let directory = root.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["displayName": "Fixture Pet", "spriteVersionNumber": version, "spritesheetPath": path])
            .write(to: directory.appendingPathComponent("pet.json"))
        if let bytes { try bytes.write(to: directory.appendingPathComponent(path)) }
    }

    private func sheet(rows: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 96, height: rows * 13, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.systemOrange.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 96, height: rows * 13))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
