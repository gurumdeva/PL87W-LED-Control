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

# ad-hoc 코드 서명 — Apple Developer ID 가 없어도 "손상됨" 메시지를 완화해 준다.
# 모든 리소스 (binary, plist, icon, resources) 가 번들에 들어간 후 마지막에 서명.
# notarization 은 못 받지만 적어도 서명된 번들로 만들어 quarantine 시 차단 강도를 낮춤.
# 다운로드 후 quarantine 이 붙은 상태라면 사용자가 `xattr -dr com.apple.quarantine`
# 명령으로 한 번 우회해 줘야 한다 (README 안내).
codesign --force --deep --sign - "$APP" 2>&1 || echo "codesign 실패 — Gatekeeper 우회 안내가 더 필요할 수 있음"

echo "$APP"
