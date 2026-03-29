import Foundation

// MARK: — Errors
enum MoleError: LocalizedError {
    case binaryNotFound
    case commandFailed(exitCode: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "The `mo` CLI was not found. Install it with: brew install tw93/tap/mole"
        case .commandFailed(let code, let out):
            return "mo exited with code \(code): \(out)"
        }
    }
}

// MARK: — MoleService
// Wraps the `mo` CLI via Swift's Process() API for one purpose only:
// running `mo purge --dry-run` and `mo purge` on behalf of PurgeViewModel.
//
// Everything else (clean, uninstall, status) is handled directly by the
// relevant ViewModels using FileManager and AppScanner — NOT this service.
// Do not add new public methods here without a real CLI implementation behind them.
actor MoleService {

    // Resolved lazily so MoleUpdateService has time to activate any downloaded update
    private var molePath: String {
        // 1. Updated copy in Application Support (downloaded by MoleUpdateService)
        // 2. Bundled copy inside .app Resources/mole-src/
        // 3. Homebrew fallback (for devs who have it installed)
        let candidates = [
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?.appendingPathComponent("CacheOut/mole-update/mole").path ?? "",
            Bundle.main.bundlePath + "/Contents/Resources/mole-src/mole",
            "/opt/homebrew/bin/mo",
            "/usr/local/bin/mo",
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
            ?? Bundle.main.bundlePath + "/Contents/Resources/mole-src/mole"
    }

    // The mole script expects its own directory as working directory
    // so lib/ and bin/ are discoverable relative to it
    private var moleWorkingDir: String {
        (molePath as NSString).deletingLastPathComponent
    }

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: molePath)
    }

    // MARK: — Core runner
    // CRITICAL: stdout/stderr pipes are read BEFORE waitUntilExit to prevent
    // pipe buffer deadlock. If the process writes > ~65KB, the pipe fills,
    // the child blocks on write, and waitUntilExit never returns.
    func run(_ args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: molePath)
            process.arguments     = args
            process.currentDirectoryURL = URL(fileURLWithPath: moleWorkingDir)

            var env = ProcessInfo.processInfo.environment
            env["TERM"]        = "dumb"
            env["NO_COLOR"]    = "1"
            env["MOLE_BIN_DIR"] = moleWorkingDir + "/bin"
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError  = stderrPipe

            do { try process.run() } catch {
                continuation.resume(throwing: MoleError.binaryNotFound)
                return
            }

            // Read pipes on a background thread FIRST, then wait for exit.
            // This pattern is required for correctness — do not reorder.
            DispatchQueue.global(qos: .utility).async {
                let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let out = String(data: outData, encoding: .utf8) ?? ""
                let err = String(data: errData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: out)
                } else {
                    continuation.resume(throwing:
                        MoleError.commandFailed(exitCode: process.terminationStatus,
                                                output: err.isEmpty ? out : err))
                }
            }
        }
    }

    // MARK: — Public commands

    func scanForCleanup() async throws -> ScanResult {
        let out = try await run(["clean", "--dry-run"])
        return MoleOutputParser.parseCleanDryRun(out)
    }

    // NOTE: clean(categories:) has been intentionally removed.
    // CleanViewModel.startCleaning() performs its own per-path trashItem loop
    // over selected categories — it never calls MoleService for the clean flow.
    // The mo CLI does not support per-category flags, so exposing a categories
    // parameter here would silently discard the user's checkbox selections.
    // Keeping a broken method in a file-deletion tool is a safety hazard.

    func purgeDryRun(paths: [String] = []) async throws -> [ProjectArtifact] {
        var args = ["purge", "--dry-run"]
        if !paths.isEmpty { args += ["--paths", paths.joined(separator: ",")] }
        let out = try await run(args)
        return MoleOutputParser.parsePurge(out)
    }

    func purge(paths: [String] = []) async throws {
        var args = ["purge"]
        if !paths.isEmpty { args += ["--paths", paths.joined(separator: ",")] }
        _ = try await run(args)
    }
}

// MARK: — Stub models used by parser (real models live in Models.swift & ViewModels)
struct ScanResult {
    var totalBytes: Int64
    var items: [String]
}

struct ProjectArtifact {
    let name: String
    let path: String
    let size: Int64
}
