# Contributing to Cache Out

Cache Out is open source and welcomes contributions. This guide covers everything you need to get started.

---

## Requirements

- macOS 26 (Tahoe) or later
- Xcode 16+
- Apple Silicon or Intel Mac

---

## Getting started

```bash
git clone https://github.com/approved200/CacheOut
cd "Cache Out"
bash setup-hooks.sh          # install git hooks (one-time, per clone)
python3 generate_xcodeproj.py
open "Cache Out.xcodeproj"
```

The `setup-hooks.sh` step installs a pre-commit hook that automatically re-runs `generate_xcodeproj.py` whenever you stage a `.swift` file, so `project.pbxproj` stays in sync without any manual step.

In Xcode: select the **Cache Out** scheme → set your Team under Signing & Capabilities → ⌘R.

> **Note:** The app requires Full Disk Access to scan cache folders. Go to System Settings → Privacy & Security → Full Disk Access → Cache Out.

---

## Running the tests

```bash
xcodebuild test \
  -project "Cache Out.xcodeproj" \
  -scheme CacheOutTests \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

Or in Xcode: select the **CacheOutTests** scheme → ⌘U.

---

## Adding a new .swift file

If you ran `setup-hooks.sh` after cloning, this is handled automatically — the pre-commit hook re-runs `generate_xcodeproj.py` and stages the updated `project.pbxproj` whenever you commit a `.swift` change.

If you skipped the hook setup, run `python3 generate_xcodeproj.py` manually after adding or removing any `.swift` file.

---

## Code style

- Swift 6 strict concurrency — no `@unchecked Sendable` without a comment explaining why
- All ViewModels on `@MainActor`; scanners run on `Task.detached(priority: .userInitiated)`
- Zero hardcoded hex colors — only semantic Apple colors (`Color(nsColor: .labelColor)`, `.accentColor`, etc.)
- Sentence case for all UI strings
- Comments on non-obvious code paths; no commented-out code in PRs

---

## Submitting a PR

1. Fork the repo and create a branch: `git checkout -b feature/your-feature`
2. Make your changes with focused commits
3. Run the tests (`xcodebuild test`) — all tests must pass
4. Open a pull request against `main` with a clear description

### What makes a good PR

- Bug fixes with a test that reproduces the bug first
- Features that fit one of the existing tabs (Clean, Uninstall, Analyze, etc.)
- UI changes that follow Apple's HIG and use the existing design language

### What we won't merge

- New external dependencies without discussion (open an issue first)
- Features that require the Mac App Store sandbox (the app is distributed outside MAS intentionally)
- Anything that touches Trash operations without a dry-run test

---

## Reporting a bug

Open a GitHub issue with:
- macOS version
- Cache Out version
- Steps to reproduce
- Expected vs actual behavior
- Logs from `~/Library/Logs/CacheOut/` if available

---

## License

By contributing you agree that your code will be released under the [MIT License](LICENSE).
