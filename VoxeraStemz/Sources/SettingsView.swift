import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var confirmClear = false

    var body: some View {
        TabScaffold {
            Card {
                Text("Token de MVSEP")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.silver)
                SecureField("Pega el token", text: $app.tokenDraft)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Probar clave") { app.testKey() }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(app.tokenStatus)
                    .font(.footnote)
                    .foregroundStyle(Theme.silver)
                Text(creditLine)
                    .foregroundStyle(.white)
                Button("Actualizar cuenta") {
                    Task { await app.refreshUser(status: true) }
                }
                .foregroundStyle(Theme.blue)
                Toggle("Premium de la cuenta", isOn: Binding(
                    get: { app.user?.premiumEnabled ?? false },
                    set: { app.setAccountPremium($0) }
                ))
                .tint(Theme.blue)
                .disabled(app.user == nil || app.hasActiveJob)
                Toggle("No gastar créditos en modelos gratis", isOn: Binding(
                    get: { app.settings.protectFreeModels },
                    set: { value in app.updateSettings { $0.protectFreeModels = value } }
                ))
                .tint(Theme.blue)
            }

            Card {
                Picker("Formato por defecto", selection: Binding(
                    get: { app.settings.defaultOutputFormat },
                    set: { value in app.updateSettings { $0.defaultOutputFormat = value } }
                )) {
                    ForEach(OutputFormat.allCases) { format in
                        Text(format.title).tag(format.rawValue)
                    }
                }
                .pickerStyle(.menu)
                Picker("Frecuencia al exportar", selection: Binding(
                    get: { app.settings.defaultSampleRate },
                    set: { value in app.updateSettings { $0.defaultSampleRate = value } }
                )) {
                    Text("44.100 Hz").tag(44100)
                    Text("48.000 Hz").tag(48000)
                }
                .pickerStyle(.menu)
                Toggle("Las cadenas siguen solas", isOn: Binding(
                    get: { app.settings.defaultAutoContinue },
                    set: { value in app.updateSettings { $0.defaultAutoContinue = value } }
                ))
                .tint(Theme.blue)
                Toggle("Avisos al terminar", isOn: Binding(
                    get: { app.settings.notificationsEnabled },
                    set: { app.setNotifications($0) }
                ))
                .tint(Theme.blue)
            }

            Card {
                Text("Abreviaciones")
                    .font(.headline)
                    .foregroundStyle(.white)
                ForEach(AbbreviationDefaults.values.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(AbbreviationDefaults.label(key))
                            .font(.footnote)
                            .foregroundStyle(Theme.silver)
                        Spacer()
                        TextField("Abrev.", text: Binding(
                            get: { app.settings.abbreviations[key] ?? AbbreviationDefaults.values[key] ?? "" },
                            set: { value in
                                app.updateSettings { $0.abbreviations[key] = value }
                            }
                        ))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                    }
                }
                Button("Volver a las de serie") { app.resetAbbreviations() }
                    .foregroundStyle(Theme.blue)
            }

            Card {
                Text("Almacenamiento \(ByteFormat.megabytes(app.storageBytes))")
                    .foregroundStyle(.white)
                Button("Borrar historial y archivos") { confirmClear = true }
                    .foregroundStyle(Theme.danger)
                Button("Actualizar modelos") { app.refreshCatalog() }
                    .foregroundStyle(Theme.blue)
                if !app.catalogMessage.isEmpty {
                    Text(app.catalogMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.silver)
                }
                if !app.catalog.missing.isEmpty {
                    Text("No están en MVSEP: \(app.catalog.missing.joined(separator: ", ")).")
                        .font(.footnote)
                        .foregroundStyle(Theme.silver)
                }
                Text(app.versionText)
                    .font(.footnote)
                    .foregroundStyle(Theme.silver)
                Link("Cuenta MVSEP", destination: URL(string: "https://mvsep.com/login")!)
                    .foregroundStyle(Theme.blue)
            }
        }
        .alert("Borrar archivos", isPresented: $confirmClear) {
            Button("Borrar", role: .destructive) { app.clearStorage() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borran las canciones guardadas en el dispositivo.")
        }
    }

    private var creditLine: String {
        guard let user = app.user else { return "Créditos: sin datos" }
        let minutes = String(format: user.premiumMinutes.rounded() == user.premiumMinutes ? "%.0f" : "%.1f", user.premiumMinutes)
        let state = user.premiumEnabled ? "activo" : "apagado"
        return "Créditos: \(minutes) · Premium \(state)"
    }
}
