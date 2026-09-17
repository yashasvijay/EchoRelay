import Foundation

final class ThreeBandEQ {
    var settings = EQSettings() { didSet { resetIfBypassedChanged() } }

    private let lowAlpha: Float
    private let highAlpha: Float
    private var lowL: Float = 0
    private var lowR: Float = 0
    private var highL: Float = 0
    private var highR: Float = 0

    init(sampleRate: Float = 44_100) {
        lowAlpha = 1 - exp(-2 * Float.pi * 250 / sampleRate)
        highAlpha = 1 - exp(-2 * Float.pi * 4000 / sampleRate)
    }

    func process(_ input: Data) -> Data {
        guard settings.bass != 0 || settings.mid != 0 || settings.treble != 0 else { return input }
        var samples = [Int16](repeating: 0, count: input.count / MemoryLayout<Int16>.size)
        input.copyBytes(to: &samples, count: input.count)
        let bass = Float(pow(10, settings.bass / 20))
        let mid = Float(pow(10, settings.mid / 20))
        let treble = Float(pow(10, settings.treble / 20))

        var index = 0
        while index + 1 < samples.count {
            let xL = Float(samples[index]) / 32768
            let xR = Float(samples[index + 1]) / 32768
            lowL += lowAlpha * (xL - lowL)
            lowR += lowAlpha * (xR - lowR)
            highL += highAlpha * (xL - highL)
            highR += highAlpha * (xR - highR)
            let highBandL = xL - highL
            let highBandR = xR - highR
            let midBandL = xL - lowL - highBandL
            let midBandR = xR - lowR - highBandR
            let yL = lowL * bass + midBandL * mid + highBandL * treble
            let yR = lowR * bass + midBandR * mid + highBandR * treble
            samples[index] = Int16(clamping: Int32(max(-1, min(1, yL)) * 32767))
            samples[index + 1] = Int16(clamping: Int32(max(-1, min(1, yR)) * 32767))
            index += 2
        }
        return samples.withUnsafeBytes { Data($0) }
    }

    func reset() {
        lowL = 0; lowR = 0; highL = 0; highR = 0
    }

    private func resetIfBypassedChanged() {
        if settings.bass == 0 && settings.mid == 0 && settings.treble == 0 { reset() }
    }
}

final class SilenceMonitor {
    var enabled = false
    var thresholdDB: Float = -55
    var holdSeconds: Double = 5
    private var silentSeconds: Double = 0

    func update(rms: Float, duration: Double) -> Bool {
        guard enabled else { silentSeconds = 0; return false }
        let db = rms > 0 ? 20 * log10(rms) : -120
        if db <= thresholdDB { silentSeconds += duration } else { silentSeconds = 0 }
        if silentSeconds >= holdSeconds {
            silentSeconds = 0
            return true
        }
        return false
    }
}
