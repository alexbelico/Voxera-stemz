import Foundation

enum MVError: Error, Equatable {
    case api(String)
    case transport(String)
    case http(Int, String)
}

struct MVUser: Equatable {
    var name: String
    var premiumEnabled: Bool
    var premiumMinutes: Double
}

struct RemoteFile: Equatable {
    var type: String
    var url: String
}

struct SeparationStatus: Equatable {
    var success: Bool
    var status: String
    var message: String
    var queueCount: Int?
    var currentOrder: Int?
    var files: [RemoteFile]
}

struct QueueSummary: Equatable {
    var queued: Int?
    var processing: Int?
    var ahead: Int?
    var estimatedWait: Int?
}

enum CreateBody: Equatable {
    case remoteURL(String)
    case audioFile
    case matchering
    case none
}

struct CreatePlan: Equatable {
    var sepType: Int
    var outputFormat: Int
    var options: [String: String]
    var body: CreateBody

    var textFields: [String: String] {
        var fields = [
            "sep_type": String(sepType),
            "output_format": String(outputFormat),
            "is_demo": "0",
        ]
        for (key, value) in options where key.hasPrefix("add_opt") {
            fields[key] = value
        }
        if case let .remoteURL(url) = body {
            fields["url"] = url
            fields["remote_type"] = "direct"
        }
        return fields
    }
}

enum JSONBlob {
    static func object(from data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data)
    }

    static func dictionary(_ any: Any?) -> [String: Any] {
        any as? [String: Any] ?? [:]
    }

    static func string(_ any: Any?) -> String? {
        guard let any, !(any is NSNull) else { return nil }
        if let value = any as? String { return value }
        if let number = any as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            let double = number.doubleValue
            if double.rounded(.towardZero) == double && abs(double) < 1_000_000_000_000 {
                return String(number.int64Value)
            }
            return String(double)
        }
        return nil
    }

    static func bool(_ any: Any?) -> Bool? {
        guard let any, !(any is NSNull) else { return nil }
        if let value = any as? Bool { return value }
        if let number = any as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
            return number.intValue != 0
        }
        if let text = any as? String {
            switch text.lowercased() {
            case "1", "true", "yes": return true
            case "0", "false", "no": return false
            default: return nil
            }
        }
        return nil
    }

    static func double(_ any: Any?) -> Double? {
        guard let any, !(any is NSNull) else { return nil }
        if let number = any as? NSNumber { return number.doubleValue }
        if let text = any as? String { return Double(text) }
        return nil
    }

    static func int(_ any: Any?) -> Int? {
        guard let any, !(any is NSNull) else { return nil }
        if let number = any as? NSNumber { return number.intValue }
        if let text = any as? String { return Int(text) }
        return nil
    }
}

enum APIParser {
    static func user(from data: Data) throws -> MVUser {
        let root = try dictionary(data)
        let payload = JSONBlob.dictionary(root["data"])
        if JSONBlob.bool(root["success"]) == false {
            throw MVError.api(message(in: root, payload: payload, fallback: "Clave rechazada"))
        }
        return MVUser(
            name: JSONBlob.string(payload["name"]) ?? "",
            premiumEnabled: JSONBlob.bool(payload["premium_enabled"]) ?? false,
            premiumMinutes: JSONBlob.double(payload["premium_minutes"]) ?? 0
        )
    }

    static func createdHash(from data: Data) throws -> String {
        let root = try dictionary(data)
        let payload = JSONBlob.dictionary(root["data"])
        if JSONBlob.bool(root["success"]) == false {
            throw MVError.api(message(in: root, payload: payload, fallback: "No se pudo crear la separación"))
        }
        let hash = JSONBlob.string(payload["hash"]) ?? JSONBlob.string(root["hash"]) ?? ""
        if hash.isEmpty {
            throw MVError.api("La respuesta no trajo hash")
        }
        return hash
    }

    static func separation(from data: Data) throws -> SeparationStatus {
        let root = try dictionary(data)
        let payload = JSONBlob.dictionary(root["data"])
        let status = JSONBlob.string(root["status"]) ?? JSONBlob.string(payload["status"]) ?? ""
        let files = (payload["files"] as? [Any] ?? []).compactMap { item -> RemoteFile? in
            let file = JSONBlob.dictionary(item)
            let url = JSONBlob.string(file["url"]) ?? ""
            guard !url.isEmpty else { return nil }
            let type = JSONBlob.string(file["type"]) ?? "Audio"
            return RemoteFile(type: type, url: url)
        }
        return SeparationStatus(
            success: JSONBlob.bool(root["success"]) ?? true,
            status: status,
            message: message(in: root, payload: payload, fallback: ""),
            queueCount: JSONBlob.int(payload["queue_count"]),
            currentOrder: JSONBlob.int(payload["current_order"]),
            files: files
        )
    }

    static func queue(from data: Data) throws -> QueueSummary {
        let root = try dictionary(data)
        let payload = JSONBlob.dictionary(root["data"])
        func pick(_ key: String) -> Any? { root[key] ?? payload[key] }
        return QueueSummary(
            queued: JSONBlob.int(pick("queued")),
            processing: JSONBlob.int(pick("processing")),
            ahead: JSONBlob.int(pick("ahead")),
            estimatedWait: JSONBlob.int(pick("estimated_wait_seconds"))
        )
    }

