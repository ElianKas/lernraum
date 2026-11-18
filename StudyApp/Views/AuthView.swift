import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var store: AppStore
    @State private var email = ""
    @State private var password = ""
    @State private var register = false
    @State private var busy = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "rectangle.stack.fill").font(.system(size: 38)).foregroundStyle(Theme.ink).padding(.top, 36)
                    Text("Wissen bleibt.").font(.system(.largeTitle, design: .serif, weight: .bold))
                    Text("Deine Karten. Dein Tempo.\nEin Kapitel nach dem anderen.").font(.title3).foregroundStyle(Theme.secondaryText)
                    VStack(alignment: .leading, spacing: 16) {
                        Text(register ? "Konto erstellen" : "Willkommen zurück").font(.title2.bold())
                        TextField("E-Mail", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().padding().background(.background, in: RoundedRectangle(cornerRadius: 12))
                        SecureField("Passwort", text: $password).textContentType(register ? .newPassword : .password).padding().background(.background, in: RoundedRectangle(cornerRadius: 12))
                        if register { Text("Mindestens 8 Zeichen. Falls dein Projekt strengere Regeln hat, gelten diese zusätzlich.").font(.caption).foregroundStyle(Theme.secondaryText) }
                        PrimaryButton(title: register ? "Registrieren" : "Anmelden", busy: busy) { authenticate() }
                            .disabled(!email.contains("@") || password.count < (register ? 8 : 1) || store.api == nil)
                        if let message { Text(message).font(.callout).foregroundStyle(Theme.secondaryText) }
                        Button(register ? "Bereits ein Konto? Anmelden" : "Neu hier? Konto erstellen") { register.toggle(); message = nil }.frame(maxWidth: .infinity)
                    }
                    if store.api == nil {
                        Label("Supabase noch nicht verbunden", systemImage: "gearshape").font(.headline)
                        Text("Trage Projekt-URL und Publishable Key in StudyApp/Configuration/Config.xcconfig ein. Bis dahin kannst du den Lernablauf mit Beispieldaten ausprobieren.").font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                    Button { store.startDemo() } label: { Label("Mit Beispielkarten ausprobieren", systemImage: "play.circle").frame(maxWidth: .infinity) }.padding(.vertical)
                    Text("Im Demo-Modus werden keine Daten gespeichert.").font(.caption).foregroundStyle(Theme.secondaryText).frame(maxWidth: .infinity)
                }.padding(28).frame(maxWidth: 520)
            }.background(Theme.paper)
        }
    }
    private func authenticate() {
        busy = true; message = nil
        Task {
            defer { busy = false }
            do {
                if try await !store.login(email: email, password: password, register: register) {
                    message = "Bitte bestätige deine E-Mail-Adresse und melde dich danach an."; register = false
                }
            } catch { message = error.localizedDescription }
        }
    }
}
