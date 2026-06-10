import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../data/datasources/repositories/account_repository.dart';
import '../../../../data/datasources/repositories/customer_repository.dart';
import '../../../../data/datasources/repositories/supplier_repository.dart';
import '../../../../data/datasources/repositories/reference_data_repository.dart';
import '../../../../data/datasources/services/cash_box_service.dart';
import 'report_helpers.dart';

// ═══════════════════════════════════════════════════════════════════
//  Report Filters Section – date presets, custom dates, entity
//  dropdowns (currency, account, customer, supplier, etc.)
// ═══════════════════════════════════════════════════════════════════

class ReportFiltersSection extends StatelessWidget {
  final String? selectedReportKey;
  final DatePreset selectedDatePreset;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final String selectedCurrency;
  final int? selectedAccountId;
  final int? selectedCustomerId;
  final int? selectedSupplierId;
  final int? selectedCashBoxId;
  final int? selectedWarehouseId;
  final int? selectedCategoryId;
  final String selectedAccountType;

  final ValueChanged<DatePreset> onDatePresetChanged;
  final ValueChanged<DateTime?> onDateFromChanged;
  final ValueChanged<DateTime?> onDateToChanged;
  final ValueChanged<String> onCurrencyChanged;
  final ValueChanged<int?> onAccountChanged;
  final ValueChanged<int?> onCustomerChanged;
  final ValueChanged<int?> onSupplierChanged;
  final ValueChanged<int?> onCashBoxChanged;
  final ValueChanged<int?> onWarehouseChanged;
  final ValueChanged<int?> onCategoryChanged;
  final ValueChanged<String> onAccountTypeChanged;

