# ClipHaven

ClipHaven은 텍스트와 이미지를 Mac 안에만 보관하는 개인용 메뉴바 클립보드 기록 도구입니다. 계정, 동기화, 분석, 공유, 네트워크 전송 기능은 포함하지 않습니다.

## 한국어 사용 가이드

### 시작과 기록 열기

설치된 앱은 Finder에서 `~/Applications/ClipHaven.app`을 열거나 아래 명령으로 시작합니다.

```sh
open -gj ~/Applications/ClipHaven.app
```

메뉴바의 ClipHaven 아이콘을 선택하거나 `Command-Option-Space`를 누르면 히스토리 창이 열립니다. 새로 복사한 일반 텍스트, 서식 있는 텍스트의 읽을 수 있는 텍스트, 이미지만 기록합니다. 지원하지 않는 형식은 조용히 무시합니다.

메뉴바 정리 앱(예: **Hidden Bar**)을 사용 중이면 새 아이콘이 숨김 영역으로 이동할 수 있습니다. 메뉴바의 Hidden Bar 화살표를 눌러 `ClipHaven`을 펼친 다음, 아이콘을 화살표 오른쪽의 표시 영역으로 드래그하면 항상 보입니다. 아이콘이 숨겨져 있어도 `Command-Option-Space`는 히스토리 창을 엽니다.

### 재사용

히스토리 창에서 항목을 선택한 뒤 Return 또는 keypad Enter를 누르거나, 행을 클릭하면 원래 내용이 시스템 클립보드로 돌아갑니다. 자동 붙여넣기가 꺼져 있으면 대상 앱으로 돌아간 뒤 직접 `Command-V`로 붙여넣습니다.

### 수집 일시정지와 삭제

창의 **Pause collection**을 켜면 새 복사 내용은 수집하지 않지만 기존 기록은 그대로 보입니다. **Clear history**는 현재 모든 기록을 즉시 삭제하므로 실행 전에 주의하세요.

### 보존 정책

현재 구현은 일반 항목을 **30일** 보관하고 최대 750개까지 유지합니다. 이 값은 현재 UI에서 변경할 수 없는 고정 정책입니다.

### 자동 붙여넣기 권한

자동 붙여넣기는 기본적으로 꺼져 있습니다. 히스토리 창의 **Auto-paste (Accessibility required)**를 명시적으로 켠 뒤, **시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용(Accessibility)**에서 ClipHaven을 수동으로 허용하세요. 권한이 없거나 자동 붙여넣기가 꺼져 있으면 선택한 내용은 클립보드에만 복원되고, 직접 `Command-V`로 붙여넣으면 됩니다.

### 개인정보

ClipHaven은 지원되는 모든 일반 텍스트와 TIFF 이미지를 수집할 수 있으며, 비밀번호·토큰·개인정보를 자동으로 식별하거나 제외하지 않습니다. 민감한 앱을 사용할 때는 수집을 일시정지하고, 필요하면 즉시 **Clear history**를 사용하세요.

클립보드 항목, 이미지 데이터, 원본 앱 bundle identifier와 설정은 이 Mac의 `~/Library/Application Support/ClipHaven/history.json`에 암호화되지 않은 JSON으로 저장됩니다. 저장 위치의 파일 접근 권한은 macOS 사용자 계정 보호에 의존합니다. 앱은 업로드·계정·동기화·분석·공유 기능을 구현하지 않지만, 이 설명은 네트워크 차단이나 비밀 보관의 보증이 아닙니다.

## 소스에서 빌드 및 패키징

```sh
git clone <repository-url> ClipHaven
cd ClipHaven
./scripts/package-app.sh
```

위 명령은 `dist/ClipHaven.app`을 만듭니다. 검증은 다음과 같습니다.

```sh
swift build
swift test
./scripts/verify-cleanroom-contract.sh
```

## License

ClipHaven is licensed under the GNU Lesser General Public License v2.1 only (`LGPL-2.1-only`). See [LICENSE](LICENSE).
