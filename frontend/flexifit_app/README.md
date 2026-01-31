# FlexiFit Flutter App

Flutter client for FlexiFit (AI Wellness Negotiator).

## Prerequisites
- Flutter SDK installed (`flutter doctor` should be clean)
- A backend URL (local or deployed)

## Install deps
```bash
flutter pub get
```

## Run (Web)
```bash
flutter devices
flutter run -d chrome
# or
flutter run -d edge
```

## Run (Android physical device / emulator)
1) List devices:
```bash
flutter devices
```

2) Run using a device id:
```bash
flutter run -d <device-id>
```

### Start an emulator (optional)
```bash
flutter emulators
flutter emulators --launch <emulator-id>
flutter devices
flutter run -d <device-id>
```

## Configure backend (no hardcoded URL)
Pass the backend base URL at runtime:
```bash
# Local
flutter run -d <device-id> --dart-define=API_BASE_URL=http://localhost:8000

# Deployed
flutter run -d <device-id> --dart-define=API_BASE_URL=<your-backend-url>
```

If your build supports it, you can also toggle local mode:
```bash
flutter run -d <device-id> --dart-define=USE_LOCAL_API=true
```
