import Foundation

struct FieldChoice: Equatable, Identifiable {
    var key: String
    var label: String
    var id: String { key }
}

struct AlgoField: Equatable, Identifiable {
    var name: String
    var text: String
    var inputType: String
    var choices: [FieldChoice]
    var defaultKey: String?
    var priceRules: [PriceRule]
    var id: String { name }

    var spanishTitle: String { FieldTitles.spanish(text) }
}

struct Algorithm: Equatable, Identifiable {
    var renderID: Int
    var name: String
    var orientation: Int
    var widget: String
    var fields: [AlgoField]
    var outputs: [FieldChoice]
    var id: Int { renderID }

    var rules: [PriceRule] { fields.flatMap(\.priceRules) }

    func defaultOptions() -> [String: String] {
        var options: [String: String] = [:]
        for field in fields {
            if let key = field.defaultKey, !key.isEmpty {
                options[field.name] = key
            }
        }
        return options
    }

    static let muscriptor = Algorithm(
        renderID: 141,
        name: "Muscriptor",
        orientation: 0,
        widget: "single_upload",
        fields: [
            AlgoField(
                name: "add_opt1",
                text: "Quantize",
                inputType: "select",
                choices: [FieldChoice(key: "0", label: "No"), FieldChoice(key: "1", label: "Yes")],
                defaultKey: "0",
                priceRules: []
            ),
            AlgoField(
                name: "add_opt2",
                text: "Cfg coef",
                inputType: "select",
                choices: [
                    FieldChoice(key: "1.0", label: "1.0"),
                    FieldChoice(key: "1.5", label: "1.5"),
                    FieldChoice(key: "2.0", label: "2.0"),
                ],
                defaultKey: "1.0",
                priceRules: []
            ),
        ],
        outputs: []
    )
}

enum FieldTitles {
    static func spanish(_ text: String) -> String {
        switch text.lowercased() {
        case "vocal model type", "model type", "karaoke model type":
            return "Variante"
        case "overlap":
            return "Solapamiento"
        case "set of stems":
            return "Conjunto"
        case "extraction type", "how to extract", "preprocess":
            return "Extracción"
        case "cutoff", "cutoff (hz)":
            return "Corte"
        case "lyrics":
            return "Letra"
        case "tags (optional)", "tags":
            return "Etiquetas"
        case "genre":
            return "Género"
        case "timbre":
            return "Timbre"
        case "gender":
            return "Voz"
        case "mood":
            return "Ánimo"
        case "instrument":
            return "Instrumento"
        case "scene":
            return "Escena"
        case "region":
            return "Región"
        case "topic":
            return "Tema"
        case "guidance scale":
            return "Guía"
        case "input sample rate":
            return "Frecuencia de entrada"
        case "quantize":
            return "Cuantizar"
        case "cfg coef":
            return "Cfg"
        default:
            return text
        }
    }
}

enum AlgorithmParser {
    static func parse(data: Data) throws -> [Algorithm] {
        let root = try JSONSerialization.jsonObject(with: data)
        let items: [Any]
        if let array = root as? [Any] {
            items = array
        } else if let object = root as? [String: Any], let array = object["data"] as? [Any] {
            items = array
        } else {
            throw MVError.api("Catálogo ilegible")
        }
        return items.compactMap(parseAlgorithm)
    }

    private static func parseAlgorithm(_ any: Any) -> Algorithm? {
        let object = JSONBlob.dictionary(any)
        guard let renderID = JSONBlob.int(object["render_id"]),
              let name = JSONBlob.string(object["name"]), !name.isEmpty else { return nil }
        let fields = (object["algorithm_fields"] as? [Any] ?? []).compactMap { parseField($0) }
        var outputs: [FieldChoice] = []
        if let map = outputMap(object["outputs"]) {
            outputs = map.keys.sorted().map { key in
                FieldChoice(key: key, label: JSONBlob.string(map[key]) ?? key)
            }
        }
        return Algorithm(
            renderID: renderID,
            name: name,
            orientation: JSONBlob.int(object["orientation"]) ?? 0,
            widget: JSONBlob.string(object["audio_widget"]) ?? "single_upload",
            fields: fields,
            outputs: outputs
        )
    }

