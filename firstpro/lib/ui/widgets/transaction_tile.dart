import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';

/// Status of a transaction displayed in the tile.
enum TransactionStatus { paid, unpaid, pending }

/// A reusable list-tile for recent transactions / invoices.
///
/// Shows a coloured status circle as leading, customer name as title,
/// date as subtitle, and formatted amount + status badge as trailing.
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.customerName,
    required this.amount,
    required this.date,
    required this.status,
    this.onTap,
  });

  final String customerName;
  final double amount;
  final DateTime date;
  final TransactionStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListTile(
      onTap: onTap,
      leading: _buildStatusAvatar(isDark),
      title: Text(
        customerName,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        DateFormatter.formatDate(date),
        style: theme.textTheme.bodySmall?.copyWith(
          color:
              isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── Amount ───────────────────────────────────────────
          Text(
            CurrencyFormatter.format(amount),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),

          // ── Status badge ─────────────────────────────────────
          _buildStatusBadge(),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────

  /// Leading circle avatar coloured by status.
  Widget _buildStatusAvatar(bool isDark) {
    final color = _statusColor;
    final initial = customerName.isNotEmpty ? customerName[0] : '?';

    return CircleAvatar(
      radius: 22,
      backgroundColor: color.withValues(alpha: 0.12),
      child: Text(
        initial,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }

  /// Small status badge chip.
  Widget _buildStatusBadge() {
    final color = _statusColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _statusLabel,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Color get _statusColor {
    switch (status) {
      case TransactionStatus.paid:
        return AppColors.success;
      case TransactionStatus.unpaid:
        return AppColors.error;
      case TransactionStatus.pending:
        return AppColors.warning;
    }
  }

  String get _statusLabel {
    switch (status) {
      case TransactionStatus.paid:
        return AppConstants.statusPaid;
      case TransactionStatus.unpaid:
        return AppConstants.statusUnpaid;
      case TransactionStatus.pending:
        return AppConstants.statusPending;
    }
  }
}
