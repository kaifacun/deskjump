#!/bin/bash
# 이 맥에서 배포: 빌드 → 서명 → 공증 → GitHub Release 게시 → Homebrew cask 갱신
# 사용법: ./release.sh <version>      예) ./release.sh 1.0.1
#
# 필요 조건 (이 맥에 한 번만):
#   - 키체인에 "Developer ID Application" 인증서
#   - xcrun notarytool store-credentials deskjump-notary --apple-id <email> --team-id <TEAMID>
#   - gh auth login
# 다른 컴퓨터에서는 태그만 푸시하면 GitHub Actions 가 같은 일을 한다 (README 참고)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?usage: ./release.sh <version>}"
TAG="v${VERSION}"

#region 사전 확인
if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: working tree has uncommitted changes" >&2
    exit 1
fi
if gh release view "$TAG" >/dev/null 2>&1; then
    echo "error: release $TAG already exists" >&2
    exit 1
fi
git push --quiet origin HEAD
#endregion

#region 빌드·공증
NOTARY_PROFILE="${NOTARY_PROFILE:-deskjump-notary}" VERSION="$VERSION" ./build.sh --release
ZIP="dist/DeskJump-${VERSION}.zip"
SHA256=$(cat "$ZIP.sha256")
spctl --assess --type execute DeskJump.app || { echo "error: app is not notarized" >&2; exit 1; }
#endregion

#region 게시
# Release 를 먼저 만들어 두면, 같이 생성되는 태그로 실행되는 GitHub Actions 는 중복 배포를 건너뛴다
gh release create "$TAG" "$ZIP" --target "$(git rev-parse HEAD)" --title "DeskJump ${VERSION}" --generate-notes
scripts/update-cask.sh "$VERSION" "$SHA256"
echo "Released DeskJump ${VERSION}"
#endregion
