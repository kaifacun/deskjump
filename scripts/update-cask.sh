#!/bin/bash
# Homebrew tap(kaifacun/homebrew-tap)의 Casks/deskjump.rb 를 새 버전으로 갱신해 푸시한다
# 사용법: scripts/update-cask.sh <version> <sha256>
#   TAP_DEPLOY_KEY(SSH 개인 키)가 있으면 그 키로(CI), 없으면 현재 git 인증으로(로컬) 푸시
set -euo pipefail
VERSION="$1"
SHA256="$2"

#region tap 저장소 받기
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
if [[ -n "${TAP_DEPLOY_KEY:-}" ]]; then
    # homebrew-tap 저장소에 쓰기 권한으로 등록된 배포 키
    printf '%s\n' "$TAP_DEPLOY_KEY" > "$WORK/deploy_key"
    chmod 600 "$WORK/deploy_key"
    export GIT_SSH_COMMAND="ssh -i $WORK/deploy_key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
    TAP_URL="git@github.com:kaifacun/homebrew-tap.git"
else
    TAP_URL="https://github.com/kaifacun/homebrew-tap.git"
fi
git clone --quiet --depth 1 "$TAP_URL" "$WORK/tap"
mkdir -p "$WORK/tap/Casks"
#endregion

#region Cask 파일 작성
cat > "$WORK/tap/Casks/deskjump.rb" <<CASK
cask "deskjump" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/kaifacun/deskjump/releases/download/v#{version}/DeskJump-#{version}.zip"
  name "DeskJump"
  desc "Menu bar desktop switcher: click a number to jump to that desktop"
  homepage "https://github.com/kaifacun/deskjump"

  depends_on macos: :ventura

  app "DeskJump.app"

  caveats <<~EOS
    Open DeskJump once to finish setup:
      open -a DeskJump
    Then allow it in System Settings > Privacy & Security > Accessibility.
  EOS

  uninstall quit: "com.kaifacun.deskjump"

  zap trash: [
    "~/Library/Logs/DeskJump.log",
    "~/Library/Preferences/com.kaifacun.deskjump.plist",
  ]
end
CASK
#endregion

#region 커밋 및 푸시
cd "$WORK/tap"
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    git config user.name "github-actions[bot]"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
fi
git add Casks/deskjump.rb
if git diff --cached --quiet; then
    echo "Cask already at ${VERSION}"
    exit 0
fi
git commit --quiet -m "deskjump ${VERSION}"
git push --quiet
echo "Updated cask: deskjump ${VERSION}"
#endregion
