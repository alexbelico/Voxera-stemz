import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        TabView(selection: $app.tab) {
            ChainsView()
                .tabItem { Label("Cadenas", systemImage: "link") }
                .tag(0)
            ToolsView()
                .tabItem { Label("Herramientas", systemImage: "wrench.and.screwdriver") }
                .tag(1)
            HistoryView()
                .tabItem { Label("Historial", systemImage: "clock") }
                .tag(2)
            QueueView()
                .tabItem { Label("Cola", systemImage: "list.bullet") }
                .tag(3)
            SettingsView()
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
                .tag(4)
        }
        .tint(Theme.blue)
        .preferredColorScheme(.dark)
        .confirmationDialog(
            app.duplicatePrompt?.message ?? "Audio ya procesado",
            isPresented: Binding(
                get: { app.duplicatePrompt != nil },
                set: { if !$0 { app.dismissDuplicate() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Abrir resultado anterior") { app.openPrevious() }
            if app.duplicatePrompt?.resumeCount != nil {
                Button("Continuar desde el último paso igual") { app.resumePrefix() }
            }
            Button("Correr de nuevo") { app.runAnyway() }
            Button("Cancelar", role: .cancel) { app.dismissDuplicate() }
        } message: {
            Text("Es un aviso. Cancelar no gasta créditos. Correr de nuevo puede usarlos.")
        }
        .confirmationDialog(
            "Frecuencia",
            isPresented: Binding(
                get: { app.exportRequest != nil },
                set: { if !$0 { app.exportRequest = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let request = app.exportRequest {
                Button("44.100 Hz") { app.export(url: request.url, sampleRate: 44100) }
                Button("48.000 Hz") { app.export(url: request.url, sampleRate: 48000) }
                Button("Original") { app.export(url: request.url, sampleRate: nil) }
            }
            Button("Cancelar", role: .cancel) { app.exportRequest = nil }
        } message: {
            Text("Se convierte en este dispositivo. No usa créditos.")
        }
        .sheet(item: $app.sharePayload) { payload in
            ActivityView(url: payload.url)
        }
    }
}

@main
struct VoxeraStemzApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(app.player)
        }
    }
}
