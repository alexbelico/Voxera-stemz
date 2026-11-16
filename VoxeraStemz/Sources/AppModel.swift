import SwiftUI
import UIKit
import UserNotifications

struct PickedAudio: Equatable {
    var songName: String
    var relativePath: String
    var sha256: String
}

struct PendingRun {
    var kind: String
    var presetName: String
    var songName: String
    var inputRelativePath: String
    var inputSHA256: String
    var autoContinue: Bool
    var steps: [JobStep]
    var referenceRelativePath: String?
    var skipNote: String
}

struct DuplicatePrompt: Identifiable {
    var id = UUID()
    var message: String
    var jobID: UUID
    var resumeCount: Int?
    var pending: PendingRun
}

struct ExportRequest: Identifiable {
    var id = UUID()
    var url: URL
    var name: String
}

struct SharePayload: Identifiable {
    var id = UUID()
    var url: URL
}

enum ChainRoute: Equatable {
    case list
    case edit(UUID)
    case run(UUID)
    case results(UUID)
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var tab = 0
    @Published var settings = AppSettings.standard
    @Published var tokenDraft = ""
    @Published var tokenStatus = "Sin comprobar"
    @Published var user: MVUser?
    @Published var catalog = CatalogSnapshot.empty
    @Published var catalogMessage = ""
    @Published var presets: [ChainPreset] = []
    @Published var selectedPresetID: UUID?
    @Published var jobs: [ChainJob] = []
    @Published var input: PickedAudio?
    @Published var autoContinue = false
    @Published var startGate = false
    @Published var banner: String?
    @Published var duplicatePrompt: DuplicatePrompt?
    @Published var exportRequest: ExportRequest?
    @Published var sharePayload: SharePayload?
    @Published var editingStepID: UUID?
    @Published var focusJobID: UUID?
    @Published var storageBytes: Int64 = 0
    @Published var showSavePreset = false
    @Published var chainRoute: ChainRoute = .list

    let store: DiskStore
    let player = PlayerModel()
    private let client = MVSEPClient()
    private let notifications = NotificationDelegate()
    private var backgroundID: UIBackgroundTaskIdentifier = .invalid
    private var submitting: Set<String> = []
    private var executing: Set<UUID> = []

    var hasActiveJob: Bool { jobs.contains(where: \.isActive) }

    var selectedPreset: ChainPreset? {
        presets.first { $0.id == selectedPresetID } ?? presets.first
    }

