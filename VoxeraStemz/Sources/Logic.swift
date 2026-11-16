import Foundation

enum OutputFormat: Int, Codable, CaseIterable, Identifiable {
    case mp3 = 0
    case wav16 = 1
    case flac16 = 2
    case m4a = 3
    case wav32 = 4
    case flac24 = 5

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .mp3: return "MP3 320"
        case .wav16: return "WAV 16"
        case .flac16: return "FLAC 16"
        case .m4a: return "M4A"
        case .wav32: return "WAV 32"
        case .flac24: return "FLAC 24"
        }
    }

    var fileExtension: String {
        switch self {
        case .mp3: return "mp3"
        case .wav16, .wav32: return "wav"
        case .flac16, .flac24: return "flac"
        case .m4a: return "m4a"
        }
    }

    var premiumOnly: Bool { self == .wav32 || self == .flac24 }
}

struct PriceRule: Equatable, Codable {
    var fieldName: String
    var optionKey: String
    var mode: String
    var value: Double
}

struct BillingDecision: Equatable {
    var paid: Bool
    var reasons: [String]
}

enum PremiumPolicy {
    static func decide(orientation: Int, sepType: Int, options: [String: String], rules: [PriceRule]) -> BillingDecision {
        var reasons: [String] = []
        if orientation == 2 {
            reasons.append("orientation")
        }
        if sepType == 40 && options["add_opt1"] == "171" {
            reasons.append("bsr124")
        }
        if sepType == 49 && options["add_opt1"] == "8" {
            reasons.append("karaoke124")
        }
        for rule in rules where options[rule.fieldName] == rule.optionKey {
            reasons.append("rule:\(rule.fieldName)=\(rule.optionKey)")
        }
        return BillingDecision(paid: !reasons.isEmpty, reasons: reasons)
    }

    static func resolvedFormat(requested: Int, usePremium: Bool) -> (format: Int, note: String?) {
        let format = OutputFormat(rawValue: requested) ?? .wav16
        if !usePremium && format.premiumOnly {
            return (
                OutputFormat.wav16.rawValue,
                "WAV 32 y FLAC 24 solo se pueden pedir con créditos. Este paso va sin créditos, así que se usará WAV 16."
            )
        }
        return (format.rawValue, nil)
    }

    static func effectiveUsePremium(stored: Bool, overridden: Bool, rulePaid: Bool) -> Bool {
        overridden ? stored : rulePaid
    }
}

enum StemMatch {
    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func matches(wanted: String, typeLabel: String) -> Bool {
        let wanted = normalize(wanted)
        let label = normalize(typeLabel)
        if wanted.isEmpty || label.isEmpty { return false }
        if label == wanted || label.contains(wanted) || wanted.contains(label) { return true }
        if isVocal(wanted) && isVocal(label) { return true }
        if isBeat(wanted) && isBeat(label) { return true }
        return false
    }

    static func canonical(planned: String, typeLabel: String) -> String {
        if matches(wanted: planned, typeLabel: typeLabel), !normalize(planned).isEmpty {
            return normalize(planned)
        }
        let label = normalize(typeLabel)
        if isVocal(label) { return "vocals" }
        if isBeat(label) { return "other" }
        return label
    }

    static func displayStem(_ type: String) -> String {
        let label = normalize(type)
        if isDry(label) { return "Dry" }
        if isVocal(label) { return "Acapella" }
        if isBeat(label) { return "Beat" }
        return type
    }

    static func fileStem(_ type: String) -> String {
        let label = normalize(type)
        if isDry(label) { return "Dry" }
        if label == "other" || label == "instrumental" || label == "instrum" || label == "instrumental only" {
            return "Beat"
        }
        return FilenameBuilder.sanitize(type)
    }

    static func isVocal(_ label: String) -> Bool {
        let value = normalize(label)
        return value == "vocals" || value == "vocal" || value == "acapella" || value == "a cappella" || value.contains("acapella")
    }

    static func isDry(_ label: String) -> Bool {
        let value = normalize(label)
        return value == "dry" || value.contains("no reverb")
    }

    static func isBeat(_ label: String) -> Bool {
        let value = normalize(label)
        return value == "other" || value == "instrumental" || value == "instrum" || value == "beat" || value == "instrumental only" || value.contains("instrumental")
    }
}

