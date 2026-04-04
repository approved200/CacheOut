#!/usr/bin/env bash
# setup-hooks.sh — installs the Cache Out git hooks for your local repo.
# Run once after cloning: bash setup-hooks.sh
#
# What this installs:
#   pre-commit  — auto-runs generate_xcodeproj.py when .swift files change,
#                 so project.pbxproj is always in sync without a manual step.

set -e
REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_SRC="$REPO_ROOT/hooks"
HOOKS_DEST="$REPO_ROOT/.git/hooks"

install_hook() {
    local name="$1"
    cp "$HOOKS_SRC/$name" "$HOOKS_DEST/$name"
    chmod +x "$HOOKS_DEST/$name"
    echo "✅ Installed $name"
}

install_hook "pre-commit"

echo ""
echo "Git hooks installed. The pre-commit hook will automatically regenerate"
echo "project.pbxproj whenever you stage a .swift file change."
