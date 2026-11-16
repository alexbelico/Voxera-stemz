import CryptoKit
import Foundation
import Security

enum FileHash {
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1024 * 1024)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hex(Array(hasher.finalize()))
    }

    static func sha256(of data: Data) -> String {
        hex(Array(SHA256.hash(data: data)))
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

enum KeychainStore {
    static let service = "com.alex.voxerastemz"
    static let account = "api_token"

    static func save(_ token: String) -> Bool {
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class DiskStore {
    let root: URL
    let documents: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(root: URL, documents: URL) {
        self.root = root
        self.documents = documents
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    }

    func loadPresets() -> [ChainPreset] {
        load([ChainPreset].self, name: "presets.json") ?? BuiltInPresets.examples()
    }

    func savePresets(_ presets: [ChainPreset]) { save(presets, name: "presets.json") }

    func loadJobs() -> [ChainJob] { load([ChainJob].self, name: "jobs.json") ?? [] }

    func saveJobs(_ jobs: [ChainJob]) { save(jobs, name: "jobs.json") }

    func loadSettings() -> AppSettings { load(AppSettings.self, name: "settings.json") ?? .standard }

    func saveSettings(_ settings: AppSettings) { save(settings, name: "settings.json") }

    func loadCatalog() -> Data? {
        let url = root.appendingPathComponent("algorithms.json")
        return try? Data(contentsOf: url)
    }

    func saveCatalog(_ data: Data) {
        try? data.write(to: root.appendingPathComponent("algorithms.json"), options: .atomic)
    }

    func url(_ relative: String) -> URL {
        documents.appendingPathComponent(relative)
    }

    func relative(from url: URL) -> String {
        let base = documents.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(base) else { return url.lastPathComponent }
        var suffix = String(path.dropFirst(base.count))
        if suffix.hasPrefix("/") { suffix.removeFirst() }
        return suffix
    }

    func songFolder(_ name: String) -> URL {
        let folder = documents.appendingPathComponent(FilenameBuilder.sanitize(name), isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func uniqueFile(song: String, abbreviations: [String], stem: String, ext: String) -> URL {
        let folder = songFolder(song)
        let primary = FilenameBuilder.make(song: song, abbreviations: abbreviations, stem: stem, ext: ext)
        var candidate = folder.appendingPathComponent(primary)
        let base = (primary as NSString).deletingPathExtension
        let fileExt = (primary as NSString).pathExtension
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(index).\(fileExt)")
            index += 1
        }
        return candidate
    }

    func storageBytes() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: documents, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    func removeAllSongs() {
        guard let items = try? FileManager.default.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil) else { return }
        for item in items { try? FileManager.default.removeItem(at: item) }
    }

    private func load<T: Decodable>(_ type: T.Type, name: String) -> T? {
        let url = root.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, name: String) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: root.appendingPathComponent(name), options: .atomic)
    }
}
