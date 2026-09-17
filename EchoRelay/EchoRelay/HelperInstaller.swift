import Foundation

actor HelperInstaller {
    enum InstallError: LocalizedError {
        case noAsset
        case badArchive
        case downloadFailed

        var errorDescription: String? {
            switch self {
            case .noAsset: return "No compatible cliairplay release asset was found."
            case .badArchive: return "The downloaded AirPlay engine archive could not be unpacked."
            case .downloadFailed: return "The AirPlay engine download failed."
            }
        }
    }

    static let shared = HelperInstaller()
    private let repository = "music-assistant/airplay-cli"

    private var installDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EchoRelay", isDirectory: true)
    }

    func installedHelper() -> URL? {
        let url = installDirectory.appendingPathComponent("cliairplay")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    func installLatest(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let requestURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        var request = URLRequest(url: requestURL)
        request.setValue("EchoRelay/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (jsonData, _) = try await URLSession.shared.data(for: request)
        guard let release = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let assets = release["assets"] as? [[String: Any]] else { throw InstallError.noAsset }

        let archName = currentArchitectureSuffix()
        guard let asset = assets.first(where: {
            guard let name = $0["name"] as? String else { return false }
            return name.contains(archName) && !name.contains("checksum") && !name.contains("SHA256")
        }),
        let downloadString = asset["browser_download_url"] as? String,
        let assetName = asset["name"] as? String,
        let downloadURL = URL(string: downloadString) else { throw InstallError.noAsset }

        try FileManager.default.createDirectory(at: installDirectory, withIntermediateDirectories: true)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("EchoRelayInstall-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let destination = tempDir.appendingPathComponent(assetName)
        var downloadRequest = URLRequest(url: downloadURL)
        downloadRequest.setValue("EchoRelay/1.0", forHTTPHeaderField: "User-Agent")
        let (blob, response) = try await URLSession.shared.data(for: downloadRequest)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw InstallError.downloadFailed }
        try blob.write(to: destination)
        progress(0.65)

        let executable = try extractExecutable(from: destination, into: tempDir)
        let finalURL = installDirectory.appendingPathComponent("cliairplay")
        try? FileManager.default.removeItem(at: finalURL)
        try FileManager.default.copyItem(at: executable, to: finalURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: finalURL.path)
        progress(1)
        return finalURL
    }

    private func currentArchitectureSuffix() -> String {
        #if arch(arm64)
        return "macos-arm64"
        #else
        return "macos-x86_64"
        #endif
    }

    private func extractExecutable(from file: URL, into directory: URL) throws -> URL {
        let fm = FileManager.default
        let lower = file.path.lowercased()
        if lower.hasSuffix(".zip") {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = ["-q", file.path, "-d", directory.path]
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw InstallError.badArchive }
        } else if lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz") {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
            process.arguments = ["-xzf", file.path, "-C", directory.path]
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw InstallError.badArchive }
        } else {
            return file
        }

        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            throw InstallError.badArchive
        }
        for case let candidate as URL in enumerator where candidate.lastPathComponent.hasPrefix("cliairplay") {
            if fm.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        throw InstallError.badArchive
    }
}
