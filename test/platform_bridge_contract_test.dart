import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshstream_p2p/src/meshstream_exception.dart';
import 'package:meshstream_p2p/src/models.dart';
import 'package:meshstream_p2p/src/pigeon/generated/meshstream_api.g.dart'
    as api;
import 'package:meshstream_p2p/src/platform/pigeon_meshstream_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all eleven host operations forward IDs, values, and typed replies',
      () async {
    final host = _RecordingHost();
    final bridge = PigeonMeshStreamPlatform(hostApi: host);
    expect(
        (await bridge
                .createClient(MeshStreamConfig(key: 'key', p2pEnabled: false)))
            .clientId,
        'c1');
    final session = await bridge.createPlaybackSession(
        'c1',
        PlaybackSessionOptions(
          url: 'https://cdn.example/a.mp4',
          contentId: 'movie',
          mimeType: MeshStreamMimeType.mp4,
          originHeaders: {'X-Test': 'value'},
        ));
    expect((session.sessionId, session.playbackUrl, session.playbackMode),
        ('s1', 'http://127.0.0.1/a.mp4', MeshStreamPlaybackMode.nativeP2p));
    expect(await bridge.preload('c1', 's1'), true);
    await bridge.setP2pEnabled('c1', 's1', false);
    await bridge.updateBufferedDurationMs('c1', 's1', 500);
    await bridge.updateCurrentPositionMs('c1', 's1', 250);
    final status = await bridge.getStatus('c1');
    final stats = await bridge.getStats('c1', 's1');
    final diagnostics = await bridge.getDiagnostics('c1', 's1');
    await bridge.closeSession('c1', 's1');
    await bridge.closeClient('c1');
    expect(host.calls, [
      'createClient:key:false',
      'createPlaybackSession:c1:https://cdn.example/a.mp4:movie:mp4:value',
      'preload:c1:s1',
      'setP2pEnabled:c1:s1:false',
      'updateBufferedDurationMs:c1:s1:500',
      'updateCurrentPositionMs:c1:s1:250',
      'getStatus:c1',
      'getStats:c1:s1',
      'getDiagnostics:c1:s1',
      'closeSession:c1:s1',
      'closeClient:c1',
    ]);
    expect((
      status.accountEnabled,
      status.applicationEnabled,
      status.keyEnabled,
      status.platformEnabled,
      status.effectiveP2pEnabled,
      status.reason,
      status.configVersion,
      status.edgeRegion,
      status.quotaStatus,
      status.trackerPoolReady
    ), (
      true,
      false,
      true,
      true,
      false,
      MeshStreamUnavailableReason.appDisabled,
      'v2',
      'eu',
      'limited',
      true
    ));
    expect((
      stats.httpDownloaded,
      stats.p2pDownloaded,
      stats.p2pUploaded,
      stats.httpSegmentDownloadSuccesses,
      stats.httpSegmentDownloadFailures,
      stats.p2pSegmentDownloadSuccesses,
      stats.p2pSegmentDownloadFailures,
      stats.p2pSegmentUploadSuccesses,
      stats.p2pSegmentUploadFailures,
      stats.connectedPeers,
      stats.peerConnectErrors,
      stats.trackerErrors,
      stats.downloadOffloadRatio,
      stats.p2pSegmentDownloadSuccessRatio,
      stats.p2pSegmentUploadSuccessRatio
    ), (
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
      11,
      12,
      0.25,
      0.5,
      0.75
    ));
    expect((
      diagnostics.fallbackCount,
      diagnostics.firstPeerConnectMs,
      diagnostics.coldStart?.p2pDownloaded,
      diagnostics.coldStart?.httpDownloaded,
      diagnostics.lastTrackerError,
      diagnostics.lastPeerError,
      diagnostics.lastErrorAtMs,
      diagnostics.iceAttempts,
      diagnostics.iceSuccesses,
      diagnostics.iceFailures,
      diagnostics.iceDurationMs
    ), (
      1,
      33,
      44,
      55,
      'tracker',
      'peer',
      123,
      8,
      6,
      2,
      99
    ));
  });

  test('all 21 unavailable reasons decode by exact wire values', () async {
    final host = _RecordingHost();
    final bridge = PigeonMeshStreamPlatform(hostApi: host);
    const wires = <String, MeshStreamUnavailableReason>{
      'OK': MeshStreamUnavailableReason.ok,
      'ACCOUNT_DISABLED': MeshStreamUnavailableReason.accountDisabled,
      'APP_DISABLED': MeshStreamUnavailableReason.appDisabled,
      'APP_NOT_FOUND': MeshStreamUnavailableReason.appNotFound,
      'KEY_DISABLED': MeshStreamUnavailableReason.keyDisabled,
      'PLATFORM_DISABLED': MeshStreamUnavailableReason.platformDisabled,
      'ORIGIN_DENIED': MeshStreamUnavailableReason.originDenied,
      'PACKAGE_DENIED': MeshStreamUnavailableReason.packageDenied,
      'BUNDLE_DENIED': MeshStreamUnavailableReason.bundleDenied,
      'SIGNING_CERT_DENIED': MeshStreamUnavailableReason.signingCertDenied,
      'TEAM_DENIED': MeshStreamUnavailableReason.teamDenied,
      'AUTH_FAILED': MeshStreamUnavailableReason.authFailed,
      'CONFIG_UNAVAILABLE': MeshStreamUnavailableReason.configUnavailable,
      'TRACKER_ERROR': MeshStreamUnavailableReason.trackerError,
      'NO_PEERS': MeshStreamUnavailableReason.noPeers,
      'UNSUPPORTED': MeshStreamUnavailableReason.unsupported,
      'INITIALIZATION_FAILED': MeshStreamUnavailableReason.initializationFailed,
      'DISABLED': MeshStreamUnavailableReason.disabled,
      'KEY_P2P_DISABLED': MeshStreamUnavailableReason.keyP2pDisabled,
      'QUOTA_EXHAUSTED': MeshStreamUnavailableReason.quotaExhausted,
      'QUOTA_DISABLED': MeshStreamUnavailableReason.quotaDisabled,
    };
    expect(wires.length, 21);
    for (final entry in wires.entries) {
      host.reason = entry.key;
      expect((await bridge.getStatus('c1')).reason, entry.value);
      host.mode = 'NATIVE_CDN';
      expect(
          (await bridge.createPlaybackSession(
                  'c1', PlaybackSessionOptions(url: 'u')))
              .fallbackReason,
          entry.value);
    }
    host.reason = 'UNKNOWN_REASON';
    await expectLater(bridge.getStatus('c1'), throwsFormatException);
  });

  for (final scenario in <({
    Map<String, Object?> payload,
    MeshStreamEventName type,
    Object? detail
  })>[
    (
      payload: {'type': 'peerCountChanged', 'peerCount': 3},
      type: MeshStreamEventName.peerCountChanged,
      detail: 3
    ),
    (
      payload: {'type': 'playbackPrepared', 'playbackUrl': 'local'},
      type: MeshStreamEventName.playbackPrepared,
      detail: 'local'
    ),
    (
      payload: {'type': 'p2pReady'},
      type: MeshStreamEventName.p2pReady,
      detail: null
    ),
    (
      payload: {'type': 'p2pUnavailable', 'reason': 'NO_PEERS'},
      type: MeshStreamEventName.p2pUnavailable,
      detail: MeshStreamUnavailableReason.noPeers
    ),
    (
      payload: {'type': 'statistics', 'statistics': _statsMap},
      type: MeshStreamEventName.statistics,
      detail: 2
    ),
    (
      payload: {'type': 'cdnFallback', 'bytes': 7},
      type: MeshStreamEventName.cdnFallback,
      detail: 7
    ),
    (
      payload: {'type': 'trackerError', 'totalErrors': 4},
      type: MeshStreamEventName.trackerError,
      detail: 4
    ),
    (
      payload: {'type': 'peerConnectError', 'totalErrors': 5},
      type: MeshStreamEventName.peerConnectError,
      detail: 5
    ),
  ]) {
    test('EventChannel decodes ${scenario.type.name}', () async {
      final event = await _event(
          {...scenario.payload, 'clientId': 'c1', 'sessionId': 's1'});
      expect((event.clientId, event.sessionId, event.type),
          ('c1', 's1', scenario.type));
      final detail = switch (event.type) {
        MeshStreamEventName.peerCountChanged => event.peerCount,
        MeshStreamEventName.playbackPrepared => event.playbackUrl,
        MeshStreamEventName.p2pReady => null,
        MeshStreamEventName.p2pUnavailable => event.reason,
        MeshStreamEventName.statistics => event.statistics?.p2pDownloaded,
        MeshStreamEventName.cdnFallback => event.bytes,
        MeshStreamEventName.trackerError ||
        MeshStreamEventName.peerConnectError =>
          event.totalErrors,
      };
      expect(detail, scenario.detail);
    });
  }

  test('EventChannel rejects unknown and malformed payloads', () async {
    await expectLater(
        _event({'type': 'bogus', 'clientId': 'c1', 'sessionId': 's1'}),
        throwsFormatException);
    await expectLater(
        _event(
            {'type': 'peerCountChanged', 'clientId': 'c1', 'sessionId': 's1'}),
        throwsA(isA<TypeError>()));
  });

  test('EventChannel native errors preserve code and details', () async {
    final channel = EventChannel('test.meshstream.errors');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockStreamHandler(
        channel,
        MockStreamHandler.inline(
          onListen: (_, events) => events.error(
              code: 'TRACKER_ERROR', message: 'down', details: {'retry': 1}),
        ));
    addTearDown(() => messenger.setMockStreamHandler(channel, null));
    final bridge = PigeonMeshStreamPlatform(eventChannel: channel);
    await expectLater(
        bridge.events.first,
        throwsA(isA<MeshStreamException>()
            .having((e) => e.code, 'code', 'TRACKER_ERROR')
            .having((e) => e.details?['retry'], 'retry', 1)));
  });
}

