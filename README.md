<p align="center">
  <img src="logo-source.png" width="180" alt="oh-my-grid 로고">
</p>

<h1 align="center">oh-my-grid 🪟</h1>

<p align="center"><b>English</b> · <a href="#한국어">한국어</a></p>

**Snap any window to a grid with one gesture.** Start dragging a window, click the right mouse button once, and a grid appears over the screen. Sweep across the cells you want and release — the window fills exactly that block. Halves and quarters are also one keystroke away (`⌃⌥←` `⌃⌥→` `⌃⌥↑` `⌃⌥↓`, `⌃⌥U/I/J/K`, `⌃⌥↩` to maximize).

- macOS 26 (Tahoe) or later · lives in the menu bar · free & open source · English / 한국어
- Install: `brew install --cask canine89/tap/oh-my-grid` or grab the notarized `.dmg` from [Releases](../../releases/latest)
- Needs the **Accessibility** permission (System Settings → Privacy & Security → Accessibility). No screen recording; app bundles are read only when you choose excluded apps.
- Trackpad? Press `⌃⌥G` while dragging instead of right-clicking. Everything is configurable in **Settings…**; a first-run guide walks you through it.

---

<a id="한국어"></a>

드래그하던 창을 **그리드에 맞춰 한 번에 배치**하는 macOS 창 정렬 도구. 창을 옮기는 도중 오른쪽 버튼만 누르면 화면에 그리드가 뜨고, 셀을 가로질러 끌어 놓으면 창이 그 영역에 딱 맞게 들어갑니다.

> macOS 26 (Tahoe) 이상 · 메뉴 막대 상주 · 무료 / 오픈소스

---

## 왜 만들었나

Windows 에는 **WindowGrid** 라는 훌륭한 창 정렬 도구가 있습니다. 창을 드래그하다 우클릭하면 그리드가 뜨고, 원하는 칸으로 끌어 놓으면 창이 그 영역에 스냅되죠. 마우스만으로 화면을 반·1/4·임의 블록으로 빠르게 나눠 쓸 수 있습니다.

문제는 **WindowGrid 가 Windows 전용**이라는 것. macOS 에는 똑같은 손맛의 도구가 없어서, 직접 만들어 무료로 배포합니다. 그게 oh-my-grid 입니다.

---

## 📥 설치

Homebrew로 설치할 수 있습니다.

```sh
brew install --cask canine89/tap/oh-my-grid
```

또는 [**Releases**](../../releases/latest) 에서 `oh-my-grid-x.x.x.dmg` 를 받아 직접 설치할 수 있습니다.

1. `.dmg` 를 열고 **`oh-my-grid` 아이콘을 `Applications` 폴더로 드래그**합니다.
2. `Applications` 폴더에서 `oh-my-grid` 를 실행합니다. 배포용 DMG는 **Apple Developer ID 서명 및 공증**을 거쳤습니다.
3. 첫 실행 때 뜨는 **손쉬운 사용(접근성) 권한**을 켭니다
   (시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 → `oh-my-grid` ON). 권한을 켠 뒤 잠시 기다리면 바로 동작합니다.

> 그림과 함께 한 단계씩 따라 하려면 👉 [INSTALL.md](INSTALL.md)

설치 후에는 앱이 **자동으로 업데이트를 확인**합니다(Sparkle). 메뉴바 → **업데이트 확인…** 으로 수동 확인도 가능합니다.

> 기존 안내와 달리 최신 릴리스는 공증된 앱이므로 보통 `그래도 열기` 보안 우회가 필요하지 않습니다. macOS가 확인 대화상자를 띄우면 안내에 따라 열면 됩니다.

### 삭제

Homebrew로 설치했다면 아래 명령으로 삭제할 수 있습니다.

```sh
brew uninstall --cask oh-my-grid
```

설정과 캐시까지 지우는 클린 삭제는 아래 명령을 사용하세요.

```sh
brew uninstall --cask --zap oh-my-grid
```

---

## ✨ 사용법

1. 아무 창이나 **타이틀바를 왼쪽 버튼으로 잡고 드래그**를 시작합니다.
2. 드래그하는 도중 마우스 **오른쪽 버튼을 한 번 클릭**합니다 → 화면에 그리드 가이드가 켜집니다. (오른쪽 버튼은 계속 누르고 있지 않아도 됩니다)
3. 왼쪽 버튼을 누른 채 마우스를 움직여 **원하는 셀 블록**(시작 칸 ~ 끝 칸)을 지정합니다. 선택 영역이 파랗게 표시됩니다.
4. **왼쪽 버튼을 놓으면** 창이 그 영역에 딱 맞게 배치됩니다.
5. 취소하려면 **다시 오른쪽 클릭** 하거나 **`Esc`** 를 누르세요(창은 그대로 유지).

기본 그리드는 **6 열 × 4 행** 이며, 메뉴바 → **설정…** 에서 칸 수를 바꿀 수 있습니다.

### 🖐️ 트랙패드 사용 (우클릭 대신 단축키)

트랙패드에서는 "드래그 중 우클릭"이 어렵습니다. 대신 창을 **드래그하는 도중 단축키(기본 `⌃⌥G`)** 를 누르면 우클릭과 똑같이 그리드가 켜집니다. 그대로 셀을 가로질러 움직인 뒤 손을 떼면 배치됩니다. (`Esc` 로 취소)