enum FilenameBuilder {
    static func sanitize(_ raw: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let pieces = raw.components(separatedBy: forbidden).joined(separator: " ")
        let collapsed = pieces
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Audio" : trimmed
    }

    static func make(song: String, abbreviations: [String], stem: String, ext: String) -> String {
        let name = sanitize(song)
        let abbr = abbreviations.map(sanitize).filter { !$0.isEmpty && $0 != "Audio" }.joined(separator: "-")
        let stemName = StemMatch.fileStem(stem)
        let extClean = ext.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        let head = abbr.isEmpty ? name : "\(name) \(abbr)"
        return "\(head) \(stemName).\(extClean)"
    }
}

enum AbbreviationDefaults {
    static let values: [String: String] = [
        "bs-roformer:171": "BSR124",
        "bs-roformer:172": "BSR124",
        "bs-roformer:81": "BSR25",
        "bs-roformer": "BSR",
        "deeffect": "DFX",
        "dry-acapella": "DRY",
        "phase": "PHC",
        "phase-deux": "PHCD",
        "lead-backing": "LBV",
        "karaoke": "KAR",
        "male-female": "MF",
        "medley": "MVX",
        "stereoize": "STR",
        "upmix": "UPM",
        "universr": "USR",
        "clean-inverted": "CIV",
        "aspiration": "ASP",
        "phantom": "PCE",
        "mega53": "M53",
        "muscriptor": "MUS",
        "apollo": "APO",
        "noreverb": "NRV",
        "denoise": "DNZ",
        "audiosr": "ASR",
        "flashsr": "FSR",
        "matchering": "MTC",
        "heartmula": "HML",
    ]

    static func label(_ key: String) -> String {
        switch key {
        case "bs-roformer:171", "bs-roformer:172": return "BS Roformer 124 bandas"
        case "bs-roformer:81": return "BS Roformer 2025.07"
        case "bs-roformer": return "BS Roformer"
        case "deeffect": return "DeEffect"
        case "dry-acapella": return "Dry acapella (de-reverbed)"
        case "phase": return "Instrumental phase correction"
        case "phase-deux": return "Instrumental phase correction by Deux"
        case "lead-backing": return "Lead/backing vocals (two-stage)"
        case "karaoke": return "Karaoke"
        case "male-female": return "Hombre / mujer"
        case "medley": return "Medley Vox"
        case "stereoize": return "Stereoize"
        case "upmix": return "Upmix 5.1"
        case "universr": return "UniverSR"
        case "clean-inverted": return "Clean Inverted"
        case "aspiration": return "Aspiration"
        case "phantom": return "Phantom Centre"
        case "mega53": return "Mega 53"
        case "muscriptor": return "Muscriptor"
        case "apollo": return "Apollo"
        case "noreverb": return "Sin reverb"
        case "denoise": return "DeNoise"
        case "audiosr": return "AudioSR"
        case "flashsr": return "FlashSR"
        case "matchering": return "Matchering"
        case "heartmula": return "HeartMuLa"
        default: return key
        }
    }

