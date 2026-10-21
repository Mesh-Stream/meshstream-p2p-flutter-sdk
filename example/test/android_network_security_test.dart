import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
  test('Android permits cleartext only for MeshStream loopback proxy', () {
    const androidNamespace = 'http://schemas.android.com/apk/res/android';
    final manifest = XmlDocument.parse(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
    );
    final application = manifest.findAllElements('application').single;
    expect(
      application.getAttribute(
        'networkSecurityConfig',
        namespace: androidNamespace,
      ),
      '@xml/meshstream_network_security_config',
    );

    final config = XmlDocument.parse(
      File('android/app/src/main/res/xml/meshstream_network_security_config.xml')
          .readAsStringSync(),
    );
    expect(
      config.findAllElements('base-config').single.getAttribute(
            'cleartextTrafficPermitted',
          ),
      'false',
    );
    final cleartextConfigs = config.findAllElements('domain-config').where(
          (element) =>
              element.getAttribute('cleartextTrafficPermitted') == 'true',
        );
    expect(cleartextConfigs, hasLength(1));
    expect(
      cleartextConfigs.single
          .findAllElements('domain')
          .map((element) => element.innerText)
          .toSet(),
      {'127.0.0.1', 'localhost'},
    );
  });
}
