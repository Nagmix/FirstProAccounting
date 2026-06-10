import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';

/// Extracted summary section widget for the CreateInvoiceScreen.
///
/// Receives calculated totals, controllers, and callbacks.
class InvoiceSummarySection extends StatelessWidget {
  const InvoiceSummarySection({
    super.key,
    required this.isDark,
    required this.subtotal,
    required this.discountAmount,
    required this.taxAmount,
    required this.transportCharges,
    required this.total,
    required this.paidAmount,
    required this.remaining,
    required this.totalInBaseCurrency,
    required this.paidAmountInBaseCurrency,
    required this.remainingInBaseCurrency,
    required this.selectedCurrency,
    required this.discountController,
    required this.transportChargesController,
    required this.notesController,
    required this.onDiscountChanged,
    required this.onTransportChanged,
  });

  // ── State values ─────────────────────────────────────────────────
  final bool isDark;
  final double subtotal;
  final double discountAmount;
  final double taxAmount;
  final double transportCharges;
  final double total;
  final double paidAmount;
  final double remaining;
  final double totalInBaseCurrency;
  final double paidAmountInBaseCurrency;
  final double remainingInBaseCurrency;
  final String selectedCurrency;
  final TextEditingController discountController;
  final TextEditingController transportChargesController;
  final TextEditingController notesController;

  // ── Callbacks ────────────────────────────────────────────────────
  final VoidCallback onDiscountChanged;
  final VoidCallback onTransportChanged;

  // ── Design constants (duplicated from parent) ────────────────────
  static const Color _accentBlue = Color(0xFF4F6AF0);
  static const Color _accentPurple = Color(0xFF7C3AED);

  LinearGradient get _primaryGradient => const LinearGradient(
        colors: [_accentBlue, _accentPurple],
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.04),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gradient accent header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _accentBlue.withValues(alpha: isDark ? 0.15 : 0.08),
                  _accentPurple.withValues(alpha: isDark ? 0.08 : 0.03),
                ],
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: _primaryGradient,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.summarize_rounded, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text('ملخص الفاتورة',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: isDark ? AppColors.darkTextPrimary : const Color(0xFF1E293B),
                    )),
              ],
            ),
          ),
          // Summary body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryRow(context, 'المجموع الفرعي', CurrencyFormatter.format(subtotal), isDark),
                const SizedBox(height: 8),
                // Discount inline
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.discount_rounded, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text('الخصم', style: context.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                      ],
                    ),
                    SizedBox(
                      width: 130,
                      child: TextField(
                        controller: discountController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.left,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          suffixText: selectedCurrency,
                          hintText: '0.00',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _accentBlue, width: 1.5),
                          ),
                          filled: true,
                          fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant.withValues(alpha: 0.3),
                        ),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        onChanged: (_) => onDiscountChanged(),
                      ),
                    ),
                  ],
                ),
                if (AppConstants.defaultVatRate > 0) ...[
                  const SizedBox(height: 8),
                  _summaryRow(context, 'الضريبة (${AppConstants.defaultVatRate.toStringAsFixed(0)}%)', CurrencyFormatter.format(taxAmount), isDark),
                ],
                // Transport inline
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.local_shipping_rounded, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text('أجور النقل', style: context.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                      ],
                    ),
                    SizedBox(
                      width: 130,
                      child: TextField(
                        controller: transportChargesController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.left,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          suffixText: selectedCurrency,
                          hintText: '0.00',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _accentBlue, width: 1.5),
                          ),
                          filled: true,
                          fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant.withValues(alpha: 0.3),
                        ),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        onChanged: (_) => onTransportChanged(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Total divider
                Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, _accentBlue.withValues(alpha: 0.2), Colors.transparent],
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Total with gradient accent
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _accentBlue.withValues(alpha: isDark ? 0.12 : 0.06),
                        _accentPurple.withValues(alpha: isDark ? 0.06 : 0.02),
                      ],
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _accentBlue.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('الإجمالي', style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      Text(CurrencyFormatter.format(total),
                          style: context.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: _accentBlue,
                            fontSize: 20,
                          )),
                    ],
                  ),
                ),
                if (selectedCurrency != 'YER') ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      children: [
                        _summaryRow(context, 'المعادل بالريال اليمني', '${CurrencyFormatter.format(totalInBaseCurrency)} ر.ي', isDark,
                            valueStyle: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.info)),
                        if (paidAmount > 0.005) ...[
                          const SizedBox(height: 4),
                          _summaryRow(context, 'المدفوع (ر.ي)', '${CurrencyFormatter.format(paidAmountInBaseCurrency)} ر.ي', isDark,
                              valueStyle: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: AppColors.success)),
                        ],
                        if (remaining > 0.005) ...[
                          const SizedBox(height: 4),
                          _summaryRow(context, 'المتبقي (ر.ي)', '${CurrencyFormatter.format(remainingInBaseCurrency)} ر.ي', isDark,
                              valueStyle: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: AppColors.error)),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                // Notes
                TextFormField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'ملاحظات',
                    prefixIcon: Container(
                      margin: const EdgeInsets.only(left: 8),
                      child: const Icon(Icons.edit_note_rounded, size: 18, color: _accentBlue),
                    ),
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _accentBlue, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Summary row helper ───────────────────────────────────────────
  Widget _summaryRow(BuildContext context, String label, String value, bool isDark,
      {TextStyle? valueStyle, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: context.textTheme.bodySmall?.copyWith(
              color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            )),
        Text(value,
            style: valueStyle ??
                context.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: valueColor ?? (isDark ? AppColors.darkTextPrimary : AppColors.textPrimary),
                )),
      ],
    );
  }
}
