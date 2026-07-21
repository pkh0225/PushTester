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
2. Apple Developer에서 발급한 APNs Auth Key (`.p8`) 임포트
3. Team ID, Key ID, 앱 Bundle ID, Device Token 입력
4. Sandbox / Production 선택
5. Payload 편집 후 **Send**

### Android

1. 상단 탭에서 **Android** 선택
2. Firebase 콘솔의 서비스 계정 JSON 임포트
3. Project ID, FCM Device Token 확인/입력
4. Payload 편집 후 **Send**

### 히스토리

- 왼쪽 목록에 성공한 전송이 쌓입니다.
- 항목을 선택한 뒤 **적용**, 또는 더블클릭으로 폼에 반영합니다.
- iOS / Android 탭에 따라 히스토리가 분리됩니다.

## 참고

- Payload는 일반 JSON이어야 합니다. 스마트 따옴표(`“ ”`)가 들어가면 파싱에 실패할 수 있습니다.
- APNs JWT는 짧게 캐시해 `TooManyProviderTokenUpdates`(HTTP 429)를 줄입니다.
- 키·토큰·서비스 계정은 로컬에만 저장되며, 외부로 전송되지 않습니다(푸시 API 호출 제외).