    private static func parseField(_ any: Any) -> AlgoField? {
        let object = JSONBlob.dictionary(any)
        guard let name = JSONBlob.string(object["name"]), name.hasPrefix("add_opt") else { return nil }
        let choices = parseChoices(object["options"])
        let rawDefault = JSONBlob.string(object["default_key"])
        let rules = (object["price_rules"] as? [Any] ?? []).compactMap { item -> PriceRule? in
            let rule = JSONBlob.dictionary(item)
            guard let optionKey = JSONBlob.string(rule["option_key"]), !optionKey.isEmpty else { return nil }
            return PriceRule(
                fieldName: name,
                optionKey: optionKey,
                mode: JSONBlob.string(rule["mode"]) ?? "",
                value: JSONBlob.double(rule["value"]) ?? 0
            )
        }
        return AlgoField(
            name: name,
            text: JSONBlob.string(object["text"]) ?? name,
            inputType: JSONBlob.string(object["input_type"]) ?? "select",
            choices: choices,
            defaultKey: match(rawDefault, choices: choices),
            priceRules: rules
        )
    }

    private static func outputMap(_ raw: Any?) -> [String: Any]? {
        if let map = raw as? [String: Any] { return map }
        guard let text = raw as? String, let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func parseChoices(_ raw: Any?) -> [FieldChoice] {
        if let text = raw as? String {
            guard let data = text.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
            let order = quotedKeys(text)
            let keys = order.isEmpty ? object.keys.sorted() : order
            return keys.compactMap { key in
                guard object[key] != nil else { return nil }
                return FieldChoice(key: key, label: JSONBlob.string(object[key]) ?? key)
            }
        }
        if let object = raw as? [String: Any] {
            return object.keys.sorted().map { key in
                FieldChoice(key: key, label: JSONBlob.string(object[key]) ?? key)
            }
        }
        return []
    }

    private static func quotedKeys(_ json: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\"((?:\\\\.|[^\"\\\\])*)\"\\s*:") else { return [] }
        let range = NSRange(json.startIndex..., in: json)
        return regex.matches(in: json, range: range).compactMap { match in
            guard let slice = Range(match.range(at: 1), in: json) else { return nil }
            return json[slice].replacingOccurrences(of: "\\\"", with: "\"")
        }
    }

    private static func match(_ raw: String?, choices: [FieldChoice]) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        if choices.contains(where: { $0.key == raw }) { return raw }
        if let number = Double(raw), let hit = choices.first(where: { Double($0.key) == number }) {
            return hit.key
        }
        return raw
    }
}

struct CuratedSpec {
    var key: String
    var title: String
    var role: String
    var renderID: Int?
    var options: [String: String]
    var fallback: Algorithm?
    var matches: (String) -> Bool
}

