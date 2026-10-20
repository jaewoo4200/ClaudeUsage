import AppKit
import Combine
import ImageIO

struct CodexPetSource {
    let name: String
    let rows: Int?
    let url: URL
    let offset: UInt64
    let length: Int
    let revision: String

    func data() throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)
        let bytes = try handle.read(upToCount: length) ?? Data()
        guard bytes.count == length else { throw CocoaError(.fileReadCorruptFile) }
        return bytes
    }
}

enum CodexPetReader {
    static let maximumBytes = 32 * 1024 * 1024
    static let builtInIDs = ["codex", "bsod", "dewey", "fireball", "hoots", "null-signal", "rocky", "seedy", "stacky"]

    static var home: URL {
        if let path = ProcessInfo.processInfo.environment["CODEX_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    static var archives: [URL] {
        [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
            .flatMap { root in
                ["Codex.app", "ChatGPT.app"].map {
                    root.appendingPathComponent($0).appendingPathComponent("Contents/Resources/app.asar")
                }
            }
    }

    static func selectedID(config: String) -> String? {
        var desktop = false
        let pattern = #"^\s*["']?selected-avatar-id["']?\s*=\s*("(?:[^"\\]|\\.)*"|'[^']*')\s*(?:#.*)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        for rawLine in config.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                desktop = line.split(separator: "#", maxSplits: 1)[0].trimmingCharacters(in: .whitespaces) == "[desktop]"
                continue
            }
            guard desktop, let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let range = Range(match.range(at: 1), in: line) else { continue }
            let value = String(line[range])
            return value.first == "'" ? String(value.dropFirst().dropLast())
                : (try? JSONDecoder().decode(String.self, from: Data(value.utf8)))
        }
        return nil
    }

    static func selectedID(home: URL) -> String? {
        if let bytes = limitedData(home.appendingPathComponent("config.toml"), maximum: 2 * 1024 * 1024),
           let config = String(data: bytes, encoding: .utf8), let id = selectedID(config: config) { return id }
        guard let bytes = limitedData(home.appendingPathComponent(".codex-global-state.json"), maximum: 16 * 1024 * 1024),
              let state = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return nil }
        return (state["electron-persisted-atom-state"] as? [String: Any])?["selected-avatar-id"] as? String
            ?? state["selected-avatar-id"] as? String
    }

    static func localID(for cloudID: String, state: [String: Any]) -> String? {
        let atoms = state["electron-persisted-atom-state"] as? [String: Any] ?? state
        guard let accounts = atoms["migrated-cloud-pet-ids-v1"] as? [String: Any] else { return nil }
        let matches = Set(accounts.values.compactMap { $0 as? [String: String] }.flatMap { mapping in
            mapping.compactMap { key, value in value == cloudID && key.hasPrefix("custom:") ? key : nil }
        })
        return matches.count == 1 ? matches.first : nil
    }

    static func source(home: URL, archives: [URL], previous: CodexPetSource? = nil) -> CodexPetSource? {
        var id = selectedID(home: home) ?? "codex"
        if id.hasPrefix("uploaded:pet_") { id = String(id.dropFirst(9)) }
        if id.hasPrefix("pet_") {
            guard let bytes = limitedData(home.appendingPathComponent(".codex-global-state.json"), maximum: 16 * 1024 * 1024),
                  let state = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                  let local = localID(for: id, state: state) else { return nil }
            id = local
        }
        if id.hasPrefix("custom:") {
            let name = String(id.dropFirst(7))
            guard safeID(name) else { return nil }
            for (folder, manifest) in [("pets", "pet.json"), ("avatars", "avatar.json")] {
                if let source = localSource(root: home.appendingPathComponent(folder), id: name, manifest: manifest) {
                    return source
                }
            }
            return nil
        }
        guard builtInIDs.contains(id) else { return nil }
        for archive in archives {
            if let previous, previous.url == archive,
               let stamp = archiveStamp(archive), previous.revision.hasPrefix(stamp + "|" + id + "-spritesheet-") {
                return previous
            }
            if let source = archiveSource(id: id, archive: archive) { return source }
        }
        return nil
    }

    static func safeID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 128 && id != "." && id != ".."
            && !id.contains(where: { $0 == "/" || $0 == "\\" || $0 == ":" || $0.isNewline || $0.asciiValue == 0 })
    }

    static func localSource(root: URL, id: String, manifest: String) -> CodexPetSource? {
        guard safeID(id) else { return nil }
        let directory = root.appendingPathComponent(id, isDirectory: true)
        let manifestURL = directory.appendingPathComponent(manifest)
        guard contained(manifestURL, in: root), contained(manifestURL, in: directory),
              let bytes = limitedData(manifestURL, maximum: 64 * 1024),
              let object = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return nil }
        let version = object["spriteVersionNumber"] as? Int ?? 1
        guard version == 1 || version == 2 else { return nil }
        let path = object["spritesheetPath"] as? String ?? "spritesheet.webp"
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"), !path.contains("\0") else { return nil }
        let sheet = directory.appendingPathComponent(path).standardizedFileURL
        guard contained(sheet, in: directory), contained(sheet, in: root),
              let info = metadata(sheet),
              info.isRegularFile == true, let length = info.fileSize, (1...maximumBytes).contains(length) else { return nil }
        let name = (object["displayName"] as? String).map { String($0.prefix(80)) } ?? id
        let modified = metadata(manifestURL)?.contentModificationDate
        let revision = "\(sheet.path)|\(length)|\(info.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(modified?.timeIntervalSince1970 ?? 0)"
        return CodexPetSource(name: name, rows: version == 2 ? 11 : 9, url: sheet, offset: 0, length: length, revision: revision)
    }

    // Both lexical and resolved boundaries are required: a pet directory itself may be a symlink.
    private static func contained(_ file: URL, in directory: URL) -> Bool {
        file.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/")
            && file.resolvingSymlinksInPath().path.hasPrefix(directory.resolvingSymlinksInPath().path + "/")
    }

    private static func limitedData(_ url: URL, maximum: Int) -> Data? {
        guard let info = metadata(url),
              info.isRegularFile == true, let size = info.fileSize, size > 0, size <= maximum,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let bytes = try? handle.read(upToCount: maximum + 1), bytes.count <= maximum else { return nil }
        return bytes
    }

    private static func archiveSource(id: String, archive: URL) -> CodexPetSource? {
        guard let handle = try? FileHandle(forReadingFrom: archive) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 16), header.count == 16 else { return nil }
        func integer(_ offset: Int) -> Int { (0..<4).reduce(0) { $0 | Int(header[offset + $1]) << ($1 * 8) } }
        let headerLength = integer(4), jsonLength = integer(12)
        guard jsonLength > 0, headerLength >= jsonLength + 8, headerLength <= maximumBytes,
              let json = try? handle.read(upToCount: jsonLength), json.count == jsonLength,
              let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let files = object["files"] as? [String: Any],
              let webview = files["webview"] as? [String: Any], let webFiles = webview["files"] as? [String: Any],
              let assets = webFiles["assets"] as? [String: Any], let entries = assets["files"] as? [String: Any],
              let info = metadata(archive),
              let archiveLength = info.fileSize else { return nil }
        for name in entries.keys.sorted() where name.hasPrefix(id + "-spritesheet-") && (name.hasSuffix(".webp") || name.hasSuffix(".png")) {
            guard let entry = entries[name] as? [String: Any],
                  let text = entry["offset"] as? String, let offset = UInt64(text),
                  let length = entry["size"] as? Int, (1...maximumBytes).contains(length),
                  offset <= UInt64(archiveLength), UInt64(8 + headerLength + length) <= UInt64(archiveLength) - offset else { continue }
            return CodexPetSource(name: id.capitalized, rows: nil, url: archive,
                                  offset: UInt64(8 + headerLength) + offset, length: length,
                                  revision: "\(archive.path)|\(info.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(archiveLength)|\(name)")
        }
        return nil
    }

    private static func archiveStamp(_ archive: URL) -> String? {
        guard let info = metadata(archive),
              let size = info.fileSize else { return nil }
        return "\(archive.path)|\(info.contentModificationDate?.timeIntervalSince1970 ?? 0)|\(size)"
    }

    private static func metadata(_ url: URL) -> URLResourceValues? {
        var fresh = url
        fresh.removeAllCachedResourceValues()
        return try? fresh.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
    }

    static func rows(width: Int, height: Int, expected: Int?) -> Int? {
        guard width > 0, height > 0, width <= 8192, height <= 8192,
              width * height <= 16_777_216, width.isMultiple(of: 8) else { return nil }
        return [9, 11].first { rows in
            (expected == nil || expected == rows) && height.isMultiple(of: rows)
                && (width / 8) * 13 == (height / rows) * 12
        }
    }
}

