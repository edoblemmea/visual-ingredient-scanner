import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/recipe.dart';
import '../services/recipe_service.dart';
import '../services/saved_recipe_repository.dart';
import '../state/settings_provider.dart';

class RecipeScreen extends StatefulWidget {
  const RecipeScreen({super.key, required this.ingredientWeights});

  final Map<String, double> ingredientWeights;

  @override
  State<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends State<RecipeScreen> {
  final PageController _pageController = PageController(viewportFraction: 0.92);
  bool _started = false;
  bool _loading = true;
  final Set<int> _savedRecipeIndexes = {};
  int _selected = 0;
  List<Recipe> _recipes = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _generateOnce();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _generateOnce() async {
    final settings = context.read<SettingsProvider>().settings;
    final recipes = await RecipeService(
      apiKey: settings.geminiApiKey,
      modelName: settings.geminiModel,
    ).generate(widget.ingredientWeights);
    if (!mounted) return;
    setState(() {
      _recipes = recipes;
      _loading = false;
    });
  }

  Future<void> _saveRecipe(int index) async {
    if (index < 0 || index >= _recipes.length) return;
    final recipe = _recipes[index];
    await context.read<SavedRecipeRepository>().saveRecipe(
      recipe,
      ingredientWeights: widget.ingredientWeights,
    );
    if (!mounted) return;
    setState(() => _savedRecipeIndexes.add(index));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${recipe.name} saved')));
  }

  Future<void> _finish() async {
    if (_savedRecipeIndexes.isNotEmpty) {
      _goHome();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No recipes saved'),
        content: const Text(
          'No recipes have been saved. Current recipes will be discarded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) _goHome();
  }

  void _goHome() => Navigator.of(context).popUntil((route) => route.isFirst);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Recipes')),
      body: _loading
          ? const _LoadingRecipes()
          : _recipes.isEmpty
          ? _EmptyRecipes(ingredientWeights: widget.ingredientWeights)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: _YourIngredients(
                    ingredientWeights: widget.ingredientWeights,
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _recipes.length,
                    onPageChanged: (i) => setState(() => _selected = i),
                    itemBuilder: (context, i) => _RecipePage(
                      recipe: _recipes[i],
                      selected: i == _selected,
                      saved: _savedRecipeIndexes.contains(i),
                      onSave: () => _saveRecipe(i),
                    ),
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < _recipes.length; i++)
                          Container(
                            width: i == _selected ? 20 : 8,
                            height: 8,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: i == _selected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outlineVariant,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            icon: const Icon(Icons.check),
            label: const Text('Finished'),
            onPressed: _finish,
          ),
        ),
      ),
    );
  }
}

class _LoadingRecipes extends StatelessWidget {
  const _LoadingRecipes();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Generating recipes…'),
      ],
    ),
  );
}

class _EmptyRecipes extends StatelessWidget {
  const _EmptyRecipes({required this.ingredientWeights});

  final Map<String, double> ingredientWeights;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.restaurant_menu, size: 56),
        const SizedBox(height: 16),
        Text(
          'No recipes available',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Check your Gemini API key and network connection, then try again from the ingredients screen.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final entry in ingredientWeights.entries)
              _CompactIngredientChip(
                label: '${entry.key} ${entry.value.round()}g',
              ),
          ],
        ),
      ],
    ),
  );
}

class _YourIngredients extends StatelessWidget {
  const _YourIngredients({required this.ingredientWeights});

  final Map<String, double> ingredientWeights;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your ingredients:',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final entry in ingredientWeights.entries)
              _CompactIngredientChip(
                label: '${entry.key} ${entry.value.round()}g',
              ),
          ],
        ),
      ],
    );
  }
}

class _CompactIngredientChip extends StatelessWidget {
  const _CompactIngredientChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label, style: Theme.of(context).textTheme.labelSmall),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6),
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

class _RecipePage extends StatelessWidget {
  const _RecipePage({
    required this.recipe,
    required this.selected,
    required this.saved,
    required this.onSave,
  });

  final Recipe recipe;
  final bool selected;
  final bool saved;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedScale(
      scale: selected ? 1 : 0.96,
      duration: const Duration(milliseconds: 180),
      child: Card(
        margin: const EdgeInsets.fromLTRB(6, 4, 6, 16),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    recipe.name,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  icon: Icon(saved ? Icons.bookmark_added : Icons.bookmark_add),
                  label: Text(saved ? 'Saved' : 'Save'),
                  onPressed: saved ? null : onSave,
                ),
              ],
            ),
            if (recipe.servings > 0) ...[
              const SizedBox(height: 6),
              Text(
                '${recipe.servings} servings',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            if (recipe.ingredientsUsed.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Ingredients', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final ingredient in recipe.ingredientsUsed)
                    _RecipeIngredientChip(label: ingredient),
                ],
              ),
            ],
            if (recipe.steps.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('Steps', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              for (var i = 0; i < recipe.steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 13,
                        child: Text(
                          '${i + 1}',
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(recipe.steps[i])),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecipeIngredientChip extends StatelessWidget {
  const _RecipeIngredientChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      labelPadding: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