    static func resolve(curatedKey: String, options: [String: String], custom: [String: String]) -> String {
        if curatedKey == "bs-roformer", let option = options["add_opt1"] {
            let special = "bs-roformer:\(option)"
            if let value = nonempty(custom[special]) { return value }
            if let value = nonempty(values[special]) { return value }
        }
        if let value = nonempty(custom[curatedKey]) { return value }
        return values[curatedKey] ?? "STEP"
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct StepSignature: Codable, Equatable, Hashable {
    var sepType: Int
    var options: [String: String]
    var outputFormat: Int
    var chosenStem: String
}

enum SignatureOptions {
    static func normalize(_ options: [String: String]) -> [String: String] {
        options.filter { $0.key.hasPrefix("add_opt") || $0.key == "_referenceSHA256" }
    }
}

struct JobFingerprint: Equatable {
    var id: UUID
    var inputHash: String
    var steps: [StepSignature]
}

enum DuplicateHit: Equatable {
    case none
    case exact(UUID)
    case prefix(UUID, Int)
}

enum DuplicateMatcher {
    static func match(inputHash: String, planned: [StepSignature], jobs: [JobFingerprint]) -> DuplicateHit {
        var exact: UUID?
        var best: (UUID, Int)?
        for job in jobs where job.inputHash == inputHash && !job.steps.isEmpty {
            let count = sharedPrefix(planned, job.steps)
            if count == 0 { continue }
            if count == planned.count {
                exact = job.id
            } else if best == nil || count > best!.1 {
                best = (job.id, count)
            }
        }
        if let exact { return .exact(exact) }
        if let best { return .prefix(best.0, best.1) }
        return .none
    }

    static func sharedPrefix(_ planned: [StepSignature], _ stored: [StepSignature]) -> Int {
        let count = min(planned.count, stored.count)
        var index = 0
        while index < count && planned[index] == stored[index] {
            index += 1
        }
        return index
    }
}

enum CreateDecision: Equatable {
    case poll(String)
    case create
    case doNotRetry
}

enum CreatePolicy {
    static func decide(existingHash: String?, phase: String) -> CreateDecision {
        if let hash = existingHash?.trimmingCharacters(in: .whitespacesAndNewlines), !hash.isEmpty {
            return .poll(hash)
        }
        if phase == "creating" || phase == "uncertain" || phase == "polling" {
            return .doNotRetry
        }
        return .create
    }
}

enum RemoteFallback: Equatable {
    case uploadLocal
    case stop
}

enum FallbackPolicy {
    static func afterRemoteFailure(definitive: Bool, localReady: Bool, uploadTried: Bool) -> RemoteFallback {
        if definitive && localReady && !uploadTried { return .uploadLocal }
        return .stop
    }
}

enum StartGate {
    static func allow(locked: Bool, busy: Bool) -> Bool {
        !locked && !busy
    }
}

enum ContinuationUpload {
    static func filename(song: String, ext: String) -> String {
        let name = FilenameBuilder.sanitize(song)
        let clean = ext.trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return clean.isEmpty ? name : "\(name).\(clean)"
    }
}

enum RetryPolicy {
    static func canRetry(state: String, phase: String, hash: String?) -> Bool {
        guard state == "failed" else { return false }
        if phase == "uncertain" { return false }
        let token = hash?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !token.isEmpty && (phase == "creating" || phase == "polling") { return false }
        return true
    }
}

enum QueueList {
    static func collapse(_ jobs: [ChainJob]) -> [ChainJob] {
        var seen: Set<String> = []
        var output: [ChainJob] = []
        for job in jobs {
            guard job.state == "failed" else {
                output.append(job)
                continue
            }
            let key = "\(job.inputSHA256)|\(job.presetName)|\(job.songName)|\(job.currentIndex)"
            if seen.contains(key) { continue }
            seen.insert(key)
            output.append(job)
        }
        return output
    }
}

enum MVSEPMessage {
    static func spanish(_ text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("file or file hash not found") || lower.contains("file hash not found") {
            return "MVSEP no encontró el archivo. Hay que subir el audio guardado en el dispositivo."
        }
        let collapsed = text.replacingOccurrences(of: "\n", with: " ")
        if collapsed.count <= 180 { return collapsed }
        return String(collapsed.prefix(180))
    }
}

struct ChainStep: Codable, Identifiable, Equatable {
    var id: UUID
    var enabled: Bool
    var curatedKey: String
    var options: [String: String]
    var outputFormat: Int
    var continueStem: String
    var usePremium: Bool
    var usePremiumOverridden: Bool
}

struct ChainPreset: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var autoContinue: Bool
    var builtIn: Bool
    var steps: [ChainStep]
}

enum BuiltInPresets {
    static func examples() -> [ChainPreset] {
        [
            ChainPreset(
                id: UUID(),
                name: "Acapella limpia",
                autoContinue: false,
                builtIn: true,
                steps: [
                    step("bs-roformer", ["add_opt1": "171", "add_opt2": "2", "add_opt3": "0"], 1, "vocals", true),
                    step("deeffect", [:], 1, "vocals", false),
                    step("aspiration", ["add_opt1": "0"], 1, "", false),
                ]
            ),
            ChainPreset(
                id: UUID(),
                name: "Beat con fase",
                autoContinue: false,
                builtIn: true,
                steps: [
                    step("bs-roformer", ["add_opt1": "81", "add_opt2": "2", "add_opt3": "0"], 1, "other", false),
                    step("phase-deux", ["add_opt1": "11", "add_opt2": "2"], 1, "other", false),
                ]
            ),
            ChainPreset(
                id: UUID(),
                name: "Acapella seca",
                autoContinue: false,
                builtIn: true,
                steps: [
                    step("bs-roformer", ["add_opt1": "171", "add_opt2": "2", "add_opt3": "0"], 1, "vocals", true),
                    step("dry-acapella", ["add_opt1": "9", "add_opt2": "1"], 1, "dry", false),
                    step("deeffect", [:], 1, "", false),
                ]
            ),
        ]
    }

