# 배포 설명서 (메인테이너용)

DeskJump 새 버전을 내는 방법이다. 배포는 두 가지 방법 중 하나로 한다. 어느 쪽이든 결과는 같다.

1. Universal 앱(Apple silicon + Intel)을 빌드한다.
2. **Developer ID** 로 서명하고 Apple **공증**을 받는다.
3. [GitHub Release](https://github.com/kaifacun/deskjump/releases) 에 `DeskJump-<버전>.zip` 을 올린다.
4. [kaifacun/homebrew-tap](https://github.com/kaifacun/homebrew-tap) 의 Cask 를 갱신한다. 사용자는 `brew upgrade` 로 받는다.

| | A. 아무 컴퓨터에서 (GitHub Actions) | B. 서명 인증서가 있는 맥에서 |
|---|---|---|
| 명령 | `git tag v1.0.1 && git push origin v1.0.1` | `./release.sh 1.0.1` |
| 필요한 것 | git + 이 저장소 푸시 권한 | 인증서 + 공증 프로필 + gh 로그인 |
| 서명·공증 | GitHub 서버가 함 | 그 맥에서 함 |
| 맥 필요 | 아니오 (실행해서 시험해 보려면 필요) | 예 |

---

## A. 아무 컴퓨터에서 배포하기 (GitHub Actions)

### 순서

```bash
git clone https://github.com/kaifacun/deskjump.git   # 처음 한 번만
cd deskjump

# … 코드 수정 …

git commit -am "Fix something"
git push
git tag v1.0.1 && git push origin v1.0.1             # 이 순간 배포 시작
```

태그를 올리면 GitHub 서버가 [`.github/workflows/release.yml`](../.github/workflows/release.yml) 을 실행한다. 10분 안팎이 걸린다.

1. 빌드
2. Developer ID 서명
3. 공증
4. Release 게시
5. Homebrew Cask 갱신

진행 상황 보기:

```bash
gh run list -R kaifacun/deskjump --limit 3
gh run watch -R kaifacun/deskjump
```

또는 https://github.com/kaifacun/deskjump/actions 에서 본다.

### 처음 한 번: 저장소 비밀값 등록

*Settings › Secrets and variables › Actions* 에 비밀값 6개가 있어야 한다. 없으면 서명 단계에서 실패한다. 아래 순서로 한 번에 등록한다.

1. **인증서 내보내기**: Xcode › Settings › Apple Accounts › Manage Certificates… › **Developer ID Application** 우클릭 › **Export Certificate** 를 누른다. 정한 암호는 잘 적어 둔다.
2. **앱 암호 만들기**: [account.apple.com](https://account.apple.com) › 로그인 및 보안 › 앱 암호 › 생성. 나온 값을 적어 둔다.
3. **터미널에서 실행**:
   ```bash
   scripts/setup-ci-secrets.sh path/to/DeveloperID.p12
   ```
   두 암호를 물으면 입력한다. 스크립트가 tap 배포 키를 새로 만들어 등록하고, 비밀값 6개를 모두 넣는다.

| 비밀값 | 값 |
|---|---|
| `DEVELOPER_ID_CERT_P12_BASE64` | *Developer ID Application* 인증서와 개인 키를 내보낸 `.p12` 의 base64 |
| `DEVELOPER_ID_CERT_PASSWORD` | 그 `.p12` 의 암호 |
| `APPLE_ID` | 공증에 쓰는 Apple ID |
| `APPLE_TEAM_ID` | 10자리 Team ID |
| `APPLE_APP_PASSWORD` | 앱 암호 |
| `TAP_DEPLOY_KEY` | `kaifacun/homebrew-tap` 에 쓰기 권한으로 등록된 배포 키(SSH)의 개인 키 |

비밀값을 잃거나 바꿔야 하면 같은 스크립트를 다시 실행하면 된다.

---

## B. 서명 인증서가 있는 맥에서 배포하기

### 순서

```bash
# … 코드 수정 후 커밋 …
./release.sh 1.0.1
```

[`release.sh`](../release.sh) 는 다음을 차례로 한다.

1. 커밋 안 된 변경이 있거나 같은 버전이 이미 있으면 멈춘다.
2. 현재 브랜치를 푸시한다.
3. 빌드, 서명, 공증을 하고 Gatekeeper 통과를 확인한다.
4. Release 를 게시한다.
5. Cask 를 갱신한다.

이 방법으로 배포한 태그는 GitHub Actions 가 감지하고 건너뛴다. 같은 버전이 두 번 배포되지 않는다.

### 처음 한 번: 그 맥에 준비할 것

1. **인증서**: 키체인에 *Developer ID Application* 인증서가 있어야 한다. Xcode 에서 발급하거나 `.p12` 를 더블클릭해 설치한다.
   ```bash
   security find-identity -v -p codesigning   # "Developer ID Application: …" 이 보여야 함
   ```
2. **공증 인증 정보**를 키체인에 저장한다.
   ```bash
   xcrun notarytool store-credentials deskjump-notary --apple-id <Apple ID> --team-id <Team ID>
   ```
   프로필 이름을 다르게 정했다면 `NOTARY_PROFILE=<이름> ./release.sh 1.0.1` 로 실행한다.
3. **GitHub 로그인**: `gh auth login`

---

## 버전 규칙

- 태그 `v1.2.3` 이 곧 앱 버전 `1.2.3` 이 된다. `CFBundleShortVersionString` 과 zip 파일 이름에 들어간다.
- 이미 쓴 버전 번호는 다시 쓸 수 없다. 매번 올린다.
- **번들 ID `com.kaifacun.deskjump` 와 서명 팀은 바꾸지 않는다.** 바꾸면 macOS 가 다른 앱으로 보고, 모든 사용자가 손쉬운 사용 권한을 다시 켜야 한다.

## 문제가 생겼을 때

| 증상 | 확인할 것 |
|---|---|
| Actions 가 `Developer ID Application certificate not found` 로 실패 | `DEVELOPER_ID_CERT_P12_BASE64` / `DEVELOPER_ID_CERT_PASSWORD` 비밀값 |
| 공증 단계에서 인증 실패 | `APPLE_ID` / `APPLE_TEAM_ID` / `APPLE_APP_PASSWORD`. 앱 암호는 새로 만들어 덮어쓰면 된다 |
| Cask 갱신 단계에서 `Permission denied (publickey)` | homebrew-tap › Settings › Deploy keys 에 쓰기 권한 키가 있는지 확인. `scripts/setup-ci-secrets.sh` 를 다시 실행 |
| 인증서 만료 | Xcode 에서 같은 팀으로 재발급 → 새 `.p12` 로 비밀값 갱신. 이미 배포된 버전은 계속 열린다 |
| 잘못 배포함 | `gh release delete v1.0.1 --cleanup-tag` 후 더 높은 버전으로 다시 배포. 이미 받은 사용자를 위해 **같은 번호는 재사용하지 않는다** |

## 로컬에서 시험만 하기

```bash
./build.sh --install    # 빌드 → /Applications 설치 → 실행 (배포 안 함)
```