Future<MeshStreamEvent> _event(Map<String, Object?> payload) async {
  final channel =
      EventChannel('test.meshstream.${payload['type']}.${payload.hashCode}');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockStreamHandler(
      channel,
      MockStreamHandler.inline(
        onListen: (_, events) => events.success(payload),
      ));
  final bridge = PigeonMeshStreamPlatform(eventChannel: channel);
  try {
    return await bridge.events.first;
  } finally {
    messenger.setMockStreamHandler(channel, null);
  }
}

const _statsMap = <String, Object?>{
  'httpDownloaded': 1,
  'p2pDownloaded': 2,
  'p2pUploaded': 3,
  'httpSegmentDownloadSuccesses': 4,
  'httpSegmentDownloadFailures': 5,
  'p2pSegmentDownloadSuccesses': 6,
  'p2pSegmentDownloadFailures': 7,
  'p2pSegmentUploadSuccesses': 8,
  'p2pSegmentUploadFailures': 9,
  'connectedPeers': 10,
  'peerConnectErrors': 11,
  'trackerErrors': 12,
  'downloadOffloadRatio': 0.25,
  'p2pSegmentDownloadSuccessRatio': 0.5,
  'p2pSegmentUploadSuccessRatio': 0.75,
};

class _RecordingHost extends api.MeshStreamHostApi {
  final calls = <String>[];
  String reason = 'APP_DISABLED';
  String mode = 'NATIVE_P2P';

