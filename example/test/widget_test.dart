import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshstream_p2p/meshstream_p2p.dart';
import 'package:meshstream_p2p_example/example_app.dart';

void main() {
  test('formats traffic metrics like the web demo', () {
    expect(formatTrafficBytes(0), '0 B');
    expect(formatTrafficBytes(1023), '1023 B');
    expect(formatTrafficBytes(1024), '1.0 KB');
    expect(formatTrafficBytes(2338324), '2.23 MB');
    expect(formatTrafficBytes(20080230), '19.15 MB');
    expect(formatTrafficBytes(3565158), '3.40 MB');
    expect(formatOffloadPercent(2338324, 20080230), '10%');
    expect(formatOffloadPercent(0, 0), '0%');
  });

  testWidgets('shows session inputs before creating a player', (tester) async {
    final backend = _FakeBackend();
    await tester.pumpWidget(MyApp(
      backend: backend,
      playerFactory: (_) => _FakePlayer(backend.actions),
    ));

    expect(find.widgetWithText(TextField, 'Key'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Source URL'), findsOneWidget);
    expect(
        find.widgetWithText(TextField, 'Content ID (optional)'), findsNothing);
    expect(find.text('Mime type'), findsNothing);
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

    expect(backend.lastSessionOptions!.contentId, isNull);
    expect(backend.lastSessionOptions!.mimeType, isNull);
    expect(playerUrl.toString(), 'https://cdn.example.com/meshstream.m3u8');
    expect(find.byKey(const Key('playback-player')), findsOneWidget);
    expect(find.text('Playback mode: nativeP2p'), findsOneWidget);
    expect(find.text('Peers: 2'), findsOneWidget);
    expect(find.text('P2P down: 120 B'), findsOneWidget);
    expect(find.text('HTTP down: 30 B'), findsOneWidget);
    expect(find.text('P2P up: 0 B'), findsOneWidget);
    expect(find.text('Offload: 80%'), findsOneWidget);
    expect(backend.actions, contains('position:2500'));
    expect(backend.actions, contains('buffer:4000'));

    backend.emit(const MeshStreamEvent.cdnFallback(
      clientId: 'client-1',
      sessionId: 'session-1',
      bytes: 12,
    ));
    backend.emit(const MeshStreamEvent.cdnFallback(
      clientId: 'client-1',
      sessionId: 'session-1',
      bytes: 7,
    ));
    await tester.pumpAndSettle();
    expect(find.text('Playback mode: nativeP2p'), findsOneWidget);
    expect(find.textContaining('CDN fallback:'), findsNothing);

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

  testWidgets('refreshes session statistics every two seconds', (tester) async {
    final backend = _FakeBackend();
    await tester.pumpWidget(MyApp(
      backend: backend,
      playerFactory: (_) => _FakePlayer(backend.actions),
    ));
    await tester.enterText(find.widgetWithText(TextField, 'Key'), 'test-key');
    await tester.enterText(find.widgetWithText(TextField, 'Source URL'),
        'https://cdn.example.com/demo.m3u8');
    await tester.tap(find.widgetWithText(FilledButton, 'Create session'));
    await tester.pumpAndSettle();

    backend.actions.clear();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(backend.actions, ['stats:get', 'diagnostics:get']);
  });

  testWidgets('cleanup reports first failure and still releases every owner',
      (tester) async {
    final backend = _FakeBackend(
      failEventCancel: true,
      failSessionClose: true,
    );
    final reported = <Object>[];

    await tester.pumpWidget(MyApp(
      backend: backend,
      playerFactory: (_) => _FakePlayer(backend.actions, failDispose: true),
      cleanupErrorReporter: (error, _) => reported.add(error),
    ));
    await tester.enterText(find.widgetWithText(TextField, 'Key'), 'test-key');
    await tester.enterText(find.widgetWithText(TextField, 'Source URL'),
        'https://cdn.example.com/demo.m3u8');
    await tester.tap(find.widgetWithText(FilledButton, 'Create session'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    for (var i = 0; i < 10 && !backend.closed.isCompleted; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(backend.actions.sublist(backend.actions.indexOf('events:cancel')),
        ['events:cancel', 'player:dispose', 'session:close', 'client:close']);
    expect(reported, hasLength(1));
    expect(reported.single.toString(), contains('cancel failed'));
  });
}

class _FakeBackend implements ExampleBackend {
  _FakeBackend({
    this.failEventCancel = false,
    this.failSessionClose = false,
  });
  final bool failEventCancel;
  final bool failSessionClose;
  final actions = <String>[];
  final closed = Completer<void>();
  PlaybackSessionOptions? lastSessionOptions;
  late final _events = StreamController<MeshStreamEvent>.broadcast(
    onCancel: () {
      if (!failEventCancel) actions.add('events:cancel');
    },
  );

  @override
  Future<ExampleClient> createClient(MeshStreamConfig config) async {
    actions.add('client:create:${config.key}');
    return _FakeClient(actions, closed, failSessionClose, (options) {
      lastSessionOptions = options;
    });
  }

  @override
  Stream<MeshStreamEvent> eventsFor(String sessionId) {
    assert(sessionId == 'session-1');
    if (failEventCancel) {
      return _FailingCancelStream(_events.stream, actions);
    }
    return _events.stream;
  }

  void emit(MeshStreamEvent event) => _events.add(event);
}

class _FailingCancelStream extends Stream<MeshStreamEvent> {
  _FailingCancelStream(this.source, this.actions);
  final Stream<MeshStreamEvent> source;
  final List<String> actions;

  @override
  StreamSubscription<MeshStreamEvent> listen(
    void Function(MeshStreamEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      _FailingCancelSubscription(
        source.listen(onData,
            onError: onError, onDone: onDone, cancelOnError: cancelOnError),
        actions,
      );
}

class _FailingCancelSubscription
    implements StreamSubscription<MeshStreamEvent> {
  _FailingCancelSubscription(this.inner, this.actions);
  final StreamSubscription<MeshStreamEvent> inner;
  final List<String> actions;

  @override
  Future<void> cancel() async {
    actions.add('events:cancel');
    await inner.cancel();
    throw StateError('cancel failed');
  }

  @override
  Future<E> asFuture<E>([E? futureValue]) => inner.asFuture(futureValue);
  @override
  bool get isPaused => inner.isPaused;
  @override
  void onData(void Function(MeshStreamEvent)? handleData) =>
      inner.onData(handleData);
  @override
  void onDone(void Function()? handleDone) => inner.onDone(handleDone);
  @override
  void onError(Function? handleError) => inner.onError(handleError);
  @override
  void pause([Future<void>? resumeSignal]) => inner.pause(resumeSignal);
  @override
  void resume() => inner.resume();
}

class _FakeClient implements ExampleClient {
  _FakeClient(this.actions, this.closed, this.failSessionClose, this.onCreate);
  final List<String> actions;
  final Completer<void> closed;
  final bool failSessionClose;
  final void Function(PlaybackSessionOptions options) onCreate;

  @override
  Future<ExampleSession> createSession(PlaybackSessionOptions options) async {
    actions.add('session:create:${options.url}');
    onCreate(options);
    return _FakeSession(actions, failSessionClose);
  }

  @override
  Future<void> close() async {
    actions.add('client:close');
    closed.complete();
  }
}

class _FakeSession implements ExampleSession {
  _FakeSession(this.actions, this.failClose);
  final List<String> actions;
  final bool failClose;

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
  Future<MeshStreamStats> getStats() async {
    actions.add('stats:get');
    return const MeshStreamStats(
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
  }

  @override
  Future<MeshStreamDiagnostics> getDiagnostics() async {
    actions.add('diagnostics:get');
    return const MeshStreamDiagnostics(
      fallbackCount: 0,
      iceAttempts: 0,
      iceSuccesses: 0,
      iceFailures: 0,
      iceDurationMs: 0,
    );
  }

  @override
  Future<void> close() async {
    actions.add('session:close');
    if (failClose) throw StateError('session close failed');
  }
}

class _FakePlayer implements ExamplePlayer {
  _FakePlayer(this.actions, {this.failDispose = false});
  final List<String> actions;
  final bool failDispose;
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
  Future<void> dispose() async {
    actions.add('player:dispose');
    if (failDispose) throw StateError('player dispose failed');
  }
}
