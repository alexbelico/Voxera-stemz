import XCTest
@testable import VoxeraStemz

final class LogicTests: XCTestCase {
    func testFilenameKeepsVocalsAndMapsBeat() {
        XCTAssertEqual(
            FilenameBuilder.make(song: "MiCancion", abbreviations: ["BSR124", "DFX"], stem: "Vocals", ext: "wav"),
            "MiCancion BSR124-DFX Vocals.wav"
        )
        XCTAssertEqual(
            FilenameBuilder.make(song: "MiCancion", abbreviations: ["BSR124"], stem: "Other", ext: "wav"),
            "MiCancion BSR124 Beat.wav"
        )
        XCTAssertEqual(
            FilenameBuilder.make(song: "MiCancion", abbreviations: ["BSR124"], stem: "Instrumental", ext: "flac"),
            "MiCancion BSR124 Beat.flac"
        )
        XCTAssertEqual(FilenameBuilder.sanitize("a/b:c*?"), "a b c")
        XCTAssertEqual(FilenameBuilder.sanitize("   "), "Audio")
        XCTAssertEqual(StemMatch.displayStem("Vocals"), "Acapella")
        XCTAssertEqual(StemMatch.displayStem("instrumental only"), "Beat")
        XCTAssertEqual(StemMatch.fileStem("Vocals"), "Vocals")
    }

    func testPremiumDecisionAndFormatFallback() {
        let rule = PriceRule(fieldName: "add_opt1", optionKey: "171", mode: "multiplier", value: 1)
        let overlap = PriceRule(fieldName: "add_opt2", optionKey: "8", mode: "multiplier", value: 2)
        XCTAssertTrue(PremiumPolicy.decide(orientation: 2, sepType: 1, options: [:], rules: []).paid)
        XCTAssertTrue(PremiumPolicy.decide(orientation: 0, sepType: 40, options: ["add_opt1": "171"], rules: []).paid)
        XCTAssertTrue(PremiumPolicy.decide(orientation: 0, sepType: 49, options: ["add_opt1": "8"], rules: []).paid)
        XCTAssertTrue(PremiumPolicy.decide(orientation: 0, sepType: 40, options: ["add_opt1": "171"], rules: [rule]).paid)
        XCTAssertFalse(PremiumPolicy.decide(orientation: 0, sepType: 40, options: ["add_opt1": "81", "add_opt2": "2"], rules: [rule, overlap]).paid)
        XCTAssertTrue(PremiumPolicy.decide(orientation: 0, sepType: 40, options: ["add_opt1": "81", "add_opt2": "8"], rules: [rule, overlap]).paid)
        let fallback = PremiumPolicy.resolvedFormat(requested: OutputFormat.wav32.rawValue, usePremium: false)
        XCTAssertEqual(fallback.format, OutputFormat.wav16.rawValue)
        XCTAssertNotNil(fallback.note)
        XCTAssertEqual(PremiumPolicy.resolvedFormat(requested: OutputFormat.wav32.rawValue, usePremium: true).format, OutputFormat.wav32.rawValue)
        XCTAssertFalse(PremiumPolicy.effectiveUsePremium(stored: true, overridden: false, rulePaid: false))
        XCTAssertTrue(PremiumPolicy.effectiveUsePremium(stored: true, overridden: true, rulePaid: false))
    }

