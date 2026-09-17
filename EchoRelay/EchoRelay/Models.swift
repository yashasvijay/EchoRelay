import Foundation
import ScreenCaptureKit

struct AudioApp: Identifiable, Hashable {
    let id: String
    let name: String
    let bundleIdentifier: String
    let processID: pid_t
}

enum SpeakerTransport: String, Hashable {
    case airPlay2
    case raop

    var label: String {
        switch self {
        case .airPlay2: return "AirPlay"
        case .raop: return "AirPlay 1"
        }
    }
}

struct Speaker: Identifiable, Hashable {
    let id: String
    var name: String
    var host: String
    var port: Int
    var transport: SpeakerTransport
    var txt: [String: String]
    var raopTXT: [String: String]

    var systemIcon: String {
        if name.localizedCaseInsensitiveContains("tv") { return "tv" }
        if name.localizedCaseInsensitiveContains("homepod") { return "hifispeaker.2" }
        return "hifispeaker.2"
    }
}

enum AudioSource: Hashable {
    case system
    case application(bundleIdentifier: String, name: String)

    var displayName: String {
        switch self {
        case .system: return "All Mac Audio"
        case .application(_, let name): return name
        }
    }
}

struct EQSettings: Equatable {
    var bass: Double = 0
    var mid: Double = 0
    var treble: Double = 0
}

struct OutputSettings: Identifiable {
    let id: UUID
    let speakerID: String
    var enabled: Bool = false
    var muted: Bool = false
    var volume: Double = 0.85
}
