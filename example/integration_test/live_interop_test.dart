import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:meshstream_p2p/meshstream_p2p.dart';
import 'package:video_player/video_player.dart';

// Run on iOS and Android at the same time with the same media playlist.
// Pass Keys using --dart-define-from-file pointing to an untracked local file.
// This test uses the real Flutter plugins, public native SDKs, and live services.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('live native playback and cross-platform peer discovery',
      (tester) async {
    const androidKey = String.fromEnvironment('MESHSTREAM_ANDROID_KEY');
    const iosKey = String.fromEnvironment('MESHSTREAM_IOS_KEY');
    const source = String.fromEnvironment(
      'MESHSTREAM_SOURCE',
      defaultValue:
          'https://test-streams.mux.dev/x36xhzz/url_2/193039199_mp4_h264_aac_ld_7.m3u8',
    );
    const contentId = String.fromEnvironment(
      'MESHSTREAM_CONTENT_ID',
      defaultValue: 'flutter-live-interop',
    );
    const seconds =
        int.fromEnvironment('MESHSTREAM_SECONDS', defaultValue: 180);
    final platform = Platform.isIOS ? 'ios' : 'android';
    final key = Platform.isIOS ? iosKey : androidKey;
    expect(key, isNotEmpty, reason: 'Supply this platform\'s Key at runtime.');

    void record(String kind, Map<String, Object?> values) {
      // Never include Keys, signed URLs, or session credentials in the record.
      // ignore: avoid_print
      print('MESHSTREAM_INTEROP ${jsonEncode({
            'time': DateTime.now().toUtc().toIso8601String(),
            'platform': platform,
            'kind': kind,
            ...values,
          })}');
    }

    final client = await MeshStream.create(MeshStreamConfig(key: key));
    MeshStreamPlaybackSession? session;
    VideoPlayerController? player;
    StreamSubscription<MeshStreamEvent>? events;
    var maxPeers = 0;
    var peerSamples = 0;
    var maxP2pDownloaded = 0;
    var maxP2pUploaded = 0;
    var maxPositionMs = 0;
    var maxHttpDownloaded = 0;
    var effectiveP2pEnabled = false;
    var trackerErrors = 0;
    var peerErrors = 0;

    try {
      session = await client.createPlaybackSession(PlaybackSessionOptions(
        url: source,
        contentId: contentId,
        mimeType: MeshStreamMimeType.m3u8,
      ));
      final activeSession = session;
      record('session', {
        'mode': session.playbackMode.name,
        'fallback': session.fallbackReason?.name,
        'playbackHost': Uri.parse(session.playbackUrl).host,
      });
      events =
          MeshStream.eventsFor(sessionId: session.sessionId).listen((event) {
        if (event.type == MeshStreamEventName.trackerError) trackerErrors++;
        if (event.type == MeshStreamEventName.peerConnectError) peerErrors++;
      });
      player = VideoPlayerController.networkUrl(Uri.parse(session.playbackUrl));
      final activePlayer = player;
      await player.initialize().timeout(const Duration(seconds: 60));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: VideoPlayer(activePlayer))),
      ));
      await player.play();
      record('player', {
        'initialized': player.value.isInitialized,
        'width': player.value.size.width,
        'height': player.value.size.height,
        'durationMs': player.value.duration.inMilliseconds,
      });

      await tester.runAsync(() async {
        final started = DateTime.now();
        while (DateTime.now().difference(started).inSeconds < seconds) {
          final position = activePlayer.value.position.inMilliseconds;
          var bufferedMs = 0;
          for (final range in activePlayer.value.buffered) {
            if (range.start.inMilliseconds <= position &&
                range.end.inMilliseconds >= position) {
              bufferedMs = range.end.inMilliseconds - position;
              break;
            }
          }
          await activeSession.updateCurrentPositionMs(position);
          await activeSession.updateBufferedDurationMs(bufferedMs);
          final status = await client.getStatus();
          final stats = await activeSession.getStats();
          final diagnostics = await activeSession.getDiagnostics();
          if (position > maxPositionMs) maxPositionMs = position;
          if (stats.connectedPeers > maxPeers) maxPeers = stats.connectedPeers;
          if (stats.connectedPeers > 0) peerSamples++;
          if (stats.p2pDownloaded > maxP2pDownloaded) {
            maxP2pDownloaded = stats.p2pDownloaded;
          }
          if (stats.p2pUploaded > maxP2pUploaded) {
            maxP2pUploaded = stats.p2pUploaded;
          }
          if (stats.httpDownloaded > maxHttpDownloaded) {
            maxHttpDownloaded = stats.httpDownloaded;
          }
          effectiveP2pEnabled |= status.effectiveP2pEnabled;
          record('sample', {
            'elapsedSeconds': DateTime.now().difference(started).inSeconds,
            'positionMs': position,
            'bufferedMs': bufferedMs,
            'playing': activePlayer.value.isPlaying,
            'playerError': activePlayer.value.errorDescription,
            'p2pEnabled': status.effectiveP2pEnabled,
            'statusReason': status.reason.name,
            'peers': stats.connectedPeers,
            'httpDownloaded': stats.httpDownloaded,
            'p2pDownloaded': stats.p2pDownloaded,
            'p2pUploaded': stats.p2pUploaded,
            'trackerErrors': stats.trackerErrors,
            'peerErrors': stats.peerConnectErrors,
            'firstPeerConnectMs': diagnostics.firstPeerConnectMs,
            'iceAttempts': diagnostics.iceAttempts,
            'iceSuccesses': diagnostics.iceSuccesses,
            'iceFailures': diagnostics.iceFailures,
            'fallbackCount': diagnostics.fallbackCount,
          });
          await Future<void>.delayed(const Duration(seconds: 5));
        }
      });

      record('summary', {
        'maxPeers': maxPeers,
        'peerSamples': peerSamples,
        'maxPositionMs': maxPositionMs,
        'httpDownloaded': maxHttpDownloaded,
        'p2pDownloaded': maxP2pDownloaded,
        'p2pUploaded': maxP2pUploaded,
        'p2pEnabled': effectiveP2pEnabled,
        'trackerErrorEvents': trackerErrors,
        'peerErrorEvents': peerErrors,
      });
      expect(maxPositionMs, greaterThan(5000),
          reason: 'Playback must advance.');
      expect(effectiveP2pEnabled, isTrue,
          reason: 'Live authorization must pass.');
      expect(maxPeers, greaterThan(0), reason: 'A live peer must connect.');
      expect(maxP2pDownloaded + maxP2pUploaded, greaterThan(0),
          reason: 'The peers must exchange media bytes.');
    } finally {
      await events?.cancel();
      await player?.dispose();
      await session?.close();
      await client.close();
      record('cleanup', {'closed': true});
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
