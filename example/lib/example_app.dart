import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meshstream_p2p/meshstream_p2p.dart';
import 'package:video_player/video_player.dart';

abstract interface class ExampleBackend {
  Future<ExampleClient> createClient(MeshStreamConfig config);
  Stream<MeshStreamEvent> eventsFor(String sessionId);
}

abstract interface class ExampleClient {
  Future<ExampleSession> createSession(PlaybackSessionOptions options);
  Future<void> close();
}

abstract interface class ExampleSession {
  String get sessionId;
  String get playbackUrl;
  MeshStreamPlaybackMode get playbackMode;
  MeshStreamUnavailableReason? get fallbackReason;
  Future<void> updateCurrentPositionMs(int positionMs);
  Future<void> updateBufferedDurationMs(int durationMs);
  Future<MeshStreamStats> getStats();
  Future<MeshStreamDiagnostics> getDiagnostics();
  Future<void> close();
}

abstract interface class ExamplePlayer {
  bool get isInitialized;
  bool get isPlaying;
  Duration get position;
  Duration get bufferedDuration;
  Widget get view;
  void addListener(VoidCallback listener);
  void removeListener(VoidCallback listener);
  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  Future<void> dispose();
}

typedef ExamplePlayerFactory = ExamplePlayer Function(Uri url);
typedef ExampleCleanupErrorReporter = void Function(
    Object error, StackTrace stack);

String formatTrafficBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

String formatOffloadPercent(int p2pDownloaded, int httpDownloaded) {
  final totalDownloaded = p2pDownloaded + httpDownloaded;
  if (totalDownloaded == 0) return '0%';
  return '${(p2pDownloaded * 100 / totalDownloaded).round()}%';
}

final class MeshStreamExampleBackend implements ExampleBackend {
  const MeshStreamExampleBackend();

  @override
  Future<ExampleClient> createClient(MeshStreamConfig config) async =>
      _SdkClient(await MeshStream.create(config));

  @override
  Stream<MeshStreamEvent> eventsFor(String sessionId) =>
      MeshStream.eventsFor(sessionId: sessionId);
}

final class _SdkClient implements ExampleClient {
  _SdkClient(this.client);
  final MeshStreamClient client;

  @override
  Future<ExampleSession> createSession(PlaybackSessionOptions options) async =>
      _SdkSession(await client.createPlaybackSession(options));

  @override
  Future<void> close() => client.close();
}

final class _SdkSession implements ExampleSession {
  _SdkSession(this.session);
  final MeshStreamPlaybackSession session;

  @override
  String get sessionId => session.sessionId;
  @override
  String get playbackUrl => session.playbackUrl;
  @override
  MeshStreamPlaybackMode get playbackMode => session.playbackMode;
  @override
  MeshStreamUnavailableReason? get fallbackReason => session.fallbackReason;
  @override
  Future<void> updateCurrentPositionMs(int positionMs) =>
      session.updateCurrentPositionMs(positionMs);
  @override
  Future<void> updateBufferedDurationMs(int durationMs) =>
      session.updateBufferedDurationMs(durationMs);
  @override
  Future<MeshStreamStats> getStats() => session.getStats();
  @override
  Future<MeshStreamDiagnostics> getDiagnostics() => session.getDiagnostics();
  @override
  Future<void> close() => session.close();
}

final class VideoPlayerAdapter implements ExamplePlayer {
  VideoPlayerAdapter(Uri url)
      : controller = VideoPlayerController.networkUrl(url);
  final VideoPlayerController controller;

  @override
  bool get isInitialized => controller.value.isInitialized;
  @override
  bool get isPlaying => controller.value.isPlaying;
  @override
  Duration get position => controller.value.position;
  @override
  Duration get bufferedDuration {
    final positionMs = position.inMilliseconds;
    for (final range in controller.value.buffered) {
      if (range.start.inMilliseconds <= positionMs &&
          range.end.inMilliseconds >= positionMs) {
        return range.end - position;
      }
    }
    return Duration.zero;
  }

