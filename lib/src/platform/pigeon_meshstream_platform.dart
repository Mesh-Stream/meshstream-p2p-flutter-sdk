import 'package:flutter/services.dart';

import '../meshstream_exception.dart';
import '../models.dart';
import '../pigeon/generated/meshstream_api.g.dart' as api;
import 'meshstream_platform.dart';

class PigeonMeshStreamPlatform extends MeshStreamPlatform {
  PigeonMeshStreamPlatform(
      {api.MeshStreamHostApi? hostApi, EventChannel? eventChannel})
      : _hostApi = hostApi ?? api.MeshStreamHostApi(),
        _eventChannel = eventChannel ??
            const EventChannel('net.meshstream/meshstream_p2p/events');

  final api.MeshStreamHostApi _hostApi;
  final EventChannel _eventChannel;
  Stream<MeshStreamEvent>? _events;

  @override
  Stream<MeshStreamEvent> get events => _events ??= _eventChannel
          .receiveBroadcastStream()
          .map(_decodeEvent)
          .handleError((Object error) {
        if (error is PlatformException) throw _translate(error);
        throw error;
      });

  Future<T> _invoke<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on PlatformException catch (error) {
      throw _translate(error);
    }
  }

  @override
  Future<NativeClientReply> createClient(MeshStreamConfig config) =>
      _invoke(() async {
        final result = await _hostApi.createClient(api.ApiClientConfig(
          key: config.key,
          p2pEnabled: config.p2pEnabled,
        ));
        return NativeClientReply(result.clientId);
      });

  @override
  Future<NativeSessionReply> createPlaybackSession(
          String clientId, PlaybackSessionOptions options) =>
      _invoke(() async {
        final result = await _hostApi.createPlaybackSession(
          clientId,
          api.ApiPlaybackSessionOptions(
            url: options.url,
            contentId: options.contentId,
            mimeType: options.mimeType?.name,
            originHeaders: options.originHeaders,
          ),
        );
        return NativeSessionReply(
          sessionId: result.sessionId,
          playbackUrl: result.playbackUrl,
          playbackMode: _playbackMode(result.playbackMode),
          fallbackReason: result.fallbackReason == null
              ? null
              : _reason(result.fallbackReason!),
        );
      });

  @override
  Future<bool> preload(String clientId, String sessionId) =>
      _invoke(() => _hostApi.preload(clientId, sessionId));

  @override
  Future<void> setP2pEnabled(String clientId, String sessionId, bool enabled) =>
      _invoke(() => _hostApi.setP2pEnabled(clientId, sessionId, enabled));

  @override
  Future<void> updateBufferedDurationMs(
          String clientId, String sessionId, int durationMs) =>
      _invoke(() =>
          _hostApi.updateBufferedDurationMs(clientId, sessionId, durationMs));

  @override
  Future<void> updateCurrentPositionMs(
          String clientId, String sessionId, int positionMs) =>
      _invoke(() =>
          _hostApi.updateCurrentPositionMs(clientId, sessionId, positionMs));

  @override
  Future<MeshStreamStatus> getStatus(String clientId) => _invoke(() async {
        final value = await _hostApi.getStatus(clientId);
        return MeshStreamStatus(
          accountEnabled: value.accountEnabled,
          applicationEnabled: value.applicationEnabled,
          keyEnabled: value.keyEnabled,
          platformEnabled: value.platformEnabled,
          effectiveP2pEnabled: value.effectiveP2pEnabled,
          reason: _reason(value.reason),
          configVersion: value.configVersion,
          edgeRegion: value.edgeRegion,
          quotaStatus: value.quotaStatus,
          trackerPoolReady: value.trackerPoolReady,
        );
      });

  @override
  Future<MeshStreamStats> getStats(String clientId, String sessionId) =>
      _invoke(() async => _stats(await _hostApi.getStats(clientId, sessionId)));

  @override
  Future<MeshStreamDiagnostics> getDiagnostics(
          String clientId, String sessionId) =>
      _invoke(() async {
        final value = await _hostApi.getDiagnostics(clientId, sessionId);
        return MeshStreamDiagnostics(
          fallbackCount: value.fallbackCount,
          firstPeerConnectMs: value.firstPeerConnectMs,
          coldStart: value.coldStart == null
              ? null
              : MeshStreamColdStartSnapshot(
                  p2pDownloaded: value.coldStart!.p2pDownloaded,
                  httpDownloaded: value.coldStart!.httpDownloaded,
                ),
          lastTrackerError: value.lastTrackerError,
          lastPeerError: value.lastPeerError,
          lastErrorAtMs: value.lastErrorAtMs,
          iceAttempts: value.iceAttempts,
          iceSuccesses: value.iceSuccesses,
          iceFailures: value.iceFailures,
          iceDurationMs: value.iceDurationMs,
        );
      });

  @override
  Future<void> closeSession(String clientId, String sessionId) =>
      _invoke(() => _hostApi.closeSession(clientId, sessionId));

  @override
  Future<void> closeClient(String clientId) =>
      _invoke(() => _hostApi.closeClient(clientId));
}

