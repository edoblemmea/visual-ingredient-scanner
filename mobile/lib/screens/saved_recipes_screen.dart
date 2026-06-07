import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/saved_recipe.dart';
import '../services/saved_recipe_repository.dart';

class SavedRecipesScreen extends StatefulWidget {
  const SavedRecipesScreen({super.key});

  @override
  State<SavedRecipesScreen> createState() => _SavedRecipesScreenState();
}

class _SavedRecipesScreenState extends State<SavedRecipesScreen> {
  late List<SavedRecipe> _recipes;

  @override
  void initState() {
    super.initState();
    _recipes = const [];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  void _reload() {
    _recipes = context.read<SavedRecipeRepository>().load();
  }

  Future<void> _delete(SavedRecipe recipe) async {
    final repository = context.read<SavedRecipeRepository>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete recipe?'),
        content: Text('${recipe.recipe.name} will be removed from My recipes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repository.delete(recipe.id);
    if (!mounted) return;
    setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My recipes')),
      body: _recipes.isEmpty
          ? const _EmptySavedRecipes()
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              itemCount: _recipes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final saved = _recipes[i];
                return _SavedRecipeTile(
                  saved: saved,
                  onOpen: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SavedRecipeDetailScreen(saved: saved),
                    ),
                  ),
                  onDelete: () => _delete(saved),
                );
              },
            ),
    );
  }
}

class _EmptySavedRecipes extends StatelessWidget {
  const _EmptySavedRecipes();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bookmark_border, size: 56),
          const SizedBox(height: 12),
          Text(
            'No saved recipes',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Saved recipe ideas will appear here after a scan.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _SavedRecipeTile extends StatelessWidget {
  const _SavedRecipeTile({
    required this.saved,
    required this.onOpen,
    required this.onDelete,
  });

  final SavedRecipe saved;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final recipe = saved.recipe;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        title: Text(recipe.name),
        subtitle: Text(_subtitle(saved)),
        leading: const Icon(Icons.restaurant_menu),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete',
          onPressed: onDelete,
        ),
        onTap: onOpen,
      ),
    );
  }

  String _subtitle(SavedRecipe saved) {
    final date =
        '${saved.savedAt.day.toString().padLeft(2, '0')}/'
        '${saved.savedAt.month.toString().padLeft(2, '0')}/'
        '${saved.savedAt.year}';
    final count = saved.ingredientWeights.length;
    return '$date · $count ingredients';
  }
}

class SavedRecipeDetailScreen extends StatelessWidget {
  const SavedRecipeDetailScreen({super.key, required this.saved});

  final SavedRecipe saved;

  @override
  Widget build(BuildContext context) {
    final recipe = saved.recipe;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Recipe')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(recipe.name, style: theme.textTheme.headlineSmall),
          if (recipe.servings > 0) ...[
            const SizedBox(height: 6),
            Text('${recipe.servings} servings'),
          ],
          const SizedBox(height: 20),
          Text('Ingredients used', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ingredient in recipe.ingredientsUsed)
                _RecipeIngredientChip(label: ingredient),
            ],
          ),
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
                    child: Text('${i + 1}', style: theme.textTheme.labelSmall),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(recipe.steps[i])),
                ],
              ),
            ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 6),
      visualDensity: const VisualDensity(vertical: -2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}
