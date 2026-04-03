#!/bin/bash
# validate_placeholders.sh
# Pre-archive guard: fails the build if any release-critical placeholder
# is still unfilled. Wire this into Xcode: Build Phases → Run Script (before Sign).
#
# Wiring steps:
#   1. Xcode → Target: Cache Out → Build Phases → "+" → New Run Script Phase
#   2. Drag it ABOVE "Sign Binary With Entitlements"
#   3. Script: "${SRCROOT}/validate_placeholders.sh"
#   4. "For install builds only" → ON  (runs on archive, not debug builds)

set -euo pipefail

ERRORS=()

# ── exportOptions.plist ──────────────────────────────────────────────────────
EXPORT_PLIST="${SRCROOT}/exportOptions.plist"
if grep -q "YOUR_TEAM_ID" "$EXPORT_PLIST" 2>/dev/null; then
    ERRORS+=("exportOptions.plist: YOUR_TEAM_ID not replaced with your Apple Developer Team ID")
fi

# ── appcast.xml ──────────────────────────────────────────────────────────────
APPCAST="${SRCROOT}/appcast.xml"
if grep -q "REPLACE_WITH_DMG_BYTE_SIZE" "$APPCAST" 2>/dev/null; then
    ERRORS+=("appcast.xml: REPLACE_WITH_DMG_BYTE_SIZE not filled (run sign_update after notarizing)")
fi
if grep -q "REPLACE_WITH_ED_SIGNATURE" "$APPCAST" 2>/dev/null; then
    ERRORS+=("appcast.xml: REPLACE_WITH_ED_SIGNATURE not filled (run sign_update after notarizing)")
fi

# ── Info.plist — Sparkle public key ──────────────────────────────────────────
INFO_PLIST="${SRCROOT}/CacheOut/Info.plist"
if grep -q "YOUR_PUBLIC_ED_KEY" "$INFO_PLIST" 2>/dev/null; then
    ERRORS+=("Info.plist: SUPublicEDKey not set (run Sparkle generate_keys)")
fi

# ── Report ────────────────────────────────────────────────────────────────────
if [ ${#ERRORS[@]} -gt 0 ]; then
    echo "❌ validate_placeholders.sh: Release blockers found:"
    for err in "${ERRORS[@]}"; do
        echo "   • $err"
    done
    exit 1
fi

echo "✅ validate_placeholders.sh: All release placeholders are filled."
