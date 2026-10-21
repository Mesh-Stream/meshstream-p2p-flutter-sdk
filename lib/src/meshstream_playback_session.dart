import 'meshstream_exception.dart';
import 'models.dart';
import 'platform/meshstream_platform.dart';

final class MeshStreamPlaybackSession {
  MeshStreamPlaybackSession({
    required this.clientId,
    required this.sessionId,
    required this.playbackUrl,
    required this.playbackMode,
    required this.fallbackReason,
    required MeshStreamPlatform platform,
  }) : _platform = platform;

  final String clientId;
  final String sessionId;
  final String playbackUrl;
  final MeshStreamPlaybackMode playbackMode;
  final MeshStreamUnavailableReason? fallbackReason;
  final MeshStreamPlatform _platform;
  final _activeOperations = <Future<void>>{};
  bool _closed = false;
  Future<void>? _closing;

  Future<T> _withOpen<T>(Future<T> Function() operation) {
    if (_closed || _closing != null) {
      return Future.error(
        const MeshStreamException(
          'SESSION_CLOSED',
          'MeshStream playback session is closed.',
        ),
      );
    }
    final result = Future.sync(operation);
    final settled = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _activeOperations.add(settled);
    settled.then((_) => _activeOperations.remove(settled));
    return result;
  }

  Future<bool> preload() =>
      _withOpen(() => _platform.preload(clientId, sessionId));

  Future<void> setP2pEnabled(bool enabled) =>
      _withOpen(() => _platform.setP2pEnabled(clientId, sessionId, enabled));

  Future<void> updateBufferedDurationMs(int durationMs) {
    if (durationMs < 0) {
      throw ArgumentError.value(
          durationMs, 'durationMs', 'must be non-negative');
    }
    return _withOpen(() =>
        _platform.updateBufferedDurationMs(clientId, sessionId, durationMs));
  }

  Future<void> updateCurrentPositionMs(int positionMs) {
    if (positionMs < 0) {
      throw ArgumentError.value(
          positionMs, 'positionMs', 'must be non-negative');
    }
    return _withOpen(() =>
        _platform.updateCurrentPositionMs(clientId, sessionId, positionMs));
  }

  Future<MeshStreamStats> getStats() =>
      _withOpen(() => _platform.getStats(clientId, sessionId));

  Future<MeshStreamDiagnostics> getDiagnostics() =>
      _withOpen(() => _platform.getDiagnostics(clientId, sessionId));

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    try {
      await Future.wait(_activeOperations.toList());
      await _platform.closeSession(clientId, sessionId);
    } finally {
      _closed = true;
    }
  }
}
