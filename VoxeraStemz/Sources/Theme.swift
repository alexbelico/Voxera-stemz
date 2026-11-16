import SwiftUI

enum Theme {
    static let bg = Color(red: 0.016, green: 0.027, blue: 0.051)
    static let card = Color(red: 0.035, green: 0.055, blue: 0.095)
    static let blue = Color(red: 0.102, green: 0.639, blue: 1)
    static let deep = Color(red: 0.051, green: 0.420, blue: 0.860)
    static let silver = Color(red: 0.780, green: 0.835, blue: 0.890)
    static let line = Color(red: 0.45, green: 0.55, blue: 0.66).opacity(0.35)
    static let danger = Color(red: 0.93, green: 0.45, blue: 0.38)
    static let ok = Color(red: 0.55, green: 0.82, blue: 0.62)
}

struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
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
}

struct PrimaryButton: View {
    var title: String
    var enabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(enabled ? Theme.blue : Theme.blue.opacity(0.35))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .disabled(!enabled)
    }
}

struct CostBadge: View {
    var premium: Bool

    var body: some View {
        Text(premium ? "Premium" : "Gratis")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(premium ? Theme.blue.opacity(0.22) : Color.white.opacity(0.08))
            .foregroundStyle(premium ? Theme.blue : Theme.silver)
            .clipShape(Capsule())
            .accessibilityLabel(premium ? "Premium" : "Gratis")
    }
}
