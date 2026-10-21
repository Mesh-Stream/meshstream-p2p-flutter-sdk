import 'dart:collection';

enum MeshStreamMimeType { m3u8, mpd, mp4, mp3 }

enum MeshStreamPlaybackMode { nativeP2p, nativeCdn }

/// Reasons defined by the MeshStream React Native 1.0 contract.
enum MeshStreamUnavailableReason {
  ok,
  accountDisabled,
  appDisabled,
  appNotFound,
  keyDisabled,
  platformDisabled,
  originDenied,
  packageDenied,
  bundleDenied,
  signingCertDenied,
  teamDenied,
  authFailed,
  configUnavailable,
  trackerError,
  noPeers,
  unsupported,
  initializationFailed,
  disabled,
  keyP2pDisabled,
  quotaExhausted,
  quotaDisabled,
}

enum MeshStreamEventName {
  peerCountChanged,
  playbackPrepared,
  p2pReady,
  p2pUnavailable,
  statistics,
  cdnFallback,
  trackerError,
  peerConnectError,
}

final class MeshStreamConfig {
  factory MeshStreamConfig({required String key, bool? p2pEnabled}) {
    if (key.trim().isEmpty) {
      throw ArgumentError.value(key, 'key', 'must contain non-whitespace text');
    }
    return MeshStreamConfig._(key: key, p2pEnabled: p2pEnabled);
  }

  const MeshStreamConfig._({required this.key, this.p2pEnabled});

  final String key;
  final bool? p2pEnabled;
}

final class PlaybackSessionOptions {
  factory PlaybackSessionOptions({
    required String url,
    String? contentId,
    MeshStreamMimeType? mimeType,
    Map<String, String>? originHeaders,
  }) {
    if (url.trim().isEmpty) {
      throw ArgumentError.value(url, 'url', 'must contain non-whitespace text');
    }
    return PlaybackSessionOptions._(
      url: url,
      contentId: contentId,
      mimeType: mimeType,
      originHeaders: UnmodifiableMapView(Map.of(originHeaders ?? const {})),
    );
  }

  const PlaybackSessionOptions._({
    required this.url,
    this.contentId,
    this.mimeType,
    required this.originHeaders,
  });

  final String url;
  final String? contentId;
  final MeshStreamMimeType? mimeType;
  final Map<String, String> originHeaders;
}

final class MeshStreamStatus {
  const MeshStreamStatus({
    required this.accountEnabled,
    required this.applicationEnabled,
    required this.keyEnabled,
    required this.platformEnabled,
    required this.effectiveP2pEnabled,
    required this.reason,
    this.configVersion,
    this.edgeRegion,
    this.quotaStatus,
    this.trackerPoolReady,
  });

  final bool accountEnabled;
  final bool applicationEnabled;
  final bool keyEnabled;
  final bool platformEnabled;
  final bool effectiveP2pEnabled;
  final MeshStreamUnavailableReason reason;
  final String? configVersion;
  final String? edgeRegion;
  final String? quotaStatus;
  final bool? trackerPoolReady;
}

final class MeshStreamStats {
  const MeshStreamStats({
    required this.httpDownloaded,
    required this.p2pDownloaded,
    required this.p2pUploaded,
    required this.httpSegmentDownloadSuccesses,
    required this.httpSegmentDownloadFailures,
    required this.p2pSegmentDownloadSuccesses,
    required this.p2pSegmentDownloadFailures,
    required this.p2pSegmentUploadSuccesses,
    required this.p2pSegmentUploadFailures,
    required this.connectedPeers,
    required this.peerConnectErrors,
    required this.trackerErrors,
    required this.downloadOffloadRatio,
    required this.p2pSegmentDownloadSuccessRatio,
    required this.p2pSegmentUploadSuccessRatio,
  });

  final int httpDownloaded;
  final int p2pDownloaded;
  final int p2pUploaded;
  final int httpSegmentDownloadSuccesses;
  final int httpSegmentDownloadFailures;
  final int p2pSegmentDownloadSuccesses;
  final int p2pSegmentDownloadFailures;
  final int p2pSegmentUploadSuccesses;
  final int p2pSegmentUploadFailures;
  final int connectedPeers;
  final int peerConnectErrors;
  final int trackerErrors;
  final double downloadOffloadRatio;
  final double p2pSegmentDownloadSuccessRatio;
  final double p2pSegmentUploadSuccessRatio;
}

