#!/bin/bash
# DeskJump.app build script
#
#   ./build.sh              Build DeskJump.app (Universal: arm64 + x86_64)
#   ./build.sh --install    Build, copy to /Applications and launch
#   ./build.sh --release    Build, sign, notarize (if credentials exist) and zip into dist/
#
# Environment:
#   VERSION              Marketing version (default: 1.0.0)
#   SIGN_IDENTITY        Code signing identity. Default: first "Developer ID Application",
#                        then "Apple Development", then ad-hoc ("-")
#   APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD
#                        Notarization credentials (used by --release with a Developer ID identity)
#   NOTARY_PROFILE       Alternatively, a keychain profile saved with `xcrun notarytool store-credentials`
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"
VERSION="${VERSION:-1.0.0}"
BUNDLE_ID="com.kaifacun.deskjump"
APP="DeskJump.app"

#region Universal 빌드
swift build -c release --arch arm64 --arch x86_64
BIN_DIR=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
#endregion

#region .app 번들 구성
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/DeskJump" "$APP/Contents/MacOS/DeskJump"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>DeskJump</string>
    <key>CFBundleDisplayName</key><string>DeskJump</string>
    <key>CFBundleExecutable</key><string>DeskJump</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST
#endregion

#region 코드 서명
# 고정된 인증서로 서명해야 업데이트 후에도 손쉬운 사용 권한이 유지된다 (ad-hoc 서명은 빌드마다 권한이 풀림)
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    IDENTITIES=$(security find-identity -v -p codesigning)
    SIGN_IDENTITY=$(awk -F'"' '/Developer ID Application/ {print $2; exit}' <<<"$IDENTITIES")
    [[ -z "$SIGN_IDENTITY" ]] && SIGN_IDENTITY=$(awk -F'"' '/Apple Development/ {print $2; exit}' <<<"$IDENTITIES")
    SIGN_IDENTITY="${SIGN_IDENTITY:--}"
fi

if [[ "$SIGN_IDENTITY" == Developer\ ID* ]]; then
    # 공증에는 Hardened Runtime 과 보안 타임스탬프가 필요하다
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
else
    codesign --force --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
fi
echo "Built: $(pwd)/$APP (signed with: $SIGN_IDENTITY)"
#endregion

#region 설치 (--install)
# 로그인 시 외장 볼륨이 늦게 마운트될 수 있으므로 /Applications 에 설치해 그 사본을 실행한다
if [[ "$MODE" == "--install" ]]; then
    pkill -x DeskJump || true
    rm -rf "/Applications/$APP"
    cp -R "$APP" "/Applications/$APP"
    open "/Applications/$APP"
    echo "Installed: /Applications/$APP"
fi
#endregion

#region 배포 패키지 (--release)
if [[ "$MODE" == "--release" ]]; then
    mkdir -p dist
    ZIP="dist/DeskJump-${VERSION}.zip"
    rm -f "$ZIP"

    # 공증 인증 정보: 키체인 프로필(로컬) 또는 환경 변수(CI)
    NOTARY_ARGS=()
    if [[ -n "${NOTARY_PROFILE:-}" ]]; then
        NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
    elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
        NOTARY_ARGS=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
    fi

    if [[ "$SIGN_IDENTITY" == Developer\ ID* && ${#NOTARY_ARGS[@]} -gt 0 ]]; then
        # 공증 제출용 임시 zip → 공증 완료 후 티켓을 앱에 붙이고(staple) 최종 zip 생성
        ditto -c -k --keepParent "$APP" "dist/notarize.zip"
        xcrun notarytool submit "dist/notarize.zip" --wait "${NOTARY_ARGS[@]}"
        rm -f "dist/notarize.zip"
        xcrun stapler staple "$APP"
        spctl --assess --type execute --verbose "$APP"
    else
        echo "warning: not notarized (needs a Developer ID identity and NOTARY_PROFILE or APPLE_ID / APPLE_TEAM_ID / APPLE_APP_PASSWORD)" >&2
    fi

    ditto -c -k --keepParent "$APP" "$ZIP"
    shasum -a 256 "$ZIP" | awk '{print $1}' > "$ZIP.sha256"
    echo "Release: $(pwd)/$ZIP"
    echo "SHA-256: $(cat "$ZIP.sha256")"
fi
#endregion
