import Foundation
import Darwin

final class AirPlaySession {
    let speaker: Speaker
    private let process: Process
    private let inputPipe = Pipe()
    private var commandHandle: FileHandle?
    private let commandLock = NSLock()
    private let writeQueue: DispatchQueue
    private let commandQueue = DispatchQueue(label: "EchoRelay.airplay.command")
    private var fifoPath: String?

    var onStatus: ((String) -> Void)?

    init(speaker: Speaker, helperURL: URL) throws {
        self.speaker = speaker
        self.process = Process()
        self.writeQueue = DispatchQueue(label: "EchoRelay.airplay.audio.\(speaker.id)", qos: .userInitiated)

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("EchoRelay-\(UUID().uuidString).pipe")
        try FileManager.default.createDirectory(at: temp.deletingLastPathComponent(), withIntermediateDirectories: true)
        let pipeURL = temp
        mkfifo(pipeURL.path, 0o600)
        fifoPath = pipeURL.path

        process.executableURL = helperURL
        var args = ["--samplerate", "44100", "--bitdepth", "16", "--channels", "2", "--volume", "85", "--cmdpipe", pipeURL.path]
        switch speaker.transport {
        case .airPlay2:
            args += ["--latency", "600", "--timing", "ntp", "--protocol", "auto", "--txt", speaker.txt.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " "), "--name", speaker.name, speaker.host]
        case .raop:
            args += ["--protocol", "raop"]
            for key in ["et", "md", "am", "pk", "pw", "cn"] {
                if let value = speaker.raopTXT[key] { args += ["--\(key)", value] }
            }
            args += ["--port", String(speaker.port), speaker.host]
        }
        if speaker.transport == .airPlay2 && speaker.port != 7000 { args += ["--port", String(speaker.port)] }
        process.arguments = args
        process.standardInput = inputPipe

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.emitLines(text)
        }
        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.emitLines(text)
        }
    }

    func start() throws {
        try process.run()
        commandQueue.async { [weak self] in
            guard let self, let path = self.fifoPath else { return }
            let handle = FileHandle(forWritingAtPath: path)
            self.commandLock.lock()
            self.commandHandle = handle
            self.commandLock.unlock()
        }
    }

    func sendPCM(_ data: Data) {
        guard process.isRunning, !data.isEmpty else { return }
        writeQueue.async { [weak self] in
            guard let self else { return }
            do {
                try self.inputPipe.fileHandleForWriting.write(contentsOf: data)
            } catch {
                self.onStatus?("Audio write failed: \(error.localizedDescription)")
            }
        }
    }

    func command(_ line: String) {
        commandQueue.async { [weak self] in
            guard let self else { return }
            self.commandLock.lock()
            let handle = self.commandHandle
            self.commandLock.unlock()
            guard let handle else { return }
            do {
                try handle.write(contentsOf: Data((line + "\n").utf8))
            } catch {
                self.onStatus?("Command failed: \(error.localizedDescription)")
            }
        }
    }

    func setVolume(_ value: Double) { command("VOLUME=\(Int(max(0, min(100, value * 100))))") }
    func standby() { command("ACTION=STANDBY") }
    func play() { command("ACTION=PLAY") }
    func pause() { command("ACTION=PAUSE") }
    func startAt(unixMilliseconds: Int64, join: Bool = false) {
        command("START_UNIX_MS=\(unixMilliseconds)")
        if join { command("START_JOIN=1") }
        command("ACTION=START")
    }
    func stop() {
        command("ACTION=STOP")
        process.terminate()
        closeCommandPipe()
    }

    private func emitLines(_ text: String) {
        for line in text.split(separator: "\n") where !line.isEmpty {
            onStatus?(String(line))
        }
    }

    private func closeCommandPipe() {
        commandLock.lock()
        try? commandHandle?.close()
        commandHandle = nil
        commandLock.unlock()
        if let fifoPath { unlink(fifoPath) }
        fifoPath = nil
    }

    deinit {
        closeCommandPipe()
        stdoutCleanup()
    }

    private func stdoutCleanup() {
        process.standardOutput as? Pipe
        process.standardError as? Pipe
    }
}
