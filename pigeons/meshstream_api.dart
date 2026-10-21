// Pigeon reads these declarations as a schema; it generates the constructors.
// ignore_for_file: not_initialized_non_nullable_instance_field

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions())
class ApiClientConfig {
  String key;
  bool? p2pEnabled;
}

class ApiPlaybackSessionOptions {
  String url;
  String? contentId;
  String? mimeType;
  Map<String, String>? originHeaders;
}

class ApiClientReply {
  String clientId;
}

class ApiSessionReply {
  String sessionId;
  String playbackUrl;
  String playbackMode;
  String? fallbackReason;
}

class ApiStatus {
  bool accountEnabled;
  bool applicationEnabled;
  bool keyEnabled;
  bool platformEnabled;
  bool effectiveP2pEnabled;
  String reason;
  String? configVersion;
  String? edgeRegion;
  String? quotaStatus;
  bool? trackerPoolReady;
}

class ApiStats {
  int httpDownloaded;
  int p2pDownloaded;
  int p2pUploaded;
  int httpSegmentDownloadSuccesses;
  int httpSegmentDownloadFailures;
  int p2pSegmentDownloadSuccesses;
  int p2pSegmentDownloadFailures;
  int p2pSegmentUploadSuccesses;
  int p2pSegmentUploadFailures;
  int connectedPeers;
  int peerConnectErrors;
  int trackerErrors;
  double downloadOffloadRatio;
  double p2pSegmentDownloadSuccessRatio;
  double p2pSegmentUploadSuccessRatio;
}

class ApiColdStartSnapshot {
  int p2pDownloaded;
  int httpDownloaded;
}

class ApiDiagnostics {
  int fallbackCount;
  int? firstPeerConnectMs;
  ApiColdStartSnapshot? coldStart;
  String? lastTrackerError;
  String? lastPeerError;
  int? lastErrorAtMs;
  int iceAttempts;
  int iceSuccesses;
  int iceFailures;
  int iceDurationMs;
}

@HostApi()
abstract class MeshStreamHostApi {
  @async
  ApiClientReply createClient(ApiClientConfig config);

  @async
  ApiSessionReply createPlaybackSession(
      String clientId, ApiPlaybackSessionOptions options);

  @async
  bool preload(String clientId, String sessionId);

  @async
  void setP2pEnabled(String clientId, String sessionId, bool enabled);

  @async
  void updateBufferedDurationMs(
      String clientId, String sessionId, int durationMs);

  @async
  void updateCurrentPositionMs(
      String clientId, String sessionId, int positionMs);

  @async
  ApiStatus getStatus(String clientId);

  @async
  ApiStats getStats(String clientId, String sessionId);

  @async
  ApiDiagnostics getDiagnostics(String clientId, String sessionId);

  @async
  void closeSession(String clientId, String sessionId);

  @async
  void closeClient(String clientId);
}
