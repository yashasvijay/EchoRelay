@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

final class SystemAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    enum CaptureError: LocalizedError {
        case noDisplay
        case applicationNotFound(String)
        case startFailed(Error)

        var errorDescription: String? {
            switch self {
            case .noDisplay: return "No display is available for system-audio capture."
            case .applicationNotFound(let bundle): return "The app \(bundle) is no longer available to capture."
            case .startFailed(let error): return "Could not start audio capture: \(error.localizedDescription)"
            }
        }
    }

    private let queue = DispatchQueue(label: "EchoRelay.audio.capture", qos: .userInitiated)
    private var stream: SCStream?
    private var isRunning = false
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                             sampleRate: 44_100,
                                             channels: 2,
                                             interleaved: true)!
    var onAudio: ((Data) -> Void)?
    var onLevel: ((Float) -> Void)?

    func start(source: AudioSource) async throws {
        guard !isRunning else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else { throw CaptureError.noDisplay }

        let filter: SCContentFilter
        switch source {
        case .system:
            filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        case .application(let bundleIdentifier, _):
            guard let app = content.applications.first(where: { $0.bundleIdentifier == bundleIdentifier }) else {
                throw CaptureError.applicationNotFound(bundleIdentifier)
            }
            filter = SCContentFilter(display: display, includingApplications: [app], exceptingWindows: [])
        }

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false

        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        do {
            try await newStream.startCapture()
            stream = newStream
            isRunning = true
        } catch {
            throw CaptureError.startFailed(error)
        }
    }

    func stop() async {
        guard let stream else { return }
        isRunning = false
        try? await stream.stopCapture()
        self.stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, isRunning else { return }
        guard let pcm = convert(sampleBuffer) else { return }
        let level = Self.rms16(pcm)
        let output = onAudio
        let levelHandler = onLevel
        DispatchQueue.main.async {
            levelHandler?(level)
            output?(pcm)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        isRunning = false
        let message = "Audio capture stopped: \(error.localizedDescription)"
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .echoRelayError, object: message)
        }
    }

    private func convert(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              CMSampleBufferGetNumSamples(sampleBuffer) > 0 else { return nil }

        var asbd = asbdPointer.pointee
        guard let inputFormat = AVAudioFormat(streamDescription: &asbd) else { return nil }

        var needed = 0
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &needed,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            blockBufferOut: nil
        ) == noErr, needed > 0 else { return nil }

        let storage = UnsafeMutableRawPointer.allocate(byteCount: needed, alignment: 16)
        defer { storage.deallocate() }
        let list = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        var retainedBlock: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: list,
            bufferListSize: needed,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &retainedBlock
        ) == noErr, retainedBlock != nil else { return nil }

        return withExtendedLifetime(retainedBlock) {
            guard let input = AVAudioPCMBuffer(pcmFormat: inputFormat, bufferListNoCopy: list),
                  let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else { return nil }
            let ratio = targetFormat.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio + 1024)
            guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: max(capacity, 1024)) else { return nil }

            var supplied = false
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
                if supplied {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                supplied = true
                outStatus.pointee = .haveData
                return input
            }

            guard (status == .haveData || status == .endOfStream || status == .inputRanDry), conversionError == nil,
                  output.frameLength > 0,
                  let audioBuffer = output.audioBufferList.pointee.mBuffers.mData else { return nil }
            let byteCount = Int(output.frameLength) * Int(targetFormat.streamDescription.pointee.mBytesPerFrame)
            return Data(bytes: audioBuffer, count: byteCount)
        }
    }

    private static func rms16(_ data: Data) -> Float {
        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            guard !samples.isEmpty else { return 0 }
            var sum: Double = 0
            for value in samples {
                let normalized = Double(value) / 32768.0
                sum += normalized * normalized
            }
            return Float(sqrt(sum / Double(samples.count)))
        }
    }
}

extension Notification.Name {
    static let echoRelayError = Notification.Name("EchoRelayError")
}
