import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const VisualIngredientScannerApp());
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
