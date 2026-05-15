#!/usr/bin/env bash
set -euo pipefail

# DMG 패키저 — 다른 사용자가 다운로드해서 드래그-드롭으로 설치할 수 있는 dmg 를 만든다.
#
# 흐름:
# 1. build.sh 가 만든 .app 을 staging 폴더에 복사
# 2. /Applications 심볼릭 링크를 같이 둬서 "앱을 Applications 로 끌어다 놓기" UX 제공
# 3. hdiutil 로 압축된 UDZO dmg 작성
#
# 결과물: build/PL87W_LED_Control.dmg

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/PL87W LED Control.app"
DMG="$ROOT/build/PL87W_LED_Control.dmg"
STAGE="$ROOT/build/dmg-stage"
VOLNAME="PL87W LED Control"

# 1) 앱이 없으면 먼저 빌드
if [ ! -d "$APP" ]; then
  echo "앱 번들이 없어요. build.sh 를 먼저 실행합니다…"
  "$ROOT/build.sh"
fi

# 2) staging — dmg 안의 레이아웃
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# 3) DMG 생성 (UDZO = compressed)
rm -f "$DMG"
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$DMG" >/dev/null

# 4) staging 정리
rm -rf "$STAGE"

echo ""
echo "DMG 생성 완료:"
ls -lh "$DMG"
echo ""
echo "사용자에게 배포할 파일: $DMG"
