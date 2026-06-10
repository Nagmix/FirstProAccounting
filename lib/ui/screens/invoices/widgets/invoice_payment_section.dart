import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';

/// Extracted payment section widget for the CreateInvoiceScreen.
///
/// Receives all state and callbacks from the parent stateful widget.
/// No business logic resides here — only UI rendering.
class InvoicePaymentSection extends StatelessWidget {
  const InvoicePaymentSection({
    super.key,
    // ── State values ──
    required this.isDark,
    required this.paymentMechanism,
    required this.paymentMethod,
    required this.isReturn,
    required this.autoPay,
    required this.selectedCurrency,
    required this.selectedExchangeRate,
    required this.selectedCashBoxId,
    required this.selectedEwalletProvider,
    required this.selectedBankTransferProvider,
    required this.attachmentPath,
    required this.originalInvoiceId,
    required this.originalInvoiceDisplay,
    required this.currencies,
    required this.cashBoxes,
    required this.paidController,
    required this.transferNumberController,
    required this.total,
    required this.paidAmount,
    required this.remaining,
    required this.isSale,
    required this.showPartialPaymentWarning,
    // ── Callbacks ──
    required this.onToggleReturn,
    required this.onSetCashMechanism,
    required this.onSetCreditMechanism,
    required this.onPaymentMethodChanged,
    required this.onCurrencyChanged,
    required this.onCashBoxChanged,
    required this.onEwalletProviderChanged,
    required this.onBankTransferProviderChanged,
    required this.onPickImageFromGallery,
    required this.onPickImageFromCamera,
    required this.onRemoveAttachment,
    required this.onToggleAutoPay,
    required this.onShowOriginalInvoiceSelector,
    required this.onClearOriginalInvoice,
    required this.onPaidChanged,
  });

  // ── State values ─────────────────────────────────────────────────
  final bool isDark;
  final String paymentMechanism;
  final String paymentMethod;
  final bool isReturn;
  final bool autoPay;
  final String selectedCurrency;
  final double selectedExchangeRate;
  final int? selectedCashBoxId;
  final String? selectedEwalletProvider;
  final String? selectedBankTransferProvider;
  final String? attachmentPath;
  final String? originalInvoiceId;
  final String? originalInvoiceDisplay;
  final List<Map<String, dynamic>> currencies;
  final List<Map<String, dynamic>> cashBoxes;
  final TextEditingController paidController;
  final TextEditingController transferNumberController;
  final double total;
  final double paidAmount;
  final double remaining;
  final bool isSale;
  final bool showPartialPaymentWarning;

  // ── Callbacks ────────────────────────────────────────────────────
  final VoidCallback onToggleReturn;
  final VoidCallback onSetCashMechanism;
  final VoidCallback onSetCreditMechanism;
  final ValueChanged<String> onPaymentMethodChanged;
  final ValueChanged<String> onCurrencyChanged;
  final ValueChanged<int?> onCashBoxChanged;
  final ValueChanged<String?> onEwalletProviderChanged;
  final ValueChanged<String?> onBankTransferProviderChanged;
  final VoidCallback onPickImageFromGallery;
  final VoidCallback onPickImageFromCamera;
  final VoidCallback onRemoveAttachment;
  final VoidCallback onToggleAutoPay;
  final VoidCallback onShowOriginalInvoiceSelector;
  final VoidCallback onClearOriginalInvoice;
  final VoidCallback onPaidChanged;

  // ── Design constants (duplicated from parent) ────────────────────
  static const Color _accentBlue = Color(0xFF4F6AF0);
  static const Color _accentPurple = Color(0xFF7C3AED);

  LinearGradient get _primaryGradient => const LinearGradient(
        colors: [_accentBlue, _accentPurple],
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
      );

  // ── E-wallet / bank-transfer providers ───────────────────────────
  static const List<String> _ewalletProviders = [
    'جيب', 'فلوسك', 'كاش', 'ون كاش', 'جوالي', 'الكريمي',
    'موبايل موني', 'محفظتي', 'شامل موني', 'سبأ كاش', 'ايزي', 'يمن والت', 'أخرى',
  ];

  static const List<String> _bankTransferProviders = [
    'الامتياز', 'النجم', 'يمن اكسبرس', 'الحزمي اكسبرس', 'الاكوع كوني',
    'السريع للحوالات', 'ياه موني', 'عامري كاش', 'الناصر اكسبرس',
    'المحيط اكسبرس', 'تحويل', 'أخرى',
  ];

