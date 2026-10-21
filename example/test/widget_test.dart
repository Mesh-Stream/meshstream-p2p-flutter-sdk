import 'package:flutter_test/flutter_test.dart';
import 'package:meshstream_p2p_example/main.dart';

void main() {
  testWidgets('renders the example placeholder', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('MeshStream P2P example'), findsOneWidget);
  });
}