    func testAbbreviationsAndBuiltInPresets() {
        XCTAssertEqual(AbbreviationDefaults.resolve(curatedKey: "bs-roformer", options: ["add_opt1": "171"], custom: [:]), "BSR124")
        XCTAssertEqual(AbbreviationDefaults.resolve(curatedKey: "bs-roformer", options: ["add_opt1": "172"], custom: [:]), "BSR124")
        XCTAssertEqual(AbbreviationDefaults.resolve(curatedKey: "bs-roformer", options: ["add_opt1": "81"], custom: [:]), "BSR25")
        XCTAssertEqual(AbbreviationDefaults.resolve(curatedKey: "bs-roformer", options: ["add_opt1": "3"], custom: [:]), "BSR")
        XCTAssertEqual(AbbreviationDefaults.resolve(curatedKey: "deeffect", options: [:], custom: ["deeffect": "DX"]), "DX")
        let presets = BuiltInPresets.examples()
        XCTAssertEqual(presets.map(\.name), ["Acapella limpia", "Beat con fase", "Acapella seca"])
        XCTAssertEqual(presets[0].steps.map(\.curatedKey), ["bs-roformer", "deeffect", "aspiration"])
        XCTAssertEqual(presets[0].steps[0].options["add_opt1"], "171")
        XCTAssertEqual(presets[0].steps[2].options["add_opt1"], "0")
        XCTAssertEqual(presets[0].steps.map(\.outputFormat), [1, 1, 1])
        XCTAssertEqual(presets[0].steps.map(\.continueStem), ["vocals", "vocals", ""])
        XCTAssertEqual(presets[1].steps[0].options["add_opt1"], "81")
        XCTAssertEqual(presets[1].steps[0].continueStem, "other")
        XCTAssertEqual(presets[1].steps[1].curatedKey, "phase-deux")
        XCTAssertEqual(presets[1].steps[1].options["add_opt1"], "11")
        XCTAssertEqual(presets[1].steps[1].continueStem, "other")
        XCTAssertEqual(presets[2].steps.map(\.curatedKey), ["bs-roformer", "dry-acapella", "deeffect"])
        XCTAssertEqual(presets[2].steps[1].options["add_opt1"], "9")
        XCTAssertEqual(presets[2].steps[1].options["add_opt2"], "1")
        XCTAssertEqual(presets[2].steps[1].continueStem, "dry")
        XCTAssertEqual(StemMatch.fileStem("No reverb (dry)"), "Dry")
        XCTAssertEqual(StemMatch.displayStem("dry"), "Dry")
        XCTAssertTrue(AppSettings.standard.protectFreeModels)
        XCTAssertEqual(AppSettings.standard.defaultSampleRate, 48000)
    }

    func testDuplicateWarningMatchesChainsAndSingleTools() {
        let vocals = signature(40, ["add_opt1": "171"], 1, "vocals")
        let effect = signature(138, [:], 1, "vocals")
        let chain = fingerprint("abc", [vocals, effect])
        XCTAssertEqual(DuplicateMatcher.match(inputHash: "abc", planned: [vocals, effect], jobs: [chain]), .exact(chain.id))
        XCTAssertEqual(DuplicateMatcher.match(inputHash: "abc", planned: [vocals], jobs: [chain]), .exact(chain.id))
        if case let .prefix(id, count) = DuplicateMatcher.match(inputHash: "abc", planned: [vocals, effect, signature(50, ["add_opt1": "0"], 1, "")], jobs: [chain]) {
            XCTAssertEqual(id, chain.id)
            XCTAssertEqual(count, 2)
        } else {
            XCTFail("expected prefix")
        }
        XCTAssertEqual(DuplicateMatcher.match(inputHash: "other", planned: [vocals], jobs: [chain]), .none)
        let reference = signature(68, ["_referenceSHA256": "ref-a"], 1, "")
        let otherReference = signature(68, ["_referenceSHA256": "ref-b"], 1, "")
        let tool = fingerprint("song", [reference])
        XCTAssertEqual(DuplicateMatcher.match(inputHash: "song", planned: [reference], jobs: [tool]), .exact(tool.id))
        XCTAssertEqual(DuplicateMatcher.match(inputHash: "song", planned: [otherReference], jobs: [tool]), .none)
        XCTAssertEqual(SignatureOptions.normalize(["add_opt1": "0", "note": "x", "_referenceSHA256": "abc"]), ["add_opt1": "0", "_referenceSHA256": "abc"])
    }

