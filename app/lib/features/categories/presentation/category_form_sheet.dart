import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/data_failure.dart';
import '../../../core/widgets/async_body.dart';
import '../data/categories_repository.dart';
import '../domain/category.dart';
import 'category_icons.dart';

/// Kategori ekleme (category == null) veya düzenleme formu.
Future<void> showCategoryForm(
  BuildContext context, {
  required EntryKind kind,
  Category? category,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _CategoryFormSheet(kind: kind, category: category),
);

class _CategoryFormSheet extends ConsumerStatefulWidget {
  const _CategoryFormSheet({required this.kind, this.category});

  final EntryKind kind;
  final Category? category;

  @override
  ConsumerState<_CategoryFormSheet> createState() => _CategoryFormSheetState();
}

class _CategoryFormSheetState extends ConsumerState<_CategoryFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.category?.name);
  late String _icon = CategoryIcons.all.containsKey(widget.category?.icon)
      ? widget.category!.icon!
      : 'more_horiz';
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.category != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function(CategoriesRepository repo) action,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(ref.read(categoriesRepositoryProvider));
      ref.invalidate(categoriesProvider);
      if (mounted) Navigator.of(context).pop();
    } on DataFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _save() {
    if (_busy || !_formKey.currentState!.validate()) return;
    final name = _name.text.trim();
    _run(
      (repo) => _isEdit
          ? repo.update(widget.category!.id, name: name, icon: _icon)
          : repo.create(kind: widget.kind, name: name, icon: _icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEdit
                    ? 'Kategoriyi düzenle'
                    : 'Yeni ${widget.kind.label.toLowerCase()} kategorisi',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                autofocus: !_isEdit,
                decoration: const InputDecoration(labelText: 'Kategori adı'),
                maxLength: 40,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Kategori adı gerekli.'
                    : null,
              ),
              const SizedBox(height: 8),
              Text('Simge', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final MapEntry(:key, :value)
                      in CategoryIcons.all.entries)
                    IconButton(
                      key: Key('icon-$key'),
                      isSelected: key == _icon,
                      style: IconButton.styleFrom(
                        backgroundColor: key == _icon
                            ? colors.primaryContainer
                            : null,
                      ),
                      icon: Icon(value),
                      onPressed: () => setState(() => _icon = key),
                    ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                FormErrorText(_error!),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('Kaydet'),
              ),
              if (category != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                          (repo) => repo.setArchived(
                            category.id,
                            archived: !category.isArchived,
                          ),
                        ),
                  icon: Icon(
                    category.isArchived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                  ),
                  label: Text(
                    category.isArchived ? 'Arşivden çıkar' : 'Arşivle',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
