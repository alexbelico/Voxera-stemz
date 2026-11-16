import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        TabScaffold {
            if app.jobs.isEmpty {
                Text("No hay trabajos.")
                    .foregroundStyle(Theme.silver)
            }
            ForEach(QueueList.collapse(app.jobs)) { job in
                Card {
                    HStack {
                        Text(job.songName)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer()
                        Text(StatusText.spanish(job.state))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.silver)
                    }
                    Text(job.presetName)
                        .font(.subheadline)
                        .foregroundStyle(Theme.silver)
                    if job.steps.indices.contains(job.currentIndex) {
                        let step = job.steps[job.currentIndex]
                        Text("Paso: \(step.title)")
                            .foregroundStyle(.white)
                        Text(StatusText.spanish(job.remoteStatus ?? step.phase))
                            .font(.footnote)
                            .foregroundStyle(Theme.silver)
                    }
                    if let ahead = job.queueAhead {
                        Text("Hay \(ahead) por delante")
                            .font(.footnote)
                            .foregroundStyle(Theme.silver)
                    }
                    if let wait = job.estimatedWait {
                        Text("Espera estimada \(max(wait / 60, 1)) min")
                            .font(.footnote)
                            .foregroundStyle(Theme.silver)
                    } else if job.isActive {
                        Text("Espera estimada desconocida")
                            .font(.footnote)
                            .foregroundStyle(Theme.silver)
                    }
                    if let message = job.message, !message.isEmpty {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Theme.silver)
                    }
                    if job.isActive {
                        Button("Cancelar") { app.cancelJob(job.id) }
                            .foregroundStyle(Theme.danger)
                    }
                }
            }
        }
    }
}
