import 'dart:async';

import 'package:meshstream_p2p/src/models.dart';
import 'package:meshstream_p2p/src/platform/meshstream_platform.dart';

class FakeMeshStreamPlatform extends MeshStreamPlatform {
  final calls = <String>[];
  final clientConfigs = <MeshStreamConfig>[];
  final sessionRequests =
      <({String clientId, PlaybackSessionOptions options})>[];
  final _events = StreamController<MeshStreamEvent>.broadcast();
  NativeClientReply clientReply = const NativeClientReply('c1');
  NativeSessionReply sessionReply = const NativeSessionReply(
    sessionId: 's1',
    playbackUrl: 'http://127.0.0.1:9000/a.m3u8',
    playbackMode: MeshStreamPlaybackMode.nativeP2p,
  );
  MeshStreamStatus? statusReply;
  MeshStreamStats? statsReply;
  MeshStreamDiagnostics? diagnosticsReply;
  bool preloadReply = true;

  @override
  Stream<MeshStreamEvent> get events => _events.stream;
  void emit(MeshStreamEvent event) => _events.add(event);
  Future<void> dispose() => _events.close();

  @override
  Future<NativeClientReply> createClient(MeshStreamConfig config) async {
    calls.add('createClient:${config.key}');
    clientConfigs.add(config);
    return clientReply;
  }

  @override
  Future<NativeSessionReply> createPlaybackSession(
      String clientId, PlaybackSessionOptions options) async {
    calls.add('createPlaybackSession:$clientId:${options.url}');
    sessionRequests.add((clientId: clientId, options: options));
    return sessionReply;
  }

  @override
  Future<bool> preload(String clientId, String sessionId) async {
    calls.add('preload:$clientId:$sessionId');
    return preloadReply;
  }

  @override
  Future<void> setP2pEnabled(
      String clientId, String sessionId, bool enabled) async {
    calls.add('setP2pEnabled:$clientId:$sessionId:$enabled');
  }

  @override
  Future<void> updateBufferedDurationMs(
      String clientId, String sessionId, int durationMs) async {
    calls.add('updateBufferedDurationMs:$clientId:$sessionId:$durationMs');
  }

  @override
  Future<void> updateCurrentPositionMs(
      String clientId, String sessionId, int positionMs) async {
    calls.add('updateCurrentPositionMs:$clientId:$sessionId:$positionMs');
  }

  @override
  Future<MeshStreamStatus> getStatus(String clientId) async {
    calls.add('getStatus:$clientId');
    return statusReply ??
        (throw StateError('Configure statusReply before getStatus.'));
  }

  @override
  Future<MeshStreamStats> getStats(String clientId, String sessionId) async {
    calls.add('getStats:$clientId:$sessionId');
    return statsReply ??
        (throw StateError('Configure statsReply before getStats.'));
  }

  @override
  Future<MeshStreamDiagnostics> getDiagnostics(
      String clientId, String sessionId) async {
    calls.add('getDiagnostics:$clientId:$sessionId');
    return diagnosticsReply ??
        (throw StateError('Configure diagnosticsReply before getDiagnostics.'));
  }

  @override
  Future<void> closeSession(String clientId, String sessionId) async {
    calls.add('closeSession:$clientId:$sessionId');
  }

  @override
  Future<void> closeClient(String clientId) async {
    calls.add('closeClient:$clientId');
  }
}