  const ReportFiltersSection({
    super.key,
    required this.selectedReportKey,
    required this.selectedDatePreset,
    this.dateFrom,
    this.dateTo,
    required this.selectedCurrency,
    this.selectedAccountId,
    this.selectedCustomerId,
    this.selectedSupplierId,
    this.selectedCashBoxId,
    this.selectedWarehouseId,
    this.selectedCategoryId,
    required this.selectedAccountType,
    required this.onDatePresetChanged,
    required this.onDateFromChanged,
    required this.onDateToChanged,
    required this.onCurrencyChanged,
    required this.onAccountChanged,
    required this.onCustomerChanged,
    required this.onSupplierChanged,
    required this.onCashBoxChanged,
    required this.onWarehouseChanged,
    required this.onCategoryChanged,
    required this.onAccountTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: isDark ? AppColors.darkBorder : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick date presets
          if (needsDateFilter(selectedReportKey)) ...[
            _DatePresetsRow(
              selectedPreset: selectedDatePreset,
              isDark: isDark,
              onPresetSelected: onDatePresetChanged,
            ),
            const SizedBox(height: 8),
            if (selectedDatePreset == DatePreset.custom)
              _CustomDateRow(
                dateFrom: dateFrom,
                dateTo: dateTo,
                isDark: isDark,
                onDateFromChanged: onDateFromChanged,
                onDateToChanged: onDateToChanged,
              ),
          ],
          // Currency and entity filters
          if (needsCurrencyFilter(selectedReportKey) ||
              needsAccountFilter(selectedReportKey) ||
              needsCustomerFilter(selectedReportKey) ||
              needsSupplierFilter(selectedReportKey) ||
              needsCashBoxFilter(selectedReportKey) ||
              needsWarehouseFilter(selectedReportKey) ||
              needsCategoryFilter(selectedReportKey) ||
              needsAccountTypeFilter(selectedReportKey)) ...[
            const SizedBox(height: 8),
            _EntityFiltersRow(
              selectedReportKey: selectedReportKey,
              selectedCurrency: selectedCurrency,
              selectedAccountId: selectedAccountId,
              selectedCustomerId: selectedCustomerId,
              selectedSupplierId: selectedSupplierId,
              selectedCashBoxId: selectedCashBoxId,
              selectedWarehouseId: selectedWarehouseId,
              selectedCategoryId: selectedCategoryId,
              selectedAccountType: selectedAccountType,
              onCurrencyChanged: onCurrencyChanged,
              onAccountChanged: onAccountChanged,
              onCustomerChanged: onCustomerChanged,
              onSupplierChanged: onSupplierChanged,
              onCashBoxChanged: onCashBoxChanged,
              onWarehouseChanged: onWarehouseChanged,
              onCategoryChanged: onCategoryChanged,
              onAccountTypeChanged: onAccountTypeChanged,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Date Presets Row ───────────────────────────────────────────

class _DatePresetsRow extends StatelessWidget {
  final DatePreset selectedPreset;
  final bool isDark;
  final ValueChanged<DatePreset> onPresetSelected;

  const _DatePresetsRow({
    required this.selectedPreset,
    required this.isDark,
    required this.onPresetSelected,
  });

  @override
  Widget build(BuildContext context) {
    final presets = [
      (DatePreset.today, 'اليوم'),
      (DatePreset.thisWeek, 'هذا الأسبوع'),
      (DatePreset.thisMonth, 'هذا الشهر'),
      (DatePreset.thisQuarter, 'هذا الربع'),
      (DatePreset.thisYear, 'هذا العام'),
      (DatePreset.custom, 'مخصص'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: presets.map((p) {
          final isSelected = selectedPreset == p.$1;
          return Padding(
            padding: const EdgeInsets.only(left: 6),
            child: ChoiceChip(
              label: Text(p.$2),
              selected: isSelected,
              selectedColor: AppColors.primary.withValues(alpha: 0.2),
              backgroundColor:
                  isDark ? AppColors.darkSurface : AppColors.surface,
              side: BorderSide(
                color: isSelected
                    ? AppColors.primary
                    : (isDark ? AppColors.darkBorder : AppColors.border),
              ),
              labelStyle: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? AppColors.primary
                    : (isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.textSecondary),
              ),
              visualDensity: VisualDensity.compact,
              onSelected: (_) => onPresetSelected(p.$1),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Custom Date Row ────────────────────────────────────────────

class _CustomDateRow extends StatelessWidget {
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final bool isDark;
  final ValueChanged<DateTime?> onDateFromChanged;
  final ValueChanged<DateTime?> onDateToChanged;

  const _CustomDateRow({
    this.dateFrom,
    this.dateTo,
    required this.isDark,
    required this.onDateFromChanged,
    required this.onDateToChanged,
  });

  Future<void> _pickDate(BuildContext context, DateTime? initial,
      ValueChanged<DateTime?> onChanged) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: _FilterChip(
            icon: Icons.calendar_today,
            label: dateFrom != null
                ? fmtDate(dateFrom!.toIso8601String())
                : 'من تاريخ',
            onTap: () => _pickDate(context, dateFrom, onDateFromChanged),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _FilterChip(
            icon: Icons.calendar_today,
            label: dateTo != null
                ? fmtDate(dateTo!.toIso8601String())
                : 'إلى تاريخ',
            onTap: () => _pickDate(context, dateTo, onDateToChanged),
          ),
        ),
        if (dateFrom != null || dateTo != null) ...[
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.clear, size: 18, color: AppColors.error),
            tooltip: 'مسح التاريخ',
            onPressed: () {
              onDateFromChanged(null);
              onDateToChanged(null);
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ],
    );
  }
}

// ── Entity Filters Row ─────────────────────────────────────────

class _EntityFiltersRow extends StatelessWidget {
  final String? selectedReportKey;
  final String selectedCurrency;
  final int? selectedAccountId;
  final int? selectedCustomerId;
  final int? selectedSupplierId;
  final int? selectedCashBoxId;
  final int? selectedWarehouseId;
  final int? selectedCategoryId;
  final String selectedAccountType;

  final ValueChanged<String> onCurrencyChanged;
  final ValueChanged<int?> onAccountChanged;
  final ValueChanged<int?> onCustomerChanged;
  final ValueChanged<int?> onSupplierChanged;
  final ValueChanged<int?> onCashBoxChanged;
  final ValueChanged<int?> onWarehouseChanged;
  final ValueChanged<int?> onCategoryChanged;
  final ValueChanged<String> onAccountTypeChanged;

  const _EntityFiltersRow({
    required this.selectedReportKey,
    required this.selectedCurrency,
    this.selectedAccountId,
    this.selectedCustomerId,
    this.selectedSupplierId,
    this.selectedCashBoxId,
    this.selectedWarehouseId,
    this.selectedCategoryId,
    required this.selectedAccountType,
    required this.onCurrencyChanged,
    required this.onAccountChanged,
    required this.onCustomerChanged,
    required this.onSupplierChanged,
    required this.onCashBoxChanged,
    required this.onWarehouseChanged,
    required this.onCategoryChanged,
    required this.onAccountTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (needsCurrencyFilter(selectedReportKey))
          SizedBox(
              width: 100,
              child: _CurrencyDropdown(
                value: selectedCurrency,
                onChanged: onCurrencyChanged,
              )),
        if (needsAccountFilter(selectedReportKey))
          SizedBox(
              width: 180,
              child: _AccountDropdown(
                value: selectedAccountId,
                onChanged: onAccountChanged,
              )),
        if (needsCustomerFilter(selectedReportKey))
          SizedBox(
              width: 180,
              child: _CustomerDropdown(
                value: selectedCustomerId,
                onChanged: onCustomerChanged,
              )),
        if (needsSupplierFilter(selectedReportKey))
          SizedBox(
              width: 180,
              child: _SupplierDropdown(
                value: selectedSupplierId,
                onChanged: onSupplierChanged,
              )),
        if (needsCashBoxFilter(selectedReportKey))
          SizedBox(
              width: 180,
              child: _CashBoxDropdown(
                value: selectedCashBoxId,
                onChanged: onCashBoxChanged,
              )),
        if (needsWarehouseFilter(selectedReportKey))
          SizedBox(
              width: 140,
              child: _WarehouseDropdown(
                value: selectedWarehouseId,
                onChanged: onWarehouseChanged,
              )),
        if (needsCategoryFilter(selectedReportKey))
          SizedBox(
              width: 140,
              child: _CategoryDropdown(
                value: selectedCategoryId,
                onChanged: onCategoryChanged,
              )),
        if (needsAccountTypeFilter(selectedReportKey))
          SizedBox(
              width: 140,
              child: _AccountTypeDropdown(
                value: selectedAccountType,
                onChanged: onAccountTypeChanged,
              )),
      ],
    );
  }
}

// ── Filter Chip ────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _FilterChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dropdown Widgets ───────────────────────────────────────────

class _CurrencyDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _CurrencyDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          icon: const Icon(Icons.arrow_drop_down, size: 16),
          style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: AppColors.primary,
              fontWeight: FontWeight.w600),
          items: currencyOptions
              .map((c) => DropdownMenuItem(
                  value: c,
                  child: Text(c, style: const TextStyle(fontSize: 11))))
              .toList(),
          onChanged: (val) {
            if (val != null) onChanged(val);
          },
        ),
      ),
    );
  }
}

class _AccountDropdown extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;

  const _AccountDropdown({this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final theme = Theme.of(context);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: locator<AccountRepository>().getAllAccounts(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        return _FilterDropdown<int>(
          value: value,
          items: snap.data!
              .map((a) => DropdownMenuItem<int>(
                    value: a['id'] as int,
                    child: Text('${a['name_ar']} (${a['currency']})',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: onChanged,
          hint: 'اختر الحساب',
        );
      },
    );
  }
}

class _CustomerDropdown extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;

  const _CustomerDropdown({this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: locator<CustomerRepository>().getAllCustomers(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        return _FilterDropdown<int>(
          value: value,
          items: snap.data!
              .map((c) => DropdownMenuItem<int>(
                    value: c['id'] as int,
                    child: Text(c['name'] as String? ?? '',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: onChanged,
          hint: 'اختر العميل',
        );
      },
    );
  }
}

class _SupplierDropdown extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;

  const _SupplierDropdown({this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: locator<SupplierRepository>().getAllSuppliers(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        return _FilterDropdown<int>(
          value: value,
          items: snap.data!
              .map((s) => DropdownMenuItem<int>(
                    value: s['id'] as int,
                    child: Text(s['name'] as String? ?? '',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: onChanged,
          hint: 'اختر المورد',
        );
      },
    );
  }
}

class _CashBoxDropdown extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;

  const _CashBoxDropdown({this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: locator<CashBoxService>().getAllCashBoxes(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        return _FilterDropdown<int>(
          value: value,
          items: snap.data!
              .map((cb) => DropdownMenuItem<int>(
                    value: cb['id'] as int,
                    child: Text('${cb['name']}',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: onChanged,
          hint: 'اختر الصندوق',
        );
      },
    );
  }
}

class _WarehouseDropdown extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;

  const _WarehouseDropdown({this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: locator<ReferenceDataRepository>().getAllWarehouses(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final items = [
          DropdownMenuItem<int>(
              value: null,
              child: Text('كل المخازن', style: TextStyle(fontSize: 12)))
        ];
        items.addAll(snap.data!.map((w) => DropdownMenuItem<int>(
              value: w['id'] as int,
              child: Text(w['name'] as String? ?? '',
                  style: const TextStyle(fontSize: 12)),
            )));
        return _FilterDropdown<int>(
          value: value,
          items: items,
          onChanged: onChanged,
          hint: 'المخزن',
        );
      },
    );
  }
}

class _CategoryDropdown extends StatelessWidget {
  final int? value;
  final ValueChanged<int?> onChanged;

  const _CategoryDropdown({this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: locator<ReferenceDataRepository>().getAllCategories(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final items = [
          DropdownMenuItem<int>(
              value: null,
              child: Text('كل الفئات', style: TextStyle(fontSize: 12)))
        ];
        items.addAll(snap.data!.map((c) => DropdownMenuItem<int>(
              value: c['id'] as int,
              child: Text(c['name'] as String? ?? '',
                  style: const TextStyle(fontSize: 12)),
            )));
        return _FilterDropdown<int>(
          value: value,
          items: items,
          onChanged: onChanged,
          hint: 'الفئة',
        );
      },
    );
  }
}

class _AccountTypeDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _AccountTypeDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return _FilterDropdown<String>(
      value: value,
      items: accountTypes
          .map((e) => DropdownMenuItem<String>(
                value: e.key,
                child: Text(e.key, style: const TextStyle(fontSize: 12)),
              ))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
      hint: 'نوع الحساب',
    );
  }
}

// ── Generic Filter Dropdown ────────────────────────────────────

class _FilterDropdown<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String hint;

  const _FilterDropdown({
    this.value,
    required this.items,
    required this.onChanged,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isDense: true,
          isExpanded: true,
          icon: const Icon(Icons.arrow_drop_down, size: 16),
          hint: Text(hint,
              style: TextStyle(
                  fontSize: 11,
                  color: AppColors.primary.withValues(alpha: 0.6))),
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
