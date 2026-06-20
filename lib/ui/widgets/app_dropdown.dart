import 'package:flutter/material.dart';
import 'package:firstpro/core/theme/app_colors.dart';

/// A reusable dropdown widget that fixes common issues:
/// - Properly expands to fit screen width
/// - Has scroll when items overflow
/// - Consistent styling with the app theme
/// - RTL-friendly
class AppDropdown<T> extends StatelessWidget {
  final T? value;
  final String label;
  final IconData? prefixIcon;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? Function(T?)? validator;
  final bool isExpanded;
  final bool enabled;

  const AppDropdown({
    super.key,
    this.value,
    required this.label,
    this.prefixIcon,
    required this.items,
    this.onChanged,
    this.validator,
    this.isExpanded = true,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: isExpanded,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      icon: const Icon(Icons.arrow_drop_down, size: 18),
      items: items,
      onChanged: enabled ? onChanged : null,
      validator: validator,
      menuMaxHeight: 300,
      itemHeight: 48,
      dropdownColor: Theme.of(context).colorScheme.surface,
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}
