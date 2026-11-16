import SwiftUI

@main struct WaveAceApp: App {
    @StateObject private var model = ScopeModel()
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1080, minHeight: 720)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1360, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Osciloskop") {
                Button("Připojit") { model.connect() }.disabled(model.connected || model.connecting)
                Button("Odpojit") { model.disconnect() }.disabled(!model.connected && !model.connecting)
                Divider()
                Button(model.live ? "Pozastavit přenos" : "Obnovit přenos") { model.live.toggle() }.keyboardShortcut(" ", modifiers: [])
                Button("Exportovat CSV…") { model.exportCSV() }.keyboardShortcut("s").disabled(model.shownWaves.isEmpty)
            }
        }
    }
}