struct CodexPetSheet {
    let name: String
    let image: CGImage
    let rows: Int
    let revision: String

    static func load(_ source: CodexPetSource) -> CodexPetSheet? {
        guard let bytes = try? source.data(),
              let decoder = CGImageSourceCreateWithData(bytes as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(decoder, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let rows = CodexPetReader.rows(width: width, height: height, expected: source.rows),
              let image = CGImageSourceCreateImageAtIndex(decoder, 0, nil) else { return nil }
        return CodexPetSheet(name: source.name, image: image, rows: rows, revision: source.revision)
    }
}

@MainActor
final class CodexPetStore: ObservableObject {
    static let shared = CodexPetStore()
    @Published private(set) var sheet: CodexPetSheet?
    private var lastRead = Date.distantPast
    private var refreshing = false
    private var frames: [Int: CGImage] = [:]
    private var previousSource: CodexPetSource?

    func refresh() async {
        guard !refreshing, Date().timeIntervalSince(lastRead) >= 4 else { return }
        refreshing = true
        lastRead = Date()
        defer { refreshing = false }
        let previous = previousSource
        let result = await Task.detached(priority: .utility) { () -> (Bool, CodexPetSource?, CodexPetSheet?) in
            guard let source = CodexPetReader.source(home: CodexPetReader.home, archives: CodexPetReader.archives, previous: previous) else { return (true, nil, nil) }
            guard source.revision != previous?.revision else { return (false, previous, nil) }
            return (true, source, CodexPetSheet.load(source))
        }.value
        if result.0 {
            frames.removeAll()
            previousSource = result.1
            sheet = result.2
        }
    }

    static func pose(mood: PetMood, time: TimeInterval) -> (row: Int, column: Int) {
        let row: Int
        switch mood {
        case .focused: row = 7
        case .tired, .sleepy: row = 5
        case .refreshed: row = 3
        case .waiting: row = 6
        case .calm: row = 0
        }
        let count = [6, 8, 8, 4, 5, 8, 6, 6, 6][row]
        return (row, Int(max(0, time).truncatingRemainder(dividingBy: Double(count) * 0.16) / 0.16) % count)
    }

    func frame(mood: PetMood, time: TimeInterval) -> CGImage? {
        guard let sheet else { return nil }
        let pose = Self.pose(mood: mood, time: time)
        let key = pose.row * 8 + pose.column
        if let cached = frames[key] { return cached }
        let width = sheet.image.width / 8, height = sheet.image.height / sheet.rows
        let frame = sheet.image.cropping(to: CGRect(x: pose.column * width, y: pose.row * height, width: width, height: height))
        frames[key] = frame
        return frame
    }
}