    static func separationURL(hash: String) -> URL? {
        var components = URLComponents(string: "https://mvsep.com/api/separation/get")
        components?.queryItems = [URLQueryItem(name: "hash", value: hash)]
        return components?.url
    }

    private static func dictionary(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONBlob.object(from: data) as? [String: Any] else {
            throw MVError.api("Respuesta ilegible")
        }
        return object
    }

    private static func message(in root: [String: Any], payload: [String: Any], fallback: String) -> String {
        JSONBlob.string(payload["message"]) ?? JSONBlob.string(root["message"]) ?? fallback
    }
}

struct MVSEPClient {
    var session: URLSession = .shared

    func user(token: String) async throws -> MVUser {
        let data = try await get(url: url("/api/app/user", ["api_token": token]))
        return try APIParser.user(from: data)
    }

    func setPremium(enabled: Bool, token: String) async throws {
        let path = enabled ? "/api/app/enable_premium" : "/api/app/disable_premium"
        let data = try await post(url: url(path), fields: ["api_token": token], files: [])
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        if JSONBlob.bool(root["success"]) == false {
            throw MVError.api(JSONBlob.string(root["message"]) ?? "No se pudo cambiar premium")
        }
    }

    func queue(token: String) async throws -> QueueSummary {
        let data = try await get(url: url("/api/app/queue/summary", ["api_token": token]))
        return try APIParser.queue(from: data)
    }

    func separation(hash: String) async throws -> SeparationStatus {
        guard let target = APIParser.separationURL(hash: hash) else {
            throw MVError.api("Hash inválido")
        }
        let data = try await get(url: target)
        return try APIParser.separation(from: data)
    }

    func cancel(hash: String, token: String) async throws {
        _ = try await post(
            url: url("/api/separation/cancel"),
            fields: ["api_token": token, "hash": hash],
            files: []
        )
    }

    func algorithms() async throws -> Data {
        let target = url("/api/app/algorithms", ["scopes": "single_upload,no_upload,matchering_upload"])
        return try await get(url: target)
    }

    func create(plan: CreatePlan, token: String, audio: URL?, reference: URL?) async throws -> String {
        var fields = plan.textFields
        fields["api_token"] = token
        var files: [(String, URL)] = []
        switch plan.body {
        case .audioFile:
            guard let audio else { throw MVError.api("Falta el audio") }
            files.append(("audiofile", audio))
        case .matchering:
            guard let audio, let reference else { throw MVError.api("Faltan el audio y la referencia") }
            files.append(("target_audiofile", audio))
            files.append(("reference_audiofile", reference))
        case .remoteURL, .none:
            break
        }
        let data = try await post(url: url("/api/separation/create"), fields: fields, files: files)
        return try APIParser.createdHash(from: data)
    }

    func download(from remote: URL, to destination: URL) async throws {
        if FileManager.default.fileExists(atPath: destination.path),
           (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 0 {
            return
        }
        let (temporary, response) = try await session.download(from: remote)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MVError.http(http.statusCode, "No se pudo guardar el stem")
        }
        let folder = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: temporary)
            return
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }

    private func url(_ path: String, _ query: [String: String] = [:]) -> URL {
        var components = URLComponents(string: "https://mvsep.com\(path)")!
        if !query.isEmpty {
            components.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) }
        }
        return components.url!
    }

    private func get(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        return try await send(request)
    }

    private func post(url: URL, fields: [String: String], files: [(String, URL)]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        if files.isEmpty {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let body = fields.keys.sorted().map { key in
                "\(formEscape(key))=\(formEscape(fields[key] ?? ""))"
            }.joined(separator: "&")
            request.httpBody = Data(body.utf8)
        } else {
            let boundary = "Boundary-\(UUID().uuidString)"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpBody = try multipart(fields: fields, files: files, boundary: boundary)
        }
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as MVError {
            throw error
        } catch {
            throw MVError.transport("Error de red")
        }
        guard let http = response as? HTTPURLResponse else {
            throw MVError.transport("Respuesta inválida")
        }
        if (200..<300).contains(http.statusCode) {
            return data
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        if http.statusCode == 408 || http.statusCode == 429 || http.statusCode >= 500 {
            throw MVError.transport("HTTP \(http.statusCode)")
        }
        throw MVError.http(http.statusCode, text.isEmpty ? "HTTP \(http.statusCode)" : text)
    }

    private func multipart(fields: [String: String], files: [(String, URL)], boundary: String) throws -> Data {
        var body = Data()
        for key in fields.keys.sorted() {
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.appendUTF8(fields[key] ?? "")
            body.appendUTF8("\r\n")
        }
        for (name, file) in files {
            let filename = file.lastPathComponent.replacingOccurrences(of: "\"", with: "")
            body.appendUTF8("--\(boundary)\r\n")
            body.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
            body.appendUTF8("Content-Type: application/octet-stream\r\n\r\n")
            body.append(try Data(contentsOf: file))
            body.appendUTF8("\r\n")
        }
        body.appendUTF8("--\(boundary)--\r\n")
        return body
    }

    private func formEscape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
