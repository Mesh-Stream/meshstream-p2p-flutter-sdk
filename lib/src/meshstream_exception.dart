final class MeshStreamException implements Exception {
  const MeshStreamException(this.code, this.message, [this.details]);

  final String code;
  final String message;
  final Map<String, Object?>? details;

  @override
  String toString() => 'MeshStreamException($code): $message';
}
