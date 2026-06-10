import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_system.dart';
import '../../../core/services/bluetooth_printer_service.dart';
import '../../../core/utils/account_statement_pdf_generator.dart';
import '../../../core/utils/excel_exporter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/services/voucher_auto_mapping_service.dart';
import '../../screens/settings/bluetooth_printer_settings_screen.dart';

// ═══════════════════════════════════════════════════════════════════════
//  DATA CLASSES
// ═══════════════════════════════════════════════════════════════════════

/// Filter tab definition used by entity detail screens.
class FilterTab {
  final String key;
  final String label;
  const FilterTab({required this.key, required this.label});
}

// ═══════════════════════════════════════════════════════════════════════
//  ABSTRACT BASE STATE
// ═══════════════════════════════════════════════════════════════════════

/// Abstract base state for entity detail screens (Customer, Supplier, Employee).
///
/// Encapsulates shared filtering, printing, exporting, voucher-creation,
/// and UI-building logic so that each concrete screen only implements the
/// data-loading and entity-specific parts.
///
/// Usage:
/// ```dart
/// class _CustomerDetailScreenState
///     extends EntityDetailState<CustomerDetailScreen> { ... }
/// ```
abstract class EntityDetailState<T extends StatefulWidget> extends State<T> {
  // ─── State Variables ──────────────────────────────────────────────

  bool _isLoading = true;
  List<Map<String, dynamic>> _allMovements = [];
  List<Map<String, dynamic>> _filteredMovements = [];

  int _selectedFilterIndex = 0;
  String? _selectedCurrency = 'YER';
  DateTimeRange? _dateRange;
  String _searchQuery = '';

  /// Period filter: 0=daily, 1=monthly, 2=yearly, 3=all
  int _periodFilter = 3;

  bool _sortDescending = false;

  final TextEditingController _searchController = TextEditingController();

  double _totalDebit = 0.0;
  double _totalCredit = 0.0;
  double _netBalance = 0.0;

  List<Map<String, dynamic>> _cashBoxes = [];

  static const List<MapEntry<String, String>> _currencyOptions = [
    MapEntry('YER', 'YER'),
    MapEntry('SAR', 'SAR'),
    MapEntry('USD', 'USD'),
  ];

  // ─── Abstract Methods (must be implemented by subclasses) ──────────

  /// The filter tabs for this entity type.
  List<FilterTab> get filterTabs;

  /// Reload entity data + movements from the database.
  ///
  /// Implementations should set [isLoading] = true at the start,
  /// refresh entity info, load cash boxes, call [loadMovements],
  /// and finally set [isLoading] = false.
  Future<void> loadData();

  /// Load movements data for this entity.
  ///
  /// Implementations should populate [allMovements] with
  /// `Map<String, dynamic>` entries containing at minimum:
  /// `'id'`, `'date'`, `'type'`, `'type_ar'`, `'filter_key'`,
  /// `'icon'`, `'color'`, `'description'`, `'debit'`, `'credit'`,
  /// `'currency'`, `'source'`, `'voucher_type'`, `'created_at'`.
  ///
  /// After populating [allMovements], implementations should
  /// compute running balances and then call [applyFilters].
  Future<void> loadMovements();

  /// Entity name for display in headers and print-outs.
  String get entityName;

  /// Entity phone for display (may be empty).
  String get entityPhone;

  /// Optional subtitle for the header (e.g. job title for employee).
  String get entitySubtitle => '';

  /// Entity type string used by voucher creation
  /// (one of [VoucherAutoMappingService.entityCustomer],
  /// [VoucherAutoMappingService.entitySupplier],
  /// [VoucherAutoMappingService.entityEmployee]).
  String get entityTypeName;

  /// Entity database ID.
  int? get entityId;

  /// The avatar icon for this entity type.
  IconData get entityIcon;

  /// The first letter of the entity name for avatar display.
  String get avatarLetter => entityName.isNotEmpty ? entityName[0] : '?';

  /// Entity label for the voucher dialog's InputDecorator
  /// (e.g. 'العميل', 'المورد', 'الموظف').
  String get entityLabel;

