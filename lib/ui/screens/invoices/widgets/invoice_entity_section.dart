import 'package:flutter/material.dart';

import 'package:firstpro/core/extensions/context_extensions.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/utils/currency_formatter.dart';
import 'package:firstpro/core/utils/money_helper.dart';

/// Extracted entity (customer/supplier) section widget for the CreateInvoiceScreen.
///
/// Receives all state and callbacks from the parent stateful widget.
class InvoiceEntitySection extends StatelessWidget {
  const InvoiceEntitySection({
    super.key,
    required this.isDark,
    required this.showEntityDropdown,
    required this.selectedEntityId,
    required this.selectedEntityType,
    required this.selectedEntityName,
    required this.filteredEntities,
    required this.entitySearchController,
    required this.isEntityRequired,
    required this.isSale,
    required this.paymentMechanism,
    required this.onToggleDropdown,
    required this.onEntitySelected,
    required this.onClearEntity,
    required this.onAddNewEntity,
    required this.onFilterEntities,
  });

  // ── State values ─────────────────────────────────────────────────
  final bool isDark;
  final bool showEntityDropdown;
  final int? selectedEntityId;
  final String? selectedEntityType;
  final String? selectedEntityName;
  final List<Map<String, dynamic>> filteredEntities;
  final TextEditingController entitySearchController;
  final bool isEntityRequired;
  final bool isSale;
  final String paymentMechanism;

  // ── Callbacks ────────────────────────────────────────────────────
  final VoidCallback onToggleDropdown;
  final void Function(int id, String type) onEntitySelected;
  final VoidCallback onClearEntity;
  final VoidCallback onAddNewEntity;
  final ValueChanged<String> onFilterEntities;

  // ── Design constants (duplicated from parent) ────────────────────
  static const Color _accentBlue = Color(0xFF4F6AF0);
  static const Color _accentPurple = Color(0xFF7C3AED);

