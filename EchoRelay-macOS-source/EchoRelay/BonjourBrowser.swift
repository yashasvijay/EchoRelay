import Foundation
import Darwin

@MainActor
final class BonjourBrowser: NSObject, ObservableObject {
    @Published private(set) var speakers: [Speaker] = []
    @Published private(set) var scanning = false

    private var browsers: [NetServiceBrowser] = []
    private var pendingServices: [String: NetService] = [:]
    private var records: [String: ServiceRecord] = [:]

    private struct ServiceRecord {
        var name: String
        var host: String?
        var port: Int
        var txt: [String: String]
        var kind: SpeakerTransport
        var serviceKey: String
    }

    func start() {
        stop()
        scanning = true
        let types = ["_airplay._tcp.", "_raop._tcp."]
        for type in types {
            let browser = NetServiceBrowser()
            browser.delegate = self
            browsers.append(browser)
            browser.searchForServices(ofType: type, inDomain: "local.")
        }
    }

    func stop() {
        for browser in browsers { browser.stop() }
        browsers.removeAll()
        pendingServices.removeAll()
        scanning = false
    }

    nonisolated private func displayName(for service: NetService) -> String {
        if let at = service.name.firstIndex(of: "@") {
            return String(service.name[service.name.index(after: at)...])
        }
        return service.name
    }

    nonisolated private func txtDictionary(_ data: Data?) -> [String: String] {
        guard let data else { return [:] }
        let raw = NetService.dictionary(fromTXTRecord: data)
        var result: [String: String] = [:]
        for (key, value) in raw {
            if let string = String(data: value, encoding: .utf8) {
                result[key] = string
            } else {
                result[key] = value.map { String(format: "%02x", $0) }.joined()
            }
        }
        return result
    }

    nonisolated private func ipv4Address(from data: Data) -> String? {
        data.withUnsafeBytes { rawBuffer -> String? in
            guard let base = rawBuffer.baseAddress else { return nil }
            let family = base.assumingMemoryBound(to: sockaddr.self).pointee.sa_family
            if family == sa_family_t(AF_INET) {
                var addr = base.assumingMemoryBound(to: sockaddr_in.self).pointee
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                let result = inet_ntop(AF_INET, &addr.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                guard result != nil else { return nil }
                return String(cString: buffer)
            }
            return nil
        }
    }

    nonisolated private func resolvedIP(for service: NetService) -> String? {
        if let address = service.addresses?.compactMap({ ipv4Address(from: $0) }).first {
            return address
        }
        return service.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private func merge(record: ServiceRecord) {
        records[record.serviceKey] = record
        var merged: [String: Speaker] = [:]

        for item in records.values {
            guard let host = item.host else { continue }
            let normalizedName = item.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let key = normalizedName + "|" + host

            if var speaker = merged[key] {
                if item.kind == .airPlay2 {
                    speaker.transport = .airPlay2
                    speaker.port = item.port
                    speaker.txt = item.txt
                }
                if item.kind == .raop { speaker.raopTXT = item.txt }
                merged[key] = speaker
            } else {
                merged[key] = Speaker(
                    id: key,
                    name: item.name,
                    host: host,
                    port: item.port,
                    transport: item.kind,
                    txt: item.kind == .airPlay2 ? item.txt : [:],
                    raopTXT: item.kind == .raop ? item.txt : [:]
                )
            }
        }

        speakers = merged.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

extension BonjourBrowser: NetServiceBrowserDelegate {
    nonisolated func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        Task { @MainActor in self.scanning = true }
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        Task { @MainActor in self.scanning = false }
    }

    nonisolated func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        Task { @MainActor in self.scanning = false }
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        let key = "\(service.type)|\(service.name)"
        Task { @MainActor in self.pendingServices[key] = service }
        service.resolve(withTimeout: 5)
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let key = "\(service.type)|\(service.name)"
        Task { @MainActor in
            self.pendingServices.removeValue(forKey: key)
            self.records.removeValue(forKey: key)
            self.rebuild()
        }
    }

    private func rebuild() {
        var merged: [String: Speaker] = [:]
        for item in records.values {
            guard let host = item.host else { continue }
            let key = item.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) + "|" + host
            if var current = merged[key] {
                if item.kind == .airPlay2 {
                    current.transport = .airPlay2
                    current.port = item.port
                    current.txt = item.txt
                } else {
                    current.raopTXT = item.txt
                }
                merged[key] = current
            } else {
                merged[key] = Speaker(id: key, name: item.name, host: host, port: item.port,
                                      transport: item.kind,
                                      txt: item.kind == .airPlay2 ? item.txt : [:],
                                      raopTXT: item.kind == .raop ? item.txt : [:])
            }
        }
        speakers = merged.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

extension BonjourBrowser: NetServiceDelegate {
    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        let key = "\(sender.type)|\(sender.name)"
        let kind: SpeakerTransport = sender.type.contains("airplay") ? .airPlay2 : .raop
        let txt = txtDictionary(sender.txtRecordData())
        let record = ServiceRecord(name: displayName(for: sender), host: resolvedIP(for: sender), port: sender.port,
                                   txt: txt, kind: kind, serviceKey: key)
        Task { @MainActor in self.merge(record: record) }
    }

    nonisolated func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        let key = "\(sender.type)|\(sender.name)"
        Task { @MainActor in self.pendingServices.removeValue(forKey: key) }
    }
}