  /// Icon for the entity in the voucher dialog.
  IconData get entityLabelIcon;

  /// Entity type string in Arabic for Excel export
  /// (e.g. 'عميل', 'مورد', 'موظف').
  String get entityTypeAr;

  /// Entity type string for PDF generator
  /// (e.g. 'customer', 'supplier', 'employee').
  String get entityTypePdf;

  /// Whether to show an edit button in the action bar.
  bool get showEditButton => false;

  /// Called when the edit button is pressed.
  void onEditPressed() {}

  /// Extra actions to show in the AppBar (before print/export buttons).
  /// Override in subclasses to add entity-specific AppBar actions
  /// (e.g. edit button for supplier).
  List<Widget> buildExtraAppBarActions() => [];

  // ─── Shared Getters / Setters ──────────────────────────────────────

  bool get isLoading => _isLoading;
  set isLoading(bool v) => setState(() => _isLoading = v);

  List<Map<String, dynamic>> get allMovements => _allMovements;
  set allMovements(List<Map<String, dynamic>> v) => _allMovements = v;

  List<Map<String, dynamic>> get filteredMovements => _filteredMovements;
  set filteredMovements(List<Map<String, dynamic>> v) =>
      _filteredMovements = v;

  int get selectedFilterIndex => _selectedFilterIndex;
  set selectedFilterIndex(int v) => _selectedFilterIndex = v;

  String? get selectedCurrency => _selectedCurrency;
  set selectedCurrency(String? v) => _selectedCurrency = v;

  DateTimeRange? get dateRange => _dateRange;
  set dateRange(DateTimeRange? v) => _dateRange = v;

  String get searchQuery => _searchQuery;
  set searchQuery(String v) => _searchQuery = v;

  int get periodFilter => _periodFilter;
  set periodFilter(int v) => _periodFilter = v;

  bool get sortDescending => _sortDescending;
  set sortDescending(bool v) => _sortDescending = v;

  double get totalDebit => _totalDebit;
  set totalDebit(double v) => _totalDebit = v;

  double get totalCredit => _totalCredit;
  set totalCredit(double v) => _totalCredit = v;

  double get netBalance => _netBalance;
  set netBalance(double v) => _netBalance = v;

  List<Map<String, dynamic>> get cashBoxes => _cashBoxes;
  set cashBoxes(List<Map<String, dynamic>> v) => _cashBoxes = v;

  TextEditingController get searchController => _searchController;
  List<MapEntry<String, String>> get currencyOptions => _currencyOptions;

  // ─── Lifecycle ─────────────────────────────────────────────────────

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ─── Filter Logic ──────────────────────────────────────────────────

