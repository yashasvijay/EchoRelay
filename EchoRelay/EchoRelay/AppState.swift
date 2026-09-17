import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var source: AudioSource = .system
    @Published var applications: [AudioApp] = []
    @Published var selectedSpeakerIDs = Set<String>()
    @Published var outputSettings: [String: OutputSettings] = [:]
    @Published var transmitting = false
    @Published var installingHelper = false
    @Published var installProgress: Double = 0
    @Published var helperAvailable = false
    @Published var statusMessage = "Ready"
    @Published var inputLevel: Float = 0
    @Published var eq = EQSettings()
    @Published var silenceMonitorEnabled = false { didSet { silenceMonitor.enabled = silenceMonitorEnabled } }
    @Published var autoTransmit = false

    let browser = BonjourBrowser()
    private let capture = SystemAudioCapture()
    private let eqProcessor = ThreeBandEQ()
    private let silenceMonitor = SilenceMonitor()
    private var sessions: [String: AirPlaySession] = [:]
    private var helperURL: URL?
    private var cancellables: Set<AnyCancellable> = []
    private var didLoadApps = false

    init() {
        capture.onAudio = { [weak self] data in
            guard let self else { return }
            let processed = self.eqProcessor.process(data)
            for session in self.sessions.values { session.sendPCM(processed) }
        }
        capture.onLevel = { [weak self] level in
            Task { @MainActor in
                guard let self else { return }
                self.inputLevel = level
                let duration = Double(44100 > 0 ? 1024 : 1024) / 44100.0
                if self.silenceMonitor.update(rms: level, duration: duration) {
                    await self.stopTransmission(reason: "Stopped after prolonged silence")
                }
            }
        }
        NotificationCenter.default.publisher(for: .echoRelayError)
            .sink { [weak self] note in
                let message = note.object as? String ?? "An audio error occurred."
                Task { @MainActor in self?.statusMessage = message }
            }
            .store(in: &cancellables)
        browser.$speakers
            .sink { [weak self] speakers in
                guard let self else { return }
                for speaker in speakers where self.outputSettings[speaker.id] == nil {
                    self.outputSettings[speaker.id] = OutputSettings(id: UUID(), speakerID: speaker.id)
                }
            }
            .store(in: &cancellables)
        eqProcessor.settings = eq
    }

    func appear() async {
        helperURL = await HelperInstaller.shared.installedHelper()
        helperAvailable = helperURL != nil
        browser.start()
        await refreshApplications()
    }

    func refreshApplications() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let current = content.applications.compactMap { app -> AudioApp? in
                let name = app.applicationName
                let bundle = app.bundleIdentifier
                guard !name.isEmpty, !bundle.isEmpty else { return nil }
                return AudioApp(id: bundle, name: name, bundleIdentifier: bundle, processID: app.processID)
            }
            applications = current.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            didLoadApps = true
        } catch {
            statusMessage = "Grant Screen & System Audio Recording permission to enumerate apps."
        }
    }

    func installHelper() async {
        guard !installingHelper else { return }
        installingHelper = true
        installProgress = 0
        statusMessage = "Installing AirPlay engine…"
        defer { installingHelper = false }
        do {
            let url = try await HelperInstaller.shared.installLatest { [weak self] progress in
                Task { @MainActor in self?.installProgress = progress }
            }
            helperURL = url
            helperAvailable = true
            statusMessage = "AirPlay engine ready"
        } catch {
            statusMessage = "AirPlay engine install failed: \(error.localizedDescription)"
        }
    }

    func toggleSpeaker(_ speaker: Speaker) {
        if selectedSpeakerIDs.contains(speaker.id) { selectedSpeakerIDs.remove(speaker.id) }
        else { selectedSpeakerIDs.insert(speaker.id) }
    }

    func isSelected(_ speaker: Speaker) -> Bool { selectedSpeakerIDs.contains(speaker.id) }

    func setVolume(_ speakerID: String, _ value: Double) {
        var current = outputSettings[speakerID] ?? OutputSettings(id: UUID(), speakerID: speakerID)
        current.volume = value
        outputSettings[speakerID] = current
        sessions[speakerID]?.setVolume(value)
    }

    func toggleMute(_ speakerID: String) {
        var current = outputSettings[speakerID] ?? OutputSettings(id: UUID(), speakerID: speakerID)
        current.muted.toggle()
        outputSettings[speakerID] = current
        sessions[speakerID]?.setVolume(current.muted ? 0 : current.volume)
    }

    func updateEQ(_ newValue: EQSettings) {
        eq = newValue
        eqProcessor.settings = newValue
    }

    func startTransmission() async {
        guard selectedSpeakerIDs.count > 0 else {
            statusMessage = "Select at least one AirPlay speaker."
            return
        }
        guard let helperURL else {
            statusMessage = "Install the AirPlay engine first."
            return
        }
        transmitting = true
        statusMessage = "Connecting to speakers…"

        for speaker in browser.speakers where selectedSpeakerIDs.contains(speaker.id) {
            if sessions[speaker.id] != nil { continue }
            do {
                let session = try AirPlaySession(speaker: speaker, helperURL: helperURL)
                session.onStatus = { [weak self] line in
                    Task { @MainActor in
                        if line.contains("connected") || line.contains("route=") || line.contains("started") {
                            self?.statusMessage = line
                        }
                    }
                }
                try session.start()
                let setting = outputSettings[speaker.id] ?? OutputSettings(id: UUID(), speakerID: speaker.id)
                session.setVolume(setting.muted ? 0 : setting.volume)
                sessions[speaker.id] = session
            } catch {
                statusMessage = "Could not connect to \(speaker.name): \(error.localizedDescription)"
            }
        }

        do {
            eqProcessor.reset()
            try await capture.start(source: source)
            statusMessage = "Buffering audio…"
            let startTime = Int64(Date().timeIntervalSince1970 * 1000) + 1500
            try await Task.sleep(for: .milliseconds(900))
            for session in sessions.values { session.startAt(unixMilliseconds: startTime) }
            statusMessage = "Transmitting"
        } catch {
            transmitting = false
            for session in sessions.values { session.stop() }
            sessions.removeAll()
            statusMessage = error.localizedDescription
        }
    }

    func stopTransmission(reason: String? = nil) async {
        await capture.stop()
        for session in sessions.values { session.stop() }
        sessions.removeAll()
        transmitting = false
        statusMessage = reason ?? "Ready"
    }

    func restartTransmission() async {
        await stopTransmission()
        await startTransmission()
    }

    func sourceChanged() {
        guard transmitting else { return }
        Task { await restartTransmission() }
    }

    func selectAll() { selectedSpeakerIDs = Set(browser.speakers.map(\.id)) }
    func selectNone() { selectedSpeakerIDs.removeAll() }
}
