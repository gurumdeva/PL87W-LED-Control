#!/usr/bin/env bash
set -euo pipefail

# DMG 패키저 — 다른 사용자가 다운로드해서 더블 클릭으로 설치할 수 있는 dmg.
#
# dmg 안 구성:
#   - PL87W LED Control.app
#   - Applications (심볼릭 링크)
#   - Install.command (Gatekeeper 우회 자동화 — GUI 사용자용)
#
# 사용자가 직접 .app 을 Applications 로 드래그하면 quarantine 때문에 "손상됨"
# 메시지가 뜬다. Install.command 를 더블 클릭하면 자동으로 복사 + xattr 제거.

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/PL87W LED Control.app"
DMG="$ROOT/build/PL87W_LED_Control.dmg"
STAGE="$ROOT/build/dmg-stage"
VOLNAME="PL87W LED Control"

if [ ! -d "$APP" ]; then
  echo "앱 번들이 없어요. build.sh 를 먼저 실행합니다…"
  "$ROOT/build.sh"
fi

# 1) staging
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# 2) dmg 안에 들어갈 자동 설치 스크립트
cat > "$STAGE/Install.command" <<'INSTALLER'
#!/usr/bin/env bash
# GUI 사용자용 자동 설치기 — dmg 안에서 더블 클릭으로 실행.
# 이 .command 가 위치한 dmg 의 .app 을 /Applications 로 복사하고
# Gatekeeper quarantine 속성을 제거한다.

set -e

APP_NAME="PL87W LED Control"
INSTALL_DIR="/Applications"
APP_PATH="$INSTALL_DIR/$APP_NAME.app"

# 이 .command 파일과 같은 폴더 (= 마운트된 dmg) 안의 .app 을 찾는다
HERE="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$HERE/$APP_NAME.app"

if [ ! -d "$SOURCE_APP" ]; then
    osascript -e 'display alert "설치 실패" message "dmg 내부에서 PL87W LED Control.app 을 찾을 수 없습니다."'
    exit 1
fi

# 기존 설치본 제거 (업그레이드)
if [ -d "$APP_PATH" ]; then
    rm -rf "$APP_PATH"
fi

# 복사 + quarantine 제거
cp -R "$SOURCE_APP" "$INSTALL_DIR/"
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true

# 사용자 알림 + 앱 실행 여부 묻기
RESULT=$(osascript -e 'display alert "PL87W LED Control 설치 완료" message "Applications 폴더로 복사되었습니다. 지금 실행할까요?" buttons {"닫기", "지금 열기"} default button "지금 열기"' || echo "")
if echo "$RESULT" | grep -q "지금 열기"; then
    open "$APP_PATH"
fi
INSTALLER
chmod +x "$STAGE/Install.command"

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
