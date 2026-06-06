import 'package:flutter_test/flutter_test.dart';

import 'package:visual_ingredient_scanner/main.dart';

void main() {
  testWidgets('App boots and loads the bundled catalog', (tester) async {
    await tester.pumpWidget(const VisualIngredientScannerApp());

    // AppBar title is shown immediately, while the catalog future resolves.
    expect(find.text('Visual Ingredient Scanner'), findsOneWidget);

    await tester.pumpAndSettle();

    // Once assets are parsed, the home body reports what was loaded.
    expect(find.textContaining('classes loaded'), findsOneWidget);
    expect(find.text('Scan (coming soon)'), findsOneWidget);
  });
}
