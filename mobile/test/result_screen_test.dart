import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:visual_ingredient_scanner/models/app_settings.dart';
import 'package:visual_ingredient_scanner/models/scan_result.dart';
import 'package:visual_ingredient_scanner/screens/result_screen.dart';
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

  Future<void> pumpResultScreen(
    WidgetTester tester, {
    required ScanController controller,
    AppSettings settings = AppSettings.defaults,
  }) async {
    final repo = await SettingsRepository.create();
    final settingsProvider = SettingsProvider(
      repository: repo,
      registry: catalog.registry,
      initial: settings,
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ScanController>.value(value: controller),
          ChangeNotifierProvider<SettingsProvider>.value(
            value: settingsProvider,
          ),
        ],
        child: const MaterialApp(home: ResultScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows actionable error state', (tester) async {
    final controller = ScanController(catalog: catalog)
      ..status = ScanStatus.error
      ..error = 'ORT runtime failed';

    await pumpResultScreen(tester, controller: controller);

    expect(find.text('Scan failed'), findsOneWidget);
    expect(find.text('ORT runtime failed'), findsOneWidget);
    expect(find.text('Back to scan'), findsOneWidget);
  });

  testWidgets('empty result shows recovery actions', (tester) async {
    final controller = ScanController(catalog: catalog)
      ..status = ScanStatus.success
      ..result = ScanResult.empty
      ..scanDuration = const Duration(milliseconds: 4321);

    await pumpResultScreen(
      tester,
      controller: controller,
      settings: AppSettings.defaults.copyWith(showBoxes: true),
    );

    expect(find.text('No ingredients detected'), findsOneWidget);
    expect(find.text('4.32 s'), findsOneWidget);
    expect(find.text('Edit items'), findsOneWidget);
    expect(find.text('Scan again'), findsOneWidget);
  });
}
