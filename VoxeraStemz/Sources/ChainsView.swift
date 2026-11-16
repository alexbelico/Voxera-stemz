import SwiftUI

private let favoriteKeys = [
    "bs-roformer", "deeffect", "dry-acapella", "phase-deux", "phase",
    "lead-backing", "karaoke", "aspiration", "muscriptor",
]

struct ChainsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var adding = false

    var body: some View {
        TabScaffold {
            switch app.chainRoute {
            case .list:
                chainList
            case let .edit(id):
                ChainEditor(presetID: id, adding: $adding)
            case let .run(id):
                ChainRun(presetID: id)
            case let .results(id):
                ChainResults(jobID: id)
            }
        }
        .sheet(isPresented: $adding) {
            AddStepSheet()
        }
    }

    private var chainList: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Elige una cadena. Editar arma los pasos. Correr elige la canción.")
                .font(.footnote)
                .foregroundStyle(Theme.silver)
            ForEach(app.presets) { preset in
                chainCard(preset)
            }
            PrimaryButton(title: "+ Nueva cadena") { app.newPreset() }
            Button("Restaurar ejemplos") { app.restoreExamples() }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.blue)
        }
    }

    private func chainCard(_ preset: ChainPreset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(preset.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text(abbreviationLine(preset.steps))
                .font(.subheadline)
                .foregroundStyle(Theme.silver)
            if let job = latestJob(preset) {
                Button(StatusText.spanish(job.state)) {
                    app.chainRoute = .results(job.id)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.blue)
            }
            HStack(spacing: 16) {
                Button("Editar") {
                    app.selectPreset(preset.id)
                    app.chainRoute = .edit(preset.id)
                }
                Button("Correr") {
                    app.selectPreset(preset.id)
                    app.chainRoute = .run(preset.id)
                }
            }
            .font(.headline)
            .foregroundStyle(Theme.blue)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
    }

    private func latestJob(_ preset: ChainPreset) -> ChainJob? {
        app.jobs.first { $0.kind == "chain" && $0.presetName == preset.name }
    }

    private func abbreviationLine(_ steps: [ChainStep]) -> String {
        let parts = steps.filter(\.enabled).map {
            AbbreviationDefaults.resolve(curatedKey: $0.curatedKey, options: $0.options, custom: app.settings.abbreviations)
        }
        return parts.isEmpty ? "Sin pasos activos" : parts.joined(separator: " → ")
    }
}

struct ChainEditor: View {
    @EnvironmentObject private var app: AppModel
    var presetID: UUID
    @Binding var adding: Bool
    @State private var draft = ""
    @State private var ordering = false
    @State private var editor: StepSheet?

    private var preset: ChainPreset? { app.presets.first { $0.id == presetID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            back("Cadenas")
            Text("Editar cadena")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text("Arma el orden. El audio se elige después, en Correr.")
                .font(.footnote)
                .foregroundStyle(Theme.silver)
            TextField("Nombre", text: $draft)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .padding(12)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Toggle("Ordenar o borrar", isOn: $ordering)
                .tint(Theme.blue)
            if let preset {
                ForEach(Array(preset.steps.enumerated()), id: \.element.id) { index, step in
                    stepRow(step, index: index, count: preset.steps.count)
                }
            }
            Button("Agregar paso") { adding = true }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            PrimaryButton(title: "Guardar") {
                app.savePreset(name: draft)
                app.chainRoute = .list
            }
            Button("Borrar cadena") {
                app.selectPreset(presetID)
                app.deletePreset()
                app.chainRoute = .list
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.danger)
        }
        .onAppear {
            app.selectPreset(presetID)
            draft = preset?.name ?? ""
        }
        .sheet(item: $editor) { item in
            StepEditor(stepID: item.id)
        }
    }

    private func stepRow(_ step: ChainStep, index: Int, count: Int) -> some View {
        let title = CuratedModels.spec(for: step.curatedKey)?.title ?? step.curatedKey
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                if !ordering { editor = StepSheet(id: step.id) }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(index + 1). \(title)")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        CostBadge(premium: app.effectivePremium(step))
                    }
                    Text(variantLabel(step))
                        .font(.footnote)
                        .foregroundStyle(Theme.silver)
                        .multilineTextAlignment(.leading)
                    Text(OutputFormat(rawValue: step.outputFormat)?.title ?? "WAV 16")
                        .font(.footnote)
                        .foregroundStyle(Theme.silver)
                    if !step.enabled {
                        Text("Desactivado")
                            .font(.footnote)
                            .foregroundStyle(Theme.silver)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            if ordering {
                HStack {
                    Button("Subir") { app.moveStep(step.id, up: true) }.disabled(index == 0)
                    Button("Bajar") { app.moveStep(step.id, up: false) }.disabled(index == count - 1)
                    Button("Quitar") { app.deleteStep(step.id) }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.blue)
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(step.enabled ? 1 : 0.55)
    }

    private func variantLabel(_ step: ChainStep) -> String {
        guard let algorithm = app.catalog.algorithm(for: step.curatedKey),
              let field = algorithm.fields.first(where: { $0.name == "add_opt1" }) else { return "Variante automática" }
        let key = step.options["add_opt1"] ?? field.defaultKey ?? ""
        let label = field.choices.first { $0.key == key }?.label ?? "Variante automática"
        if let range = label.range(of: " (SDR") { return String(label[..<range.lowerBound]) }
        return label
    }

    private func back(_ title: String) -> some View {
        Button(title) { app.chainRoute = .list }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.blue)
    }
}