enum CuratedModels {
    static let specs: [CuratedSpec] = [
        spec("bs-roformer", "BS Roformer", "chain") { name in
            let text = name.lowercased()
            return text.contains("bs roformer") && text.contains("instrumental") && !text.contains(" sw") && !text.contains("polar")
        },
        spec("deeffect", "DeEffect vocals by gilliaan", "chain") { $0.lowercased().contains("deeffect") && $0.lowercased().contains("gilliaan") },
        spec(
            "dry-acapella",
            "Dry acapella (de-reverbed)",
            "chain",
            renderID: 22,
            options: ["add_opt1": "9", "add_opt2": "1"]
        ) { _ in false },
        spec(
            "phase-deux",
            "Instrumental phase correction by Deux",
            "chain",
            renderID: 48,
            options: ["add_opt1": "11", "add_opt2": "2"]
        ) { _ in false },
        spec(
            "phase",
            "Instrumental phase correction",
            "chain",
            renderID: 40,
            options: ["add_opt1": "142", "add_opt2": "2", "add_opt3": "0"]
        ) { _ in false },
        spec(
            "lead-backing",
            "Lead/backing vocals (two-stage)",
            "chain",
            renderID: 49,
            options: ["add_opt1": "8", "add_opt2": "1"]
        ) { _ in false },
        spec("karaoke", "MVSep Karaoke", "chain") { $0.lowercased().contains("karaoke") },
        spec("male-female", "MVSep Male/Female", "chain") { $0.lowercased().contains("male/female") || $0.lowercased().contains("male / female") },
        spec("medley", "Medley Vox", "chain") { $0.lowercased().contains("medley vox") },
        spec("stereoize", "Stereoize by gilliaan", "chain") { $0.lowercased().contains("stereoize") },
        spec("upmix", "Upmixing Music", "chain") { $0.lowercased().contains("upmixing") },
        spec("universr", "UniverSR", "chain") { $0.lowercased().contains("universr") },
        spec("clean-inverted", "Clean Inverted Vocals", "chain") { $0.lowercased().contains("clean inverted") },
        spec("aspiration", "Aspiration by Sucial", "chain") { $0.lowercased().contains("aspiration") },
        spec("phantom", "Phantom Centre", "chain") { name in
            let text = name.lowercased()
            return text.contains("phantom centre") || text.contains("phantom center")
        },
        spec("mega53", "Mega 53-stem", "chain") { name in
            let text = name.lowercased()
            return text.contains("53-stem") || text.contains("53 stem")
        },
        spec(
            "muscriptor",
            "Muscriptor",
            "chain",
            renderID: 141,
            options: ["add_opt1": "0", "add_opt2": "1.0"],
            fallback: Algorithm.muscriptor
        ) { $0.lowercased().contains("muscriptor") },
        spec("apollo", "Apollo Enhancers", "chain") { $0.lowercased().contains("apollo") },
        spec("noreverb", "Reverb Removal", "chain") { name in
            let text = name.lowercased()
            return text.contains("noreverb") || text.contains("reverb removal")
        },
        spec("denoise", "DeNoise", "chain") { $0.lowercased().contains("denoise") },
        spec("audiosr", "AudioSR", "chain") { $0.lowercased().contains("audiosr") },
        spec("flashsr", "FlashSR", "chain") { $0.lowercased().contains("flashsr") },
        spec("matchering", "Matchering", "tool") { $0.lowercased().contains("matchering") },
        spec("heartmula", "HeartMuLa", "tool") { $0.lowercased().contains("heartmula") },
    ]

    static func spec(
        _ key: String,
        _ title: String,
        _ role: String,
        renderID: Int? = nil,
        options: [String: String] = [:],
        fallback: Algorithm? = nil,
        _ matches: @escaping (String) -> Bool
    ) -> CuratedSpec {
        CuratedSpec(key: key, title: title, role: role, renderID: renderID, options: options, fallback: fallback, matches: matches)
    }

    static func options(for key: String) -> [String: String] {
        spec(for: key)?.options ?? [:]
    }

    static func spec(for key: String) -> CuratedSpec? {
        specs.first { $0.key == key }
    }
}

struct CatalogSnapshot: Equatable {
    var algorithms: [Algorithm]
    var resolved: [String: Algorithm]
    var missing: [String]

    static var empty: CatalogSnapshot {
        CatalogSnapshot(algorithms: [], resolved: [:], missing: CuratedModels.specs.map(\.title))
    }

    static func build(from algorithms: [Algorithm]) -> CatalogSnapshot {
        var resolved: [String: Algorithm] = [:]
        var missing: [String] = []
        for spec in CuratedModels.specs {
            if let renderID = spec.renderID, let exact = algorithms.first(where: { $0.renderID == renderID }) {
                resolved[spec.key] = exact
            } else if let best = algorithms.filter({ spec.matches($0.name) }).min(by: { $0.name.count < $1.name.count }) {
                resolved[spec.key] = best
            } else if let fallback = spec.fallback {
                resolved[spec.key] = fallback
            } else {
                missing.append(spec.title)
            }
        }
        return CatalogSnapshot(algorithms: algorithms, resolved: resolved, missing: missing)
    }

    func algorithm(for key: String) -> Algorithm? { resolved[key] }

    var chainModels: [CuratedSpec] {
        CuratedModels.specs.filter { $0.role == "chain" }
    }
}
