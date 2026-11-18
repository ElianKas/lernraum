import SwiftUI

@main
struct StudyApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            Group {
                if !store.ready { ProgressView("Lernraum wird geöffnet …") }
                else if store.user == nil { AuthView() }
                else { LibraryView() }
            }
            .environmentObject(store)
            .tint(Theme.ink)
            .task { await store.restore() }
            .alert("Etwas hat nicht geklappt", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
                Button("OK") { store.error = nil }
            } message: { Text(store.error ?? "") }
        }
    }
}

enum Theme {
    // Explicit light/dark pairs keep tinted surfaces and small text readable.
    static let ink = adaptive(light: (0.12, 0.27, 0.23), dark: (0.70, 0.89, 0.76))
    static let buttonBackground = Color(red: 0.12, green: 0.27, blue: 0.23)
    static let secondaryText = adaptive(light: (0.29, 0.31, 0.32), dark: (0.77, 0.79, 0.80))
    static let warningText = adaptive(light: (0.48, 0.23, 0.02), dark: (1.0, 0.76, 0.43))
    static let warningBackground = adaptive(light: (1.0, 0.92, 0.81), dark: (0.25, 0.17, 0.08))
    static let errorText = adaptive(light: (0.68, 0.12, 0.16), dark: (1.0, 0.61, 0.64))
    static let paper = Color(uiColor: .systemGroupedBackground)
    static let mint = adaptive(light: (0.80, 0.91, 0.79), dark: (0.12, 0.23, 0.18))

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}
struct PrimaryButton: View {
    let title: String
    var busy = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { Spacer(); if busy { ProgressView().tint(.white) } else { Text(title).fontWeight(.semibold) }; Spacer() }
                .padding(16).background(Theme.buttonBackground, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.white)
        }.disabled(busy)
    }
}
