import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @State private var showEffects = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                sourceSidebar
                    .frame(width: 250)
                Divider()
                outputsPane
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .task { await state.appear() }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { showEffects = true } label: { Label("Effects", systemImage: "slider.horizontal.3") }
            }
            ToolbarItem(placement: .automatic) {
                Button { state.browser.start() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
        }
        .sheet(isPresented: $showEffects) { EffectsView().environmentObject(state).frame(width: 420).padding(24) }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 24, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text("EchoRelay").font(.title2.weight(.semibold))
                Text(state.transmitting ? state.statusMessage : "Send your Mac audio around the room")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state.installingHelper {
                ProgressView(value: state.installProgress)
                    .frame(width: 130)
            } else if !state.helperAvailable {
                Button("Install AirPlay Engine") { Task { await state.installHelper() } }
                    .buttonStyle(.borderedProminent)
            }
            Toggle(isOn: Binding(get: { state.transmitting }, set: { value in
                Task { if value { await state.startTransmission() } else { await state.stopTransmission() } }
            })) {
                Text("Transmit")
            }
            .toggleStyle(.switch)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var sourceSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SOURCE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Button {
                state.source = .system
                state.sourceChanged()
            } label: {
                sourceRow(icon: "waveform", title: "All Mac Audio", selected: isSystemSource)
            }
            .buttonStyle(.plain)

            if !state.applications.isEmpty {
                Text("APPS").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 8)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(state.applications.prefix(80)) { app in
                            Button {
                                state.source = .application(bundleIdentifier: app.bundleIdentifier, name: app.name)
                                state.sourceChanged()
                            } label: {
                                sourceRow(icon: "app.dashed", title: app.name, selected: isSelected(app))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Text("Apps appear after Screen & System Audio Recording permission is granted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }
        }
        .padding(18)
    }

    private var outputsPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Outputs").font(.title3.weight(.semibold))
                    Text("AirPlay receivers discovered on your local network")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Select All") { state.selectAll() }
                    Button("Select None") { state.selectNone() }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
            }

            if state.browser.speakers.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "hifispeaker.2").font(.system(size: 34)).foregroundStyle(.secondary)
                    Text(state.browser.scanning ? "Looking for AirPlay speakers…" : "No AirPlay speakers found")
                    Text("Make sure the receiver is on the same local network.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(state.browser.speakers) { speaker in
                            SpeakerRow(speaker: speaker)
                        }
                    }
                }
            }
            HStack {
                Circle()
                    .fill(state.inputLevel > 0.001 ? .green : .secondary)
                    .frame(width: 8, height: 8)
                Text("Input level \(Int(max(0, min(1, state.inputLevel)) * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("NTP sync mode")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(20)
    }

    private func sourceRow(icon: String, title: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 20)
            Text(title).lineLimit(1)
            Spacer()
            if selected { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selected ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
    }

    private var isSystemSource: Bool {
        if case .system = state.source { return true }
        return false
    }

    private func isSelected(_ app: AudioApp) -> Bool {
        if case .application(let bundle, _) = state.source { return bundle == app.bundleIdentifier }
        return false
    }
}

struct SpeakerRow: View {
    @EnvironmentObject private var state: AppState
    let speaker: Speaker

    var settings: OutputSettings { state.outputSettings[speaker.id] ?? OutputSettings(id: UUID(), speakerID: speaker.id) }

    var body: some View {
        HStack(spacing: 14) {
            Button { state.toggleSpeaker(speaker) } label: {
                Image(systemName: state.isSelected(speaker) ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
            }
            .buttonStyle(.plain)

            Image(systemName: speaker.systemIcon)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(speaker.name).font(.headline)
                Text("\(speaker.transport.label) • \(speaker.host)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            Button { state.toggleMute(speaker.id) } label: {
                Image(systemName: settings.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(.plain)

            Slider(value: Binding(get: { settings.volume }, set: { state.setVolume(speaker.id, $0) }), in: 0...1)
                .frame(width: 150)
                .disabled(!state.isSelected(speaker))

            Text("\(Int(settings.volume * 100))")
                .font(.caption.monospacedDigit())
                .frame(width: 28, alignment: .trailing)
        }
        .padding(14)
        .background(state.isSelected(speaker) ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct EffectsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Effects").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
            }
            Text("Three-band EQ").font(.headline)
            band("Bass", value: Binding(get: { state.eq.bass }, set: { var x = state.eq; x.bass = $0; state.updateEQ(x) }))
            band("Mid", value: Binding(get: { state.eq.mid }, set: { var x = state.eq; x.mid = $0; state.updateEQ(x) }))
            band("Treble", value: Binding(get: { state.eq.treble }, set: { var x = state.eq; x.treble = $0; state.updateEQ(x) }))
            Divider()
            Toggle("Silence monitor", isOn: $state.silenceMonitorEnabled)
            Text("Stops transmission after roughly five seconds of silence.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Auto-transmit on launch", isOn: $state.autoTransmit)
                .disabled(true)
            Text("Launch automation is reserved for a future version; the setting is kept here so it has a stable home in the UI.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func band(_ name: String, value: Binding<Double>) -> some View {
        HStack {
            Text(name).frame(width: 58, alignment: .leading)
            Slider(value: value, in: -12...12)
            Text(String(format: "%+.0f dB", value.wrappedValue)).font(.caption.monospacedDigit()).frame(width: 55, alignment: .trailing)
        }
    }
}
