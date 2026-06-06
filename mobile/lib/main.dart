import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/asset_catalog.dart';
import 'services/settings_repository.dart';
import 'state/settings_provider.dart';

void main() {
  runApp(const AppBootstrap());
}

class _Boot {
  const _Boot(this.catalog, this.settings);
  final AppCatalog catalog;
  final SettingsProvider settings;
}

Future<_Boot> _bootstrap() async {
  final catalog = await AppCatalog.load();
  final repository = await SettingsRepository.create();
  final settings =
      SettingsProvider(repository: repository, registry: catalog.registry);
  return _Boot(catalog, settings);
}

/// Loads bundled assets + persisted settings before building the app. Providers
/// must wrap [MaterialApp] (not its `home`) so routes pushed onto the Navigator
/// — e.g. the settings screen — can still read them.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late final Future<_Boot> _future = _bootstrap();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Boot>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _SplashApp(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Failed to start:\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const _SplashApp(child: CircularProgressIndicator());
        }
        final boot = snapshot.requireData;
        return MultiProvider(
          providers: [
            Provider<AppCatalog>.value(value: boot.catalog),
            ChangeNotifierProvider<SettingsProvider>.value(value: boot.settings),
          ],
          child: const VisualIngredientScannerApp(),
        );
      },
    );
  }
}

/// Minimal themed shell shown while bootstrapping or on a startup error.
class _SplashApp extends StatelessWidget {
  const _SplashApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: Center(child: child)),
    );
  }
}

class VisualIngredientScannerApp extends StatelessWidget {
  const VisualIngredientScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Visual Ingredient Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
