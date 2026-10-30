#!/bin/bash
# GitHub Actions 배포용 비밀값 6개를 한 번에 등록한다 (터미널에서 직접 실행)
# 사용법: scripts/setup-ci-secrets.sh [DeveloperID.p12 경로]
#
# 준비물:
#   1) Developer ID 인증서 .p12  (Xcode › Settings › Apple Accounts › Manage Certificates ›
#      Developer ID Application 우클릭 › Export Certificate)
#   2) 앱 암호                   (account.apple.com › 로그인 및 보안 › 앱 암호)
# 입력한 암호는 화면에 표시되지 않고 GitHub 비밀값으로만 전송된다.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="kaifacun/deskjump"
TAP="kaifacun/homebrew-tap"
P12="${1:-credentials/DeveloperID.p12}"

#region 입력 받기
[[ -f "$P12" ]] || { echo "error: $P12 not found" >&2; exit 1; }
read -r -s -p "DeveloperID.p12 암호: " P12_PASSWORD; echo
read -r -s -p "Apple 앱 암호 (xxxx-xxxx-xxxx-xxxx): " APP_PASSWORD; echo
#endregion

#region Apple 서명·공증 비밀값
base64 -i "$P12" | gh secret set DEVELOPER_ID_CERT_P12_BASE64 -R "$REPO"
printf '%s' "$P12_PASSWORD" | gh secret set DEVELOPER_ID_CERT_PASSWORD -R "$REPO"
gh secret set APPLE_ID -R "$REPO" --body kaifacun@gmail.com
gh secret set APPLE_TEAM_ID -R "$REPO" --body 2Z8PMQ5YFB
printf '%s' "$APP_PASSWORD" | gh secret set APPLE_APP_PASSWORD -R "$REPO"
#endregion

#region Homebrew tap 배포 키 (새 SSH 키를 만들어 tap 에 쓰기 권한으로 등록)
KEY_DIR=$(mktemp -d)
trap 'rm -rf "$KEY_DIR"' EXIT
ssh-keygen -q -t ed25519 -N "" -C deskjump-release -f "$KEY_DIR/tap_key"
gh repo deploy-key add "$KEY_DIR/tap_key.pub" -R "$TAP" --allow-write --title "deskjump-release $(date +%Y-%m-%d)"
gh secret set TAP_DEPLOY_KEY -R "$REPO" < "$KEY_DIR/tap_key"
#endregion

echo
gh secret list -R "$REPO"
echo "Done. 다른 컴퓨터에서는 git tag vX.Y.Z && git push origin vX.Y.Z 로 배포할 수 있습니다."
