import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        TabScaffold {
            if app.jobs.isEmpty {
                Text("Todavía no hay canciones.")
                    .foregroundStyle(Theme.silver)
            }
            ForEach(songs, id: \.self) { song in
                Card {
                    Text(song)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    ForEach(app.jobs.filter { $0.songName == song }) { job in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(job.presetName) · \(StatusText.spanish(job.state))")
                                .font(.subheadline)
                                .foregroundStyle(job.id == app.focusJobID ? Theme.blue : Theme.silver)
                            ForEach(job.steps) { step in
                                if !step.files.isEmpty {
                                    Text(step.title)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(Theme.silver)
                                    ForEach(step.files) { stem in
                                        StemRow(stem: stem, chooseTitle: "Usar como entrada") {
                                            app.useStemAsInput(stem, song: song)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var songs: [String] {
        var names: [String] = []
        for job in app.jobs where !names.contains(job.songName) {
            names.append(job.songName)
        }
        if let focus = app.jobs.first(where: { $0.id == app.focusJobID })?.songName,
           let index = names.firstIndex(of: focus) {
            names.remove(at: index)
            names.insert(focus, at: 0)
        }
        return names
    }
}
