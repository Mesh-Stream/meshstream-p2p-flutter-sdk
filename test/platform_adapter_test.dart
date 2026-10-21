import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshstream_p2p/src/models.dart';
import 'package:meshstream_p2p/src/meshstream_exception.dart';
import 'package:meshstream_p2p/src/pigeon/generated/meshstream_api.g.dart'
    as api;
import 'package:meshstream_p2p/src/platform/meshstream_platform.dart';
import 'package:meshstream_p2p/src/platform/pigeon_meshstream_platform.dart';

import 'support/fake_meshstream_platform.dart';

void main() {
  test('fake platform preserves client and session operation arguments',
      () async {
    final platform = FakeMeshStreamPlatform();
    addTearDown(platform.dispose);

    final client = await platform.createClient(MeshStreamConfig(key: 'key'));
    final session = await platform.createPlaybackSession(
      client.clientId,
      PlaybackSessionOptions(url: 'https://cdn.example/video.m3u8'),
    );
    await platform.closeSession(client.clientId, session.sessionId);

    expect(client, isA<NativeClientReply>());
    expect(session, isA<NativeSessionReply>());
    expect(platform.calls, [
      'createClient:key',
      'createPlaybackSession:c1:https://cdn.example/video.m3u8',
      'closeSession:c1:s1',
    ]);
  });

  test('fake platform broadcasts typed events', () async {
    final platform = FakeMeshStreamPlatform();
    addTearDown(platform.dispose);
    final event = MeshStreamEvent.peerCountChanged(
      clientId: 'c1',
      sessionId: 's1',
      peerCount: 3,
    );
    final received = platform.events.first;
    platform.emit(event);
    expect(await received, same(event));
  });

  test('Pigeon adapter sends typed options and converts CDN fallback',
      () async {
    final host = _Host();
    final platform = PigeonMeshStreamPlatform(hostApi: host);
    final result = await platform.createPlaybackSession(
      'client-7',
      PlaybackSessionOptions(
        url: 'https://cdn.example/a.m3u8',
        mimeType: MeshStreamMimeType.m3u8,
        originHeaders: {'Authorization': 'token'},
      ),
    );
    expect(host.receivedClientId, 'client-7');
    expect(host.receivedOptions?.mimeType, 'm3u8');
    expect(host.receivedOptions?.originHeaders, {'Authorization': 'token'});
    expect(result.playbackMode, MeshStreamPlaybackMode.nativeCdn);
    expect(result.fallbackReason, MeshStreamUnavailableReason.quotaExhausted);
  });

  test('Pigeon adapter preserves native error code and details', () async {
    final platform = PigeonMeshStreamPlatform(hostApi: _Host());
    await expectLater(
      platform.createClient(MeshStreamConfig(key: 'key')),
      throwsA(isA<MeshStreamException>()
          .having((error) => error.code, 'code', 'CREATE_CLIENT_FAILED')
          .having((error) => error.details?['retryable'], 'details', false)),
    );
  });
}

class _Host extends api.MeshStreamHostApi {
  String? receivedClientId;
  api.ApiPlaybackSessionOptions? receivedOptions;

  @override
  Future<api.ApiClientReply> createClient(api.ApiClientConfig config) async {
    throw PlatformException(
      code: 'CREATE_CLIENT_FAILED',
      message: 'No key',
      details: {'retryable': false},
    );
  }

  @override
  Future<api.ApiSessionReply> createPlaybackSession(
      String clientId, api.ApiPlaybackSessionOptions options) async {
    receivedClientId = clientId;
    receivedOptions = options;
    return api.ApiSessionReply(
      sessionId: 's1',
      playbackUrl: 'https://cdn.example/a.m3u8',
      playbackMode: 'NATIVE_CDN',
      fallbackReason: 'QUOTA_EXHAUSTED',
    );
  }
}
