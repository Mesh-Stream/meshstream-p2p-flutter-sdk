import 'meshstream_exception.dart';
import 'meshstream_playback_session.dart';
import 'models.dart';
import 'platform/meshstream_platform.dart';

final class MeshStreamClient {
  MeshStreamClient(this.clientId, this._platform);

  final String clientId;
  final MeshStreamPlatform _platform;
  final _sessions = <MeshStreamPlaybackSession>{};
  final _pendingCreations = <Future<MeshStreamPlaybackSession>>{};
  bool _closed = false;
  Future<void>? _closing;

  Future<T> _withOpen<T>(Future<T> Function() operation) async {
    if (_closed || _closing != null) {
      throw const MeshStreamException(
        'CLIENT_CLOSED',
        'MeshStream client is closed.',
      );
    }
    return operation();
  }

  Future<MeshStreamPlaybackSession> createPlaybackSession(
    PlaybackSessionOptions options,
  ) {
    final creation = _withOpen(() async {
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
    _pendingCreations.add(creation);
    creation.then<void>(
      (_) => _pendingCreations.remove(creation),
      onError: (Object _, StackTrace __) => _pendingCreations.remove(creation),
    );
    return creation;
  }

  Future<MeshStreamStatus> getStatus() =>
      _withOpen(() => _platform.getStatus(clientId));

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    try {
      await Future.wait(_pendingCreations.map((creation) => creation.then<void>(
            (_) {},
            onError: (Object _, StackTrace __) {},
          )));
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
