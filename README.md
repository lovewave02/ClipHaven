# ClipHaven

ClipHaven은 텍스트와 이미지를 Mac 안에만 보관하는 개인용 메뉴바 클립보드 기록 도구입니다. 계정, 동기화, 분석, 공유, 네트워크 전송 기능은 포함하지 않습니다.

## 한국어 사용 가이드

### 시작과 기록 열기

설치된 앱은 Finder에서 `~/Applications/ClipHaven.app`을 열거나 아래 명령으로 시작합니다.

```sh
open -gj ~/Applications/ClipHaven.app
```

메뉴바의 ClipHaven 아이콘을 선택하거나 `Command-Option-Space`를 누르면 히스토리 창이 열립니다. 새로 복사한 일반 텍스트, 서식 있는 텍스트의 읽을 수 있는 텍스트, 이미지만 기록합니다. 지원하지 않는 형식은 조용히 무시합니다.

### 찾기와 재사용

히스토리 창의 검색창에 텍스트를 입력합니다. 검색은 대소문자와 악센트를 구분하지 않으며, 검색어가 있을 때 이미지는 결과에서 제외됩니다. 항목을 선택하면 원래 내용이 시스템 클립보드로 돌아갑니다. 핀 아이콘으로 중요한 항목을 고정하고, 휴지통 아이콘으로 항목 하나를 지울 수 있습니다.

### 수집 일시정지와 삭제

창 상단의 일시정지 스위치를 켜면 새 복사 내용은 수집하지 않지만 기존 기록은 그대로 보입니다. 하단의 **Clear unpinned**와 **Clear history**는 확인 뒤에만 각각 고정되지 않은 항목 또는 모든 항목을 삭제합니다.

### 설정

메뉴바 창에서 macOS 설정 화면을 열어 다음을 관리합니다.

- 제외할 앱: 번들 식별자(예: `com.example.app`)를 추가하면 그 앱이 전면에 있을 때는 수집하지 않습니다.
- 보존 기간: 현재 구현은 일반 항목을 **30일** 보관하는 고정 개인 정책입니다. 고정된 항목은 보존 기간 정리에서 제외됩니다.
- 일반 항목 한도: 최대 750개입니다. 고정된 항목은 이 한도에 포함하지 않습니다.
- 자동 붙여넣기와 로그인 시 실행 상태를 확인하거나 변경할 수 있습니다.

### 자동 붙여넣기 권한

자동 붙여넣기는 기본적으로 꺼져 있습니다. 켠 뒤 macOS가 권한을 요구하면 **시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용(Accessibility)**에서 ClipHaven을 수동으로 허용합니다. 권한이 없으면 선택한 내용은 클립보드에만 복원되고, 직접 `Command-V`로 붙여넣으면 됩니다.

### 개인정보

클립보드 항목과 설정은 이 Mac의 로컬 저장소에만 기록됩니다. ClipHaven은 암호나 자격 증명을 읽지 않으며, 업로드·계정·동기화·분석·공유 기능을 사용하지 않습니다.

## 소스에서 빌드 및 패키징

```sh
cd /Users/openclaw/dev/PersonalSoftware/ClipHaven/clean-room-runs/cliphaven-blackbox-20260801/implementation
./scripts/package-app.sh
```

위 명령은 `dist/ClipHaven.app`을 만듭니다. 검증은 다음과 같습니다.

```sh
xcodebuild -scheme ClipHaven -destination 'platform=macOS' build
xcodebuild -scheme ClipHaven -destination 'platform=macOS' test
./scripts/verify-cleanroom-contract.sh
```

릴리스 라이선스는 아직 결정되지 않았습니다. `LICENSE_PENDING` 상태를 유지합니다.
