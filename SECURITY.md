# Security Policy

Cache Out is a disk-cleaning utility that can delete files. This document explains our security boundaries, how to report vulnerabilities, and known limitations.

---

## Supported versions

| Version | Supported |
|---------|-----------|
| 1.x     | ✅ Yes     |

---

## Reporting a vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Report security issues privately by emailing the maintainer or opening a [GitHub Security Advisory](https://github.com/apoorv/cache-out/security/advisories/new).

Please include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact (what an attacker could achieve)
- Suggested fix if you have one

You will receive a response within 72 hours. Confirmed vulnerabilities will be patched and disclosed publicly after a fix is available.

---

## Safety boundaries

Cache Out is designed with safety-first defaults for all file-deletion operations:

**Trash, not delete.** All file removal goes through `FileManager.trashItem(at:resultingItemURL:)`. Files are moved to the macOS Trash, not permanently deleted. Users can recover anything within a session using the "Put back" buttons on the Clean and Duplicates tabs.

**Dry-run mode.** Settings → Advanced → Dry Run Mode scans and reports without writing anything to disk. The integration test suite verifies this: if dry-run mode is on, zero bytes are moved to Trash regardless of what the user selects.

**Selection isolation.** Only explicitly selected categories/files are cleaned. The integration test suite verifies that deselected categories are never touched.

**No root.** Cache Out never escalates privileges. It requires Full Disk Access (a macOS TCC permission) but runs as the current user with no `sudo` or privilege escalation.

**Bundled CLI.** The included `mole` script runs as the current user. It is bundled inside the app bundle and cannot be updated at runtime (to prevent Gatekeeper from blocking downloaded unsigned binaries).

---

## Known limitations

- **Orphan detection is heuristic.** The Leftovers tab matches support files to installed apps by bundle ID and display name. It can produce false positives for command-line tools or apps installed outside `/Applications`. Nothing is pre-selected — users must review each item before removing it.

- **No Mac App Store.** Cache Out requires Full Disk Access, which is incompatible with the App Store sandbox. It is distributed as a signed, notarized DMG only.

- **No crash reporting.** Cache Out does not use any third-party crash-reporting SDK. Crash logs are written to `~/Library/Logs/DiagnosticReports/` by macOS and can be shared manually when reporting issues.