    func testCreateAndFallbackNeverRetryAnUncertainCreate() {
        XCTAssertEqual(CreatePolicy.decide(existingHash: "abc", phase: "creating"), .poll("abc"))
        XCTAssertEqual(CreatePolicy.decide(existingHash: nil, phase: "creating"), .doNotRetry)
        XCTAssertEqual(CreatePolicy.decide(existingHash: "  ", phase: "uncertain"), .doNotRetry)
        XCTAssertEqual(CreatePolicy.decide(existingHash: nil, phase: "polling"), .doNotRetry)
        XCTAssertEqual(CreatePolicy.decide(existingHash: nil, phase: "pending"), .create)
        XCTAssertEqual(FallbackPolicy.afterRemoteFailure(definitive: true, localReady: true, uploadTried: false), .uploadLocal)
        XCTAssertEqual(FallbackPolicy.afterRemoteFailure(definitive: false, localReady: true, uploadTried: false), .stop)
        XCTAssertEqual(FallbackPolicy.afterRemoteFailure(definitive: true, localReady: true, uploadTried: true), .stop)
        XCTAssertFalse(StartGate.allow(locked: true, busy: false))
        XCTAssertFalse(StartGate.allow(locked: false, busy: true))
        XCTAssertTrue(StartGate.allow(locked: false, busy: false))
    }

    func testCreatePlanOmitsMirrorAndPrivateKeys() throws {
        let remote = CreatePlan(sepType: 40, outputFormat: 1, options: ["add_opt1": "81", "_referenceSHA256": "secret"], body: .remoteURL("https://de.mvsep.com/result/a.wav"))
        let fields = remote.textFields
        XCTAssertEqual(fields["sep_type"], "40")
        XCTAssertEqual(fields["output_format"], "1")
        XCTAssertEqual(fields["is_demo"], "0")
        XCTAssertEqual(fields["add_opt1"], "81")
        XCTAssertEqual(fields["url"], "https://de.mvsep.com/result/a.wav")
        XCTAssertEqual(fields["remote_type"], "direct")
        XCTAssertNil(fields["mirror"])
        XCTAssertNil(fields["_referenceSHA256"])
        let address = try XCTUnwrap(APIParser.separationURL(hash: "abc")).absoluteString
        XCTAssertFalse(address.contains("mirror"))
        XCTAssertTrue(address.contains("hash=abc"))
    }