MeshStreamException _translate(Object error) {
  if (error is PlatformException) {
    final details = error.details;
    return MeshStreamException(
      error.code,
      error.message ?? 'Native MeshStream operation failed.',
      details is Map
          ? details.map((key, value) => MapEntry('$key', value))
          : null,
    );
  }
  return MeshStreamException('NATIVE_ERROR', '$error');
}

MeshStreamPlaybackMode _playbackMode(String value) => switch (value) {
      'NATIVE_P2P' => MeshStreamPlaybackMode.nativeP2p,
      'NATIVE_CDN' => MeshStreamPlaybackMode.nativeCdn,
      _ => throw FormatException('Unknown playback mode: $value'),
    };

MeshStreamUnavailableReason _reason(String value) {
  for (final reason in MeshStreamUnavailableReason.values) {
    if (reason.wireName == value) return reason;
  }
  throw FormatException('Unknown unavailable reason: $value');
}

MeshStreamStats _stats(api.ApiStats value) => MeshStreamStats(
      httpDownloaded: value.httpDownloaded,
      p2pDownloaded: value.p2pDownloaded,
      p2pUploaded: value.p2pUploaded,
      httpSegmentDownloadSuccesses: value.httpSegmentDownloadSuccesses,
      httpSegmentDownloadFailures: value.httpSegmentDownloadFailures,
      p2pSegmentDownloadSuccesses: value.p2pSegmentDownloadSuccesses,
      p2pSegmentDownloadFailures: value.p2pSegmentDownloadFailures,
      p2pSegmentUploadSuccesses: value.p2pSegmentUploadSuccesses,
      p2pSegmentUploadFailures: value.p2pSegmentUploadFailures,
      connectedPeers: value.connectedPeers,
      peerConnectErrors: value.peerConnectErrors,
      trackerErrors: value.trackerErrors,
      downloadOffloadRatio: value.downloadOffloadRatio,
      p2pSegmentDownloadSuccessRatio: value.p2pSegmentDownloadSuccessRatio,
      p2pSegmentUploadSuccessRatio: value.p2pSegmentUploadSuccessRatio,
    );

MeshStreamEvent _decodeEvent(dynamic raw) {
  final map = (raw as Map).cast<String, Object?>();
  final clientId = map['clientId'] as String;
  final sessionId = map['sessionId'] as String;
  switch (map['type']) {
    case 'peerCountChanged':
      return MeshStreamEvent.peerCountChanged(
          clientId: clientId,
          sessionId: sessionId,
          peerCount: map['peerCount'] as int);
    case 'playbackPrepared':
      return MeshStreamEvent.playbackPrepared(
          clientId: clientId,
          sessionId: sessionId,
          playbackUrl: map['playbackUrl'] as String);
    case 'p2pReady':
      return MeshStreamEvent.p2pReady(clientId: clientId, sessionId: sessionId);
    case 'p2pUnavailable':
      return MeshStreamEvent.p2pUnavailable(
          clientId: clientId,
          sessionId: sessionId,
          reason: _reason(map['reason'] as String));
    case 'statistics':
      final data = (map['statistics'] as Map).cast<String, Object?>();
      int count(String key) => data[key] as int;
      double ratio(String key) => (data[key] as num).toDouble();
      return MeshStreamEvent.statistics(
          clientId: clientId,
          sessionId: sessionId,
          statistics: MeshStreamStats(
            httpDownloaded: count('httpDownloaded'),
            p2pDownloaded: count('p2pDownloaded'),
            p2pUploaded: count('p2pUploaded'),
            httpSegmentDownloadSuccesses: count('httpSegmentDownloadSuccesses'),
            httpSegmentDownloadFailures: count('httpSegmentDownloadFailures'),
            p2pSegmentDownloadSuccesses: count('p2pSegmentDownloadSuccesses'),
            p2pSegmentDownloadFailures: count('p2pSegmentDownloadFailures'),
            p2pSegmentUploadSuccesses: count('p2pSegmentUploadSuccesses'),
            p2pSegmentUploadFailures: count('p2pSegmentUploadFailures'),
            connectedPeers: count('connectedPeers'),
            peerConnectErrors: count('peerConnectErrors'),
            trackerErrors: count('trackerErrors'),
            downloadOffloadRatio: ratio('downloadOffloadRatio'),
            p2pSegmentDownloadSuccessRatio:
                ratio('p2pSegmentDownloadSuccessRatio'),
            p2pSegmentUploadSuccessRatio: ratio('p2pSegmentUploadSuccessRatio'),
          ));
    case 'cdnFallback':
      return MeshStreamEvent.cdnFallback(
          clientId: clientId, sessionId: sessionId, bytes: map['bytes'] as int);
    case 'trackerError':
      return MeshStreamEvent.trackerError(
          clientId: clientId,
          sessionId: sessionId,
          totalErrors: map['totalErrors'] as int);
    case 'peerConnectError':
      return MeshStreamEvent.peerConnectError(
          clientId: clientId,
          sessionId: sessionId,
          totalErrors: map['totalErrors'] as int);
    default:
      throw FormatException('Unknown MeshStream event: ${map['type']}');
  }
}
