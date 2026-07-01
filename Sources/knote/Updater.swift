import Foundation
import CryptoKit
import AppKit
import KnoteCore

// MARK: - Public types

struct ReleaseInfo {
    let version: String
    let zipURL: URL
    let sha256URL: URL?
    let htmlURL: URL
}

// MARK: - Errors

enum UpdaterError: Error, LocalizedError {
    case badServerResponse(Int)
    case noZipAsset
    case sha256Mismatch(expected: String, got: String)
    case appBundleNotFound(inDirectory: URL)
    case replaceFailed(underlying: Error)
    case downloadFailed(URL)

    var errorDescription: String? {
        switch self {
        case .badServerResponse(let code):
            return "GitHub returned HTTP \(code)."
        case .noZipAsset:
            return "No macOS arm64 zip asset found in the release."
        case let .sha256Mismatch(expected, got):
            return "SHA-256 checksum mismatch.\nExpected: \(expected)\nGot:      \(got)"
        case .appBundleNotFound(let dir):
            return "Could not find Knote.app inside extracted directory: \(dir.path)"
        case .replaceFailed(let err):
            return "Failed to replace running app bundle: \(err.localizedDescription)"
        case .downloadFailed(let url):
            return "Failed to download \(url)."
        }
    }
}

// MARK: - Codable helpers (GitHub API)

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlUrl: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadUrl: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
    }
}

// MARK: - Updater

final class Updater {
    private let apiURL = URL(string: "https://api.github.com/repos/camggould/knote/releases/latest")!