    func testParsersKeepRegionalURLAndIgnoreDownloadName() throws {
        let user = try APIParser.user(from: Data(#"{"success":true,"data":{"name":"Alex","premium_enabled":1,"premium_minutes":12.5}}"#.utf8))
        XCTAssertEqual(user.name, "Alex")
        XCTAssertTrue(user.premiumEnabled)
        XCTAssertEqual(user.premiumMinutes, 12.5)
        let off = try APIParser.user(from: Data(#"{"success":true,"data":{"premium_enabled":0,"premium_minutes":"3"}}"#.utf8))
        XCTAssertFalse(off.premiumEnabled)
        XCTAssertEqual(off.premiumMinutes, 3.0)
        let separation = try APIParser.separation(from: Data(#"{"success":true,"status":"done","data":{"files":[{"type":"Vocals","url":"https://de.mvsep.com/result/a.wav","download":"ugly_name.wav"}]}}"#.utf8))
        XCTAssertEqual(separation.files, [RemoteFile(type: "Vocals", url: "https://de.mvsep.com/result/a.wav")])
        let queue = try APIParser.queue(from: Data(#"{"queued":4,"processing":1,"ahead":2,"estimated_wait_seconds":null}"#.utf8))
        XCTAssertEqual(queue.queued, 4)
        XCTAssertEqual(queue.ahead, 2)
        XCTAssertNil(queue.estimatedWait)
        let nested = try APIParser.queue(from: Data(#"{"data":{"queued":1,"estimated_wait_seconds":90}}"#.utf8))
        XCTAssertEqual(nested.estimatedWait, 90)
        XCTAssertEqual(try APIParser.createdHash(from: Data(#"{"success":true,"data":{"hash":"h1"}}"#.utf8)), "h1")
        XCTAssertThrowsError(try APIParser.createdHash(from: Data(#"{"success":false,"message":"no"}"#.utf8)))
    }

    func testSeedCatalogMapsCuratedModels() throws {
        let url = try XCTUnwrap(Bundle(for: LogicTests.self).url(forResource: "algorithms-seed", withExtension: "json"))
        let algorithms = try AlgorithmParser.parse(data: Data(contentsOf: url))
        let snapshot = CatalogSnapshot.build(from: algorithms)
        XCTAssertEqual(snapshot.algorithm(for: "bs-roformer")?.renderID, 40)
        XCTAssertEqual(snapshot.algorithm(for: "deeffect")?.renderID, 138)
        XCTAssertEqual(snapshot.algorithm(for: "karaoke")?.renderID, 49)
        XCTAssertEqual(snapshot.algorithm(for: "aspiration")?.renderID, 50)
        XCTAssertEqual(snapshot.algorithm(for: "matchering")?.renderID, 68)
        XCTAssertEqual(snapshot.algorithm(for: "heartmula")?.renderID, 121)
        XCTAssertEqual(snapshot.algorithm(for: "male-female")?.renderID, 57)
        XCTAssertEqual(snapshot.algorithm(for: "mega53")?.renderID, 126)
        XCTAssertEqual(snapshot.algorithm(for: "dry-acapella")?.renderID, 22)
        XCTAssertEqual(snapshot.algorithm(for: "phase-deux")?.renderID, 48)
        XCTAssertEqual(snapshot.algorithm(for: "phase")?.renderID, 40)
        XCTAssertEqual(snapshot.algorithm(for: "lead-backing")?.renderID, 49)
        XCTAssertEqual(snapshot.algorithm(for: "muscriptor")?.renderID, 141)
        XCTAssertEqual(CuratedModels.options(for: "dry-acapella"), ["add_opt1": "9", "add_opt2": "1"])
        XCTAssertEqual(CuratedModels.options(for: "phase-deux"), ["add_opt1": "11", "add_opt2": "2"])
        XCTAssertEqual(CuratedModels.options(for: "phase")["add_opt1"], "142")
        XCTAssertEqual(CuratedModels.options(for: "lead-backing"), ["add_opt1": "8", "add_opt2": "1"])
        XCTAssertEqual(CuratedModels.options(for: "muscriptor")["add_opt1"], "0")
        XCTAssertTrue(snapshot.missing.isEmpty)
        let karaoke = try XCTUnwrap(snapshot.algorithm(for: "lead-backing"))
        XCTAssertTrue(PremiumPolicy.decide(orientation: karaoke.orientation, sepType: karaoke.renderID, options: CuratedModels.options(for: "lead-backing"), rules: karaoke.rules).paid)
        let bsr = try XCTUnwrap(snapshot.algorithm(for: "bs-roformer"))
        XCTAssertFalse(PremiumPolicy.decide(orientation: bsr.orientation, sepType: bsr.renderID, options: ["add_opt1": "81", "add_opt2": "2"], rules: bsr.rules).paid)
        XCTAssertTrue(PremiumPolicy.decide(orientation: bsr.orientation, sepType: bsr.renderID, options: ["add_opt1": "171", "add_opt2": "2"], rules: bsr.rules).paid)
        XCTAssertEqual(bsr.defaultOptions()["add_opt1"], "81")
        let wrapped = try AlgorithmParser.parse(data: Data(#"{"data":[{"render_id":7,"name":"Demo","orientation":2}]}"#.utf8))
        XCTAssertEqual(wrapped.first?.renderID, 7)
        XCTAssertEqual(wrapped.first?.orientation, 2)
    }

    func testChainPersistenceRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let documents = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = DiskStore(root: root, documents: documents)
        var settings = AppSettings.standard
        settings.abbreviations["deeffect"] = "DX"
        store.saveSettings(settings)
        XCTAssertEqual(store.loadSettings(), settings)
        let presets = BuiltInPresets.examples()
        store.savePresets(presets)
        XCTAssertEqual(store.loadPresets(), presets)
        let job = sampleJob()
        store.saveJobs([job])
        XCTAssertEqual(store.loadJobs(), [job])
        let file = store.uniqueFile(song: "MiCancion", abbreviations: ["BSR124"], stem: "Vocals", ext: "wav")
        XCTAssertEqual(file.lastPathComponent, "MiCancion BSR124 Vocals.wav")
        try Data("stem".utf8).write(to: file)
        let again = store.uniqueFile(song: "MiCancion", abbreviations: ["BSR124"], stem: "Vocals", ext: "wav")
        XCTAssertEqual(again.lastPathComponent, "MiCancion BSR124 Vocals 2.wav")
        XCTAssertGreaterThan(store.storageBytes(), 0)
        store.removeAllSongs()
        XCTAssertEqual(store.storageBytes(), 0)
        XCTAssertEqual(FileHash.sha256(of: Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testNextStepUploadsAShortLocalFileAndFailedStepsCanRetry() {
        XCTAssertEqual(ContinuationUpload.filename(song: "Mi canción", ext: ".wav"), "Mi canción.wav")
        let upload = CreatePlan(sepType: 138, outputFormat: 1, options: ["add_opt1": "0"], body: .audioFile)
        XCTAssertNil(upload.textFields["url"])
        XCTAssertNil(upload.textFields["remote_type"])
        XCTAssertEqual(upload.textFields["sep_type"], "138")
        XCTAssertTrue(RetryPolicy.canRetry(state: "failed", phase: "failed", hash: nil))
        XCTAssertFalse(RetryPolicy.canRetry(state: "failed", phase: "uncertain", hash: nil))
        XCTAssertFalse(RetryPolicy.canRetry(state: "running", phase: "failed", hash: nil))
        XCTAssertEqual(
            MVSEPMessage.spanish("File or File Hash not found"),
            "MVSEP no encontró el archivo. Hay que subir el audio guardado en el dispositivo."
        )
        var first = sampleJob()
        first.state = "failed"
        first.currentIndex = 1
        var second = first
        second.id = UUID()
        var running = first
        running.id = UUID()
        running.state = "running"
        let visible = QueueList.collapse([first, second, running])
        XCTAssertEqual(visible.map(\.state), ["failed", "running"])
        XCTAssertEqual(visible.first?.id, first.id)
    }

    private func signature(_ sep: Int, _ options: [String: String], _ format: Int, _ stem: String) -> StepSignature {
        StepSignature(sepType: sep, options: options, outputFormat: format, chosenStem: stem)
    }

    private func fingerprint(_ hash: String, _ steps: [StepSignature]) -> JobFingerprint {
        JobFingerprint(id: UUID(), inputHash: hash, steps: steps)
    }

    private func sampleJob() -> ChainJob {
        ChainJob(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            songName: "MiCancion",
            kind: "chain",
            presetName: "Acapella limpia",
            inputRelativePath: "MiCancion/entrada.wav",
            inputSHA256: "abc",
            autoContinue: false,
            state: "done",
            steps: [
                JobStep(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    curatedKey: "bs-roformer",
                    title: "BS Roformer",
                    sepType: 40,
                    options: ["add_opt1": "171"],
                    outputFormat: 1,
                    usePremium: true,
                    abbreviation: "BSR124",
                    continueStem: "vocals",
                    phase: "done",
                    hash: "h1",
                    formatNote: nil,
                    files: [],
                    chosenStemID: nil,
                    error: nil
                ),
            ],
            currentIndex: 1,
            message: nil,
            originalPremium: false,
            premiumDirty: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            queueAhead: nil,
            queueCount: nil,
            estimatedWait: nil,
            remoteStatus: "done",
            referenceRelativePath: nil
        )
    }
}
