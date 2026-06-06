import 'package:flutter/material.dart';

/// Settings screen placeholder. Model selection, the editable density table,
/// visualisation toggles, and the API-key field are added in later steps
/// (S12–S14); this is the scaffold route they hang off.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: const Center(
        child: Text('Settings will appear here.'),
      ),
    );
  }
}
