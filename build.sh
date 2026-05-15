#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/PL87W LED Control.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$ROOT/build"
mkdir -p "$MACOS" "$RESOURCES"

# Tools/ 의 디버깅 스크립트(probe.sh / scan-hid.sh / icon-gen 가 따로 빌드)는
# 메인 앱 빌드에서 제외한다.
SOURCES=()
while IFS= read -r -d '' file; do
  SOURCES+=("$file")
done < <(find "$ROOT/Sources" -type f -name '*.swift' -not -path "$ROOT/Sources/Tools/*" -print0)

# 컴파일 (Swift 6 strict concurrency 의 경고는 표시하되 빌드 중단은 안 함)
swiftc "${SOURCES[@]}" \
  -o "$MACOS/PL87WLedControl" \
  -framework AppKit \
  -framework IOKit \
  -framework CoreFoundation

cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"

# 앱 아이콘 — AppIcon.icns 가 없으면 IconGenerator 로 자동 생성
if [ ! -f "$ROOT/AppIcon.icns" ]; then
  echo "AppIcon.icns 없음 — 생성합니다…"
  swiftc "$ROOT/Sources/Tools/IconGenerator.swift" \
    -o "$ROOT/build/icon-gen" \
    -framework AppKit
  (cd "$ROOT" && ./build/icon-gen >/dev/null)
  (cd "$ROOT" && iconutil -c icns AppIcon.iconset)
fi
cp "$ROOT/AppIcon.icns" "$RESOURCES/AppIcon.icns"

# 펌웨어 매뉴얼 PDF — 옵션. 빌드 환경에 있으면만 포함.
MANUAL="$ROOT/../SPM_PL87W_Manual_Web_260317.pdf"
if [ -f "$MANUAL" ]; then
  cp "$MANUAL" "$RESOURCES/$(basename "$MANUAL")"
fi

echo "$APP"
