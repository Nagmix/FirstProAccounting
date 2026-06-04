import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';

// ═══════════════════════════════════════════════════════════════════
//  Step title widget
// ═══════════════════════════════════════════════════════════════════

class StepTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const StepTitle({
    super.key,
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Icon(icon, size: 22, color: AppColors.primary),
          const SizedBox(width: 10),
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Price field widget
// ═══════════════════════════════════════════════════════════════════

class ProductPriceField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;

  const ProductPriceField({
    super.key,
    required this.controller,
    required this.label,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: textInputAction,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        suffixText: AppConstants.currency,
      ),
      onChanged: onChanged,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Switch tile widget
// ═══════════════════════════════════════════════════════════════════

class ProductSwitchTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const ProductSwitchTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  Searchable dropdown with "+" add button
// ═══════════════════════════════════════════════════════════════════

class ProductSearchableDropdown extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<Map<String, dynamic>> items;
  final String idKey;
  final String nameKey;
  final int? selectedId;
  final ValueChanged<int?>? onChanged;
  final VoidCallback? onAdd;
  final String? emptyMessage;

  const ProductSearchableDropdown({
    super.key,
    required this.label,
    required this.icon,
    required this.items,
    required this.idKey,
    required this.nameKey,
    required this.selectedId,
    required this.onChanged,
    required this.onAdd,
    this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      readOnly: true,
      controller: TextEditingController(
        text: selectedId != null
            ? (items.where((i) => i[idKey] == selectedId).isNotEmpty
                ? items.firstWhere((i) => i[idKey] == selectedId)[nameKey] as String
                : '')
            : '',
      ),
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onAdd != null)
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                tooltip: 'إضافة جديد',
                onPressed: onAdd,
              ),
            if (selectedId != null && onChanged != null)
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => onChanged(null),
              ),
          ],
        ),
      ),
      onTap: () {
        if (items.isEmpty && emptyMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(emptyMessage),
              backgroundColor: AppColors.warning,
            ),
          );
          onAdd?.call();
          return;
        }
        _showSearchDialog(context);
      },
    );
  }

  void _showSearchDialog(BuildContext context) {
    final searchController = TextEditingController();
    List<Map<String, dynamic>> filteredItems = List.from(items);

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                title: Text(label),
                content: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'بحث...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: (v) {
                          setDialogState(() {
                            filteredItems = items
                                .where((i) => (i[nameKey] as String)
                                    .toLowerCase()
                                    .contains(v.toLowerCase()))
                                .toList();
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 300,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: filteredItems.length,
                          itemBuilder: (context, index) {
                            final item = filteredItems[index];
                            final id = item[idKey] as int;
                            final name = item[nameKey] as String;
                            final isSelected = id == selectedId;
                            return ListTile(
                              dense: true,
                              title: Text(name),
                              trailing: isSelected
                                  ? const Icon(Icons.check, color: AppColors.primary)
                                  : null,
                              selected: isSelected,
                              selectedTileColor: AppColors.primary.withOpacity(0.05),
                              onTap: () {
                                onChanged?.call(id);
                                Navigator.of(dialogContext).pop();
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      searchController.dispose();
    });
  }
}