  /// Apply all active filters to [allMovements] and update
  /// [filteredMovements], [totalDebit], [totalCredit], [netBalance].
  void applyFilters() {
    var filtered =
        _allMovements.map((m) => Map<String, dynamic>.from(m)).toList();

    // 1. Tab filter
    final filterKey = filterTabs[_selectedFilterIndex].key;
    if (filterKey == 'debit') {
      filtered =
          filtered.where((m) => MoneyHelper.readMoney(m['debit']) > 0).toList();
    } else if (filterKey == 'credit') {
      filtered = filtered
          .where((m) => MoneyHelper.readMoney(m['credit']) > 0)
          .toList();
    } else if (filterKey != 'all') {
      filtered =
          filtered.where((m) => m['filter_key'] == filterKey).toList();
    }

    // 2. Currency filter
    if (_selectedCurrency != null && _selectedCurrency!.isNotEmpty) {
      filtered =
          filtered.where((m) => m['currency'] == _selectedCurrency).toList();
    }

    // 3. Period filter
    if (_periodFilter != 3) {
      final now = DateTime.now();
      filtered = filtered.where((m) {
        final dateStr = m['date'] as String?;
        if (dateStr == null) return true; // Skip entries with missing dates
        try {
          final date = DateTime.parse(dateStr);
          switch (_periodFilter) {
            case 0: // يومي – today
              return date.year == now.year &&
                  date.month == now.month &&
                  date.day == now.day;
            case 1: // شهري – current month
              return date.year == now.year && date.month == now.month;
            case 2: // سنوي – current year
              return date.year == now.year;
            default:
              return true;
          }
        } catch (_) {
          return true;
        }
      }).toList();
    }

    // 4. Date range filter
    if (_dateRange != null) {
      filtered = filtered.where((m) {
        final dateStr = m['date'] as String?;
        if (dateStr == null) return true; // Skip entries with missing dates
        try {
          final date = DateTime.parse(dateStr);
          return !date.isBefore(_dateRange!.start) &&
              date.isBefore(
                  _dateRange!.end.add(const Duration(days: 1)));
        } catch (_) {
          return true;
        }
      }).toList();
    }

    // 5. Search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((m) {
        final desc = (m['description'] as String? ?? '').toLowerCase();
        final typeAr = (m['type_ar'] as String? ?? '').toLowerCase();
        return desc.contains(q) || typeAr.contains(q);
      }).toList();
    }

    // 6. Sort order
    if (_sortDescending) {
      filtered = filtered.reversed.toList();
    }

    // 7. Preserve running balance from full calculation (_allMovements)
    //    instead of recalculating from filtered subset.
    //    The running balance must reflect the true cumulative position at
    //    each point in time, including transactions hidden by filters.
    final allBalances = <String, double>{};
    for (final m in _allMovements) {
      final mId = m['id']?.toString();
      if (mId != null) {
        allBalances[mId] = MoneyHelper.readMoney(m['running_balance']);
      }
    }
    for (final m in filtered) {
      final mId = m['id']?.toString();
      if (mId != null && allBalances.containsKey(mId)) {
        m['running_balance'] = allBalances[mId];
      }
    }

    // 8. Calculate totals from filtered movements
    double totalDebit = 0.0, totalCredit = 0.0;
    for (final m in filtered) {
      totalDebit += MoneyHelper.readMoney(m['debit']);
      totalCredit += MoneyHelper.readMoney(m['credit']);
    }

    // 9. Compute net balance from ALL movements (for the selected
    //    currency), not just filtered ones
    double netBalance = 0.0;
    for (final m in _allMovements) {
      if (_selectedCurrency != null && _selectedCurrency!.isNotEmpty) {
        final mCurrency = m['currency'] as String? ?? 'YER';
        if (mCurrency != _selectedCurrency) continue;
      }
      final debit = MoneyHelper.readMoney(m['debit']);
      final credit = MoneyHelper.readMoney(m['credit']);
      netBalance += credit - debit;
    }

    setState(() {
      _filteredMovements = filtered;
      _totalDebit = totalDebit;
      _totalCredit = totalCredit;
      _netBalance = netBalance;
    });
  }

  // ─── Date Range ────────────────────────────────────────────────────

  Future<void> pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _dateRange,
      locale: const Locale('ar'),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context)
                .colorScheme
                .copyWith(primary: AppColors.primary)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
      applyFilters();
    }
  }

  void clearDateRange() {
    setState(() => _dateRange = null);
    applyFilters();
  }

  // ─── Filter Popup ──────────────────────────────────────────────────

  void showFilterPopup() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.filter_list, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text('تصفية الحركات',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setSheetState(() => _selectedFilterIndex = 0);
                        setState(() => _selectedFilterIndex = 0);
                      },
                      child: Text('الكل',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children:
                      List.generate(filterTabs.length, (index) {
                    final isSelected = _selectedFilterIndex == index;
                    return ChoiceChip(
                      label: Text(filterTabs[index].label),
                      selected: isSelected,
                      onSelected: (_) {
                        Navigator.pop(ctx);
                        setState(() => _selectedFilterIndex = index);
                        applyFilters();
                      },
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                      backgroundColor:
                          Theme.of(context).brightness == Brightness.light
                              ? AppColors.surfaceVariant
                              : AppColors.darkSurfaceVariant,
                      selectedColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                    );
                  }),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── Add Voucher Dialog ────────────────────────────────────────────

  Future<void> showAddVoucherDialog(String voucherType) async {
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    int? selectedCashBoxId;
    String selectedCurrency = _selectedCurrency ?? 'YER';
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(voucherType == 'receipt' ? 'سند قبض' : 'سند صرف'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InputDecorator(
                  decoration: InputDecoration(
                    labelText: entityLabel,
                    prefixIcon: Icon(entityLabelIcon),
                  ),
                  child: Text(entityName),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}'))
                  ],
                  decoration: InputDecoration(
                    labelText: 'المبلغ',
                    prefixIcon: const Icon(Icons.attach_money),
                    suffixText: selectedCurrency,
                  ),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: selectedCurrency,
                  decoration: const InputDecoration(
                    labelText: 'العملة',
                    prefixIcon: Icon(Icons.currency_exchange),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'YER', child: Text('ريال يمني (YER)')),
                    DropdownMenuItem(
                        value: 'SAR', child: Text('ريال سعودي (SAR)')),
                    DropdownMenuItem(
                        value: 'USD', child: Text('دولار أمريكي (USD)')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedCurrency = v);
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int?>(
                  value: selectedCashBoxId,
                  decoration: const InputDecoration(
                    labelText: 'الصندوق',
                    prefixIcon: Icon(Icons.account_balance_wallet),
                  ),
                  items: _cashBoxes
                      .map((cb) => DropdownMenuItem<int?>(
                            value: cb['id'] as int?,
                            child: Text('${cb['name']}'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setDialogState(() => selectedCashBoxId = v);
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: descriptionController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: voucherType == 'receipt'
                        ? 'بيان سند القبض'
                        : 'بيان سند الصرف',
                    prefixIcon: const Icon(Icons.description),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final amount =
                          double.tryParse(amountController.text);
                      if (amount == null || amount <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('يرجى إدخال مبلغ صالح'),
                                backgroundColor: AppColors.error));
                        return;
                      }
                      if (selectedCashBoxId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('يرجى اختيار الصندوق'),
                                backgroundColor: AppColors.error));
                        return;
                      }
                      setDialogState(() => isSaving = true);
                      try {
                        final autoMappingService =
                            locator<VoucherAutoMappingService>();
                        final dateStr = DateTime.now()
                            .toIso8601String()
                            .split('T')
                            .first;
                        await autoMappingService
                            .createReceiptPaymentVoucher(
                          voucherType: voucherType,
                          entityType: entityTypeName,
                          entityId: entityId ?? 0,
                          cashBoxId: selectedCashBoxId,
                          amount: amount,
                          currency: selectedCurrency,
                          date: dateStr,
                          description: descriptionController.text
                                  .trim()
                                  .isEmpty
                              ? '${voucherType == 'receipt' ? 'سند قبض' : 'سند صرف'} - $entityName'
                              : descriptionController.text.trim(),
                        );
                        if (context.mounted) {
                          Navigator.pop(dialogContext);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(voucherType == 'receipt'
                                ? 'تم إنشاء سند القبض بنجاح'
                                : 'تم إنشاء سند الصرف بنجاح'),
                            backgroundColor: AppColors.success,
                          ));
                          loadData();
                        }
                      } catch (e) {
                        if (context.mounted) {
                          final msg = e
                              .toString()
                              .replaceFirst('Exception: ', '');
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(msg.isNotEmpty
                                ? msg
                                : 'حدث خطأ أثناء الحفظ'),
                            backgroundColor: AppColors.error,
                          ));
                        }
                        setDialogState(() => isSaving = false);
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text(voucherType == 'receipt'
                      ? 'إنشاء سند قبض'
                      : 'إنشاء سند صرف'),
            ),
          ],
        ),
      ),
    );
    amountController.dispose();
    descriptionController.dispose();
  }

  // ─── Print / Export ────────────────────────────────────────────────

  void printReport() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('خيارات الطباعة',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.picture_as_pdf,
                      color: AppColors.primary),
                ),
                title: const Text('طباعة PDF',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('إنشاء ملف PDF لكشف الحساب'),
                trailing: const Icon(Icons.arrow_back_ios, size: 16),
                onTap: () {
                  Navigator.pop(ctx);
                  generatePdfStatement();
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: AppColors.accentBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.bluetooth,
                      color: AppColors.accentBlue),
                ),
                title: const Text('طباعة حرارية بلوتوث',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle:
                    const Text('طباعة كشف حساب على طابعة حرارية'),
                trailing: const Icon(Icons.arrow_back_ios, size: 16),
                onTap: () async {
                  Navigator.pop(ctx);
                  await printBluetoothStatement();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> generatePdfStatement() async {
    try {
      await AccountStatementPdfGenerator.printAccountStatement(
        entityName: entityName,
        entityType: entityTypePdf,
        movements: _filteredMovements,
        totalDebit: _totalDebit,
        totalCredit: _totalCredit,
        netBalance: _netBalance,
        balanceLabel: _netBalance > 0
            ? 'له'
            : (_netBalance < 0 ? 'عليه' : 'متساوي'),
        phone: entityPhone.isNotEmpty ? entityPhone : null,
        currency: _selectedCurrency ?? 'YER',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('حدث خطأ أثناء إنشاء كشف الحساب'),
            backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> printBluetoothStatement() async {
    final printerService = BluetoothPrinterService.instance;
    if (!printerService.isConnected) {
      final connected = await printerService.autoConnect();
      if (!connected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                const Text('الطابعة غير متصلة. يرجى الذهاب إلى الإعدادات لتوصيلها'),
            backgroundColor: AppColors.warning,
            action: SnackBarAction(
              label: 'الإعدادات',
              textColor: Colors.white,
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          const BluetoothPrinterSettingsScreen())),
            ),
          ));
        }
        return;
      }
    }
    try {
      await printerService.printCustomerStatement({
        'name': entityName,
        'balance': _netBalance.abs(),
        'balance_type': _netBalance >= 0 ? 'credit' : 'debit',
        'currency': _selectedCurrency ?? 'YER',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تم إرسال كشف الحساب للطابعة الحرارية'),
            backgroundColor: AppColors.success));
      }
    } on PrinterException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.message),
            backgroundColor: AppColors.error));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('حدث خطأ غير متوقع'),
            backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> exportToExcel() async {
    try {
      await ExcelExporter.exportAccountStatementToExcel(
        entityName: entityName,
        entityType: entityTypeAr,
        movements: _filteredMovements,
        totalDebit: _totalDebit,
        totalCredit: _totalCredit,
        netBalance: _netBalance,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('حدث خطأ أثناء التصدير'),
            backgroundColor: AppColors.error));
      }
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────────

  String currencySymbol(String? code) {
    switch (code) {
      case 'SAR':
        return 'ر.س';
      case 'USD':
        return r'$';
      case 'YER':
      default:
        return 'ر.ي';
    }
  }

  // ─── Shared UI Builders ────────────────────────────────────────────

  /// Period filter chip used by all entity detail screens.
  Widget buildPeriodChip(String label, int value) {
    final isSelected = _periodFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() => _periodFilter = value);
        applyFilters();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : (Theme.of(context).brightness == Brightness.light
                  ? AppColors.surfaceVariant
                  : AppColors.darkSurfaceVariant),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: AppColors.primary.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2))
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(left: 4),
                decoration: const BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle),
              ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color:
                    isSelected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Gradient header card showing entity name, type badge, phone, and balance.
  /// Matches the cash box detail screen design exactly.
  Widget buildHeaderCard() {
    final theme = Theme.of(context);
    final isDebit = _netBalance < 0;
    final balanceDisplay = CurrencyFormatter.formatValue(_netBalance.abs());

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            AppColors.primaryGradientStart,
            AppColors.primaryGradientEnd
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: DesignSystem.cardShadow(isLight: false),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Icon(
                  entityIcon,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entityName,
                      style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          entityLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      if (entityPhone.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.phone, size: 12, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(
                          entityPhone,
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                        ),
                      ],
                      if (entitySubtitle.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.work, size: 12, color: Colors.white70),
                        const SizedBox(width: 4),
                        Text(
                          entitySubtitle,
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Balance badge
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Text(
                    '$balanceDisplay ${currencySymbol(_selectedCurrency)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (isDebit ? AppColors.error : AppColors.success)
                          .withOpacity(0.9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isDebit
                          ? 'عليه'
                          : (_netBalance > 0 ? 'له' : 'متساوي'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Period filter row with daily / monthly / yearly / all chips.
  Widget buildPeriodFilterRow() {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      color: isLight ? AppColors.surface : AppColors.darkSurface,
      child: Row(
        children: [
          Icon(Icons.calendar_today_outlined,
              size: 16, color: AppColors.textHint),
          const SizedBox(width: 8),
          buildPeriodChip('اليوم', 0),
          const SizedBox(width: 6),
          buildPeriodChip('هذا الشهر', 1),
          const SizedBox(width: 6),
          buildPeriodChip('هذه السنة', 2),
          const SizedBox(width: 6),
          buildPeriodChip('الكل', 3),
        ],
      ),
    );
  }

  /// Toolbar with search, filter, date range, currency, and sort controls.
  /// Matches the cash box detail screen toolbar design exactly.
  Widget buildToolbar() {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      color: isLight ? AppColors.surface : AppColors.darkSurface,
      child: Row(
        children: [
          // Search field
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _searchController,
                onChanged: (v) {
                  setState(() => _searchQuery = v.trim());
                  applyFilters();
                },
                decoration: InputDecoration(
                  hintText: 'بحث حركة...',
                  hintStyle: TextStyle(fontSize: 13, color: AppColors.textHint),
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                            applyFilters();
                          })
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Filter button — bordered container with dot indicator
          Container(
            height: 40,
            decoration: BoxDecoration(
              border: Border.all(color: _selectedFilterIndex > 0 ? AppColors.primary : AppColors.border),
              borderRadius: BorderRadius.circular(10),
              color: _selectedFilterIndex > 0 ? AppColors.primary.withOpacity(0.08) : null,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: showFilterPopup,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.filter_list, size: 18, color: _selectedFilterIndex > 0 ? AppColors.primary : AppColors.textSecondary),
                      if (_selectedFilterIndex > 0) ...[
                        const SizedBox(width: 4),
                        Container(
                          width: 6, height: 6,
                          decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Date range button — bordered container with conditional styling
          Container(
            height: 40,
            decoration: BoxDecoration(
              border: Border.all(color: _dateRange != null ? AppColors.primary : AppColors.border),
              borderRadius: BorderRadius.circular(10),
              color: _dateRange != null ? AppColors.primary.withOpacity(0.08) : null,
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: _dateRange != null ? clearDateRange : pickDateRange,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _dateRange != null ? Icons.event_busy : Icons.date_range,
                        size: 18,
                        color: _dateRange != null ? AppColors.primary : AppColors.textSecondary,
                      ),
                      if (_dateRange != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          '${_dateRange!.start.day}/${_dateRange!.start.month}',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.primary),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Currency dropdown — bordered container
          Container(
            height: 40,
            padding: const EdgeInsets.only(left: 8, right: 4),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButton<String>(
              value: _selectedCurrency ?? 'YER',
              underline: const SizedBox.shrink(),
              icon: const Icon(Icons.arrow_drop_down, size: 18),
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary),
              items: _currencyOptions
                  .map((e) => DropdownMenuItem<String>(
                        value: e.value,
                        child: Text(e.key, style: const TextStyle(fontSize: 12)),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null && v.isNotEmpty) {
                  _selectedCurrency = v;
                  loadData();
                }
              },
            ),
          ),
          const SizedBox(width: 6),

          // Sort order toggle — icon + text label in bordered container
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () {
                _sortDescending = !_sortDescending;
                applyFilters();
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: _sortDescending ? AppColors.primary : AppColors.border),
                  borderRadius: BorderRadius.circular(10),
                  color: _sortDescending ? AppColors.primary.withOpacity(0.08) : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _sortDescending ? Icons.arrow_downward : Icons.arrow_upward,
                      size: 14,
                      color: _sortDescending ? AppColors.primary : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _sortDescending ? 'تنازلي' : 'تصاعدي',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _sortDescending ? AppColors.primary : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Active filter label chip (shown when a non-"all" tab is selected).
  /// Matches the cash box design with filter label, close button, and movement count.
  Widget buildActiveFilterLabel() {
    if (_selectedFilterIndex == 0) return const SizedBox.shrink();
    final isLight = Theme.of(context).brightness == Brightness.light;
    final theme = Theme.of(context);
    final label = filterTabs[_selectedFilterIndex].label;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      color: isLight ? AppColors.surface : AppColors.darkSurface,
      child: Row(
        children: [
          Text('الفلتر: ', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () { setState(() => _selectedFilterIndex = 0); applyFilters(); },
                  child: Icon(Icons.close, size: 14, color: AppColors.primary),
                ),
              ],
            ),
          ),
          const Spacer(),
          Text('${_filteredMovements.length} حركة', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
        ],
      ),
    );
  }

  /// Action buttons row: receipt voucher, payment voucher, optional edit.
  /// Matches the cash box design using OutlinedButton style.
  Widget buildActionButtons() {
    final isLight = Theme.of(context).brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: isLight ? AppColors.surface : AppColors.darkSurface,
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => showAddVoucherDialog('receipt'),
              icon: const Icon(Icons.assignment_turned_in, size: 16),
              label: const Text('سند قبض', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.success,
                side: const BorderSide(color: AppColors.success),
                padding: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => showAddVoucherDialog('payment'),
              icon: const Icon(Icons.assignment_return, size: 16),
              label: const Text('سند صرف', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                padding: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          if (showEditButton) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onEditPressed,
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('تعديل', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Bottom summary bar showing total credit, debit, and net balance.
  /// Matches the cash box design with colored containers for each column.
  Widget buildBottomBar() {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final balanceLabel = _netBalance >= 0 ? 'له' : 'عليه';
    final balanceColor = _netBalance >= 0 ? AppColors.success : AppColors.error;

    return Container(
      decoration: BoxDecoration(
        color: isLight ? AppColors.surface : AppColors.darkSurface,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), offset: const Offset(0, -2), blurRadius: 8)],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // له (Credit)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.success.withOpacity(0.25), width: 1),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('له', style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700, color: AppColors.success, fontSize: 12,
                      )),
                      const SizedBox(height: 4),
                      Text(
                        '${_totalCredit.toStringAsFixed(2)} ${currencySymbol(_selectedCurrency)}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900, color: AppColors.success, fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // عليه (Debit)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.error.withOpacity(0.25), width: 1),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('عليه', style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700, color: AppColors.error, fontSize: 12,
                      )),
                      const SizedBox(height: 4),
                      Text(
                        '${_totalDebit.toStringAsFixed(2)} ${currencySymbol(_selectedCurrency)}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900, color: AppColors.error, fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // الرصيد (Net Balance)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: balanceColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: balanceColor.withOpacity(0.25), width: 1),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(balanceLabel, style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700, color: balanceColor, fontSize: 12,
                      )),
                      const SizedBox(height: 4),
                      Text(
                        '${_netBalance.abs().toStringAsFixed(2)} ${currencySymbol(_selectedCurrency)}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w900, color: balanceColor, fontSize: 13,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Movements list with loading, empty state, and refresh support.
  /// Matches the cash box design with proper padding and scroll physics.
  Widget buildMovementsList() {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_filteredMovements.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(entityIcon, size: 64, color: AppColors.textHint.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text('لا توجد حركات', style: theme.textTheme.titleMedium?.copyWith(color: AppColors.textHint)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: loadData,
      color: AppColors.primary,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 80, top: 4),
        itemCount: _filteredMovements.length,
        itemBuilder: (ctx, i) => _MovementCard(
          movement: _filteredMovements[i],
          runningBalance: _computeRunningBalance(i),
          isLight: isLight,
        ),
      ),
    );
  }

  /// Compute running balance up to (and including) index [upToIndex]
  /// in the [filteredMovements] list.
  double _computeRunningBalance(int upToIndex) {
    // Use the pre-computed running_balance from the full set if available.
    // This preserves accuracy even when filters hide some transactions.
    final m = _filteredMovements[upToIndex];
    final rb = m['running_balance'];
    if (rb != null) {
      return MoneyHelper.readMoney(rb);
    }
    // Fallback: compute from filtered subset.
    double balance = 0;
    for (int i = 0; i <= upToIndex; i++) {
      balance += MoneyHelper.readMoney(_filteredMovements[i]['credit']) -
          MoneyHelper.readMoney(_filteredMovements[i]['debit']);
    }
    return balance;
  }

  /// Build the standard AppBar actions (print + export buttons).
  List<Widget> buildAppBarActions() {
    return [
      ...buildExtraAppBarActions(),
      // Print button
      Container(
        margin: const EdgeInsets.only(left: 4, top: 8, bottom: 8),
        child: Material(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: printReport,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.print_rounded,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text('طباعة',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                ],
              ),
            ),
          ),
        ),
      ),
      // Export button
      Container(
        margin: const EdgeInsets.only(left: 4, right: 8, top: 8, bottom: 8),
        child: Material(
          color: AppColors.success.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: exportToExcel,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sim_card_download_outlined,
                      size: 18, color: AppColors.success),
                  const SizedBox(width: 4),
                  Text('تصدير',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success)),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// Convenience: build the full body column that most entity detail
  /// screens share (header + period filter + toolbar + filter label +
  /// action buttons + movement list).
  /// Matches the cash box layout structure exactly.
  Widget buildBody() {
    return Column(
      children: [
        buildHeaderCard(),
        buildPeriodFilterRow(),
        buildToolbar(),
        buildActiveFilterLabel(),
        buildActionButtons(),
        Expanded(child: buildMovementsList()),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  MOVEMENT CARD WIDGET
// ═══════════════════════════════════════════════════════════════════════

/// Shared movement card widget used by entity detail screens.
class _MovementCard extends StatelessWidget {
  final Map<String, dynamic> movement;
  final double runningBalance;
  final bool isLight;

  const _MovementCard({
    required this.movement,
    required this.runningBalance,
    required this.isLight,
  });

  @override
  Widget build(BuildContext context) {
    final icon = movement['icon'] as IconData? ?? Icons.description;
    final color = movement['color'] as Color? ?? AppColors.textSecondary;
    final description =
        movement['description'] as String? ?? '';
    final dateStr = movement['date'] as String? ?? '';
    final typeAr = movement['type_ar'] as String? ?? '';
    final currency = movement['currency'] as String? ?? 'YER';
    final debit = MoneyHelper.readMoney(movement['debit']);
    final credit = MoneyHelper.readMoney(movement['credit']);
    final isDebit = debit > 0;
    final amount = isDebit ? debit : credit;

    final curSymbol = _currencySymbol(currency);

    // Format date for display
    String displayDate;
    try {
      final dt = DateTime.parse(dateStr);
      displayDate =
          '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      displayDate = dateStr;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLight ? AppColors.border : AppColors.darkBorder,
          width: 0.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // Subclasses can override or wrap for tap handling
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              // Description + date
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(description,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      '$displayDate  •  $typeAr',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              // Amount + running balance
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyFormatter.formatValue(amount),
                    style: TextStyle(
                      color:
                          isDebit ? AppColors.error : AppColors.success,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$curSymbol ${runningBalance >= 0 ? 'له' : 'عليه'} ${CurrencyFormatter.formatValue(runningBalance.abs())}',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _currencySymbol(String? code) {
    switch (code) {
      case 'SAR':
        return 'ر.س';
      case 'USD':
        return r'$';
      case 'YER':
      default:
        return 'ر.ي';
    }
  }
}
