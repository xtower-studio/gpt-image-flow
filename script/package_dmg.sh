#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_MODE="${1:---preview}"
TASK_VERSION="$(cat "$TASK_ROOT/config/version.txt")"
TASK_ARCH="${IMAGEFLOW_ARCH:-universal}"
TASK_SUFFIX="-preview"
case "$TASK_MODE" in
  --preview) export IMAGEFLOW_SIGN_IDENTITY=- ;;
  --release)
    : "${IMAGEFLOW_SIGN_IDENTITY:?Set a Developer ID Application signing identity}"
    : "${IMAGEFLOW_NOTARY_PROFILE:?Set a notarytool Keychain profile name}"
    security find-identity -v -p codesigning | grep -F "$IMAGEFLOW_SIGN_IDENTITY" | grep -q 'Developer ID Application:' || { echo 'A valid Developer ID Application identity is required.' >&2; exit 1; }
    TASK_SUFFIX="" ;;
  *) echo 'usage: package_dmg.sh [--preview|--release]' >&2; exit 2 ;;
esac
TASK_STAGE="$(mktemp -d "$TASK_ROOT/dist-stage.XXXXXX")"
TASK_MOUNT=""
cleanup() {
  if [[ -n "$TASK_MOUNT" ]]; then hdiutil detach "$TASK_MOUNT" -quiet || true; fi
  rm -rf "$TASK_STAGE"
}
trap cleanup EXIT
mkdir -p "$TASK_ROOT/dist/release"
TASK_APP="$TASK_ROOT/dist/release/Image Flow.app"
IMAGEFLOW_ARCH="$TASK_ARCH" bash "$TASK_ROOT/script/build_app.sh" release "$TASK_APP"
if [[ "$TASK_MODE" == --release ]]; then
  ditto -c -k --keepParent "$TASK_APP" "$TASK_STAGE/notarize.zip"
  xcrun notarytool submit "$TASK_STAGE/notarize.zip" --keychain-profile "$IMAGEFLOW_NOTARY_PROFILE" --wait
  xcrun stapler staple "$TASK_APP"
  xcrun stapler validate "$TASK_APP"
  rm "$TASK_STAGE/notarize.zip"
fi
mkdir "$TASK_STAGE/content"
ditto "$TASK_APP" "$TASK_STAGE/content/Image Flow.app"
ln -s /Applications "$TASK_STAGE/content/Applications"
cat > "$TASK_STAGE/content/설치 안내.txt" <<TEXT
Image Flow $TASK_VERSION

1. Image Flow 앱을 Applications 폴더로 드래그하세요.
2. 응용 프로그램에서 Image Flow를 여세요.
3. 저장 폴더를 선택하고 ChatGPT 또는 OpenAI API를 연결하세요.

기존 사용자는 생성 작업을 마친 뒤 앱을 종료하고 교체하세요.
이미지와 작업 기록은 선택한 보관함에 유지됩니다.

배포: DEAUM (Daeummoyang) · 비영리단체 다음모양 — https://deaum.org
디자인 및 개발: xtower — https://xtower.studio
도움말: https://github.com/xtower-studio/gpt-image-flow
API 요금은 OpenAI가 직접 청구합니다. 이 앱은 수수료를 받지 않습니다.
TEXT
if [[ "$TASK_MODE" == --preview ]]; then
  printf '\n이 파일은 서명·공증 전 검증용입니다. 일반 사용자용 정식 배포본이 아닙니다.\n' >> "$TASK_STAGE/content/설치 안내.txt"
fi
hdiutil create -quiet -volname 'Image Flow' -srcfolder "$TASK_STAGE/content" -format UDRW "$TASK_STAGE/layout.dmg"
TASK_MOUNT="$TASK_STAGE/mounted"
mkdir "$TASK_MOUNT"
hdiutil attach -quiet -nobrowse -mountpoint "$TASK_MOUNT" "$TASK_STAGE/layout.dmg"
# A normal Finder installation window; the app and Applications are side by side.
osascript - "$TASK_MOUNT" <<'APPLESCRIPT'
on run argv
  set mountPath to item 1 of argv
  tell application "Finder"
    set installFolder to POSIX file mountPath as alias
    open installFolder
    set w to container window of installFolder
    set current view of w to icon view
    set toolbar visible of w to false
    set statusbar visible of w to false
    set bounds of w to {200, 180, 800, 530}
    set arrangement of icon view options of w to not arranged
    set icon size of icon view options of w to 96
    set text size of icon view options of w to 13
    set position of item "Image Flow.app" of installFolder to {150, 100}
    set position of item "Applications" of installFolder to {440, 100}
    set position of item "설치 안내.txt" of installFolder to {295, 240}
    update installFolder without registering applications
    delay 2
    close w
  end tell
end run
APPLESCRIPT
sync
hdiutil detach -quiet "$TASK_MOUNT"
TASK_MOUNT=""
TASK_DMG="$TASK_ROOT/dist/Image-Flow-$TASK_VERSION-$TASK_ARCH$TASK_SUFFIX.dmg"
hdiutil convert -quiet "$TASK_STAGE/layout.dmg" -format UDZO -o "$TASK_DMG" -ov
if [[ "$TASK_MODE" == --release ]]; then
  codesign --timestamp --sign "$IMAGEFLOW_SIGN_IDENTITY" "$TASK_DMG"
  xcrun notarytool submit "$TASK_DMG" --keychain-profile "$IMAGEFLOW_NOTARY_PROFILE" --wait
  xcrun stapler staple "$TASK_DMG"
  xcrun stapler validate "$TASK_DMG"
  spctl --assess --type execute --verbose "$TASK_APP"
fi
hdiutil verify "$TASK_DMG"
(cd "$TASK_ROOT/dist" && shasum -a 256 "$(basename "$TASK_DMG")") > "$TASK_DMG.sha256"
echo "Created: $TASK_DMG"