  @override
  Future<api.ApiClientReply> createClient(api.ApiClientConfig config) async {
    calls.add('createClient:${config.key}:${config.p2pEnabled}');
    return api.ApiClientReply(clientId: 'c1');
  }

  @override
  Future<api.ApiSessionReply> createPlaybackSession(
      String clientId, api.ApiPlaybackSessionOptions options) async {
    calls.add(
        'createPlaybackSession:$clientId:${options.url}:${options.contentId}:${options.mimeType}:${options.originHeaders?['X-Test']}');
    return api.ApiSessionReply(
        sessionId: 's1',
        playbackUrl: 'http://127.0.0.1/a.mp4',
        playbackMode: mode,
        fallbackReason: mode == 'NATIVE_CDN' ? reason : null);
  }

  @override
  Future<bool> preload(String clientId, String sessionId) async {
    calls.add('preload:$clientId:$sessionId');
    return true;
  }

  @override
  Future<void> setP2pEnabled(
          String clientId, String sessionId, bool enabled) async =>
      calls.add('setP2pEnabled:$clientId:$sessionId:$enabled');
  @override
  Future<void> updateBufferedDurationMs(
          String clientId, String sessionId, int durationMs) async =>
      calls.add('updateBufferedDurationMs:$clientId:$sessionId:$durationMs');
  @override
  Future<void> updateCurrentPositionMs(
          String clientId, String sessionId, int positionMs) async =>
      calls.add('updateCurrentPositionMs:$clientId:$sessionId:$positionMs');
  @override
  Future<api.ApiStatus> getStatus(String clientId) async {
    calls.add('getStatus:$clientId');
    return api.ApiStatus(
        accountEnabled: true,
        applicationEnabled: false,
        keyEnabled: true,
        platformEnabled: true,
        effectiveP2pEnabled: false,
        reason: reason,
        configVersion: 'v2',
        edgeRegion: 'eu',
        quotaStatus: 'limited',
        trackerPoolReady: true);
  }

  @override
  Future<api.ApiStats> getStats(String clientId, String sessionId) async {
    calls.add('getStats:$clientId:$sessionId');
    return api.ApiStats(
        httpDownloaded: 1,
        p2pDownloaded: 2,
        p2pUploaded: 3,
        httpSegmentDownloadSuccesses: 4,
        httpSegmentDownloadFailures: 5,
        p2pSegmentDownloadSuccesses: 6,
        p2pSegmentDownloadFailures: 7,
        p2pSegmentUploadSuccesses: 8,
        p2pSegmentUploadFailures: 9,
        connectedPeers: 10,
        peerConnectErrors: 11,
        trackerErrors: 12,
        downloadOffloadRatio: 0.25,
        p2pSegmentDownloadSuccessRatio: 0.5,
        p2pSegmentUploadSuccessRatio: 0.75);
  }

  @override
  Future<api.ApiDiagnostics> getDiagnostics(
      String clientId, String sessionId) async {
    calls.add('getDiagnostics:$clientId:$sessionId');
    return api.ApiDiagnostics(
        fallbackCount: 1,
        firstPeerConnectMs: 33,
        coldStart:
            api.ApiColdStartSnapshot(p2pDownloaded: 44, httpDownloaded: 55),
        lastTrackerError: 'tracker',
        lastPeerError: 'peer',
        lastErrorAtMs: 123,
        iceAttempts: 8,
        iceSuccesses: 6,
        iceFailures: 2,
        iceDurationMs: 99);
  }

  @override
  Future<void> closeSession(String clientId, String sessionId) async =>
      calls.add('closeSession:$clientId:$sessionId');
  @override
  Future<void> closeClient(String clientId) async =>
      calls.add('closeClient:$clientId');
}
