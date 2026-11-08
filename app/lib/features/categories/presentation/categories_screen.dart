import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/async_body.dart';
import '../data/categories_repository.dart';
import '../domain/category.dart';
import 'category_form_sheet.dart';
import 'category_icons.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  static const _tabs = [EntryKind.expense, EntryKind.income];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    return DefaultTabController(
      length: _tabs.length,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Kategoriler'),
            bottom: TabBar(
              tabs: [for (final kind in _tabs) Tab(text: kind.label)],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => showCategoryForm(
              context,
              kind: _tabs[DefaultTabController.of(context).index],
            ),
            icon: const Icon(Icons.add),
            label: const Text('Kategori ekle'),
          ),
          body: AsyncBody(
            value: categories,
            onRetry: () => ref.invalidate(categoriesProvider),
            data: (all) => TabBarView(
              children: [
                for (final kind in _tabs)
                  _CategoryList(
                    categories: all.where((c) => c.kind == kind).toList(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryList extends StatelessWidget {
  const _CategoryList({required this.categories});

  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    final active = categories.where((c) => !c.isArchived).toList();
    final archived = categories.where((c) => c.isArchived).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 88),
      children: [
        if (active.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Bu türde kategori yok.', textAlign: TextAlign.center),
          ),
        for (final category in active) _CategoryTile(category),
        if (archived.isNotEmpty)
          ExpansionTile(
            title: Text('Arşivlenen kategoriler (${archived.length})'),
            children: [
              for (final category in archived) _CategoryTile(category),
            ],
          ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile(this.category);

  final Category category;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: category.isArchived
            ? colors.surfaceContainerHighest
            : colors.primaryContainer,
        foregroundColor: category.isArchived
            ? colors.onSurfaceVariant
            : colors.onPrimaryContainer,
        child: Icon(CategoryIcons.of(category.icon)),
      ),
      title: Text(category.name),
      textColor: category.isArchived ? Theme.of(context).disabledColor : null,
      onTap: () =>
          showCategoryForm(context, kind: category.kind, category: category),
    );
  }
}
