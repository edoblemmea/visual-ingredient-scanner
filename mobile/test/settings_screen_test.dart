import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visual_ingredient_scanner/screens/settings_screen.dart';
import 'package:visual_ingredient_scanner/services/asset_catalog.dart';
import 'package:visual_ingredient_scanner/services/settings_repository.dart';
import 'package:visual_ingredient_scanner/state/settings_provider.dart';

void main() {
  // Load bundled assets once; reloading rootBundle inside each testWidgets can
  // deadlock. Use pump() (not pumpAndSettle): the radio toggle animation plus
  // async persistence keep frames scheduled, and provider state updates
  // synchronously on interaction, which is what we assert.
  late AppCatalog catalog;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    catalog = await AppCatalog.load();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<SettingsProvider> pumpSettings(WidgetTester tester) async {
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
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();
    return settings;
  }

  testWidgets('selecting a detector updates settings', (tester) async {
    final settings = await pumpSettings(tester);
    expect(settings.modelChoice.detectorId, 'v26m_e40'); // default

    await tester.tap(find.text('YOLO v26m · best'));
    await tester.pump();

    expect(settings.settings.detectorId, 'v26m_best');
  });

  testWidgets('selecting a depth model updates settings', (tester) async {
    final settings = await pumpSettings(tester);
    expect(settings.modelChoice.depthId, 'metric3d'); // default

    await tester.tap(find.text('Depth Anything V2-S (metric indoor)'));
    await tester.pump();

    expect(settings.settings.depthId, 'depthanything');
  });

  testWidgets('editing the Gemini model updates settings', (tester) async {
    final settings = await pumpSettings(tester);
    expect(settings.settings.geminiModel, 'gemini-3.1-flash-lite');

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('geminiModelField')),
      300,
    );
    await tester.enterText(
      find.byKey(const ValueKey('geminiModelField')),
      'gemini-3.1-pro',
    );
    await tester.pump();

    expect(settings.settings.geminiModel, 'gemini-3.1-pro');
  });

  // The API-key field persistence is covered in settings_provider_test.dart.
}
