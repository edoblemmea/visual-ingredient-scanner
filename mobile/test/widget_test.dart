import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:visual_ingredient_scanner/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('App boots and loads catalog + settings', (tester) async {
    await tester.pumpWidget(const AppBootstrap());
    await tester.pumpAndSettle();

    expect(find.text('Visual Ingredient Scanner'), findsOneWidget);
    expect(find.textContaining('classes loaded'), findsOneWidget);
    expect(find.textContaining('Detector:'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
  });
}
