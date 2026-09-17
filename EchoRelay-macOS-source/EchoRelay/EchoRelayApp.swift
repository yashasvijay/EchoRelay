import SwiftUI

@main
struct EchoRelayApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("EchoRelay") {
            ContentView().environmentObject(state)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Refresh Speakers") { state.browser.start() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("EchoRelay", systemImage: "dot.radiowaves.left.and.right") {
            Text(state.transmitting ? "Transmitting" : "Idle")
            Divider()
            Button(state.transmitting ? "Stop Transmission" : "Start Transmission") {
                Task {
                    if state.transmitting { await state.stopTransmission() }
                    else { await state.startTransmission() }
                }
            }
            Button("Open EchoRelay") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
