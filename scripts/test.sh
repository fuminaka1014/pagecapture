#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
executable="$project_dir/dist/PageCapture.app/Contents/MacOS/PageCapture"
if [[ ! -x "$executable" ]]; then
  printf 'Build first: bash build.sh\n' >&2
  exit 1
fi
bash -n "$project_dir/build.sh" "$project_dir/scripts/test.sh" "$project_dir/scripts/package.sh"
plutil -lint "$project_dir/Info.plist"
for language in en ja; do
  plutil -lint "$project_dir/Resources/$language.lproj/Localizable.strings" \
    "$project_dir/Resources/$language.lproj/InfoPlist.strings"
done
plutil -lint "$project_dir/Resources/en.lproj/Localizable.stringsdict"
codesign --verify --deep --strict "$project_dir/dist/PageCapture.app"
"$executable" --self-test "$project_dir/.build/test-results"
if [[ "${RENDER_UI:-0}" == 1 ]]; then
  for language in ja en; do
    PAGECAPTURE_LANGUAGE="$language" "$executable" --render-ui "$project_dir/.build/ui/$language"
  done
fi