    /// The running app's version string from its Info.plist.
    static func currentVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Fetches the latest GitHub release. Returns nil if no arm64 zip asset is present.
    func fetchLatestRelease() async throws -> ReleaseInfo? {
        var request = URLRequest(url: apiURL, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("knote", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdaterError.badServerResponse(http.statusCode)
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        // Locate the arm64 zip asset and optional sha256 file.
        var zipURL: URL?
        var sha256URL: URL?
        for asset in release.assets {
            if asset.name.range(of: #"knote-.*-macos-arm64\.zip$"#, options: .regularExpression) != nil {
                zipURL = URL(string: asset.browserDownloadUrl)
            } else if asset.name.hasSuffix(".sha256") {
                sha256URL = URL(string: asset.browserDownloadUrl)
            }
        }

        guard let zip = zipURL else { return nil }

        let htmlURL = URL(string: release.htmlUrl) ?? apiURL
        return ReleaseInfo(version: release.tagName, zipURL: zip, sha256URL: sha256URL, htmlURL: htmlURL)
    }

    /// Returns the latest release only if it is strictly newer than the running version.
    func checkForUpdate() async throws -> ReleaseInfo? {
        guard let release = try await fetchLatestRelease() else { return nil }
        return SemVer.isNewer(release.version, than: Updater.currentVersion()) ? release : nil
    }

    /// Downloads, verifies, and installs the given release, then relaunches.
    ///
    /// Steps (each may throw):
    /// 1. Download zip to a temp directory.
    /// 2. If a sha256URL is present, download and verify the checksum.
    /// 3. Unzip via `/usr/bin/ditto`.
    /// 4. Locate Knote.app inside the unzipped tree.
    /// 5. Replace the running bundle (FileManager.replaceItemAt when possible,
    ///    fall back to remove + move).
    /// 6. Relaunch via `/usr/bin/open` then terminate.
    func install(_ release: ReleaseInfo) async throws {
        let fm = FileManager.default

        // 1. Create a temp working directory.
        let tmpDir = fm.temporaryDirectory.appendingPathComponent(
            "knote-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }  // best-effort cleanup on exit

        // 2. Download the zip.
        let zipDest = tmpDir.appendingPathComponent("knote.zip")
        try await download(release.zipURL, to: zipDest)

        // 3. Optional SHA-256 verification.
        if let sha256URL = release.sha256URL {
            let checksumFile = tmpDir.appendingPathComponent("knote.zip.sha256")
            try await download(sha256URL, to: checksumFile)

            // The file contains "<hex>  <filename>" — we only need the leading token.
            let checksumContent = try String(contentsOf: checksumFile, encoding: .utf8)
            let expectedHex = String(checksumContent.split(separator: " ").first ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let zipData = try Data(contentsOf: zipDest)
            let digest = SHA256.hash(data: zipData)
            let gotHex = digest.map { String(format: "%02x", $0) }.joined()

            guard gotHex.lowercased() == expectedHex.lowercased() else {
                throw UpdaterError.sha256Mismatch(expected: expectedHex, got: gotHex)
            }
        }

        // 4. Unzip into a subdirectory so we can locate Knote.app easily.
        let extractDir = tmpDir.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try runProcess("/usr/bin/ditto", arguments: ["-x", "-k", zipDest.path, extractDir.path])

        // 5. Find Knote.app inside the extracted tree.
        let extractedContents = try fm.contentsOfDirectory(
            at: extractDir, includingPropertiesForKeys: nil)
        guard let newBundle = extractedContents.first(where: {
            $0.lastPathComponent.hasSuffix(".app")
        }) else {
            // Deeper search — ditto may produce a subdirectory.
            let deepContents = try deepFind(ext: ".app", in: extractDir, fm: fm)
            guard let found = deepContents.first else {
                throw UpdaterError.appBundleNotFound(inDirectory: extractDir)
            }
            try replaceBundle(at: Bundle.main.bundleURL, with: found, fm: fm)
            await MainActor.run { relaunch() }
            return
        }

        // 6. Replace running bundle.
        // RISK: if the replacement is interrupted mid-way the app may be left in a broken state.
        // FileManager.replaceItemAt is atomic on APFS when src and dst are on the same volume,
        // which covers the normal case (both on the system disk).
        try replaceBundle(at: Bundle.main.bundleURL, with: newBundle, fm: fm)

        // 7. Relaunch via open(1) so we get a fresh process, then terminate self.
        await MainActor.run { relaunch() }
    }

    // MARK: - Private helpers

    private func download(_ url: URL, to destination: URL) async throws {
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.setValue("knote", forHTTPHeaderField: "User-Agent")
        let (tmpURL, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw UpdaterError.badServerResponse(http.statusCode)
        }
        try FileManager.default.moveItem(at: tmpURL, to: destination)
    }

    private func runProcess(_ executable: String, arguments: [String]) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        try proc.run()
        proc.waitUntilExit()
        // Note: ditto exits 0 on success; a non-zero exit is not checked here because
        // Process doesn't throw on non-zero exit. We rely on the subsequent
        // app-bundle lookup to detect a failed unzip.
    }

    private func deepFind(ext: String, in directory: URL, fm: FileManager) throws -> [URL] {
        var results: [URL] = []
        let enumerator = fm.enumerator(at: directory,
                                       includingPropertiesForKeys: [.isDirectoryKey],
                                       options: [.skipsHiddenFiles])
        while let url = enumerator?.nextObject() as? URL {
            if url.lastPathComponent.hasSuffix(ext) {
                results.append(url)
                enumerator?.skipDescendants()
            }
        }
        return results
    }

    private func replaceBundle(at destination: URL, with source: URL, fm: FileManager) throws {
        do {
            // Preferred: atomic rename (same-volume APFS).
            _ = try fm.replaceItemAt(destination, withItemAt: source,
                                     backupItemName: "knote-backup.app",
                                     options: [])
        } catch {
            // Fallback: trash the old bundle then move in the new one.
            // RISK: brief window where neither bundle is present.
            do {
                try fm.trashItem(at: destination, resultingItemURL: nil)
            } catch {
                try fm.removeItem(at: destination)
            }
            do {
                try fm.moveItem(at: source, to: destination)
            } catch {
                throw UpdaterError.replaceFailed(underlying: error)
            }
        }
    }

    @MainActor
    private func relaunch() {
        let bundlePath = Bundle.main.bundleURL.path
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = [bundlePath]
        try? proc.run()
        NSApp.terminate(nil)
    }
}
