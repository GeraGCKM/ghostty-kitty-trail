#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
upstream="${1:?Pass the path to the Ghostty Git checkout}"
test "$(git -C "$upstream" rev-parse --is-inside-work-tree)" = true
git -C "$upstream" describe --tags --exact-match HEAD
git -C "$upstream" diff --quiet HEAD

# Xcode discovers the additional Swift source under the synchronized Sources group.
if ! grep -q 'PBXFileSystemSynchronizedRootGroup.*Sources' "$upstream/macos/Ghostty.xcodeproj/project.pbxproj"; then
    echo 'Ghostty changed how the Xcode project discovers source files.' >&2
    exit 1
fi

for path in src/renderer/CursorTrail.zig src/config/CursorTrail.zig macos/Sources/Features/Terminal/CursorTrailView.swift; do
    if [[ -e "$upstream/$path" ]]; then
        echo "Ghostty already contains $path. Review the integration for this version." >&2
        exit 1
    fi
done

if ! git -C "$upstream" apply --check "$root/integration.patch"; then
    echo 'The upstream renderer, configuration or AppKit interfaces changed. Update integration.patch.' >&2
    exit 1
fi

git -C "$upstream" apply "$root/integration.patch"
install -m 0644 "$root/modules/animation.zig" "$upstream/src/renderer/CursorTrail.zig"
install -m 0644 "$root/modules/config.zig" "$upstream/src/config/CursorTrail.zig"
install -m 0644 "$root/modules/CursorTrailView.swift" "$upstream/macos/Sources/Features/Terminal/CursorTrailView.swift"
git -C "$upstream" diff --check