struct ChainRun: View {
    @EnvironmentObject private var app: AppModel
    var presetID: UUID

    private var preset: ChainPreset? { app.presets.first { $0.id == presetID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button("Cadenas") { app.chainRoute = .list }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.blue)
            Text("Correr")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text("El siguiente paso sube el archivo guardado, con el nombre de la canción.")
                .font(.footnote)
                .foregroundStyle(Theme.silver)
            if let preset {
                Text(preset.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(summary(preset))
                    .font(.subheadline)
                    .foregroundStyle(Theme.silver)
                Toggle("Seguir sola con el stem elegido", isOn: Binding(
                    get: { app.autoContinue },
                    set: { app.setAuto($0) }
                ))
                .tint(Theme.blue)
            }
            AudioPickButton(title: "Canción", picked: app.input?.songName) { url in
                app.importAudio(url)
            }
            PrimaryButton(title: "Correr cadena", enabled: app.input != nil && !app.hasActiveJob && !app.startGate) {
                app.selectPreset(presetID)
                app.requestChain()
            }
        }
        .onAppear { app.selectPreset(presetID) }
    }

    private func summary(_ preset: ChainPreset) -> String {
        let parts = preset.steps.filter(\.enabled).map {
            AbbreviationDefaults.resolve(curatedKey: $0.curatedKey, options: $0.options, custom: app.settings.abbreviations)
        }
        return parts.isEmpty ? "Esta cadena no tiene pasos activos." : parts.joined(separator: " → ")
    }
}

struct ChainResults: View {
    @EnvironmentObject private var app: AppModel
    var jobID: UUID

    private var job: ChainJob? { app.jobs.first { $0.id == jobID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button("Cadenas") { app.chainRoute = .list }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.blue)
            Text("Resultados")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text("Los pasos ya hechos no se vuelven a cobrar.")
                .font(.footnote)
                .foregroundStyle(Theme.silver)
            if let job {
                Text(job.presetName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(job.songName)
                    .font(.subheadline)
                    .foregroundStyle(Theme.silver)
                ForEach(Array(job.steps.enumerated()), id: \.element.id) { index, step in
                    stepBlock(job, step: step, index: index)
                }
            } else {
                Text("Todavía no hay un resultado de esta cadena.")
                    .foregroundStyle(Theme.silver)
            }
        }
    }

    private func stepBlock(_ job: ChainJob, step: JobStep, index: Int) -> some View {
        let current = index == job.currentIndex
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(marker(job, step: step, index: index))
                    .font(.headline)
                    .foregroundStyle(markerColor(job, step: step, index: index))
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(index + 1). \(step.title)")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(statusLine(job, step: step, current: current))
                        .font(.footnote)
                        .foregroundStyle(Theme.silver)
                }
            }
            if let error = step.error, !error.isEmpty, step.phase == "failed" || step.phase == "uncertain" {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
            }
            if current, step.phase == "failed", RetryPolicy.canRetry(state: job.state, phase: step.phase, hash: step.hash) {
                Button("Reintentar este paso") { app.retryFailedStep(job.id) }
                    .font(.headline)
                    .foregroundStyle(Theme.blue)
            }
            ForEach(step.files) { stem in
                StemRow(
                    stem: stem,
                    chooseTitle: continueTitle(job, step: step, index: index, stem: stem)
                ) {
                    app.chooseStem(jobID: job.id, stemID: stem.id)
                }
            }
            if current && job.state == "awaiting" && !job.autoContinue {
                Button("Quedarme con esto") { app.stopAfterCurrent(jobID: job.id) }
                    .font(.footnote)
                    .foregroundStyle(Theme.silver)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func continueTitle(_ job: ChainJob, step: JobStep, index: Int, stem: CachedStem) -> String? {
        guard job.state == "awaiting", index == job.currentIndex, !job.autoContinue else { return nil }
        return "Continuar con \(StemMatch.displayStem(stem.typeLabel))"
    }

    private func marker(_ job: ChainJob, step: JobStep, index: Int) -> String {
        if step.phase == "done" || index < job.currentIndex { return "✓" }
        if index == job.currentIndex && (job.state == "running" || step.phase == "creating" || step.phase == "polling") { return "…" }
        if step.phase == "failed" || step.phase == "uncertain" { return "!" }
        return "·"
    }

    private func markerColor(_ job: ChainJob, step: JobStep, index: Int) -> Color {
        if step.phase == "done" || index < job.currentIndex { return Theme.ok }
        if step.phase == "failed" || step.phase == "uncertain" { return Theme.danger }
        return Theme.blue
    }

    private func statusLine(_ job: ChainJob, step: JobStep, current: Bool) -> String {
        if step.phase == "done" { return "Listo" }
        if step.phase == "failed" { return "Falló" }
        if step.phase == "uncertain" { return "Sin reintento" }
        if step.phase == "awaitingChoice" { return "Elige con qué stem seguir" }
        if current && job.state == "running" { return StatusText.spanish(job.remoteStatus ?? step.phase) }
        return "En espera"
    }
}