    private static func step(_ key: String, _ options: [String: String], _ format: Int, _ stem: String, _ premium: Bool) -> ChainStep {
        ChainStep(
            id: UUID(),
            enabled: true,
            curatedKey: key,
            options: options,
            outputFormat: format,
            continueStem: stem,
            usePremium: premium,
            usePremiumOverridden: false
        )
    }
}

struct CachedStem: Codable, Identifiable, Equatable {
    var id: UUID
    var typeLabel: String
    var remoteURL: String
    var relativePath: String
    var sha256: String
}

struct JobStep: Codable, Identifiable, Equatable {
    var id: UUID
    var curatedKey: String
    var title: String
    var sepType: Int
    var options: [String: String]
    var outputFormat: Int
    var usePremium: Bool
    var abbreviation: String
    var continueStem: String
    var phase: String
    var hash: String?
    var formatNote: String?
    var files: [CachedStem]
    var chosenStemID: UUID?
    var error: String?

    var signature: StepSignature {
        StepSignature(
            sepType: sepType,
            options: SignatureOptions.normalize(options),
            outputFormat: outputFormat,
            chosenStem: continueStem
        )
    }
}

struct ChainJob: Codable, Identifiable, Equatable {
    var id: UUID
    var songName: String
    var kind: String
    var presetName: String
    var inputRelativePath: String
    var inputSHA256: String
    var autoContinue: Bool
    var state: String
    var steps: [JobStep]
    var currentIndex: Int
    var message: String?
    var originalPremium: Bool?
    var premiumDirty: Bool
    var createdAt: Date
    var queueAhead: Int?
    var queueCount: Int?
    var estimatedWait: Int?
    var remoteStatus: String?
    var referenceRelativePath: String?

    func fingerprint() -> JobFingerprint {
        JobFingerprint(
            id: id,
            inputHash: inputSHA256,
            steps: steps.filter { step in
                step.phase == "done" || (step.phase == "awaitingChoice" && !step.files.isEmpty)
            }.map(\.signature)
        )
    }

    var isActive: Bool {
        state == "running" || state == "awaiting"
    }
}

struct AppSettings: Codable, Equatable {
    var protectFreeModels: Bool
    var defaultOutputFormat: Int
    var defaultSampleRate: Int
    var defaultAutoContinue: Bool
    var notificationsEnabled: Bool
    var abbreviations: [String: String]

    static var standard: AppSettings {
        AppSettings(
            protectFreeModels: true,
            defaultOutputFormat: OutputFormat.wav16.rawValue,
            defaultSampleRate: 48000,
            defaultAutoContinue: false,
            notificationsEnabled: true,
            abbreviations: AbbreviationDefaults.values
        )
    }
}

enum StatusText {
    static func spanish(_ status: String) -> String {
        switch status.lowercased() {
        case "waiting": return "Esperando"
        case "processing": return "Procesando"
        case "distributing": return "Distribuyendo"
        case "merging": return "Uniendo"
        case "done": return "Listo"
        case "failed": return "Falló"
        case "not_found": return "No encontrado"
        case "uncertain": return "Sin reintento"
        case "awaiting": return "Elige un stem"
        case "running": return "En curso"
        case "cancelled": return "Cancelado"
        default: return status.isEmpty ? "—" : status
        }
    }
}

enum ByteFormat {
    static func megabytes(_ bytes: Int64) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
