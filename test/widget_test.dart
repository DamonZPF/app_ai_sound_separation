// Basic smoke test for AI Sound Separation app
import 'package:flutter_test/flutter_test.dart';

import 'package:app_ai_sound_separation/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const AISoundApp());
    await tester.pumpAndSettle();

    // Verify that the app renders (bottom navigation should be present)
    expect(find.byType(AISoundApp), findsOneWidget);
  });
}