final class MeshStreamColdStartSnapshot {
  const MeshStreamColdStartSnapshot({
    required this.p2pDownloaded,
    required this.httpDownloaded,
  });

  final int p2pDownloaded;
  final int httpDownloaded;
}

final class MeshStreamDiagnostics {
  const MeshStreamDiagnostics({
    required this.fallbackCount,
    this.firstPeerConnectMs,
    this.coldStart,
    this.lastTrackerError,
    this.lastPeerError,
    this.lastErrorAtMs,
    required this.iceAttempts,
    required this.iceSuccesses,
    required this.iceFailures,
    required this.iceDurationMs,
  });

  final int fallbackCount;
  final int? firstPeerConnectMs;
  final MeshStreamColdStartSnapshot? coldStart;
  final String? lastTrackerError;
  final String? lastPeerError;
  final int? lastErrorAtMs;
  final int iceAttempts;
  final int iceSuccesses;
  final int iceFailures;
  final int iceDurationMs;
}

final class MeshStreamSessionInfo {
  const MeshStreamSessionInfo({
    required this.clientId,
    required this.sessionId,
    required this.playbackUrl,
    required this.playbackMode,
    this.fallbackReason,
  });

  final String clientId;
  final String sessionId;
  final String playbackUrl;
  final MeshStreamPlaybackMode playbackMode;
  final MeshStreamUnavailableReason? fallbackReason;
}

final class MeshStreamEvent {
  const MeshStreamEvent._({
    required this.type,
    required this.clientId,
    required this.sessionId,
    this.peerCount,
    this.playbackUrl,
    this.reason,
    this.statistics,
    this.bytes,
    this.totalErrors,
  });

  const MeshStreamEvent.peerCountChanged({
    required String clientId,
    required String sessionId,
    required int peerCount,
  }) : this._(
          type: MeshStreamEventName.peerCountChanged,
          clientId: clientId,
          sessionId: sessionId,
          peerCount: peerCount,
        );

  const MeshStreamEvent.playbackPrepared({
    required String clientId,
    required String sessionId,
    required String playbackUrl,
  }) : this._(
          type: MeshStreamEventName.playbackPrepared,
          clientId: clientId,
          sessionId: sessionId,
          playbackUrl: playbackUrl,
        );

  const MeshStreamEvent.p2pReady({
    required String clientId,
    required String sessionId,
  }) : this._(
          type: MeshStreamEventName.p2pReady,
          clientId: clientId,
          sessionId: sessionId,
        );

  const MeshStreamEvent.p2pUnavailable({
    required String clientId,
    required String sessionId,
    required MeshStreamUnavailableReason reason,
  }) : this._(
          type: MeshStreamEventName.p2pUnavailable,
          clientId: clientId,
          sessionId: sessionId,
          reason: reason,
        );

  const MeshStreamEvent.statistics({
    required String clientId,
    required String sessionId,
    required MeshStreamStats statistics,
  }) : this._(
          type: MeshStreamEventName.statistics,
          clientId: clientId,
          sessionId: sessionId,
          statistics: statistics,
        );

  const MeshStreamEvent.cdnFallback({
    required String clientId,
    required String sessionId,
    required int bytes,
  }) : this._(
          type: MeshStreamEventName.cdnFallback,
          clientId: clientId,
          sessionId: sessionId,
          bytes: bytes,
        );

  const MeshStreamEvent.trackerError({
    required String clientId,
    required String sessionId,
    required int totalErrors,
  }) : this._(
          type: MeshStreamEventName.trackerError,
          clientId: clientId,
          sessionId: sessionId,
          totalErrors: totalErrors,
        );

  const MeshStreamEvent.peerConnectError({
    required String clientId,
    required String sessionId,
    required int totalErrors,
  }) : this._(
          type: MeshStreamEventName.peerConnectError,
          clientId: clientId,
          sessionId: sessionId,
          totalErrors: totalErrors,
        );

  final MeshStreamEventName type;
  final String clientId;
  final String sessionId;
  final int? peerCount;
  final String? playbackUrl;
  final MeshStreamUnavailableReason? reason;
  final MeshStreamStats? statistics;
  final int? bytes;
  final int? totalErrors;
}
