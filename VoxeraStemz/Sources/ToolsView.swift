import SwiftUI

struct ToolsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var tool = 0
    @State private var modelKey = "bs-roformer"
    @State private var options: [String: String] = [:]
    @State private var format = 1
    @State private var usePremium = false
    @State private var overridden = false
    @State private var audio: PickedAudio?
    @State private var reference: PickedAudio?
    @State private var ready = false

    var body: some View {
        TabScaffold {
            Picker("Herramienta", selection: $tool) {
                Text("Modelo").tag(0)
                Text("Matchering").tag(1)
                Text("HeartMuLa").tag(2)
            }
            .pickerStyle(.segmented)

            if tool == 0 {
                modelTool
            } else if tool == 1 {
                matcheringTool
            } else {
                heartTool
            }
        }
        .onAppear {
            guard !ready else { return }
            format = app.settings.defaultOutputFormat
            load(modelKey)
            ready = true
        }
        .onChange(of: modelKey, initial: false) { _, key in
            if tool == 0 { load(key) }
        }
        .onChange(of: tool, initial: false) { _, value in
            if value == 0 { load(modelKey) }
            if value == 1 { load("matchering") }
            if value == 2 { load("heartmula") }
        }
    }

    private var modelTool: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Modelo", selection: $modelKey) {
                ForEach(app.catalog.chainModels.filter { app.catalog.algorithm(for: $0.key) != nil }, id: \.key) { spec in
                    Text(spec.title).tag(spec.key)
                }
            }
            .pickerStyle(.menu)
            ModelFields(
                curatedKey: modelKey,
                algorithm: app.catalog.algorithm(for: modelKey),
                options: options,
                set: { name, value in options[name] = value }
            )
            FormatMenu(format: format, usePremium: formatPremium(modelKey)) { format = $0 }
            premium(modelKey)
            AudioPickButton(title: "Audio", picked: audio?.songName) { url in
                audio = app.copyAudio(url)
            }
            PrimaryButton(title: "Correr", enabled: audio != nil && !app.hasActiveJob && !app.startGate) {
                run(key: modelKey, name: CuratedModels.spec(for: modelKey)?.title ?? "Modelo", audio: audio, reference: nil)
            }
        }
    }

    private var matcheringTool: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Matchering")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            FormatMenu(format: format, usePremium: formatPremium("matchering")) { format = $0 }
            premium("matchering")
            AudioPickButton(title: "Audio a igualar", picked: audio?.songName) { url in
                audio = app.copyAudio(url)
            }
            AudioPickButton(title: "Referencia", picked: reference?.songName) { url in
                reference = app.copyAudio(url)
            }
            PrimaryButton(
                title: "Correr",
                enabled: audio != nil && reference != nil && !app.hasActiveJob && !app.startGate
            ) {
                run(key: "matchering", name: "Matchering", audio: audio, reference: reference)
            }
        }
    }

    private var heartTool: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("HeartMuLa")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            ModelFields(
                curatedKey: "heartmula",
                algorithm: app.catalog.algorithm(for: "heartmula"),
                options: options,
                set: { name, value in options[name] = value }
            )
            FormatMenu(format: format, usePremium: formatPremium("heartmula")) { format = $0 }
            premium("heartmula")
            PrimaryButton(title: "Correr", enabled: !app.hasActiveJob && !app.startGate) {
                run(key: "heartmula", name: "HeartMuLa", audio: nil, reference: nil)
            }
        }
    }

    private func premium(_ key: String) -> some View {
        PremiumSwitch(
            isOn: overridden ? usePremium : rulePaid(key),
            overridden: overridden,
            globalOn: app.settings.protectFreeModels,
            onChange: { value in
                usePremium = value
                overridden = true
            },
            onReset: { overridden = false }
        )
    }

    private func run(key: String, name: String, audio: PickedAudio?, reference: PickedAudio?) {
        let paid = overridden ? usePremium : rulePaid(key)
        let step = ChainStep(
            id: UUID(),
            enabled: true,
            curatedKey: key,
            options: options,
            outputFormat: format,
            continueStem: "",
            usePremium: paid,
            usePremiumOverridden: overridden
        )
        app.requestTool(name: name, steps: [step], audio: audio, reference: reference)
    }

    private func load(_ key: String) {
        let algorithm = app.catalog.algorithm(for: key)
        options = algorithm?.defaultOptions() ?? [:]
        for (name, value) in CuratedModels.options(for: key) {
            options[name] = value
        }
        if key == "aspiration" { options["add_opt1"] = "0" }
        overridden = false
        usePremium = rulePaid(key)
    }

    private func rulePaid(_ key: String) -> Bool {
        guard let algorithm = app.catalog.algorithm(for: key) else { return false }
        return PremiumPolicy.decide(
            orientation: algorithm.orientation,
            sepType: algorithm.renderID,
            options: options,
            rules: algorithm.rules
        ).paid
    }

    private func formatPremium(_ key: String) -> Bool {
        let paid = overridden ? usePremium : rulePaid(key)
        if app.settings.protectFreeModels { return paid }
        return app.user?.premiumEnabled ?? false
    }
}
