import 'package:flutter_test/flutter_test.dart';

import 'package:visual_ingredient_scanner/main.dart';

void main() {
  testWidgets('App boots to the home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const VisualIngredientScannerApp());

    expect(find.text('Visual Ingredient Scanner'), findsOneWidget);
    expect(find.text('Scan (coming soon)'), findsOneWidget);
  });
}