  @override
  Widget get view => AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: VideoPlayer(controller),
      );
  @override
  void addListener(VoidCallback listener) => controller.addListener(listener);
  @override
  void removeListener(VoidCallback listener) =>
      controller.removeListener(listener);
  @override
  Future<void> initialize() => controller.initialize();
  @override
  Future<void> play() => controller.play();
  @override
  Future<void> pause() => controller.pause();
  @override
  Future<void> dispose() => controller.dispose();
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.backend = const MeshStreamExampleBackend(),
    this.playerFactory = defaultPlayerFactory,
    this.cleanupErrorReporter = defaultCleanupErrorReporter,
  });

  final ExampleBackend backend;
  final ExamplePlayerFactory playerFactory;
  final ExampleCleanupErrorReporter cleanupErrorReporter;

  static ExamplePlayer defaultPlayerFactory(Uri url) => VideoPlayerAdapter(url);

  static void defaultCleanupErrorReporter(Object error, StackTrace stack) {
    FlutterError.reportError(FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'meshstream_p2p_example',
      context: ErrorDescription('while releasing playback resources'),
    ));
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _key = TextEditingController();
  final _url = TextEditingController();
  ExampleClient? _client;
  ExampleSession? _session;
  ExamplePlayer? _player;
  StreamSubscription<MeshStreamEvent>? _events;
  Timer? _statsTimer;
  bool _busy = false;
  bool _disposed = false;
  DateTime? _lastTelemetry;
  int _peerCount = 0;
  MeshStreamStats? _stats;
  MeshStreamDiagnostics? _diagnostics;
  MeshStreamPlaybackMode? _mode;
  MeshStreamUnavailableReason? _fallbackReason;
  String? _error;
  Future<void>? _closingCurrent;

  Future<void> _createSession() async {
    if (_busy) return;
    final key = _key.text.trim();
    final url = _url.text.trim();
    final uri = Uri.tryParse(url);
    if (key.isEmpty ||
        uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      setState(() => _error = 'Enter a Key and an HTTP(S) source URL.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _closeCurrent();
      if (_disposed) return;
      _client = await widget.backend.createClient(MeshStreamConfig(key: key));
      if (_disposed) return;
      _session = await _client!.createSession(PlaybackSessionOptions(url: url));
      if (_disposed) return;
      final session = _session!;
      _mode = session.playbackMode;
      _fallbackReason = session.fallbackReason;
      _events = widget.backend.eventsFor(session.sessionId).listen(_onEvent);
      _player = widget.playerFactory(Uri.parse(session.playbackUrl));
      _player!.addListener(_onPlayerChanged);
      await _player!.initialize();
      if (_disposed) return;
      _statsTimer =
          Timer.periodic(const Duration(seconds: 5), (_) => _refreshStats());
      await _refreshStats();
      if (_disposed) return;
      await _player!.play();
      if (mounted) setState(() {});
    } catch (error) {
      await _closeCurrent();
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (_disposed) await _closeCurrent();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onEvent(MeshStreamEvent event) {
    if (!mounted) return;
    setState(() {
      switch (event.type) {
        case MeshStreamEventName.peerCountChanged:
          _peerCount = event.peerCount ?? 0;
        case MeshStreamEventName.p2pReady:
          _mode = MeshStreamPlaybackMode.nativeP2p;
          _fallbackReason = null;
        case MeshStreamEventName.p2pUnavailable:
          _mode = MeshStreamPlaybackMode.nativeCdn;
          _fallbackReason = event.reason;
        case MeshStreamEventName.statistics:
          _stats = event.statistics;
        default:
          break;
      }
    });
  }

  void _onPlayerChanged() {
    if (!mounted || _session == null || _player == null) return;
    setState(() {});
    final now = DateTime.now();
    if (_lastTelemetry != null &&
        now.difference(_lastTelemetry!) < const Duration(seconds: 1)) {
      return;
    }
    final player = _player!;
    if (!player.isInitialized) return;
    _lastTelemetry = now;
    unawaited(_sendTelemetry(_session!, player));
  }

  Future<void> _sendTelemetry(
      ExampleSession session, ExamplePlayer player) async {
    try {
      await session.updateCurrentPositionMs(player.position.inMilliseconds);
      await session
          .updateBufferedDurationMs(player.bufferedDuration.inMilliseconds);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _refreshStats() async {
    final session = _session;
    if (session == null) return;
    try {
      final stats = await session.getStats();
      final diagnostics = await session.getDiagnostics();
      if (mounted && identical(session, _session)) {
        setState(() {
          _stats = stats;
          _diagnostics = diagnostics;
          _peerCount = stats.connectedPeers;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _closeCurrent() => _closingCurrent ??=
      _closeCurrentResources().whenComplete(() => _closingCurrent = null);

  Future<void> _closeCurrentResources() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    final events = _events;
    _events = null;
    final player = _player;
    _player = null;
    final session = _session;
    _session = null;
    final client = _client;
    _client = null;
    _stats = null;
    _diagnostics = null;
    _peerCount = 0;
    _mode = null;
    _fallbackReason = null;
    _lastTelemetry = null;

    Object? firstError;
    StackTrace? firstStack;
    Future<void> attempt(FutureOr<void> Function() release) async {
      try {
        await release();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }

    if (events != null) await attempt(events.cancel);
    if (player != null) {
      await attempt(() => player.removeListener(_onPlayerChanged));
      await attempt(player.dispose);
    }
    if (session != null) await attempt(session.close);
    if (client != null) await attempt(client.close);

    if (firstError != null) {
      if (!_disposed && mounted) {
        setState(() => _error = firstError.toString());
      }
      try {
        widget.cleanupErrorReporter(firstError!, firstStack!);
      } catch (reportError) {
        debugPrint(
            'Playback cleanup failed: $firstError; error reporting failed: $reportError');
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_closeCurrent());
    _key.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('MeshStream P2P example')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            TextField(
                controller: _key,
                decoration: const InputDecoration(
                    labelText: 'Key', hintText: 'key_your_meshstream_key')),
            TextField(
                controller: _url,
                decoration: const InputDecoration(
                    labelText: 'Source URL',
                    hintText: 'https://cdn.example.com/live/playlist.m3u8')),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: _busy ? null : _createSession,
                child: const Text('Create session')),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_player != null && _player!.isInitialized) ...[
              const SizedBox(height: 16),
              KeyedSubtree(
                  key: const Key('playback-player'), child: _player!.view),
              TextButton(
                  onPressed: () =>
                      _player!.isPlaying ? _player!.pause() : _player!.play(),
                  child: Text(_player!.isPlaying ? 'Pause' : 'Play')),
            ],
            if (_session != null) ...[
              Text('Playback mode: ${_mode?.name ?? 'unknown'}'),
              const SizedBox(height: 8),
              Text('Peers: $_peerCount'),
              Text(
                  'P2P down: ${formatTrafficBytes(_stats?.p2pDownloaded ?? 0)}'),
              Text(
                  'HTTP down: ${formatTrafficBytes(_stats?.httpDownloaded ?? 0)}'),
              Text('P2P up: ${formatTrafficBytes(_stats?.p2pUploaded ?? 0)}'),
              Text(
                  'Offload: ${formatOffloadPercent(_stats?.p2pDownloaded ?? 0, _stats?.httpDownloaded ?? 0)}'),
              const SizedBox(height: 8),
              Text('Fallback reason: ${_fallbackReason?.wireName ?? 'none'}'),
              Text(
                  'Diagnostics: ${_diagnostics == null ? 'loading' : 'fallbacks ${_diagnostics!.fallbackCount}, tracker ${_diagnostics!.lastTrackerError ?? 'none'}, peer ${_diagnostics!.lastPeerError ?? 'none'}'}'),
            ],
          ]),
        ),
      );
}
