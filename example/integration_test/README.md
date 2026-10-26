# Live iOS/Android interoperability test

This test uses the published `meshstream_p2p: 1.0.0` Flutter package, its public
native SDK dependencies, `video_player`, and the public MeshStream services. It
does not use fake backends. Run it on iOS and Android at the same time so each
can discover the other.

Create a private JSON file outside Git with `MESHSTREAM_ANDROID_KEY` and
`MESHSTREAM_IOS_KEY`. Do not commit that file or build outputs containing it.
Optional settings are `MESHSTREAM_SOURCE` (a media playlist, not an adaptive
master), `MESHSTREAM_CONTENT_ID` (the same on both platforms), and
`MESHSTREAM_SECONDS` (default 180).

From `example/`, run these commands in separate terminals, replacing the device
IDs and private file path:

```sh
flutter test integration_test/live_interop_test.dart \
  -d <ios-simulator-id> \
  --dart-define-from-file /private/tmp/meshstream-interop.json
```

```sh
flutter test integration_test/live_interop_test.dart \
  -d <android-emulator-id> \
  --dart-define-from-file /private/tmp/meshstream-interop.json
```

Both Keys must authorize P2P for the same application. The default source is the
repository's public Mux HLS media playlist. The test logs structured
`MESHSTREAM_INTEROP` samples without Keys or signed playback URLs. It checks that
playback advances, live authorization succeeds, a peer connects, and P2P media
bytes increase. The player, session, client, and event subscription are closed
afterward, including after a failed assertion.

A simulator pass covers simulator interoperability. Record physical-device
acceptance separately.
