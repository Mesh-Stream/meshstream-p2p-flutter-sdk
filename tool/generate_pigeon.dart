import 'dart:io';

import 'package:pigeon/kotlin_generator.dart';
import 'package:pigeon/pigeon_lib.dart';

const _input = 'pigeons/meshstream_api.dart';
const _outputs = <String>[
  'lib/src/pigeon/generated/meshstream_api.g.dart',
  'android/src/main/kotlin/net/meshstream/flutter/generated/MeshStreamApi.g.kt',
  'ios/Classes/Generated/MeshStreamApi.g.swift',
];

Future<void> main(List<String> arguments) async {
  if (arguments.length > 1 ||
      (arguments.isNotEmpty && arguments.single != '--check')) {
    stderr.writeln('Usage: dart run tool/generate_pigeon.dart [--check]');
    exitCode = 64;
    return;
  }
  if (!File(_input).existsSync()) {
    stderr.writeln('Missing Pigeon input: $_input');
    exitCode = 1;
    return;
  }

  final check = arguments.isNotEmpty;
  final temporaryDirectory = check
      ? await Directory.systemTemp.createTemp('meshstream-pigeon-')
      : null;
  try {
    String outputPath(String path) =>
        temporaryDirectory == null ? path : '${temporaryDirectory.path}/$path';

    final result = await Pigeon.runWithOptions(
      PigeonOptions(
        input: _input,
        dartOut: outputPath(_outputs[0]),
        kotlinOut: outputPath(_outputs[1]),
        swiftOut: outputPath(_outputs[2]),
        kotlinOptions: const KotlinOptions(package: 'net.meshstream.flutter'),
        dartPackageName: 'meshstream_p2p',
        copyrightHeader: 'tool/pigeon_header.txt',
      ),
    );
    if (result != 0) {
      exitCode = result;
      return;
    }

    if (check) {
      var stale = false;
      for (final path in _outputs) {
        final committed = File(path);
        final generated = File(outputPath(path));
        if (!committed.existsSync() ||
            !generated.existsSync() ||
            !await _sameBytes(committed, generated)) {
          stderr.writeln('Stale Pigeon output: $path');
          stale = true;
        }
      }
      if (stale) exitCode = 1;
    }
  } finally {
    await temporaryDirectory?.delete(recursive: true);
  }
}

Future<bool> _sameBytes(File first, File second) async {
  final firstBytes = await first.readAsBytes();
  final secondBytes = await second.readAsBytes();
  if (firstBytes.length != secondBytes.length) return false;
  for (var index = 0; index < firstBytes.length; index++) {
    if (firstBytes[index] != secondBytes[index]) return false;
  }
  return true;
}
