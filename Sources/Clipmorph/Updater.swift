import AppKit
import CryptoKit
import Security

struct AppRelease {
    var version: String
    var notes: String
    var pageURL: URL
    var downloadURL: URL
    /// Hex SHA-256 of the zip, as published by GitHub for the release asset.
    var sha256: String?
}

struct UpdateError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// Finds, downloads, verifies and installs new releases from GitHub.
///
/// An update is only installed when its zip matches GitHub's published checksum and the app inside
/// satisfies this app's own code-signing requirement (same bundle ID, same signing certificate).
enum UpdateService {
    static let assetName = "Clipmorph.zip"

    static var feedURL: URL {
        // Overridable for testing against a local feed.
        if let override = UserDefaults.standard.string(forKey: "UpdateFeedURL"), let url = URL(string: override) {
            return url
        }
        return URL(string: "https://api.github.com/repos/nicop-hd/Clipmorph/releases/latest")!
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    // MARK: - Checking

    static func fetchLatest() async throws -> AppRelease {
        var request = URLRequest(url: feedURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Clipmorph/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw UpdateError(message: "Couldn't check for updates (HTTP \(status)).")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = json["assets"] as? [[String: Any]],
              let asset = assets.first(where: { $0["name"] as? String == assetName }),
              let download = (asset["browser_download_url"] as? String).flatMap(URL.init(string:)) else {
            throw UpdateError(message: "The latest release doesn't include \(assetName).")
        }

        let digest = asset["digest"] as? String
        return AppRelease(
            version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
            notes: json["body"] as? String ?? "",
            pageURL: page,
            downloadURL: download,
            sha256: digest?.hasPrefix("sha256:") == true ? String(digest!.dropFirst(7)).lowercased() : nil
        )
    }

    /// Compares dotted versions numerically: "0.10.0" is newer than "0.9.3".
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - Installing

    /// Replaces the running app bundle with the release. Returns the installed app's URL.
    static func install(_ release: AppRelease) async throws -> URL {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.path.contains("/AppTranslocation/") {
            throw UpdateError(message: "Move Clipmorph to your Applications folder and open it from there, then try again.")
        }
        guard FileManager.default.isWritableFile(atPath: bundleURL.deletingLastPathComponent().path) else {
            throw UpdateError(message: "Clipmorph can't write to \(bundleURL.deletingLastPathComponent().path).")
        }
        let requirement = try ownSigningRequirement()

        // A scratch folder on the same volume, so the final swap is a rename.
        let workDir = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                  appropriateFor: bundleURL, create: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let (downloaded, response) = try await URLSession.shared.download(from: release.downloadURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateError(message: "The download failed.")
        }
        let zipURL = workDir.appendingPathComponent(assetName)
        try FileManager.default.moveItem(at: downloaded, to: zipURL)

        if let expected = release.sha256 {
            let actual = SHA256.hash(data: try Data(contentsOf: zipURL)).map { String(format: "%02x", $0) }.joined()
            guard actual == expected else {
                throw UpdateError(message: "The downloaded file is damaged (checksum mismatch).")
            }
        }

        let extractDir = workDir.appendingPathComponent("extracted")
        try run("/usr/bin/ditto", ["-x", "-k", zipURL.path, extractDir.path])
        let newApp = extractDir.appendingPathComponent("Clipmorph.app")
        guard FileManager.default.fileExists(atPath: newApp.path) else {
            throw UpdateError(message: "The download doesn't contain Clipmorph.app.")
        }

        try verifySignature(of: newApp, against: requirement)

        let newInfo = Bundle(url: newApp)?.infoDictionary
        guard newInfo?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              let newVersion = newInfo?["CFBundleShortVersionString"] as? String,
              isVersion(newVersion, newerThan: currentVersion) else {
            throw UpdateError(message: "The downloaded app isn't a newer version of Clipmorph.")
        }

        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
        guard let installed = try FileManager.default.replaceItemAt(bundleURL, withItemAt: newApp) else {
            throw UpdateError(message: "Couldn't replace the installed app.")
        }
        return installed
    }

    /// Opens the app at `url` once this process has exited, then quits.
    @MainActor
    static func relaunch(_ url: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "while /bin/kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", url.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    // MARK: - Code signing

    private static func ownSigningRequirement() throws -> SecRequirement {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement else {
            throw UpdateError(message: "Couldn't read Clipmorph's own code signature.")
        }
        // An ad-hoc signature has no certificate, so there would be nothing to check the update against.
        let certificates = (info as? [String: Any])?[kSecCodeInfoCertificates as String] as? [Any] ?? []
        guard !certificates.isEmpty else {
            throw UpdateError(message: "This copy of Clipmorph isn't signed with the release certificate, so it can't verify updates. Download the new version from GitHub instead.")
        }
        return requirement
    }

    private static func verifySignature(of app: URL, against requirement: SecRequirement) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            throw UpdateError(message: "The downloaded app isn't signed.")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(staticCode, flags, requirement) == errSecSuccess else {
            throw UpdateError(message: "The downloaded app isn't signed by the Clipmorph developer, so it wasn't installed.")
        }
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError(message: "\(URL(fileURLWithPath: tool).lastPathComponent) failed (\(process.terminationStatus)).")
        }
        return process.terminationStatus
    }
}

/// Schedules background checks and presents update prompts.
@MainActor
final class UpdateController {
    private let settings: SettingsStore
    private var timer: Timer?
    private var isBusy = false
    /// Called when busy state changes, so the menu item can reflect it.
    var onBusyChange: ((Bool) -> Void)?

