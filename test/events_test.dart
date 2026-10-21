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

  test('events are broadcast and filters match all supplied fields', () async {
    expect(MeshStream.events.isBroadcast, true);
    final received = <MeshStreamEvent>[];
    final subscription = MeshStream.eventsFor(
      clientId: 'c1',
      sessionId: 's1',
      type: MeshStreamEventName.p2pReady,
    ).listen(received.add);

    fake.emit(const MeshStreamEvent.p2pReady(clientId: 'c2', sessionId: 's1'));
    fake.emit(const MeshStreamEvent.p2pReady(clientId: 'c1', sessionId: 's2'));
    fake.emit(const MeshStreamEvent.peerCountChanged(
        clientId: 'c1', sessionId: 's1', peerCount: 1));
    fake.emit(const MeshStreamEvent.p2pReady(clientId: 'c1', sessionId: 's1'));
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect((received.single.clientId, received.single.sessionId), ('c1', 's1'));
    await subscription.cancel();
  });
}