struct AddStepSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            BrandHeader()
            ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Agregar paso")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Favoritos")
                    .font(.headline)
                    .foregroundStyle(Theme.silver)
                ForEach(favorites, id: \.key) { spec in
                    addButton(spec)
                }
                Text("Todos")
                    .font(.headline)
                    .foregroundStyle(Theme.silver)
                    .padding(.top, 8)
                ForEach(others, id: \.key) { spec in
                    addButton(spec)
                }
            }
            .padding(20)
            }
            Text("CREATED BY ALEXMOET")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.silver.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private var favorites: [CuratedSpec] {
        favoriteKeys.compactMap { key in app.catalog.chainModels.first { $0.key == key } }
    }

    private var others: [CuratedSpec] {
        app.catalog.chainModels.filter { !favoriteKeys.contains($0.key) }
    }

    private func addButton(_ spec: CuratedSpec) -> some View {
        let available = app.catalog.algorithm(for: spec.key) != nil
        return Button(available ? spec.title : "\(spec.title) (no está)") {
            app.addStep(key: spec.key)
            dismiss()
        }
        .font(.headline)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct StepSheet: Identifiable {
    var id: UUID
}

struct StepEditor: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    var stepID: UUID

    private var step: ChainStep? {
        app.selectedPreset?.steps.first { $0.id == stepID }
    }

    var body: some View {
        VStack(spacing: 0) {
            BrandHeader()
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let step {
                    Text(CuratedModels.spec(for: step.curatedKey)?.title ?? step.curatedKey)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Elige la variante, el formato y qué stem sigue.")
                        .font(.footnote)
                        .foregroundStyle(Theme.silver)
                    Toggle("Paso activo", isOn: Binding(
                        get: { step.enabled },
                        set: { app.setEnabled(stepID: step.id, enabled: $0) }
                    ))
                    .tint(Theme.blue)
                    ModelFields(
                        curatedKey: step.curatedKey,
                        algorithm: app.catalog.algorithm(for: step.curatedKey),
                        options: step.options
                    ) { name, value in
                        app.setOption(stepID: step.id, name: name, value: value)
                    }
                    FormatMenu(format: step.outputFormat, usePremium: formatPremium(step)) { format in
                        app.setFormat(stepID: step.id, format: format)
                    }
                    Picker("Stem que sigue", selection: Binding(
                        get: { step.continueStem },
                        set: { app.setContinue(stepID: step.id, stem: $0) }
                    )) {
                        Text("Acapella").tag("vocals")
                        Text("Beat").tag("other")
                        Text("Dry").tag("dry")
                        Text("No seguir").tag("")
                    }
                    .pickerStyle(.menu)
                    PremiumSwitch(
                        isOn: app.effectivePremium(step),
                        overridden: step.usePremiumOverridden,
                        globalOn: app.settings.protectFreeModels,
                        onChange: { app.setStepPremium(stepID: step.id, enabled: $0) },
                        onReset: { app.clearStepPremiumOverride(stepID: step.id) }
                    )
                }
                Button("Cerrar") { dismiss() }
                    .foregroundStyle(Theme.blue)
            }
            .padding(20)
            }
            Text("CREATED BY ALEXMOET")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.silver.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private func formatPremium(_ step: ChainStep) -> Bool {
        if app.settings.protectFreeModels { return app.effectivePremium(step) }
        return app.user?.premiumEnabled ?? false
    }
}
