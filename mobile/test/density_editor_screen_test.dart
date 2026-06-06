import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visual_ingredient_scanner/screens/density_editor_screen.dart';
import 'package:visual_ingredient_scanner/services/asset_catalog.dart';
import 'package:visual_ingredient_scanner/services/settings_repository.dart';
import 'package:visual_ingredient_scanner/state/scan_controller.dart';
import 'package:visual_ingredient_scanner/state/settings_provider.dart';

void main() {
  late AppCatalog catalog;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    catalog = await AppCatalog.load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    final repo = await SettingsRepository.create();
    final settings = SettingsProvider(
      repository: repo,
      registry: catalog.registry,
      initial: await repo.load(),
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppCatalog>.value(value: catalog),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
          ChangeNotifierProvider<ScanController>(
            create: (_) => ScanController(catalog: catalog),
          ),
        ],
        child: const MaterialApp(home: DensityEditorScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('lists classes and filters by search', (tester) async {
    await pumpEditor(tester);

    // 'apple' is near the top of the sorted, lazily-built list.
    expect(find.widgetWithText(ListTile, 'apple'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'tomato');
    await tester.pump();

    // Filtered: the 'tomato' tile is visible, 'apple' is gone. (Scope to
    // ListTile so the search field's own text doesn't match.)
    expect(find.widgetWithText(ListTile, 'tomato'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'apple'), findsNothing);
  });
}
