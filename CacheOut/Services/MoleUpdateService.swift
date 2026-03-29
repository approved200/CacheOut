import Foundation

// MARK: — Update state
// BUG-04 fix: The download/extract/activate flow has been removed.
// Gatekeeper blocks unsigned binaries downloaded at runtime — any `mo` binary
// downloaded from GitHub would be blocked with "can't check for malicious software".
// The bundled `mo` binary is versioned. Cache Out ships a new .app release (via
// Sparkle) whenever `mo` updates. This service now only reads and displays the
// bundled version — no network requests, no file writes, no Gatekeeper issues.
enum MoleUpdateState: Equatable {
    case upToDate(version: String)
    case unknown
}

// MARK: — MoleUpdateService
// Reads the bundled `mo` version and publishes it for display in Settings → Advanced.
// All download/install/activate functionality has been removed (see BUG-04 above).
@MainActor
class MoleUpdateService: ObservableObject {
    static let shared = MoleUpdateService()

    @Published var state: MoleUpdateState = .unknown

    private(set) var bundledVersion: String = "unknown"

    private init() { }

    // MARK: — Read bundled version (called once at launch)
    func checkForUpdate() async {
        bundledVersion = readBundledVersion()
        state = .upToDate(version: bundledVersion)
    }

    // MARK: — Active binary path (used by MoleService)
    var activeMolePath: String {
        Bundle.main.path(forResource: "mole-src/mole", ofType: nil)
            ?? Bundle.main.bundlePath + "/Contents/Resources/mole-src/mole"
    }

    // MARK: — Private helpers
    private func readBundledVersion() -> String {
        let moleScript = Bundle.main.bundlePath + "/Contents/Resources/mole-src/mole"
        guard let content = try? String(contentsOfFile: moleScript, encoding: .utf8)
        else { return "unknown" }
        for line in content.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("VERSION=") {
                return t.replacingOccurrences(of: "VERSION=", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            }
        }
        return "unknown"
    }
}