  // ── Section header helper ────────────────────────────────────────
  Widget _sectionHeader(BuildContext context, String title,
      {IconData icon = Icons.label_important_rounded, Widget? trailing}) {
    final isDark = context.isDarkMode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              gradient: _primaryGradient,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, size: 20, color: _accentBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  letterSpacing: 0.3,
                  color: isDark ? AppColors.darkTextPrimary : const Color(0xFF1E293B),
                )),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(16),
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
          _sectionHeader(context, 'تفاصيل الدفع', icon: Icons.payment_rounded),
          // Currency + Return in one row
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildModernDropdown<String>(
                  value: selectedCurrency,
                  label: 'العملة',
                  icon: Icons.monetization_on_rounded,
                  items: currencies
                      .map((c) => DropdownMenuItem<String>(
                            value: c['code'] as String,
                            child: Text('${c['code']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) onCurrencyChanged(val);
                  },
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildReturnToggle(),
              ),
            ],
          ),
          // Original invoice selector (only when isReturn is true)
          if (isReturn) ...[
            const SizedBox(height: 12),
            _buildOriginalInvoiceSelector(context),
          ],
          if (selectedCurrency != 'YER')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _accentBlue.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swap_vert_rounded, size: 14, color: _accentBlue),
                    const SizedBox(width: 4),
                    Text(
                      'سعر الصرف: $selectedExchangeRate',
                      style: context.textTheme.bodySmall?.copyWith(color: _accentBlue, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          // Payment mechanism segmented control
          _buildPaymentMechanismControl(),
          // Credit info
          if (paymentMechanism == 'credit') ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.secondary.withValues(alpha: 0.08), AppColors.secondary.withValues(alpha: 0.03)],
                  begin: Alignment.centerRight,
                  end: Alignment.centerLeft,
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.secondary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.info_outline_rounded, color: AppColors.secondary, size: 14),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'سيتم تسجيل المبلغ كرصيد على الحساب',
                      style: context.textTheme.bodySmall?.copyWith(color: AppColors.secondary, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Payment method pills (only when cash)
          if (paymentMechanism == 'cash') ...[
            const SizedBox(height: 14),
            _buildPaymentMethodRow(),
          ],
          // E-wallet / bank transfer sections
          if (paymentMechanism == 'cash' && paymentMethod == 'ewallet')
            _buildEwalletSection(),
          if (paymentMechanism == 'cash' && paymentMethod == 'bank_transfer')
            _buildBankTransferSection(),
          // Cash box + paid amount
          if (paymentMechanism == 'cash') ...[
            const SizedBox(height: 14),
            _buildCashBoxAndPaidRow(context),
          ],
        ],
      ),
    );

    if (!showPartialPaymentWarning) return card;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPartialPaymentWarning(context),
        card,
      ],
    );
  }

  // ── Partial payment warning ──────────────────────────────────────
  Widget _buildPartialPaymentWarning(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'المبلغ المدفوع أقل من المستحق. المتبقي سيتم تسجيله كرصد آجل',
              style: context.textTheme.bodySmall?.copyWith(
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Modern dropdown helper ────────────────────────────────────────
  Widget _buildModernDropdown<T>({
    required T? value,
    required String label,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    String? Function(T?)? validator,
    bool isDark = false,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isDense: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Container(
          margin: const EdgeInsets.only(left: 8),
          child: Icon(icon, size: 20, color: _accentBlue),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accentBlue, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        filled: true,
        fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant.withValues(alpha: 0.3),
      ),
      items: items,
      onChanged: onChanged,
      validator: validator,
    );
  }

  // ── Return toggle ─────────────────────────────────────────────────
  Widget _buildReturnToggle() {
    return GestureDetector(
      onTap: onToggleReturn,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.fastOutSlowIn,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: isReturn
              ? AppColors.error.withValues(alpha: isDark ? 0.12 : 0.06)
              : (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isReturn ? AppColors.error : (isDark ? AppColors.darkBorder : AppColors.border),
            width: isReturn ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isReturn ? Icons.undo_rounded : Icons.undo_outlined,
                key: ValueKey(isReturn),
                size: 16,
                color: isReturn ? AppColors.error : AppColors.textHint,
              ),
            ),
            const SizedBox(width: 6),
            Text('مرتجع',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isReturn ? AppColors.error : AppColors.textHint,
                )),
          ],
        ),
      ),
    );
  }

  // ── Payment mechanism segmented control ──────────────────────────
  Widget _buildPaymentMechanismControl() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildMechanismSegment(
              icon: Icons.payments_rounded,
              label: 'نقداً',
              isSelected: paymentMechanism == 'cash',
              color: AppColors.success,
              onTap: onSetCashMechanism,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildMechanismSegment(
              icon: Icons.schedule_rounded,
              label: 'أجل',
              isSelected: paymentMechanism == 'credit',
              color: AppColors.secondary,
              onTap: onSetCreditMechanism,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMechanismSegment({
    required IconData icon,
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.fastOutSlowIn,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: isDark ? 0.2 : 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          border: isSelected ? Border.all(color: color.withValues(alpha: 0.3), width: 1) : null,
          boxShadow: isSelected ? [BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2))] : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(icon,
                  key: ValueKey(isSelected), size: 18, color: isSelected ? color : AppColors.textHint),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                color: isSelected ? color : AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_circle_rounded, size: 14, color: color),
            ],
          ],
        ),
      ),
    );
  }

  // ── Original Invoice Selector (for returns) ────────────────────────
  Widget _buildOriginalInvoiceSelector(BuildContext context) {
    return GestureDetector(
      onTap: onShowOriginalInvoiceSelector,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: originalInvoiceId != null
              ? AppColors.error.withValues(alpha: isDark ? 0.08 : 0.04)
              : (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: originalInvoiceId != null
                ? AppColors.error.withValues(alpha: 0.4)
                : (isDark ? AppColors.darkBorder : AppColors.border),
            width: originalInvoiceId != null ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: (originalInvoiceId != null ? AppColors.error : AppColors.textHint).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.link_rounded,
                size: 14,
                color: originalInvoiceId != null ? AppColors.error : AppColors.textHint,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                originalInvoiceDisplay ?? 'اختر الفاتورة الأصلية...',
                style: context.textTheme.bodyMedium?.copyWith(
                  color: originalInvoiceId != null ? AppColors.textPrimary : AppColors.textHint,
                  fontWeight: originalInvoiceId != null ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (originalInvoiceId != null)
              GestureDetector(
                onTap: onClearOriginalInvoice,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.close_rounded, size: 14, color: AppColors.error),
                ),
              )
            else
              Icon(Icons.arrow_drop_down_rounded, size: 22, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }

  // ── Payment method pills ──────────────────────────────────────────
  Widget _buildPaymentMethodRow() {
    const methods = [
      ('cash', 'نقدي', Icons.payments_rounded, AppColors.success),
      ('check', 'شيك', Icons.sticky_note_2_rounded, AppColors.accentBlue),
      ('transfer', 'حوالة', Icons.swap_horiz_rounded, AppColors.secondary),
      ('bank', 'بنك', Icons.account_balance_rounded, Color(0xFF4F6AF0)),
      ('ewallet', 'محفظة', Icons.account_balance_wallet_rounded, AppColors.success),
      ('bank_transfer', 'حوالة مصرفية', Icons.business_rounded, Color(0xFF6A1B9A)),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 8,
      children: methods.map((m) {
        final selected = paymentMethod == m.$1;
        return GestureDetector(
          onTap: () => onPaymentMethodChanged(m.$1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.fastOutSlowIn,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? m.$4.withValues(alpha: isDark ? 0.18 : 0.08) : (isDark ? AppColors.darkSurfaceVariant : Colors.white),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? m.$4 : (isDark ? AppColors.darkBorder : AppColors.border),
                width: selected ? 1.5 : 1,
              ),
              boxShadow: selected ? [BoxShadow(color: m.$4.withValues(alpha: 0.08), blurRadius: 6, offset: const Offset(0, 2))] : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(m.$3, size: 15, color: selected ? m.$4 : AppColors.textHint),
                const SizedBox(width: 5),
                Text(
                  m.$2,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? m.$4 : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── E-wallet section ─────────────────────────────────────────────
  Widget _buildEwalletSection() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.success.withValues(alpha: 0.06), AppColors.success.withValues(alpha: 0.02)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: selectedEwalletProvider,
            isDense: true,
            decoration: InputDecoration(
              labelText: 'اختر المحفظة الإلكترونية',
              prefixIcon: Container(
                margin: const EdgeInsets.only(left: 8),
                child: const Icon(Icons.account_balance_wallet_rounded, color: AppColors.success, size: 18),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.success.withValues(alpha: 0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.success, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: isDark ? AppColors.darkSurfaceVariant : Colors.white,
            ),
            items: _ewalletProviders.map((p) => DropdownMenuItem<String>(value: p, child: Text(p, style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: onEwalletProviderChanged,
          ),
          const SizedBox(height: 10),
          _buildAttachmentButtons(),
        ],
      ),
    );
  }

  // ── Bank transfer section ────────────────────────────────────────
  Widget _buildBankTransferSection() {
    const purpleColor = Color(0xFF6A1B9A);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [purpleColor.withValues(alpha: 0.06), purpleColor.withValues(alpha: 0.02)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: purpleColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: selectedBankTransferProvider,
            isDense: true,
            decoration: InputDecoration(
              labelText: 'اختر شركة الحوالة',
              prefixIcon: Container(
                margin: const EdgeInsets.only(left: 8),
                child: const Icon(Icons.business_rounded, color: purpleColor, size: 18),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: purpleColor.withValues(alpha: 0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: purpleColor, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: isDark ? AppColors.darkSurfaceVariant : Colors.white,
            ),
            items: _bankTransferProviders.map((p) => DropdownMenuItem<String>(value: p, child: Text(p, style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: onBankTransferProviderChanged,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: transferNumberController,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'رقم الحوالة (اختياري)',
              prefixIcon: Container(
                margin: const EdgeInsets.only(left: 8),
                child: const Icon(Icons.tag_rounded, color: purpleColor, size: 18),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: purpleColor.withValues(alpha: 0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: purpleColor, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              filled: true,
              fillColor: isDark ? AppColors.darkSurfaceVariant : Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          _buildAttachmentButtons(isBankTransfer: true),
        ],
      ),
    );
  }

  // ── Attachment buttons ───────────────────────────────────────────
  Widget _buildAttachmentButtons({bool isBankTransfer = false}) {
    return Column(
      children: [
        if (attachmentPath != null) ...[
          Container(
            height: 100,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Image.file(File(attachmentPath!), width: double.infinity, height: 100, fit: BoxFit.cover),
                Positioned(
                  top: 6,
                  left: 6,
                  child: GestureDetector(
                    onTap: onRemoveAttachment,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _accentBlue.withValues(alpha: 0.3)),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onPickImageFromGallery,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.image_rounded, size: 16, color: _accentBlue),
                          const SizedBox(width: 6),
                          Text(isBankTransfer ? 'رفق إشعار' : 'رفق صورة',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _accentBlue)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _accentBlue.withValues(alpha: 0.3)),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onPickImageFromCamera,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt_rounded, size: 16, color: _accentBlue),
                          const SizedBox(width: 6),
                          Text('تصوير', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _accentBlue)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Cash box + Paid amount row ───────────────────────────────────
  Widget _buildCashBoxAndPaidRow(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cash box dropdown — show only name (cash boxes are currency-agnostic)
        _buildModernDropdown<int>(
          value: selectedCashBoxId,
          label: 'الصندوق *',
          icon: Icons.account_balance_wallet_rounded,
          items: cashBoxes.map((cb) {
            return DropdownMenuItem<int>(
              value: cb['id'] as int,
              child: Text('${cb['name']}', style: const TextStyle(fontSize: 12)),
            );
          }).toList(),
          onChanged: onCashBoxChanged,
          validator: (v) => v == null ? 'يجب اختيار الصندوق' : null,
          isDark: isDark,
        ),
        const SizedBox(height: 12),
        // Paid amount + Auto-pay checkbox
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextFormField(
                controller: paidController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.left,
                enabled: !autoPay,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'المدفوع',
                  prefixIcon: Container(
                    margin: const EdgeInsets.only(left: 8),
                    child: const Icon(Icons.payments_rounded, size: 18, color: _accentBlue),
                  ),
                  suffixText: selectedCurrency,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.border),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _accentBlue, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: autoPay,
                  fillColor: autoPay ? (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant).withValues(alpha: 0.5) : null,
                ),
                onChanged: (_) => onPaidChanged(),
              ),
            ),
            const SizedBox(width: 10),
            // Auto-pay toggle
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: onToggleAutoPay,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44,
                    height: 24,
                    decoration: BoxDecoration(
                      color: autoPay ? _accentBlue : (isDark ? AppColors.darkSurfaceVariant : AppColors.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 200),
                      alignment: autoPay ? Alignment.centerLeft : Alignment.centerRight,
                      child: Container(
                        width: 20,
                        height: 20,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4, offset: const Offset(0, 1))],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text('مدفوع',
                    style: context.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      color: autoPay ? _accentBlue : AppColors.textHint,
                      fontWeight: autoPay ? FontWeight.w700 : FontWeight.w400,
                    )),
              ],
            ),
          ],
        ),
        // Remaining amount
        if (!autoPay && remaining.abs() > 0.005) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: remaining > 0.005 ? AppColors.error.withValues(alpha: 0.06) : AppColors.success.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: remaining > 0.005 ? AppColors.error.withValues(alpha: 0.2) : AppColors.success.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      remaining > 0.005 ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                      size: 14,
                      color: remaining > 0.005 ? AppColors.error : AppColors.success,
                    ),
                    const SizedBox(width: 6),
                    Text('المتبقي', style: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
                Text(
                  CurrencyFormatter.format(remaining),
                  style: context.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: remaining > 0.005 ? AppColors.error : AppColors.success,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
