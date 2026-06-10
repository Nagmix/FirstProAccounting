import 'package:flutter/material.dart';
import 'package:firstpro/core/theme/app_colors.dart';

// ════════════════════════════════════════════════════════════════
//  SETTINGS GROUP WRAPPER
// ════════════════════════════════════════════════════════════════

/// A titled group container for a cluster of related settings.
class SettingsGroup extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isDark;
  final List<Widget> children;

  const SettingsGroup({
    super.key,
    required this.title,
    required this.icon,
    required this.isDark,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.border,
            ),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  INDIVIDUAL SETTING BUILDERS
// ════════════════════════════════════════════════════════════════

/// Text field setting with a label and controller.
class TextSetting extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool isDark;
  final VoidCallback? onSave;

  const TextSetting({
    super.key,
    required this.label,
    required this.controller,
    required this.isDark,
    this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: controller,
        onSubmitted: (_) => onSave?.call(),
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor:
              isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
    );
  }
}

/// Read-only setting displayed as a simple ListTile.
class ReadOnlySetting extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool isDark;

  const ReadOnlySetting({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary, size: 22),
      title: Text(label),
      trailing: Text(
        value,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// Number input setting with increment/decrement buttons.
class NumberSetting extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final bool isDark;

  const NumberSetting({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Container(
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkSurfaceVariant
                  : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: value > 1 ? () => onChanged(value - 1) : null,
                  icon: const Icon(Icons.remove, size: 20),
                  splashRadius: 18,
                ),
                Container(
                  width: 40,
                  alignment: Alignment.center,
                  child: Text(
                    '$value',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: value < 999 ? () => onChanged(value + 1) : null,
                  icon: const Icon(Icons.add, size: 20),
                  splashRadius: 18,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Action tile (tappable ListTile).
class ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDark;

  const ActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary, size: 22),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
        ),
      ),
      trailing: Icon(
        Icons.arrow_back_ios,
        size: 16,
        color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
      ),
      onTap: onTap,
    );
  }
}

/// Danger action tile (red accent).
class DangerTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const DangerTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.delete, color: AppColors.error, size: 22),
      title: Text(
        title,
        style: const TextStyle(
            color: AppColors.error, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppColors.errorLight),
      ),
      trailing:
          const Icon(Icons.arrow_back_ios, size: 16, color: AppColors.error),
      onTap: onTap,
    );
  }
}
