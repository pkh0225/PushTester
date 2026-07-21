# PushTester

macOS용 iOS(APNs) / Android(FCM) 푸시 테스트 앱입니다.

## 기능

- **iOS (APNs)**
  - Auth Key (`.p8`) 임포트
  - Team ID, Bundle ID, Key ID, Device Token
  - Sandbox / Production
  - Priority, Push Type, JSON payload
- **Android (FCM HTTP v1)**
  - Firebase 서비스 계정 JSON 임포트
  - Project ID, FCM Device Token
  - Priority, JSON payload
- **필드 프리셋**
  - Bundle ID, Team ID, Key ID, Device Token, Project ID 등 값 목록 관리
  - 인증서(`.p8` / 서비스 계정 JSON) 목록 관리·선택
  - 라벨 옆 ⚙으로 추가·수정·삭제 (변경 시 자동 저장)
  - 입력칸 옆 ▼로 저장된 항목 선택 시 필드에 자동 입력
- 마지막 세션 자동 저장/복원
- 세션 JSON 저장·불러오기
- 전송 성공 히스토리 (탭별 분리, 적용/편집/삭제)
- 창 크기·위치 기억

## 요구 사항

- macOS 13+
- Xcode 15+ (권장)

## 실행

### 데스크톱 앱

이미 빌드된 앱이 있으면:

```text
~/Desktop/PushTester.app
```

### Xcode에서 빌드

```bash
cd ~/Desktop/PushTester
open PushTester.xcodeproj
```

또는:

```bash
xcodebuild -project PushTester.xcodeproj -scheme PushTester -configuration Release -destination 'platform=macOS' build
```

Bundle ID: `com.local.PushTester`

## 사용법

### iOS

1. 상단 탭에서 **iOS** 선택
2. Apple Developer에서 발급한 APNs Auth Key (`.p8`) 임포트 (또는 ▼에서 저장된 인증서 선택)
3. Team ID, Key ID, 앱 Bundle ID, Device Token 입력 (자주 쓰는 값은 프리셋으로 저장해 두면 편리합니다)
4. Sandbox / Production 선택
5. Payload 편집 후 **Push Notification**

### Android

1. 상단 탭에서 **Android** 선택
2. Firebase 콘솔의 서비스 계정 JSON 임포트 (또는 ▼에서 저장된 인증서 선택)
3. Project ID, FCM Device Token 확인/입력
4. Payload 편집 후 **Push Notification**

### 필드 프리셋

입력 필드의 값을 여러 개 저장해 두고 빠르게 바꿔 쓸 수 있습니다.

1. 라벨 오른쪽 **⚙** 을 눌러 해당 필드 목록을 엽니다.
2. 값을 추가·수정하고, 항목 옆 **x** 로 삭제합니다 (삭제 전 확인).
3. 변경 내용은 자동 저장됩니다.
4. 입력칸 오른쪽 **▼** 에서 항목을 고르면 필드에 바로 채워집니다.

**인증서**도 동일합니다. Import로 가져오거나 설정에서 파일을 추가하면 목록에 남고, ▼로 다시 선택할 수 있습니다.

프리셋 데이터는 다음에 로컬 저장됩니다.

```text
~/Library/Application Support/PushTester/field-presets.json
~/Library/Application Support/PushTester/certificate-presets.json
```

### 히스토리

- 왼쪽 목록에 성공한 전송이 쌓입니다.
- 항목을 선택한 뒤 **적용**, 또는 더블클릭으로 폼에 반영합니다.
- iOS / Android 탭에 따라 히스토리가 분리됩니다.

## 참고

- Payload는 일반 JSON이어야 합니다. 스마트 따옴표(`“ ”`)가 들어가면 파싱에 실패할 수 있습니다.
- APNs JWT는 짧게 캐시해 `TooManyProviderTokenUpdates`(HTTP 429)를 줄입니다.
- 키·토큰·서비스 계정·프리셋은 로컬에만 저장되며, 외부로 전송되지 않습니다(푸시 API 호출 제외).