  LinearGradient get _primaryGradient => const LinearGradient(
        colors: [_accentBlue, _accentPurple],
        begin: Alignment.centerRight,
        end: Alignment.centerLeft,
      );

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
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : const Color(0xFF1E293B),
                )),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
          _sectionHeader(
            context,
            'اسم الحساب',
            icon: Icons.person_rounded,
            trailing: isEntityRequired
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('مطلوب',
                        style: context.textTheme.labelSmall?.copyWith(
                            color: AppColors.error,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  )
                : Text('(اختياري)',
                    style: context.textTheme.bodySmall
                        ?.copyWith(color: AppColors.textHint, fontSize: 11)),
          ),
          // Entity selection field
          GestureDetector(
            onTap: onToggleDropdown,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkSurfaceVariant
                    : AppColors.surfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: showEntityDropdown
                      ? _accentBlue
                      : (selectedEntityId != null
                          ? _accentBlue.withValues(alpha: 0.3)
                          : (isDark ? AppColors.darkBorder : AppColors.border)),
                  width: showEntityDropdown ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  // Avatar circle
                  _buildEntityAvatar(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      selectedEntityName ?? 'اختر حساب...',
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: selectedEntityId != null
                            ? (isDark
                                ? AppColors.darkTextPrimary
                                : AppColors.textPrimary)
                            : AppColors.textHint,
                        fontWeight: selectedEntityId != null
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (selectedEntityId != null)
                    GestureDetector(
                      onTap: onClearEntity,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.close_rounded,
                            size: 14, color: AppColors.error),
                      ),
                    )
                  else
                    Icon(Icons.arrow_drop_down_rounded,
                        size: 22, color: _accentBlue),
                ],
              ),
            ),
          ),
          // Dropdown with search
          if (showEntityDropdown) ...[
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _accentBlue.withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                children: [
                  // Search field
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: TextField(
                      controller: entitySearchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'بحث عن حساب...',
                        prefixIcon: Icon(Icons.search_rounded,
                            size: 18, color: _accentBlue),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                              color: isDark
                                  ? AppColors.darkBorder
                                  : AppColors.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: _accentBlue, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        filled: true,
                        fillColor: isDark
                            ? AppColors.darkSurfaceVariant
                            : AppColors.surfaceVariant.withValues(alpha: 0.3),
                      ),
                      onChanged: onFilterEntities,
                    ),
                  ),
                  // Add new button
                  InkWell(
                    onTap: onAddNewEntity,
                    borderRadius: BorderRadius.circular(0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(
                            top: BorderSide(
                                color: isDark
                                    ? AppColors.darkDivider
                                    : AppColors.divider)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              gradient: _primaryGradient,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.add_rounded,
                                size: 16, color: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            isSale ? 'إضافة عميل جديد' : 'إضافة مورد جديد',
                            style: context.textTheme.bodyMedium?.copyWith(
                              color: _accentBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Entity list
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: filteredEntities.length,
                      separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: isDark
                              ? AppColors.darkDivider
                              : AppColors.divider),
                      itemBuilder: (context, index) {
                        final entity = filteredEntities[index];
                        final isSelected = selectedEntityId == entity['id'] &&
                            selectedEntityType == entity['type'];
                        final isCustomer = entity['type'] == 'customer';
                        final balance =
                            MoneyHelper.readMoney(entity['balance']);
                        final bt =
                            entity['balance_type'] as String? ?? 'credit';

                        return InkWell(
                          onTap: () => onEntitySelected(
                              entity['id'] as int, entity['type'] as String),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            color: isSelected
                                ? _accentBlue.withValues(alpha: 0.06)
                                : null,
                            child: Row(
                              children: [
                                // Avatar circle for entity
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: (isCustomer
                                            ? AppColors.success
                                            : const Color(0xFF3B82F6))
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isCustomer
                                        ? Icons.person_rounded
                                        : Icons.local_shipping_rounded,
                                    size: 16,
                                    color: isCustomer
                                        ? AppColors.success
                                        : const Color(0xFF3B82F6),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    entity['name'] ?? '',
                                    style:
                                        context.textTheme.bodyMedium?.copyWith(
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                                if (balance != 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (bt == 'credit'
                                              ? AppColors.success
                                              : AppColors.error)
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${CurrencyFormatter.format(balance)} ${bt == 'credit' ? 'له' : 'عليه'}',
                                      style:
                                          context.textTheme.bodySmall?.copyWith(
                                        color: bt == 'credit'
                                            ? AppColors.success
                                            : AppColors.error,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                const SizedBox(width: 6),
                                // Type badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (isCustomer
                                            ? AppColors.success
                                            : const Color(0xFF3B82F6))
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    isCustomer ? 'عميل' : 'مورد',
                                    style:
                                        context.textTheme.labelSmall?.copyWith(
                                      color: isCustomer
                                          ? AppColors.success
                                          : const Color(0xFF3B82F6),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (isEntityRequired &&
              selectedEntityId == null &&
              paymentMechanism == 'credit')
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded,
                      size: 12, color: AppColors.error),
                  const SizedBox(width: 4),
                  Text('الحساب مطلوب للفاتورة الآجلة',
                      style: context.textTheme.bodySmall
                          ?.copyWith(color: AppColors.error, fontSize: 11)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Entity avatar ────────────────────────────────────────────────
  Widget _buildEntityAvatar() {
    if (selectedEntityId == null) {
      return Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: (isDark
              ? AppColors.darkSurfaceVariant
              : AppColors.surfaceVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(Icons.person_outline_rounded,
            size: 18, color: AppColors.textHint),
      );
    }
    final isCustomer = selectedEntityType == 'customer';
    final name = selectedEntityName ?? '';
    final initial = name.isNotEmpty ? name[0] : '?';
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isCustomer
              ? [const Color(0xFF22C55E), const Color(0xFF4ADE80)]
              : [const Color(0xFF3B82F6), const Color(0xFF60A5FA)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color:
                (isCustomer ? const Color(0xFF22C55E) : const Color(0xFF3B82F6))
                    .withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(initial,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14)),
      ),
    );
  }
}