    var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Versión \(short) (\(build))"
    }

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoxeraStemz", isDirectory: true)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Canciones", isDirectory: true)
        store = DiskStore(root: support, documents: documents)
        UNUserNotificationCenter.current().delegate = notifications
        settings = store.loadSettings()
        presets = store.loadPresets()
        selectedPresetID = presets.first?.id
        autoContinue = presets.first?.autoContinue ?? settings.defaultAutoContinue
        jobs = store.loadJobs()
        tokenDraft = KeychainStore.load() ?? ""
        if store.loadCatalog() == nil, let bundled = Bundle.main.url(forResource: "algorithms-seed", withExtension: "json"),
           let data = try? Data(contentsOf: bundled) {
            store.saveCatalog(data)
        }
        if let data = store.loadCatalog(), let algorithms = try? AlgorithmParser.parse(data: data) {
            catalog = CatalogSnapshot.build(from: algorithms)
        }
        storageBytes = store.storageBytes()
        recoverInterruptedJobs()
    }

    func selectPreset(_ id: UUID) {
        selectedPresetID = id
        autoContinue = presets.first { $0.id == id }?.autoContinue ?? settings.defaultAutoContinue
    }

    func setAuto(_ value: Bool) {
        autoContinue = value
        updateSelected { $0.autoContinue = value }
    }

    private func continueStem(for key: String) -> String {
        switch key {
        case "phase", "phase-deux": return "other"
        case "dry-acapella": return "dry"
        default: return "vocals"
        }
    }

    func addStep(key: String) {
        let algorithm = catalog.algorithm(for: key)
        var options = algorithm?.defaultOptions() ?? [:]
        for (name, value) in CuratedModels.options(for: key) {
            options[name] = value
        }
        if key == "aspiration" { options["add_opt1"] = "0" }
        let paid = rulePaid(key: key, options: options)
        let step = ChainStep(
            id: UUID(),
            enabled: algorithm != nil,
            curatedKey: key,
            options: options,
            outputFormat: settings.defaultOutputFormat,
            continueStem: continueStem(for: key),
            usePremium: paid,
            usePremiumOverridden: false
        )
        updateSelected { $0.steps.append(step) }
    }

    func deleteStep(_ id: UUID) { updateSelected { $0.steps.removeAll { $0.id == id } } }

    func moveStep(_ id: UUID, up: Bool) {
        updateSelected { preset in
            guard let index = preset.steps.firstIndex(where: { $0.id == id }) else { return }
            let target = up ? index - 1 : index + 1
            guard preset.steps.indices.contains(target) else { return }
            preset.steps.swapAt(index, target)
        }
    }

    func toggleEnabled(_ id: UUID) {
        updateSelected { preset in
            guard let index = preset.steps.firstIndex(where: { $0.id == id }) else { return }
            preset.steps[index].enabled.toggle()
        }
    }

    func setEnabled(stepID: UUID, enabled: Bool) {
        updateSelected { preset in
            guard let index = preset.steps.firstIndex(where: { $0.id == stepID }) else { return }
            preset.steps[index].enabled = enabled
        }
    }

    func setOption(stepID: UUID, name: String, value: String) {
        updateSelected { preset in
            guard let index = preset.steps.firstIndex(where: { $0.id == stepID }) else { return }
            preset.steps[index].options[name] = value
        }
    }

    func setFormat(stepID: UUID, format: Int) {
        updateSelected { preset in
            guard let index = preset.steps.firstIndex(where: { $0.id == stepID }) else { return }
            preset.steps[index].outputFormat = format
        }
    }

    func setContinue(stepID: UUID, stem: String) {
        updateSelected { preset in
            guard let index = preset.steps.firstIndex(where: { $0.id == stepID }) else { return }
            preset.steps[index].continueStem = stem
        }
    }

    func setStepPremium(stepID: UUID, enabled: Bool) {
        updateSelected { preset in
            guard let index = preset.steps.firstIndex(where: { $0.id == stepID }) else { return }
            preset.steps[index].usePremium = enabled
            preset.steps[index].usePremiumOverridden = true
        }
    }

    func clearStepPremiumOverride(stepID: UUID) {
        updateSelected { preset in
            guard let index = preset.steps.firstIndex(where: { $0.id == stepID }) else { return }
            preset.steps[index].usePremiumOverridden = false
            preset.steps[index].usePremium = rulePaid(key: preset.steps[index].curatedKey, options: preset.steps[index].options)
        }
    }

    func effectivePremium(_ step: ChainStep) -> Bool {
        PremiumPolicy.effectiveUsePremium(
            stored: step.usePremium,
            overridden: step.usePremiumOverridden,
            rulePaid: rulePaid(key: step.curatedKey, options: step.options)
        )
    }

    func newPreset() {
        let preset = ChainPreset(
            id: UUID(),
            name: "Nueva cadena",
            autoContinue: settings.defaultAutoContinue,
            builtIn: false,
            steps: []
        )
        presets.append(preset)
        selectedPresetID = preset.id
        autoContinue = preset.autoContinue
        store.savePresets(presets)
        chainRoute = .edit(preset.id)
    }

    func savePreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateSelected {
            $0.name = trimmed
            $0.builtIn = false
        }
        showSavePreset = false
        banner = "Cadena guardada."
    }

    func deletePreset() {
        guard let id = selectedPreset?.id else { return }
        presets.removeAll { $0.id == id }
        selectedPresetID = presets.first?.id
        store.savePresets(presets)
    }

    func restoreExamples() {
        presets = BuiltInPresets.examples()
        selectedPresetID = presets.first?.id
        autoContinue = false
        store.savePresets(presets)
    }

    func importAudio(_ url: URL) {
        if let picked = copyAudio(url) {
            input = picked
            banner = nil
        }
    }

    func copyAudio(_ url: URL) -> PickedAudio? {
        guard let picked = copy(url: url, prefix: "entrada") else {
            banner = "No se pudo copiar el audio."
            return nil
        }
        return picked
    }

    func useStemAsInput(_ stem: CachedStem, song: String) {
        let hash = stem.sha256.isEmpty ? ((try? FileHash.sha256(of: store.url(stem.relativePath))) ?? "") : stem.sha256
        input = PickedAudio(songName: song, relativePath: stem.relativePath, sha256: hash)
        tab = 0
        banner = nil
        if let presetID = selectedPreset?.id {
            chainRoute = .run(presetID)
        }
    }

    func requestChain() {
        guard StartGate.allow(locked: startGate, busy: hasActiveJob) else { return }
        guard let preset = selectedPreset else {
            banner = "Elige una cadena."
            return
        }
        guard let input else {
            banner = "Elige un audio."
            return
        }
        guard KeychainStore.load()?.isEmpty == false else {
            banner = "Agrega el token de MVSEP en Ajustes."
            tab = 4
            return
        }
        startGate = true
        let steps = preset.steps
        let name = preset.name
        let auto = autoContinue
        Task { await prepare(kind: "chain", presetName: name, song: input.songName, relative: input.relativePath, hash: input.sha256, steps: steps, auto: auto, reference: nil) }
    }

    func requestTool(name: String, steps: [ChainStep], audio: PickedAudio?, reference: PickedAudio?) {
        guard StartGate.allow(locked: startGate, busy: hasActiveJob) else { return }
        guard KeychainStore.load()?.isEmpty == false else {
            banner = "Agrega el token de MVSEP en Ajustes."
            tab = 4
            return
        }
        let hash: String
        let song: String
        let relative: String
        if let audio {
            hash = audio.sha256
            song = audio.songName
            relative = audio.relativePath
        } else {
            let lyrics = steps.first?.options["add_opt1"] ?? ""
            hash = FileHash.sha256(of: Data(lyrics.utf8))
            song = "HeartMuLa"
            relative = ""
        }
        startGate = true
        Task {
            await prepare(
                kind: "tool",
                presetName: name,
                song: song,
                relative: relative,
                hash: hash,
                steps: steps,
                auto: false,
                reference: reference
            )
        }
    }

    func dismissDuplicate() {
        guard duplicatePrompt != nil else { return }
        duplicatePrompt = nil
        startGate = false
    }

    func openPrevious() {
        guard let prompt = duplicatePrompt else { return }
        focusJobID = prompt.jobID
        duplicatePrompt = nil
        startGate = false
        tab = 2
    }

    func runAnyway() {
        guard let pending = duplicatePrompt?.pending else { return }
        duplicatePrompt = nil
        Task {
            await startJob(pending, startIndex: 0)
            startGate = false
        }
    }

    func resumePrefix() {
        guard let prompt = duplicatePrompt, let count = prompt.resumeCount,
              let previous = jobs.first(where: { $0.id == prompt.jobID }) else {
            dismissDuplicate()
            return
        }
        duplicatePrompt = nil
        var pending = prompt.pending
        let reusable = previous.steps.filter { step in
            step.phase == "done" || (step.phase == "awaitingChoice" && !step.files.isEmpty)
        }
        let take = min(count, pending.steps.count, reusable.count)
        for index in 0..<take {
            var copy = reusable[index]
            copy.id = UUID()
            pending.steps[index] = copy
        }
        let start = take > 0 && pending.steps[take - 1].phase == "awaitingChoice" ? take - 1 : take
        Task {
            await startJob(pending, startIndex: start)
            startGate = false
        }
    }

    func chooseStem(jobID: UUID, stemID: UUID) {
        guard var job = jobs.first(where: { $0.id == jobID }), job.state == "awaiting" else { return }
        let index = job.currentIndex
        guard job.steps.indices.contains(index) else { return }
        guard let stem = job.steps[index].files.first(where: { $0.id == stemID }) else { return }
        job.steps[index].chosenStemID = stemID
        job.steps[index].continueStem = StemMatch.canonical(planned: job.steps[index].continueStem, typeLabel: stem.typeLabel)
        job.steps[index].phase = "done"
        job.currentIndex += 1
        if job.currentIndex >= job.steps.count {
            job.state = "done"
            job.message = "Cadena lista"
            replace(job)
            notify(title: "Cadena lista", body: job.songName)
            Task { await restorePremium(job.id) }
            endBackground()
            return
        }
        job.state = "running"
        replace(job)
        Task { await execute(job.id) }
    }

    func stopAfterCurrent(jobID: UUID) {
        mutate(jobID) { job in
            guard job.steps.indices.contains(job.currentIndex) else { return }
            job.steps[job.currentIndex].phase = "done"
            job.state = "done"
            job.message = "Te quedaste con este resultado."
        }
        notify(title: "Resultado listo", body: jobs.first { $0.id == jobID }?.songName ?? "")
        Task { await restorePremium(jobID) }
        endBackground()
    }

    func cancelJob(_ id: UUID) {
        guard var job = jobs.first(where: { $0.id == id }) else { return }
        let hash = job.steps.indices.contains(job.currentIndex) ? job.steps[job.currentIndex].hash : nil
        job.state = "cancelled"
        job.message = "Cancelado"
        replace(job)
        Task {
            if let hash, let token = KeychainStore.load() {
                try? await client.cancel(hash: hash, token: token)
            }
            await restorePremium(id)
            endBackground()
        }
    }

    func play(_ stem: CachedStem) {
        let url = store.url(stem.relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            banner = "El archivo local no está. No se vuelve a pedir el trabajo."
            return
        }
        player.toggle(url: url)
    }

    func beginExport(_ stem: CachedStem) {
        let url = store.url(stem.relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            banner = "El archivo local no está. No se vuelve a pedir el trabajo."
            return
        }
        exportRequest = ExportRequest(url: url, name: url.lastPathComponent)
    }

    func export(url: URL, sampleRate: Int?) {
        exportRequest = nil
        if let sampleRate {
            do {
                let wav = try AudioResampler.resample(source: url, sampleRate: Double(sampleRate))
                sharePayload = SharePayload(url: wav)
            } catch {
                banner = "No se pudo cambiar la frecuencia. Se comparte el archivo tal como está."
                sharePayload = SharePayload(url: url)
            }
        } else {
            sharePayload = SharePayload(url: url)
        }
    }

    func testKey() {
        let token = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            tokenStatus = "Pega el token primero."
            return
        }
        guard KeychainStore.save(token) else {
            tokenStatus = "No se pudo guardar en el llavero."
            return
        }
        Task { await refreshUser(status: true) }
    }

    func refreshUser(status: Bool = false) async {
        guard let token = KeychainStore.load(), !token.isEmpty else {
            tokenStatus = "Sin token."
            return
        }
        do {
            let loaded = try await client.user(token: token)
            user = loaded
            let minutes = String(format: loaded.premiumMinutes.rounded() == loaded.premiumMinutes ? "%.0f" : "%.1f", loaded.premiumMinutes)
            if status {
                tokenStatus = "Clave válida. \(minutes) créditos. Premium \(loaded.premiumEnabled ? "activo" : "apagado")."
            }
        } catch {
            user = nil
            tokenStatus = "Clave rechazada."
        }
    }

    func setAccountPremium(_ enabled: Bool) {
        guard !hasActiveJob else {
            banner = "Hay un trabajo en curso."
            return
        }
        guard let token = KeychainStore.load(), !token.isEmpty else {
            banner = "Agrega el token primero."
            return
        }
        Task {
            do {
                try await client.setPremium(enabled: enabled, token: token)
                user = try await client.user(token: token)
            } catch {
                banner = "No se pudo cambiar premium."
                user = try? await client.user(token: token)
            }
        }
    }

    func refreshCatalog() {
        Task {
            do {
                let data = try await client.algorithms()
                let algorithms = try AlgorithmParser.parse(data: data)
                store.saveCatalog(data)
                catalog = CatalogSnapshot.build(from: algorithms)
                let missing = catalog.missing.isEmpty ? "ninguno" : catalog.missing.joined(separator: ", ")
                catalogMessage = "Catálogo actualizado. \(catalog.resolved.count) modelos. Faltan: \(missing)."
            } catch {
                catalogMessage = "No se pudo actualizar. Se usa la copia guardada."
            }
        }
    }

    func updateSettings(_ body: (inout AppSettings) -> Void) {
        body(&settings)
        store.saveSettings(settings)
    }

    func setNotifications(_ enabled: Bool) {
        settings.notificationsEnabled = enabled
        store.saveSettings(settings)
        if enabled {
            Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        }
    }

    func resetAbbreviations() {
        settings.abbreviations = AbbreviationDefaults.values
        store.saveSettings(settings)
    }

    func clearStorage() {
        guard !hasActiveJob else {
            banner = "Cancela el trabajo en curso antes de borrar."
            return
        }
        jobs = []
        store.saveJobs(jobs)
        store.removeAllSongs()
        input = nil
        storageBytes = 0
        banner = "Historial y archivos borrados."
    }

    private func prepare(
        kind: String,
        presetName: String,
        song: String,
        relative: String,
        hash: String,
        steps: [ChainStep],
        auto: Bool,
        reference: PickedAudio?
    ) async {
        if user == nil, let token = KeychainStore.load(), !token.isEmpty {
            user = try? await client.user(token: token)
        }
        guard !hasActiveJob else {
            banner = "Ya hay un trabajo en curso."
            startGate = false
            return
        }
        let built = resolve(steps: steps.filter(\.enabled), reference: reference)
        if built.steps.isEmpty {
            banner = built.note.isEmpty ? "No hay pasos disponibles." : built.note
            startGate = false
            return
        }
        let pending = PendingRun(
            kind: kind,
            presetName: presetName,
            songName: song,
            inputRelativePath: relative,
            inputSHA256: hash,
            autoContinue: auto,
            steps: built.steps,
            referenceRelativePath: reference?.relativePath,
            skipNote: built.note
        )
        let hit = DuplicateMatcher.match(
            inputHash: hash,
            planned: built.steps.map(\.signature),
            jobs: jobs.map { $0.fingerprint() }
        )
        switch hit {
        case .none:
            await startJob(pending, startIndex: 0)
            startGate = false
        case let .exact(id):
            duplicatePrompt = DuplicatePrompt(
                message: kind == "tool" ? "Ya procesaste este audio con esta herramienta" : "Ya procesaste este audio con esta cadena",
                jobID: id,
                resumeCount: nil,
                pending: pending
            )
        case let .prefix(id, count):
            duplicatePrompt = DuplicatePrompt(
                message: kind == "tool" ? "Ya procesaste este audio con esta herramienta" : "Ya procesaste este audio con esta cadena",
                jobID: id,
                resumeCount: count,
                pending: pending
            )
        }
    }

    private func startJob(_ pending: PendingRun, startIndex: Int) async {
        guard !hasActiveJob else {
            startGate = false
            banner = "Ya hay un trabajo en curso."
            return
        }
        var job = ChainJob(
            id: UUID(),
            songName: pending.songName,
            kind: pending.kind,
            presetName: pending.presetName,
            inputRelativePath: pending.inputRelativePath,
            inputSHA256: pending.inputSHA256,
            autoContinue: pending.autoContinue,
            state: "running",
            steps: pending.steps,
            currentIndex: startIndex,
            message: pending.skipNote.isEmpty ? nil : pending.skipNote,
            originalPremium: nil,
            premiumDirty: false,
            createdAt: Date(),
            queueAhead: nil,
            queueCount: nil,
            estimatedWait: nil,
            remoteStatus: nil,
            referenceRelativePath: pending.referenceRelativePath
        )
        jobs.insert(job, at: 0)
        store.saveJobs(jobs)
        if job.kind == "chain" {
            tab = 0
            chainRoute = .results(job.id)
        } else {
            tab = 3
        }
        beginBackground()
        if settings.notificationsEnabled {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
        if settings.protectFreeModels {
            guard await captureOriginal(job.id) else {
                await fail(job.id, "No se pudo leer el estado de créditos. No se envió el trabajo.")
                return
            }
        }
        await execute(job.id)
    }

    private func execute(_ id: UUID) async {
        if executing.contains(id) { return }
        executing.insert(id)
        defer { executing.remove(id) }
        while true {
            guard let job = jobs.first(where: { $0.id == id }) else { return }
            if job.state == "cancelled" || job.state == "failed" || job.state == "done" {
                await restorePremium(id)
                endBackground()
                return
            }
            if job.currentIndex >= job.steps.count {
                mutate(id) {
                    $0.state = "done"
                    $0.message = "Cadena lista"
                }
                notify(title: "Cadena lista", body: job.songName)
                await restorePremium(id)
                endBackground()
                return
            }
            let index = job.currentIndex
            let step = job.steps[index]
            if step.phase == "done" {
                mutate(id) { $0.currentIndex += 1 }
                continue
            }
            if step.phase == "awaitingChoice" {
                mutate(id) {
                    $0.state = "awaiting"
                    $0.message = "Elige qué stem sigue."
                }
                tab = 0
                chainRoute = .results(id)
                await restorePremium(id)
                endBackground()
                return
            }
            switch CreatePolicy.decide(existingHash: step.hash, phase: step.phase) {
            case .doNotRetry:
                await fail(id, "No se reintentó la creación para no cobrar dos veces. Revisa la cola en MVSEP.")
                return
            case let .poll(hash):
                let outcome = await poll(id, index: index, hash: hash)
                switch outcome {
                case .advanced:
                    continue
                case .awaiting, .failed, .cancelled:
                    await restorePremium(id)
                    endBackground()
                    return
                }
            case .create:
                if settings.protectFreeModels {
                    let enabled = step.usePremium
                    guard await ensurePremium(id, enabled: enabled) else {
                        await fail(id, "No se pudo \(enabled ? "activar" : "desactivar") los créditos. No se envió el paso.")
                        return
                    }
                }
                mutate(id) { $0.steps[index].phase = "creating" }
                switch await createStep(id, index: index) {
                case let .hash(hash):
                    let outcome = await poll(id, index: index, hash: hash)
                    switch outcome {
                    case .advanced:
                        continue
                    case .awaiting, .failed, .cancelled:
                        await restorePremium(id)
                        endBackground()
                        return
                    }
                case let .uncertain(message):
                    mutate(id) { $0.steps[index].phase = "uncertain" }
                    await fail(id, "\(message) No se reintentó para no cobrar dos veces.")
                    return
                case let .failed(message):
                    await fail(id, message)
                    return
                case .inFlight:
                    return
                }
            }
        }
    }

    private enum PollOutcome { case advanced, awaiting, failed, cancelled }

    private func poll(_ id: UUID, index: Int, hash: String) async -> PollOutcome {
        while true {
            if let job = jobs.first(where: { $0.id == id }), job.state == "cancelled" { return .cancelled }
            do {
                let status = try await client.separation(hash: hash)
                if let token = KeychainStore.load(), let summary = try? await client.queue(token: token) {
                    mutate(id) {
                        $0.queueAhead = summary.ahead
                        $0.queueCount = summary.queued
                        $0.estimatedWait = summary.estimatedWait
                    }
                }
                mutate(id) {
                    $0.remoteStatus = status.status
                    $0.steps[index].hash = hash
                    $0.steps[index].phase = "polling"
                    if let order = status.currentOrder {
                        $0.message = "Posición \(order)"
                    }
                }
                switch status.status {
                case "done":
                    await cacheFiles(id, index: index, files: status.files)
                    return await finishStep(id, index: index)
                case "failed", "not_found":
                    let message = status.message.isEmpty ? StatusText.spanish(status.status) : MVSEPMessage.spanish(status.message)
                    mutate(id) {
                        $0.steps[index].phase = "failed"
                        $0.steps[index].error = message
                        $0.state = "failed"
                        $0.message = message
                    }
                    notify(title: "El paso falló", body: message)
                    return .failed
                default:
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                }
            } catch is CancellationError {
                return .cancelled
            } catch let error as MVError {
                if case .api = error {
                    mutate(id) {
                        $0.state = "failed"
                        $0.message = "No se pudo leer el trabajo."
                    }
                    return .failed
                }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            } catch {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    private func finishStep(_ id: UUID, index: Int) async -> PollOutcome {
        guard let job = jobs.first(where: { $0.id == id }) else { return .failed }
        let step = job.steps[index]
        notify(title: "Paso listo", body: "\(step.title) · \(job.songName)")
        let isLast = index + 1 >= job.steps.count
        if step.files.isEmpty {
            let message = "No se pudo guardar el audio en el dispositivo. No se envió el siguiente paso."
            mutate(id) {
                $0.steps[index].phase = "failed"
                $0.steps[index].error = message
                $0.state = "failed"
                $0.message = message
            }
            notify(title: "El paso falló", body: message)
            return .failed
        }
        if isLast {
            mutate(id) {
                $0.steps[index].phase = "done"
                $0.state = "done"
                $0.message = "Cadena lista"
                $0.currentIndex = index + 1
            }
            notify(title: "Cadena lista", body: job.songName)
            return .advanced
        }
        if job.autoContinue {
            let chosen = step.files.first { StemMatch.matches(wanted: step.continueStem, typeLabel: $0.typeLabel) }
                ?? (step.files.count == 1 ? step.files[0] : nil)
            if let chosen {
                mutate(id) {
                    $0.steps[index].chosenStemID = chosen.id
                    $0.steps[index].continueStem = StemMatch.canonical(planned: step.continueStem, typeLabel: chosen.typeLabel)
                    $0.steps[index].phase = "done"
                    $0.currentIndex = index + 1
                }
                return .advanced
            }
        }
        mutate(id) {
            $0.steps[index].phase = "awaitingChoice"
            $0.state = "awaiting"
            $0.message = "Elige qué stem sigue."
        }
        tab = 0
        chainRoute = .results(id)
        return .awaiting
    }

    func retryFailedStep(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }),
              let step = job.steps[safe: job.currentIndex] else { return }
        guard RetryPolicy.canRetry(state: job.state, phase: step.phase, hash: step.hash) else {
            banner = "No se reintenta este paso para no cobrar dos veces."
            return
        }
        guard StartGate.allow(locked: startGate, busy: hasActiveJob) else { return }
        let hash = step.hash?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let localSaveFailed = (step.error ?? "").contains("No se pudo guardar")
        let redownload = !hash.isEmpty && step.files.isEmpty && localSaveFailed
        startGate = true
        mutate(id) {
            let index = $0.currentIndex
            guard $0.steps.indices.contains(index) else { return }
            $0.steps[index].error = nil
            if redownload {
                $0.steps[index].phase = "polling"
                $0.message = "Volviendo a guardar el resultado. No se crea otro trabajo."
            } else {
                $0.steps[index].phase = "pending"
                $0.steps[index].hash = nil
                $0.message = "Reintentando este paso con el archivo guardado."
            }
            $0.state = "running"
            $0.remoteStatus = nil
        }
        tab = 0
        chainRoute = .results(id)
        Task {
            if settings.protectFreeModels {
                guard await captureOriginal(id) else {
                    await fail(id, "No se pudo leer el estado de créditos. No se reenvió el paso.")
                    startGate = false
                    return
                }
            }
            await execute(id)
            startGate = false
        }
    }

    private enum CreateOutcome { case hash(String), uncertain(String), failed(String), inFlight }

    private func createStep(_ id: UUID, index: Int) async -> CreateOutcome {
        let ticket = "\(id.uuidString)#\(index)"
        if submitting.contains(ticket) { return .inFlight }
        submitting.insert(ticket)
        defer { submitting.remove(ticket) }
        guard let job = jobs.first(where: { $0.id == id }), let token = KeychainStore.load() else {
            return .failed("Falta el token.")
        }
        let step = job.steps[index]
        guard let algorithm = catalog.algorithm(for: step.curatedKey) else {
            return .failed("El modelo no está en el catálogo.")
        }
        let base = CreatePlan(sepType: step.sepType, outputFormat: step.outputFormat, options: step.options, body: .none)
        if algorithm.widget == "no_upload" || step.curatedKey == "heartmula" {
            return await post(id, index: index, plan: base, token: token, audio: nil, reference: nil)
        }
        if algorithm.widget == "matchering_upload" || step.curatedKey == "matchering" {
            guard let audio = await ensuredLocal(job: job, index: index),
                  let referencePath = job.referenceRelativePath else {
                return .failed("Matchering necesita el audio y una referencia.")
            }
            var plan = base
            plan.body = .matchering
            let target = shortUploadFile(source: audio, song: job.songName)
            let reference = shortUploadFile(source: store.url(referencePath), song: "\(job.songName) referencia")
            let outcome = await post(id, index: index, plan: plan, token: token, audio: target, reference: reference)
            removeTemporary(target, original: audio)
            removeTemporary(reference, original: store.url(referencePath))
            return outcome
        }
        guard let local = await ensuredLocal(job: job, index: index) else {
            return .failed("No hay un archivo local para este paso. No se envió una URL.")
        }
        var plan = base
        plan.body = .audioFile
        let upload = shortUploadFile(source: local, song: job.songName)
        let outcome = await post(id, index: index, plan: plan, token: token, audio: upload, reference: nil)
        removeTemporary(upload, original: local)
        return outcome
    }

    private func post(_ id: UUID, index: Int, plan: CreatePlan, token: String, audio: URL?, reference: URL?) async -> CreateOutcome {
        do {
            let hash = try await client.create(plan: plan, token: token, audio: audio, reference: reference)
            mutate(id) {
                $0.steps[index].hash = hash
                $0.steps[index].phase = "polling"
            }
            return .hash(hash)
        } catch let error as MVError {
            switch error {
            case let .api(message):
                return .failed(MVSEPMessage.spanish(message))
            case let .http(_, message):
                return .failed(MVSEPMessage.spanish(message))
            case let .transport(message):
                mutate(id) { $0.steps[index].phase = "uncertain" }
                return .uncertain(MVSEPMessage.spanish(message))
            }
        } catch {
            mutate(id) { $0.steps[index].phase = "uncertain" }
            return .uncertain("Error de red")
        }
    }

    private func ensuredLocal(job: ChainJob, index: Int) async -> URL? {
        if index == 0 {
            guard !job.inputRelativePath.isEmpty else { return nil }
            let url = store.url(job.inputRelativePath)
            return fileReady(url) ? url : nil
        }
        guard let stem = chosenInput(job: job, index: index) else { return nil }
        let local = store.url(stem.relativePath)
        if fileReady(local) { return local }
        guard let remote = URL(string: stem.remoteURL), remote.scheme == "https" || remote.scheme == "http" else { return nil }
        do {
            try await client.download(from: remote, to: local)
        } catch {
            return nil
        }
        return fileReady(local) ? local : nil
    }

    private func chosenInput(job: ChainJob, index: Int) -> CachedStem? {
        guard index > 0 else { return nil }
        let previous = job.steps[index - 1]
        return previous.files.first { $0.id == previous.chosenStemID }
            ?? previous.files.first { StemMatch.matches(wanted: previous.continueStem, typeLabel: $0.typeLabel) }
            ?? (previous.files.count == 1 ? previous.files[0] : nil)
    }

    private func fileReady(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size > 0
    }

    private func shortUploadFile(source: URL, song: String) -> URL {
        let filename = ContinuationUpload.filename(song: song, ext: source.pathExtension)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        if destination.standardizedFileURL == source.standardizedFileURL { return source }
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            return source
        }
    }

    private func removeTemporary(_ upload: URL, original: URL) {
        guard upload.standardizedFileURL != original.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: upload)
    }

    private func cacheFiles(_ id: UUID, index: Int, files: [RemoteFile]) async {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        if !job.steps[index].files.isEmpty { return }
        let previous = job.steps.prefix(index + 1).map(\.abbreviation)
        var cached: [CachedStem] = []
        let format = OutputFormat(rawValue: job.steps[index].outputFormat) ?? .wav16
        for file in files {
            guard let remote = URL(string: file.url) else { continue }
            let ext = remote.pathExtension.isEmpty ? format.fileExtension : remote.pathExtension
            let destination = store.uniqueFile(song: job.songName, abbreviations: previous, stem: file.type, ext: ext)
            do {
                try await client.download(from: remote, to: destination)
                let hash = (try? FileHash.sha256(of: destination)) ?? ""
                cached.append(CachedStem(
                    id: UUID(),
                    typeLabel: file.type,
                    remoteURL: file.url,
                    relativePath: store.relative(from: destination),
                    sha256: hash
                ))
            } catch {
                mutate(id) { $0.message = "No se pudo guardar \(file.type) en el dispositivo." }
            }
        }
        mutate(id) {
            $0.steps[index].files = cached
            if cached.isEmpty && !files.isEmpty {
                $0.message = "No se pudo guardar el resultado en el dispositivo."
            }
        }
        storageBytes = store.storageBytes()
    }

    private func resolve(steps: [ChainStep], reference: PickedAudio?) -> (steps: [JobStep], note: String) {
        var output: [JobStep] = []
        var notes: [String] = []
        for step in steps where step.enabled {
            guard let algorithm = catalog.algorithm(for: step.curatedKey) else {
                let title = CuratedModels.spec(for: step.curatedKey)?.title ?? step.curatedKey
                notes.append("Se omitió \(title): no está en MVSEP.")
                continue
            }
            let paid = PremiumPolicy.effectiveUsePremium(
                stored: step.usePremium,
                overridden: step.usePremiumOverridden,
                rulePaid: rulePaid(key: step.curatedKey, options: step.options)
            )
            let accountPremium = settings.protectFreeModels ? paid : (user?.premiumEnabled ?? false)
            let resolved = PremiumPolicy.resolvedFormat(requested: step.outputFormat, usePremium: accountPremium)
            var options = step.options
            if let reference {
                options["_referenceSHA256"] = reference.sha256
            }
            if let note = resolved.note { notes.append(note) }
            output.append(JobStep(
                id: UUID(),
                curatedKey: step.curatedKey,
                title: CuratedModels.spec(for: step.curatedKey)?.title ?? algorithm.name,
                sepType: algorithm.renderID,
                options: options,
                outputFormat: resolved.format,
                usePremium: paid,
                abbreviation: AbbreviationDefaults.resolve(curatedKey: step.curatedKey, options: options, custom: settings.abbreviations),
                continueStem: step.continueStem,
                phase: "pending",
                hash: nil,
                formatNote: resolved.note,
                files: [],
                chosenStemID: nil,
                error: nil
            ))
        }
        return (output, notes.joined(separator: " "))
    }

    private func rulePaid(key: String, options: [String: String]) -> Bool {
        guard let algorithm = catalog.algorithm(for: key) else { return false }
        return PremiumPolicy.decide(
            orientation: algorithm.orientation,
            sepType: algorithm.renderID,
            options: options,
            rules: algorithm.rules
        ).paid
    }

    private func captureOriginal(_ id: UUID) async -> Bool {
        guard let token = KeychainStore.load() else { return false }
        do {
            let loaded = try await client.user(token: token)
            user = loaded
            mutate(id) { $0.originalPremium = loaded.premiumEnabled }
            return true
        } catch {
            return false
        }
    }

    private func ensurePremium(_ id: UUID, enabled: Bool) async -> Bool {
        guard let token = KeychainStore.load() else { return false }
        do {
            let current = try await client.user(token: token)
            user = current
            if current.premiumEnabled == enabled { return true }
            try await client.setPremium(enabled: enabled, token: token)
            let check = try await client.user(token: token)
            user = check
            guard check.premiumEnabled == enabled else { return false }
            mutate(id) { $0.premiumDirty = true }
            return true
        } catch {
            return false
        }
    }

    private func restorePremium(_ id: UUID) async {
        guard let original = jobs.first(where: { $0.id == id })?.originalPremium,
              let token = KeychainStore.load() else { return }
        do {
            let current = try await client.user(token: token)
            if current.premiumEnabled != original {
                try await client.setPremium(enabled: original, token: token)
            }
            user = try await client.user(token: token)
            mutate(id) { $0.premiumDirty = false }
        } catch {
            banner = "No se pudo restaurar el estado de créditos. Revísalo en Ajustes."
        }
    }

    private func fail(_ id: UUID, _ message: String) async {
        let text = MVSEPMessage.spanish(message)
        mutate(id) {
            $0.state = "failed"
            $0.message = text
            if $0.steps.indices.contains($0.currentIndex), $0.steps[$0.currentIndex].phase != "uncertain" {
                $0.steps[$0.currentIndex].phase = "failed"
                $0.steps[$0.currentIndex].error = text
            } else if $0.steps.indices.contains($0.currentIndex) {
                $0.steps[$0.currentIndex].error = text
            }
        }
        banner = nil
        notify(title: "Cadena detenida", body: text)
        await restorePremium(id)
        endBackground()
    }

    private func recoverInterruptedJobs() {
        for job in jobs where job.isActive {
            if let step = job.steps[safe: job.currentIndex],
               step.hash == nil,
               step.phase == "creating" || step.phase == "uncertain" || step.phase == "polling" {
                mutate(job.id) {
                    if $0.steps.indices.contains($0.currentIndex) {
                        $0.steps[$0.currentIndex].phase = "uncertain"
                    }
                    $0.state = "failed"
                    $0.message = "No se reintentó la creación para no cobrar dos veces."
                }
                Task { await restorePremium(job.id) }
            } else if job.state == "running" {
                let jobID = job.id
                beginBackground()
                Task { await execute(jobID) }
                return
            }
        }
    }

    private func copy(url: URL, prefix: String) -> PickedAudio? {
        let song = FilenameBuilder.sanitize(url.deletingPathExtension().lastPathComponent)
        let ext = url.pathExtension.isEmpty ? "audio" : url.pathExtension
        let folder = store.songFolder(song)
        var destination = folder.appendingPathComponent("\(prefix).\(ext)")
        var index = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = folder.appendingPathComponent("\(prefix) \(index).\(ext)")
            index += 1
        }
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            let hash = try FileHash.sha256(of: destination)
            storageBytes = store.storageBytes()
            return PickedAudio(songName: song, relativePath: store.relative(from: destination), sha256: hash)
        } catch {
            return nil
        }
    }

    private func updateSelected(_ body: (inout ChainPreset) -> Void) {
        guard let id = selectedPreset?.id, let index = presets.firstIndex(where: { $0.id == id }) else { return }
        body(&presets[index])
        store.savePresets(presets)
    }

    private func mutate(_ id: UUID, _ body: (inout ChainJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        body(&jobs[index])
        store.saveJobs(jobs)
    }

    private func replace(_ job: ChainJob) {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else { return }
        jobs[index] = job
        store.saveJobs(jobs)
        storageBytes = store.storageBytes()
    }

    private func notify(title: String, body: String) {
        guard settings.notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    private func beginBackground() {
        guard backgroundID == .invalid else { return }
        backgroundID = UIApplication.shared.beginBackgroundTask { [weak self] in
            Task { @MainActor in self?.endBackground() }
        }
    }

    private func endBackground() {
        guard backgroundID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundID)
        backgroundID = .invalid
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