    private let lastCheckKey = "lastUpdateCheck"
    private let skippedVersionKey = "skippedUpdateVersion"

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        // Shortly after launch, then hourly ticks that only check once a day.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
    }

    private func checkIfDue() {
        guard settings.checkForUpdates else { return }
        let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 24 * 3600 else { return }
        check(userInitiated: false)
    }

    func check(userInitiated: Bool) {
        guard !isBusy else { return }
        setBusy(true)
        Task {
            defer { setBusy(false) }
            do {
                let release = try await UpdateService.fetchLatest()
                UserDefaults.standard.set(Date(), forKey: lastCheckKey)
                let current = UpdateService.currentVersion
                guard UpdateService.isVersion(release.version, newerThan: current) else {
                    if userInitiated { showUpToDate(current) }
                    return
                }
                if !userInitiated, UserDefaults.standard.string(forKey: skippedVersionKey) == release.version { return }
                offer(release, allowSkip: !userInitiated)
            } catch {
                if userInitiated { showError(error) }
            }
        }
    }

    private func offer(_ release: AppRelease, allowSkip: Bool) {
        let alert = NSAlert()
        alert.messageText = "Clipmorph \(release.version) is available"
        var info = "You have version \(UpdateService.currentVersion)."
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            info += "\n\n" + (notes.count > 700 ? notes.prefix(700) + "…" : notes)
        }
        alert.informativeText = info
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        if allowSkip { alert.addButton(withTitle: "Skip This Version") }

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            install(release)
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(release.version, forKey: skippedVersionKey)
        default:
            break
        }
    }

    private func install(_ release: AppRelease) {
        setBusy(true)
        Task {
            do {
                let installed = try await UpdateService.install(release)
                UpdateService.relaunch(installed)
            } catch {
                setBusy(false)
                showError(error, release: release)
            }
        }
    }

    private func showUpToDate(_ version: String) {
        let alert = NSAlert()
        alert.messageText = "You're up to date"
        alert.informativeText = "Clipmorph \(version) is the latest version."
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showError(_ error: Error, release: AppRelease? = nil) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = release == nil ? "Couldn't check for updates" : "Couldn't install the update"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        if release != nil { alert.addButton(withTitle: "Open Download Page") }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn, let release {
            NSWorkspace.shared.open(release.pageURL)
        }
    }

    private func setBusy(_ busy: Bool) {
        isBusy = busy
        onBusyChange?(busy)
    }
}

@MainActor
enum UpdateCLI {
    static func run(install: Bool) -> Never {
        Task {
            do {
                let release = try await UpdateService.fetchLatest()
                let current = UpdateService.currentVersion
                let newer = UpdateService.isVersion(release.version, newerThan: current)
                print("installed \(current), latest \(release.version)\(newer ? " (newer)" : ""), sha256 \(release.sha256 ?? "none")")
                if install && newer {
                    let url = try await UpdateService.install(release)
                    print("installed update at \(url.path)")
                }
                exit(0)
            } catch {
                print("error: \(error.localizedDescription)")
                exit(1)
            }
        }
        RunLoop.main.run()
        exit(0)
    }
}
