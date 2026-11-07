import Foundation
import AppKit
import Combine

/// Manages checking for newer releases from GitHub Releases API
@MainActor
public final class UpdateManager: ObservableObject {
    public static let shared = UpdateManager()

    // MARK: - Configuration
    private let repoOwner = "amirHHP"
    private let repoName = "mirzabenevis-macOS"
    private let lastCheckKey = "mirza.lastUpdateCheckDate"
    private let backgroundCheckInterval: TimeInterval = 86400 // 24 hours

    // MARK: - Published State
    @Published public var isChecking: Bool = false
    @Published public var isUpdateAvailable: Bool = false
    @Published public var latestVersion: String? = nil
    @Published public var releaseTitle: String? = nil
    @Published public var releaseNotes: String? = nil
    @Published public var downloadURL: URL? = nil
    @Published public var releasePageURL: URL? = nil
    @Published public var checkStatusMessage: String? = nil
    @Published public var lastCheckedDate: Date? = nil

    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private init() {
        lastCheckedDate = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
    }

    // MARK: - Check for Updates
    public func checkForUpdates(isUserInitiated: Bool = false) async {
        guard !isChecking else { return }

        // Throttle automatic background checks to avoid GitHub API rate limiting
        if !isUserInitiated {
            if let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date,
               Date().timeIntervalSince(last) < backgroundCheckInterval {
                return
            }
        }

        isChecking = true
        if isUserInitiated {
            checkStatusMessage = "در حال بررسی..."
        }

        defer {
            isChecking = false
            let now = Date()
            lastCheckedDate = now
            UserDefaults.standard.set(now, forKey: lastCheckKey)
        }

        guard let url = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest") else {
            if isUserInitiated {
                checkStatusMessage = "آدرس گیت‌هاب نامعتبر است."
            }
            return
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("MirzaBenevis-MacApp", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                if isUserInitiated { checkStatusMessage = "خطا در برقراری ارتباط." }
                return
            }

            guard httpResponse.statusCode == 200 else {
                if isUserInitiated {
                    if httpResponse.statusCode == 404 {
                        checkStatusMessage = "هنوز ریلیزی در گیت‌هاب ثبت نشده است."
                    } else if httpResponse.statusCode == 403 {
                        checkStatusMessage = "محدودیت موقت درخواست به گیت‌هاب."
                    } else {
                        checkStatusMessage = "کد وضعیت گیت‌هاب: \(httpResponse.statusCode)"
                    }
                }
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let remoteTag = release.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))
            let current = currentVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\n\r"))

            latestVersion = remoteTag
            releaseTitle = release.name
            releaseNotes = release.body
            releasePageURL = URL(string: release.htmlUrl)

            // Look for DMG download asset, fallback to ZIP, fallback to release page
            if let dmgAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) {
                downloadURL = URL(string: dmgAsset.browserDownloadUrl)
            } else if let zipAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }) {
                downloadURL = URL(string: zipAsset.browserDownloadUrl)
            } else {
                downloadURL = releasePageURL
            }

            if Self.isNewer(remote: remoteTag, current: current) {
                isUpdateAvailable = true
                if isUserInitiated {
                    checkStatusMessage = "نسخه جدید \(remoteTag) موجود است!"
                }
            } else {
                isUpdateAvailable = false
                if isUserInitiated {
                    checkStatusMessage = "شما از آخرین نسخه استفاده می‌کنید (v\(current))."
                }
            }
        } catch {
            if isUserInitiated {
                checkStatusMessage = "خطا در ارتباط با اینترنت."
            }
        }
    }

    // MARK: - Open Download
    public func openDownload() {
        guard let targetURL = downloadURL ?? releasePageURL else { return }
        NSWorkspace.shared.open(targetURL)
    }

    // MARK: - Semantic Version Comparison
    public static func isNewer(remote: String, current: String) -> Bool {
        remote.compare(current, options: .numeric) == .orderedDescending
    }
}

// MARK: - Decodable Models
private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let body: String?
    let htmlUrl: String
    let assets: [GitHubAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
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
