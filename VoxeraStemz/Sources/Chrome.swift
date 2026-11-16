import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct BrandHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text("Voxera Stemz")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

struct TabScaffold<Content: View>: View {
    @EnvironmentObject private var app: AppModel
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            BrandHeader()
            if let banner = app.banner, !banner.isEmpty {
                Text(banner)
                    .font(.footnote)
                    .foregroundStyle(Theme.silver)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.card)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content()
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("CREATED BY ALEXMOET")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.silver.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .padding(.bottom, 8)
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.visible, for: .tabBar)
    }
}

struct PremiumSwitch: View {
    var isOn: Bool
    var overridden: Bool
    var globalOn: Bool
    var onChange: (Bool) -> Void
    var onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Usar créditos (premium)", isOn: Binding(get: { isOn }, set: onChange))
                .tint(Theme.blue)
            HStack {
                CostBadge(premium: isOn)
                Spacer()
                if overridden {
                    Button("Usar la regla automática", action: onReset)
                        .font(.footnote)
                        .foregroundStyle(Theme.blue)
                }
            }
            if !globalOn {
                Text("El cambio automático está apagado en Ajustes. Este interruptor no se aplica hasta que lo actives.")
                    .font(.footnote)
                    .foregroundStyle(Theme.silver)
            }
        }
    }
}

struct FormatMenu: View {
    var format: Int
    var usePremium: Bool
    var set: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Formato", selection: Binding(get: { format }, set: set)) {
                ForEach(OutputFormat.allCases) { item in
                    Text(item.title).tag(item.rawValue)
                }
            }
            .pickerStyle(.menu)
            if let note = PremiumPolicy.resolvedFormat(requested: format, usePremium: usePremium).note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(Theme.silver)
            }
        }
    }
}

struct ModelFields: View {
    var curatedKey: String
    var algorithm: Algorithm?
    var options: [String: String]
    var set: (String, String) -> Void
    @State private var picking: AlgoField?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if curatedKey == "aspiration" {
                Text("Si la entrada ya es voz, usa la opción 0.")
                    .font(.footnote)
                    .foregroundStyle(Theme.silver)
            }
            if curatedKey == "phase" {
                Text("MVSEP no tiene un campo de corrección de fase. Este paso usa BS Roformer HyperACE v2 instrumental.")
                    .font(.footnote)
                    .foregroundStyle(Theme.silver)
            }
            if let algorithm {
                ForEach(algorithm.fields) { field in
                    fieldControl(field)
                }
            } else {
                Text("Este modelo no está en MVSEP. Se omitirá al correr.")
                    .font(.footnote)
                    .foregroundStyle(Theme.silver)
            }
        }
        .sheet(item: $picking) { field in
            ChoiceList(
                title: field.spanishTitle,
                choices: field.choices,
                selected: options[field.name] ?? field.defaultKey ?? ""
            ) { key in
                set(field.name, key)
                picking = nil
            }
        }
    }

    @ViewBuilder
    private func fieldControl(_ field: AlgoField) -> some View {
        if field.choices.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(field.spanishTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.silver)
                if field.inputType.lowercased().contains("area") {
                    TextEditor(text: textBinding(field.name))
                        .frame(minHeight: 140)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundColor(.white)
                } else {
                    TextField(field.spanishTitle, text: textBinding(field.name))
                        .textFieldStyle(.roundedBorder)
                }
            }
        } else if field.choices.count > 6 {
            VStack(alignment: .leading, spacing: 6) {
                Text(field.spanishTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.silver)
                Button {
                    picking = field
                } label: {
                    Text(label(for: field))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        } else {
            Picker(field.spanishTitle, selection: selection(field)) {
                ForEach(field.choices) { choice in
                    Text(choice.label).tag(choice.key)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private func textBinding(_ name: String) -> Binding<String> {
        Binding(get: { options[name] ?? "" }, set: { set(name, $0) })
    }

    private func selection(_ field: AlgoField) -> Binding<String> {
        Binding(
            get: { options[field.name] ?? field.defaultKey ?? field.choices.first?.key ?? "" },
            set: { set(field.name, $0) }
        )
    }

    private func label(for field: AlgoField) -> String {
        let key = options[field.name] ?? field.defaultKey ?? ""
        return field.choices.first { $0.key == key }?.label ?? "Elegir"
    }
}

struct ChoiceList: View {
    var title: String
    var choices: [FieldChoice]
    var selected: String
    var onPick: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            BrandHeader()
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            List(choices) { choice in
                Button {
                    onPick(choice.key)
                } label: {
                    HStack(alignment: .top) {
                        Text(choice.label)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if choice.key == selected {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Theme.blue)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            Text("CREATED BY ALEXMOET")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.silver.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

struct StemRow: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var player: PlayerModel
    var stem: CachedStem
    var chooseTitle: String?
    var choose: (() -> Void)?

    var body: some View {
        let url = app.store.url(stem.relativePath)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(StemMatch.displayStem(stem.typeLabel))
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Button(player.isCurrent(url) && player.isPlaying ? "Pausa" : "Play") {
                    app.play(stem)
                }
                .foregroundStyle(Theme.blue)
                Button("Descargar/Compartir") { app.beginExport(stem) }
                    .foregroundStyle(Theme.silver)
            }
            if player.isCurrent(url) {
                Slider(
                    value: Binding(
                        get: { player.progress },
                        set: { player.seek(fraction: $0) }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        player.scrubbing = editing
                    }
                )
                .tint(Theme.blue)
            }
            if let chooseTitle, let choose {
                Button(chooseTitle, action: choose)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.blue)
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct AudioPickButton: View {
    var title: String
    var picked: String?
    var onPick: (URL) -> Void
    @State private var show = false

    var body: some View {
        Button {
            show = true
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(picked ?? "Ningún archivo")
                    .font(.footnote)
                    .foregroundStyle(Theme.silver)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $show) {
            AudioImporter { url in
                onPick(url)
                show = false
            }
        }
    }
}

struct AudioImporter: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        var types: [UTType] = [.audio, .mp3, .wav, .aiff, .mpeg4Audio]
        for ext in ["flac", "ogg", "opus", "aif", "aiff", "m4a"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            onPick(url)
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    var url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let pop = controller.popoverPresentationController {
            pop.sourceView = controller.view
            pop.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {
        if let pop = controller.popoverPresentationController {
            pop.sourceView = controller.view
            let bounds = controller.view.bounds
            pop.sourceRect = CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
    }
}
