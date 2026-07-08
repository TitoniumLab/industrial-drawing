import 'package:flutter_test/flutter_test.dart';
import 'package:example/main.dart';

void main() {
  testWidgets('App launches smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const IndustrialDrawingApp());

    expect(find.text('256 x 256 Pixel Canvas'), findsOneWidget);
    expect(find.byType(PixelPaintExampleScreen), findsOneWidget);
  });
}
