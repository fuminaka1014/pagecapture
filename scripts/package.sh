#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/dist/PageCapture.app"
if [[ ! -d "$app_dir" ]]; then
  printf 'Build first: bash build.sh\n' >&2
  exit 1
fi
codesign --verify --deep --strict "$app_dir"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")"
architectures="$(xcrun lipo -archs "$app_dir/Contents/MacOS/PageCapture")"
archive_arch="${architectures// /-}"
if [[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]]; then archive_arch=universal; fi
stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/pagecapture-package.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
ditto "$app_dir" "$stage_dir/PageCapture/PageCapture.app"
cp "$project_dir/LICENSE" "$stage_dir/PageCapture/LICENSE"
cp "$project_dir/使い方.md" "$stage_dir/PageCapture/README-ja.md"
archive="$project_dir/dist/PageCapture-v$version-alpha-$archive_arch.zip"
ditto -c -k --norsrc --keepParent "$stage_dir/PageCapture" "$archive"
archive_name="${archive##*/}"
(
  cd "$project_dir/dist"
  shasum -a 256 "$archive_name" > "$archive_name.sha256"
)
printf 'Packaged: %s\n' "$archive"
