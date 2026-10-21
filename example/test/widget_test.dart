import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshstream_p2p/meshstream_p2p.dart';
import 'package:meshstream_p2p_example/example_app.dart';

void main() {
  testWidgets('shows session inputs before creating a player', (tester) async {
    final backend = _FakeBackend();
    await tester.pumpWidget(MyApp(
      backend: backend,
      playerFactory: (_) => _FakePlayer(backend.actions),
    ));

    expect(find.widgetWithText(TextField, 'Key'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Source URL'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Content ID (optional)'),
        findsOneWidget);
    expect(find.text('Mime type'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Create session'), findsOneWidget);
    expect(find.byKey(const Key('playback-player')), findsNothing);
    expect(backend.actions, isEmpty);
  });

  testWidgets('uses the returned URL and releases playback in order',
      (tester) async {
    final backend = _FakeBackend();
    Uri? playerUrl;
    await tester.pumpWidget(MyApp(
      backend: backend,
      playerFactory: (url) {
        playerUrl = url;
        return _FakePlayer(backend.actions);
      },
    ));

    await tester.enterText(find.widgetWithText(TextField, 'Key'), 'test-key');
    await tester.enterText(find.widgetWithText(TextField, 'Source URL'),
        'https://cdn.example.com/demo.m3u8');
    await tester.tap(find.widgetWithText(FilledButton, 'Create session'));
    await tester.pumpAndSettle();

    expect(playerUrl.toString(), 'https://cdn.example.com/meshstream.m3u8');
    expect(find.byKey(const Key('playback-player')), findsOneWidget);
    expect(find.text('Playback mode: nativeP2p'), findsOneWidget);
    expect(find.text('P2P downloaded: 120 bytes'), findsOneWidget);
    expect(find.text('CDN downloaded: 30 bytes'), findsOneWidget);
    expect(backend.actions, contains('position:2500'));
    expect(backend.actions, contains('buffer:4000'));

    backend.emit(const MeshStreamEvent.p2pUnavailable(
      clientId: 'client-1',
      sessionId: 'session-1',
      reason: MeshStreamUnavailableReason.noPeers,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Playback mode: nativeCdn'), findsOneWidget);
    expect(find.text('Fallback reason: NO_PEERS'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    for (var i = 0; i < 10 && !backend.closed.isCompleted; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(backend.actions.sublist(backend.actions.indexOf('events:cancel')),
        ['events:cancel', 'player:dispose', 'session:close', 'client:close']);
  });
}

class _FakeBackend implements ExampleBackend {
  final actions = <String>[];
  final closed = Completer<void>();
  late final _events = StreamController<MeshStreamEvent>.broadcast(
    onCancel: () => actions.add('events:cancel'),
  );

  @override
  Future<ExampleClient> createClient(MeshStreamConfig config) async {
    actions.add('client:create:${config.key}');
    return _FakeClient(actions, closed);
  }

  @override
  Stream<MeshStreamEvent> eventsFor(String sessionId) {
    assert(sessionId == 'session-1');
    return _events.stream;
  }

  void emit(MeshStreamEvent event) => _events.add(event);
}

class _FakeClient implements ExampleClient {
  _FakeClient(this.actions, this.closed);
  final List<String> actions;
  final Completer<void> closed;

  @override
  Future<ExampleSession> createSession(PlaybackSessionOptions options) async {
    actions.add('session:create:${options.url}');
    return _FakeSession(actions);
  }

  @override
  Future<void> close() async {
    actions.add('client:close');
    closed.complete();
  }
}

class _FakeSession implements ExampleSession {
  _FakeSession(this.actions);
  final List<String> actions;

  @override
  String get sessionId => 'session-1';
  @override
  String get playbackUrl => 'https://cdn.example.com/meshstream.m3u8';
  @override
  MeshStreamPlaybackMode get playbackMode => MeshStreamPlaybackMode.nativeP2p;
  @override
  MeshStreamUnavailableReason? get fallbackReason => null;
  @override
  Future<void> updateCurrentPositionMs(int positionMs) async =>
      actions.add('position:$positionMs');
  @override
  Future<void> updateBufferedDurationMs(int durationMs) async =>
      actions.add('buffer:$durationMs');
  @override
  Future<MeshStreamStats> getStats() async => const MeshStreamStats(
        httpDownloaded: 30,
        p2pDownloaded: 120,
        p2pUploaded: 0,
        httpSegmentDownloadSuccesses: 1,
        httpSegmentDownloadFailures: 0,
        p2pSegmentDownloadSuccesses: 2,
        p2pSegmentDownloadFailures: 0,
        p2pSegmentUploadSuccesses: 0,
        p2pSegmentUploadFailures: 0,
        connectedPeers: 2,
        peerConnectErrors: 0,
        trackerErrors: 0,
        downloadOffloadRatio: 0.8,
        p2pSegmentDownloadSuccessRatio: 1,
        p2pSegmentUploadSuccessRatio: 0,
      );
  @override
  Future<MeshStreamDiagnostics> getDiagnostics() async =>
      const MeshStreamDiagnostics(
        fallbackCount: 0,
        iceAttempts: 0,
        iceSuccesses: 0,
        iceFailures: 0,
        iceDurationMs: 0,
      );
  @override
  Future<void> close() async => actions.add('session:close');
}

class _FakePlayer implements ExamplePlayer {
  _FakePlayer(this.actions);
  final List<String> actions;
  VoidCallback? listener;
  bool _initialized = false;
  bool _playing = false;

  @override
  bool get isInitialized => _initialized;
  @override
  bool get isPlaying => _playing;
  @override
  Duration get position => const Duration(milliseconds: 2500);
  @override
  Duration get bufferedDuration => const Duration(milliseconds: 4000);
  @override
  Widget get view => const Text('Fake video');
  @override
  void addListener(VoidCallback value) => listener = value;
  @override
  void removeListener(VoidCallback value) => listener = null;
  @override
  Future<void> initialize() async {
    _initialized = true;
    listener?.call();
  }

  @override
  Future<void> play() async {
    _playing = true;
    listener?.call();
  }

  @override
  Future<void> pause() async {
    _playing = false;
    listener?.call();
  }

  @override
  Future<void> dispose() async => actions.add('player:dispose');
}
