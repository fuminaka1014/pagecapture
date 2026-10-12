#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
if [[ "$(uname -s)" != Darwin ]]; then
  printf 'PageCapture requires macOS and Xcode Command Line Tools.\n' >&2
  exit 1
fi
app_dir="$project_dir/dist/PageCapture.app"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/pagecapture-build.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
bundle_dir="$build_dir/PageCapture.app"
mkdir -p "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Resources" "$project_dir/dist"
read -r -a architectures <<< "${ARCHS:-$(uname -m)}"
if [[ ${#architectures[@]} -eq 0 ]]; then
  printf 'ARCHS must contain arm64, x86_64, or both.\n' >&2
  exit 1
fi
binaries=()
for architecture in "${architectures[@]}"; do
  case "$architecture" in
    arm64|x86_64) ;;
    *) printf 'Unsupported architecture: %s\n' "$architecture" >&2; exit 1 ;;
  esac
  xcrun swiftc -parse-as-library -O -swift-version 5 -target "$architecture-apple-macos14.0" \
    "$project_dir/PageCapture.swift" -o "$build_dir/PageCapture-$architecture" \
    -framework AppKit -framework SwiftUI -framework ScreenCaptureKit \
    -framework ApplicationServices -framework PDFKit -framework ImageIO -framework UniformTypeIdentifiers
  binaries+=("$build_dir/PageCapture-$architecture")
done
xcrun lipo -create "${binaries[@]}" -output "$bundle_dir/Contents/MacOS/PageCapture"
cp "$project_dir/Info.plist" "$bundle_dir/Contents/Info.plist"
cp "$project_dir/LICENSE" "$bundle_dir/Contents/Resources/LICENSE"
codesign --force --sign - --identifier io.github.fuminaka1014.pagecapture "$bundle_dir"
ditto "$bundle_dir" "$app_dir"
codesign --verify --deep --strict "$app_dir"
printf 'Built: %s\n' "$app_dir"
