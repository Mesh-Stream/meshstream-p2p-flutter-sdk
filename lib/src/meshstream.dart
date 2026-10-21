import 'meshstream_client.dart';
import 'models.dart';
import 'platform/meshstream_platform.dart';

abstract final class MeshStream {
  const MeshStream._();

  static Future<MeshStreamClient> create(MeshStreamConfig config) async {
    final platform = MeshStreamPlatform.instance;
    final reply = await platform.createClient(config);
    return MeshStreamClient(reply.clientId, platform);
  }

  static Stream<MeshStreamEvent> get events =>
      MeshStreamPlatform.instance.events;

  static Stream<MeshStreamEvent> eventsFor({
    String? clientId,
    String? sessionId,
    MeshStreamEventName? type,
  }) =>
      events.where((event) =>
          (clientId == null || event.clientId == clientId) &&
          (sessionId == null || event.sessionId == sessionId) &&
          (type == null || event.type == type));
}
