# MeshStream Flutter example

Run `flutter pub get` and `flutter run --target lib/main.dart` from this directory, then enter your own authorized Key and source URL. Add `-d DEVICE_ID` when multiple devices are connected. The fields contain non-working hints only. The app creates a MeshStream session, passes its playback URL to `video_player`, displays P2P/CDN telemetry, and closes the event subscription, player, session, and client when the screen is disposed. See the [integration guide](../README.md) for host setup and supported media types.

For a standalone Android Demo, run `flutter run --release --target lib/main.dart -d YOUR_ANDROID_DEVICE_ID`. To generate an APK, run `flutter build apk --release --target lib/main.dart`; the result is `build/app/outputs/flutter-apk/app-release.apk`. Configure your application ID, version, and production signing before publishing your own application.
