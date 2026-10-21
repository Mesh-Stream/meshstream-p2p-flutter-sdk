import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:meshstream_p2p/meshstream_p2p.dart';
import 'package:meshstream_p2p/src/platform/meshstream_platform.dart';

import 'support/fake_meshstream_platform.dart';

void main() {
  late MeshStreamPlatform original;
  late FakeMeshStreamPlatform fake;

  setUp(() {
    original = MeshStreamPlatform.instance;
    fake = FakeMeshStreamPlatform();
    MeshStreamPlatform.instance = fake;
  });
  tearDown(() async {
    MeshStreamPlatform.instance = original;
    await fake.dispose();
  });

  test('client creates an independent playback session', () async {
    final client = await MeshStream.create(MeshStreamConfig(key: 'key'));
    final session = await client.createPlaybackSession(
      PlaybackSessionOptions(url: 'https://cdn.example/a.m3u8'),
    );

    expect(
      (session.clientId, session.sessionId, session.playbackUrl),
      ('c1', 's1', 'http://127.0.0.1:9000/a.m3u8'),
    );
    expect(session.playbackMode, MeshStreamPlaybackMode.nativeP2p);
    expect(await session.preload(), true);
    expect(fake.calls, [
      'createClient:key',
      'createPlaybackSession:c1:https://cdn.example/a.m3u8',
      'preload:c1:s1',
    ]);
  });

  test('closing a client closes its sessions once and rejects later use',
      () async {
    final client = await MeshStream.create(MeshStreamConfig(key: 'key'));
    final session = await client.createPlaybackSession(
      PlaybackSessionOptions(url: 'https://cdn.example/a.m3u8'),
    );

    await Future.wait([client.close(), client.close()]);
    await client.close();

    expect(fake.calls.where((call) => call == 'closeSession:c1:s1').length, 1);
    expect(fake.calls.where((call) => call == 'closeClient:c1').length, 1);
    await expectLater(
      client.getStatus(),
      throwsA(isA<MeshStreamException>().having(
        (error) => error.code,
        'code',
        'CLIENT_CLOSED',
      )),
    );
    await expectLater(
      session.preload(),
      throwsA(isA<MeshStreamException>().having(
        (error) => error.code,
        'code',
        'SESSION_CLOSED',
      )),
    );
  });

  test('session update values reject negative durations before native dispatch',
      () async {
    final client = await MeshStream.create(MeshStreamConfig(key: 'key'));
    final session = await client.createPlaybackSession(
      PlaybackSessionOptions(url: 'https://cdn.example/a.m3u8'),
    );
    final before = fake.calls.length;

    expect(() => session.updateBufferedDurationMs(-1), throwsArgumentError);
    expect(() => session.updateCurrentPositionMs(-1), throwsArgumentError);
    expect(fake.calls.length, before);
  });

  test('a closed session rejects operations without closing the client',
      () async {
    final client = await MeshStream.create(MeshStreamConfig(key: 'key'));
    final session = await client.createPlaybackSession(
      PlaybackSessionOptions(url: 'https://cdn.example/a.m3u8'),
    );

    await Future.wait([session.close(), session.close()]);
    expect(fake.calls.where((call) => call == 'closeSession:c1:s1').length, 1);
    expect(fake.calls.where((call) => call == 'closeClient:c1'), isEmpty);
    await expectLater(session.preload(), throwsA(isA<MeshStreamException>()));
  });

  test('client close waits for a pending session creation', () async {
    final delayed = _DelayedSessionPlatform();
    MeshStreamPlatform.instance = delayed;
    final client = await MeshStream.create(MeshStreamConfig(key: 'key'));
    final creating = client.createPlaybackSession(
      PlaybackSessionOptions(url: 'https://cdn.example/a.m3u8'),
    );

    final closing = client.close();
    delayed.completeCreation();
    final session = await creating;
    await closing;

    expect(
        delayed.calls.where((call) => call == 'closeSession:c1:s1').length, 1);
    expect(delayed.calls.last, 'closeClient:c1');
    await expectLater(session.preload(), throwsA(isA<MeshStreamException>()));
    await delayed.dispose();
  });

  test('client still closes natively when a session close fails', () async {
    final failing = _FailingSessionClosePlatform();
    MeshStreamPlatform.instance = failing;
    final client = await MeshStream.create(MeshStreamConfig(key: 'key'));
    await client.createPlaybackSession(
      PlaybackSessionOptions(url: 'https://cdn.example/a.m3u8'),
    );

    await expectLater(client.close(), throwsStateError);

    expect(failing.calls, contains('closeSession:c1:s1'));
    expect(failing.calls, contains('closeClient:c1'));
    await failing.dispose();
  });
}

class _DelayedSessionPlatform extends FakeMeshStreamPlatform {
  final _created = Completer<NativeSessionReply>();

  @override
  Future<NativeSessionReply> createPlaybackSession(
      String clientId, PlaybackSessionOptions options) {
    calls.add('createPlaybackSession:$clientId:${options.url}');
    return _created.future;
  }

  void completeCreation() => _created.complete(sessionReply);
}

class _FailingSessionClosePlatform extends FakeMeshStreamPlatform {
  @override
  Future<void> closeSession(String clientId, String sessionId) async {
    calls.add('closeSession:$clientId:$sessionId');
    throw StateError('Session close failed.');
  }
}
