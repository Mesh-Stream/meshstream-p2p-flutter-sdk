import 'package:flutter_test/flutter_test.dart';
import 'package:meshstream_p2p/meshstream_p2p.dart';

void main() {
  test('a config key must contain non-whitespace text', () {
    expect(() => MeshStreamConfig(key: '  '), throwsArgumentError);
  });

  test('session URL must contain non-whitespace text', () {
    expect(() => PlaybackSessionOptions(url: ''), throwsArgumentError);
  });

  test('event payload preserves client and session identity', () {
    final event = MeshStreamEvent.p2pReady(
      clientId: 'client-a',
      sessionId: 'session-a',
    );
    expect(
      (event.clientId, event.sessionId, event.type),
      ('client-a', 'session-a', MeshStreamEventName.p2pReady),
    );
  });

  test('exception retains a stable code and native details', () {
    final error = MeshStreamException('UNKNOWN_SESSION', 'not found', {
      'sessionId': 's',
    });
    expect(error.code, 'UNKNOWN_SESSION');
    expect(error.details!['sessionId'], 's');
  });

  test('origin headers are copied and cannot be changed', () {
    final source = {'Authorization': 'token'};
    final options = PlaybackSessionOptions(
      url: 'https://cdn.example/video.m3u8',
      originHeaders: source,
    );
    source['Authorization'] = 'changed';
    expect(options.originHeaders['Authorization'], 'token');
    expect(
        () => options.originHeaders['Other'] = 'value', throwsUnsupportedError);
  });

  test('every event constructor exposes only its matching payload', () {
    final event = MeshStreamEvent.cdnFallback(
      clientId: 'client-a',
      sessionId: 'session-a',
      bytes: 0,
    );
    expect(event.type, MeshStreamEventName.cdnFallback);
    expect(event.bytes, 0);
    expect(event.reason, isNull);
    expect(event.totalErrors, isNull);
  });

  test('zero telemetry is a valid snapshot', () {
    const stats = MeshStreamStats(
      httpDownloaded: 0,
      p2pDownloaded: 0,
      p2pUploaded: 0,
      httpSegmentDownloadSuccesses: 0,
      httpSegmentDownloadFailures: 0,
      p2pSegmentDownloadSuccesses: 0,
      p2pSegmentDownloadFailures: 0,
      p2pSegmentUploadSuccesses: 0,
      p2pSegmentUploadFailures: 0,
      connectedPeers: 0,
      peerConnectErrors: 0,
      trackerErrors: 0,
      downloadOffloadRatio: 0,
      p2pSegmentDownloadSuccessRatio: 0,
      p2pSegmentUploadSuccessRatio: 0,
    );
    expect(stats.connectedPeers, 0);
    expect(stats.downloadOffloadRatio, 0);
  });
}
