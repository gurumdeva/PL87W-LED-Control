#!/usr/bin/env bash
# PL87W LED Control — 원격 설치 스크립트
#
# 사용:
#   curl -fsSL https://github.com/gurumdeva/PL87W-LED-Control/raw/main/install.sh | bash
#
# 동작:
#   1. GitHub Releases 의 latest dmg 다운로드
#   2. dmg 마운트 → /Applications 로 복사 → 언마운트
#   3. Gatekeeper quarantine 속성 제거 ("손상됨" 메시지 우회)
#   4. 임시 파일 정리
#
# 코드 서명 없이 배포되는 오픈소스라 macOS 가 자동으로 차단하는 부분을
# 스크립트가 우회한다. xattr 명령은 사용자 본인 명의의 다운로드 파일 속성을
# 다루는 표준 macOS 도구로 시스템 보안을 깨지 않는다.

set -euo pipefail

APP_NAME="PL87W LED Control"
DMG_URL="https://github.com/gurumdeva/PL87W-LED-Control/releases/latest/download/PL87W_LED_Control.dmg"
INSTALL_DIR="/Applications"
APP_PATH="$INSTALL_DIR/$APP_NAME.app"

# 컬러 출력 (TTY 일 때만)
if [ -t 1 ]; then
    G="\033[32m"; Y="\033[33m"; R="\033[31m"; N="\033[0m"
else
    G=""; Y=""; R=""; N=""
fi

echo -e "${G}▶${N} PL87W LED Control 설치를 시작합니다…"

# macOS 체크
if [ "$(uname)" != "Darwin" ]; then
    echo -e "${R}✗${N} macOS 전용 앱입니다."
    exit 1
fi

# 임시 작업 디렉토리
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; if mount | grep -q "$TMP/mnt"; then hdiutil detach "$TMP/mnt" -quiet 2>/dev/null || true; fi' EXIT

# 1) 다운로드
echo -e "${G}▶${N} 최신 dmg 다운로드 중…"
if ! curl -fSL --progress-bar -o "$TMP/app.dmg" "$DMG_URL"; then
    echo -e "${R}✗${N} 다운로드 실패. 네트워크 또는 release URL 을 확인하세요:"
    echo "  $DMG_URL"
    exit 1
fi

# 2) 마운트
echo -e "${G}▶${N} dmg 마운트…"
mkdir -p "$TMP/mnt"
hdiutil attach "$TMP/app.dmg" -nobrowse -quiet -mountpoint "$TMP/mnt"

# 3) 기존 앱이 있으면 제거 (업그레이드)
if [ -d "$APP_PATH" ]; then
    echo -e "${Y}!${N} 기존 설치본 제거: $APP_PATH"
    rm -rf "$APP_PATH"
fi

# 4) 복사
echo -e "${G}▶${N} $INSTALL_DIR 으로 복사 중…"
cp -R "$TMP/mnt/$APP_NAME.app" "$INSTALL_DIR/"

# 5) 언마운트
hdiutil detach "$TMP/mnt" -quiet

# 6) quarantine 속성 제거 — "손상됨" 메시지 우회
echo -e "${G}▶${N} Gatekeeper quarantine 속성 제거…"
xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true

echo ""
echo -e "${G}✓ 설치 완료!${N}"
echo "  앱 위치: $APP_PATH"
echo ""
echo "  실행:"
echo "    open \"$APP_PATH\""
echo "  또는 Launchpad / Spotlight 에서 'PL87W' 검색"