단축키는 **설정… → 단축키** 탭에서 바꿀 수 있습니다. macOS 시스템·앱 기본 단축키(예: `⌘Space`, `⌃↑`, `⇧⌘4`, `⌘C` 등)는 충돌을 막기 위해 처음부터 지정할 수 없습니다.

### ↔️ 가장자리 스냅

그리드를 켜지 않아도, 창을 드래그해 **화면 가장자리에 붙이면** 왼쪽·오른쪽·아래에서는 절반, 위에서는 최대화 영역을 미리 보여 주고 손을 떼면 배치합니다. 설정 → 일반에서 끌 수 있습니다.

### ⌨️ 키보드 스냅 단축키

마우스 없이 **맨 앞 창**을 바로 배치할 수도 있습니다. 실행하면 목표 영역이 잠깐 비춰집니다.

| 단축키 | 동작 |
|---|---|
| `⌃⌥←` `⌃⌥→` `⌃⌥↑` `⌃⌥↓` | 왼쪽 / 오른쪽 / 위 / 아래 절반 |
| `⌃⌥U` `⌃⌥I` `⌃⌥J` `⌃⌥K` | 왼쪽 위 / 오른쪽 위 / 왼쪽 아래 / 오른쪽 아래 1/4 |
| `⌃⌥↩` | 최대화 |
| `⌃⌥C` | 가운데 정렬(크기 유지) |

설정 → 단축키 탭에서 조합을 바꾸거나 전체를 끌 수 있고, 메뉴 막대 → **창 스냅**에서도 같은 동작을 실행할 수 있습니다.

---

## 🧭 메뉴 막대 메뉴

메뉴 막대의 그리드 아이콘을 누르면:

| 메뉴 | 설명 |
|---|---|
| **그리드 켜기/끄기** | 드래그 제스처 활성/비활성 토글 |
| **창 스냅** | 키보드 스냅과 같은 동작(절반·1/4·최대화·가운데)을 메뉴에서 실행 |
| **창 크기 고정** | 프리셋(비디오 4:3·16:9, 사용자 지정) 선택 → 바꿀 창 클릭 → 그 크기로 고정 |
| **설정…** | 일반(언어·가장자리 스냅·로그인 시 실행·권한) / 그리드(열·행·여백, 라이브 미리보기) / 단축키 / 창 크기 / 예외 앱 / 정보 |
| **시작 가이드…** | 첫 실행 때 뜨는 가이드를 다시 열기 |
| **업데이트 확인…** | Sparkle 수동 업데이트 |
| **권한 다시 요청…** | 손쉬운 사용 권한이 없을 때만 표시 |
| **종료** | 앱 종료 |

### ⚙️ 설정에서 할 수 있는 것

- **표시 언어** — 기본은 영어. 설정 → 일반 → Language 에서 English / 한국어를 고르면 재시작 없이 바뀝니다.
- **그리드 칸 수·여백** — 열·행(각 1–24)과 화면 가장자리 여백(0–48pt)·창 사이 간격(0–32pt). 여백은 그리드·가장자리·키보드 스냅에 모두 적용됩니다. 창 간격은 인접한 두 창 사이의 전체 거리이며, 작은 칸에서는 여백이 자동으로 줄어듭니다.
- **사용자 지정 창 크기 프리셋** — 이름·너비·높이를 직접 입력하거나 **창 클릭으로 가져오기**로 아무 창의 현재 크기를 저장.
- **예외 앱** — 실행 중인 앱에서 고르거나 앱을 끌어다 놓아 추가하면 그 앱 창에는 그리드가 뜨지 않습니다.
- **로그인 시 자동 실행**

### 🚀 첫 실행 시작 가이드

처음 실행하면 ① 언어 선택 → ② 손쉬운 사용 권한 → ③ 가이드 창을 직접 드래그해 그리드 스냅 연습 → ④ 자동 실행·가장자리 스냅·그리드 크기 선택 순서로 안내합니다. 메뉴 막대 → **시작 가이드…** 로 언제든 다시 볼 수 있습니다.

---

## 🔐 권한에 대해

oh-my-grid 는 다른 앱의 창을 옮기기 위해 **손쉬운 사용(접근성)** 권한이 필요합니다. 이 권한으로 창 위치·크기를 조절하고, 드래그 중 마우스 제스처를 인식합니다. 화면 녹화 권한은 쓰지 않습니다. 예외 앱을 고를 때에만 사용자가 선택한 앱 번들을 읽습니다. 설정과 창 내용은 전송하지 않으며, Sparkle 업데이트를 위해 GitHub에 연결합니다 → [개인정보 처리방침](PRIVACY.md)

---

## 📝 변경 이력

버전별 변경 사항은 [CHANGELOG.md](CHANGELOG.md) 를 참고하세요.

---

만든 곳: Golden Rabbit · 문의: hgpark@goldenrabbit.co.kr

## 개발 및 배포

- `xcodegen generate` — Xcode 프로젝트 생성
- `./scripts/test.sh` — 회귀 테스트
- `./scripts/release.sh` — Developer ID 서명·공증을 거쳐 DMG와 업데이트용 ZIP 생성
- `./scripts/release.sh <버전>` — 새 버전 패키지와 Sparkle appcast 생성
- `./scripts/release.sh <버전> --publish` — GitHub Release 게시 및 appcast·Homebrew 캐스크 갱신

앱 배포는 DMG 설치와 Sparkle 자동 업데이트를 사용합니다. 업데이트 서명키는 기존 설치본과의 호환성을 위해 유지해야 합니다.
