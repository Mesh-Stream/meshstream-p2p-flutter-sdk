# Contributing

Please keep changes focused and add tests for observable behavior. Do not commit Keys, private media URLs, credentials, generated build output, or local SDK paths.

Before opening a pull request, run from the repository root:

```sh
dart format lib test example/lib example/test
flutter analyze
flutter test
cd example
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build ios --simulator --no-codesign
```

Android checks require the Android SDK. iOS checks require macOS, Xcode, and CocoaPods; run `pod install` in `example/ios` after dependency resolution. Include the command results and any environment limitation in the pull request.
