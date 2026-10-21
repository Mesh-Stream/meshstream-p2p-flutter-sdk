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

  test('create retains the platform that created the native client', () async {
    final creatingPlatform = _DelayedClientPlatform();
    MeshStreamPlatform.instance = creatingPlatform;
    final creating = MeshStream.create(MeshStreamConfig(key: 'key'));
    MeshStreamPlatform.instance = fake;
    creatingPlatform.completeCreation();

    final client = await creating;
    await client.createPlaybackSession(
      PlaybackSessionOptions(url: 'https://cdn.example/a.m3u8'),
    );
    expect(creatingPlatform.calls,
        contains('createPlaybackSession:c1:https://cdn.example/a.m3u8'));
    expect(fake.calls, isEmpty);
    await creatingPlatform.dispose();
  });

  test('public facade delegates player controls and telemetry', () async {
    const status = MeshStreamStatus(
      accountEnabled: true,
      applicationEnabled: true,
      keyEnabled: true,
      platformEnabled: true,
      effectiveP2pEnabled: true,
      reason: MeshStreamUnavailableReason.ok,
    );
    const stats = MeshStreamStats(
      httpDownloaded: 0,
      p2pDownloaded: 0,
      p2pUploaded: 0,
      httpSegmentDownloadSuccesses: 0,
      httpSegmentDownloadFailures: 0,
      p2pSegmentDownloadSuccesses: 0,
      p2pSegmentDownloadFailures: 0,
      p2pSegmentUploadSuccesses: 0,
      p2pSegmentUploadFailures: 0,
      connectedPeers: 0,
      peerConnectErrors: 0,
      trackerErrors: 0,
      downloadOffloadRatio: 0,
      p2pSegmentDownloadSuccessRatio: 0,
      p2pSegmentUploadSuccessRatio: 0,
    );
    const diagnostics = MeshStreamDiagnostics(
      fallbackCount: 0,
      iceAttempts: 0,
      iceSuccesses: 0,
      iceFailures: 0,
      iceDurationMs: 0,
    );
    fake.statusReply = status;
    fake.statsReply = stats;
    fake.diagnosticsReply = diagnostics;
    final client = await MeshStream.create(MeshStreamConfig(key: 'key'));
    final session = await client.createPlaybackSession(
      PlaybackSessionOptions(url: 'https://cdn.example/a.m3u8'),
    );

    await session.setP2pEnabled(false);
    await session.updateBufferedDurationMs(0);
    await session.updateCurrentPositionMs(1200);
    expect(await client.getStatus(), same(status));
    expect(await session.getStats(), same(stats));
    expect(await session.getDiagnostics(), same(diagnostics));
    expect(
        fake.calls,
        containsAllInOrder([
          'setP2pEnabled:c1:s1:false',
          'updateBufferedDurationMs:c1:s1:0',
          'updateCurrentPositionMs:c1:s1:1200',
          'getStatus:c1',
          'getStats:c1:s1',
          'getDiagnostics:c1:s1',
        ]));
  });

  test('client close drains an admitted status operation', () async {
    final delayed = _DelayedOperationsPlatform();
    MeshStreamPlatform.instance = delayed;
    final client = await MeshStream.create(MeshStreamConfig(key: 'key'));
    final status = client.getStatus();
    final closing = client.close();

    await Future<void>.delayed(Duration.zero);
    expect(delayed.calls, isNot(contains('closeClient:c1')));
    await expectLater(client.getStatus(), throwsA(isA<MeshStreamException>()));
    delayed.completeStatus();
    await status;
    await closing;
    expect(delayed.calls.last, 'closeClient:c1');
    await delayed.dispose();
  });

  test('simultaneous client and session close drains an admitted preload',
      () async {
    final delayed = _DelayedOperationsPlatform();
    MeshStreamPlatform.instance = delayed;
    final client = await MeshStream.create(MeshStreamConfig(key: 'key'));
    final session = await client.createPlaybackSession(
      PlaybackSessionOptions(url: 'https://cdn.example/a.m3u8'),
    );
    final preload = session.preload();
    final sessionClosing = session.close();
    final clientClosing = client.close();

    expect(delayed.calls, isNot(contains('closeSession:c1:s1')));
    expect(delayed.calls, isNot(contains('closeClient:c1')));
    await expectLater(session.preload(), throwsA(isA<MeshStreamException>()));
    delayed.completePreload();
    expect(await preload, true);
    await Future.wait([sessionClosing, clientClosing]);
    expect(
        delayed.calls.where((call) => call == 'closeSession:c1:s1').length, 1);
    expect(delayed.calls.where((call) => call == 'closeClient:c1').length, 1);
    expect(delayed.calls.last, 'closeClient:c1');
    await delayed.dispose();
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

class _DelayedClientPlatform extends FakeMeshStreamPlatform {
  final _created = Completer<NativeClientReply>();

  @override
  Future<NativeClientReply> createClient(MeshStreamConfig config) {
    calls.add('createClient:${config.key}');
    return _created.future;
  }

  void completeCreation() => _created.complete(clientReply);
}

class _DelayedOperationsPlatform extends FakeMeshStreamPlatform {
  final _status = Completer<MeshStreamStatus>();
  final _preload = Completer<bool>();

  @override
  Future<MeshStreamStatus> getStatus(String clientId) {
    calls.add('getStatus:$clientId');
    return _status.future;
  }

  @override
  Future<bool> preload(String clientId, String sessionId) {
    calls.add('preload:$clientId:$sessionId');
    return _preload.future;
  }

  void completeStatus() => _status.complete(const MeshStreamStatus(
        accountEnabled: true,
        applicationEnabled: true,
        keyEnabled: true,
        platformEnabled: true,
        effectiveP2pEnabled: true,
        reason: MeshStreamUnavailableReason.ok,
      ));
  void completePreload() => _preload.complete(true);
}
