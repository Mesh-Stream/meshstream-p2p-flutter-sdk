import '../models.dart';
import 'pigeon_meshstream_platform.dart';

final class NativeClientReply {
  const NativeClientReply(this.clientId);
  final String clientId;
}

final class NativeSessionReply {
  const NativeSessionReply({
    required this.sessionId,
    required this.playbackUrl,
    required this.playbackMode,
    this.fallbackReason,
  });

  final String sessionId;
  final String playbackUrl;
  final MeshStreamPlaybackMode playbackMode;
  final MeshStreamUnavailableReason? fallbackReason;
}

abstract class MeshStreamPlatform {
  static MeshStreamPlatform instance = PigeonMeshStreamPlatform();

  Stream<MeshStreamEvent> get events;
  Future<NativeClientReply> createClient(MeshStreamConfig config);
  Future<NativeSessionReply> createPlaybackSession(
    String clientId,
    PlaybackSessionOptions options,
  );
  Future<bool> preload(String clientId, String sessionId);
  Future<void> setP2pEnabled(String clientId, String sessionId, bool enabled);
  Future<void> updateBufferedDurationMs(
    String clientId,
    String sessionId,
    int durationMs,
  );
  Future<void> updateCurrentPositionMs(
    String clientId,
    String sessionId,
    int positionMs,
  );
  Future<MeshStreamStatus> getStatus(String clientId);
  Future<MeshStreamStats> getStats(String clientId, String sessionId);
  Future<MeshStreamDiagnostics> getDiagnostics(
    String clientId,
    String sessionId,
  );
  Future<void> closeSession(String clientId, String sessionId);
  Future<void> closeClient(String clientId);
}
