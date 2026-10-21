import 'meshstream_exception.dart';
import 'meshstream_playback_session.dart';
import 'models.dart';
import 'platform/meshstream_platform.dart';

final class MeshStreamClient {
  MeshStreamClient(this.clientId, this._platform);

  final String clientId;
  final MeshStreamPlatform _platform;
  final _sessions = <MeshStreamPlaybackSession>{};
  final _activeOperations = <Future<void>>{};
  bool _closed = false;
  Future<void>? _closing;

  Future<T> _withOpen<T>(Future<T> Function() operation) {
    if (_closed || _closing != null) {
      return Future.error(
        const MeshStreamException(
            'CLIENT_CLOSED', 'MeshStream client is closed.'),
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

  Future<MeshStreamPlaybackSession> createPlaybackSession(
    PlaybackSessionOptions options,
  ) =>
      _withOpen(() async {
        final reply = await _platform.createPlaybackSession(clientId, options);
        final session = MeshStreamPlaybackSession(
          clientId: clientId,
          sessionId: reply.sessionId,
          playbackUrl: reply.playbackUrl,
          playbackMode: reply.playbackMode,
          fallbackReason: reply.fallbackReason,
          platform: _platform,
        );
        _sessions.add(session);
        return session;
      });

  Future<MeshStreamStatus> getStatus() =>
      _withOpen(() => _platform.getStatus(clientId));

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    try {
      await Future.wait(_activeOperations.toList());
      Object? sessionCloseError;
      StackTrace? sessionCloseStack;
      try {
        await Future.wait(_sessions.map((session) => session.close()));
      } catch (error, stack) {
        sessionCloseError = error;
        sessionCloseStack = stack;
      }
      await _platform.closeClient(clientId);
      if (sessionCloseError != null) {
        Error.throwWithStackTrace(sessionCloseError, sessionCloseStack!);
      }
    } finally {
      _closed = true;
    }
  }
}
