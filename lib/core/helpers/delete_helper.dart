import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_colors.dart';

/// Shared delete confirmation dialog used across all entity list screens.
///
/// Previously, the delete confirmation dialog was duplicated in 5+ screen
/// files. This class provides a single source of truth with consistent
/// behavior and haptic feedback.
class DeleteHelper {
  DeleteHelper._();

  /// Shows a confirmation dialog for deleting an entity.
  ///
  /// Returns `true` if the user confirmed, `false` otherwise.
  ///
  /// [entityType] is the display name of the entity type (e.g. "العميل", "المورد").
  /// [entityName] is the display name of the specific entity being deleted.
  static Future<bool> showDeleteConfirmation({
    required BuildContext context,
    required String entityType,
    required String entityName,
  }) async {
    // Medium haptic feedback on delete action
    HapticFeedback.mediumImpact();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning, color: AppColors.error, size: 40),
        title: Text('حذف $entityType'),
        content: Text('هل أنت متأكد من حذف $entityType "$entityName"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// Shows a success snackbar after deletion.
  static void showDeleteSuccess(
    BuildContext context,
    String entityType,
    String entityName,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم حذف $entityType "$entityName"'),
        backgroundColor: AppColors.success,
      ),
    );
  }
}
