import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_system.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/account_statement_pdf_generator.dart';
import '../../../core/utils/excel_exporter.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/services/cash_box_service.dart';
import '../../../data/datasources/services/journal_service.dart';
import '../../../data/models/cash_box_model.dart';

/// Cash Box Detail / Ledger Screen — Modern Professional Design
/// Displays all financial movements for a specific cash box with
/// filtering, search, statistics, and voucher creation capabilities.
class CashBoxDetailScreen extends StatefulWidget {
  final CashBox cashBox;
  final String? initialCurrency; // pre-selected currency from list screen

  const CashBoxDetailScreen({super.key, required this.cashBox, this.initialCurrency});

  @override
  State<CashBoxDetailScreen> createState() => _CashBoxDetailScreenState();
}

class _CashBoxDetailScreenState extends State<CashBoxDetailScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _allMovements = [];
  List<Map<String, dynamic>> _filteredMovements = [];

  // Filter state
  int _selectedFilterIndex = 0;
  String? _selectedCurrency;
  DateTimeRange? _dateRange;
  String _searchQuery = '';

  // Period filter state: 0=daily, 1=monthly, 2=yearly, 3=all
  int _periodFilter = 3; // default = الجميع

  // Sort order: false=ascending (oldest first), true=descending (newest first)
  bool _sortDescending = false;

  // Search controller
  final TextEditingController _searchController = TextEditingController();

  // Statistics
  double _totalDebit = 0.0;
  double _totalCredit = 0.0;
  double _netBalance = 0.0;

  // Cash box data (refreshable)
  CashBox? _freshCashBox;

  static const List<_FilterTab> _filterTabs = [
    _FilterTab(key: 'all', label: 'جميع الحركات والفواتير'),
    _FilterTab(key: 'opening_balance', label: 'رصيد افتتاحي'),
    _FilterTab(key: 'debit', label: 'عليه'),
    _FilterTab(key: 'credit', label: 'له'),
    _FilterTab(key: 'receipt_voucher', label: 'سند قبض'),
    _FilterTab(key: 'payment_voucher', label: 'سند صرف'),
    _FilterTab(key: 'incoming_transfer', label: 'تحويل وارد'),
    _FilterTab(key: 'outgoing_transfer', label: 'تحويل صادر'),
    _FilterTab(key: 'exchange', label: 'صرافة'),
    _FilterTab(key: 'sales', label: 'مبيعات'),
    _FilterTab(key: 'purchases', label: 'مشتريات'),
    _FilterTab(key: 'returns', label: 'مرتجع'),
  ];

  static const List<MapEntry<String, String>> _currencyOptions = [
    MapEntry('YER', 'YER'),
    MapEntry('SAR', 'SAR'),
    MapEntry('USD', 'USD'),
  ];

  @override
  void initState() {
    super.initState();
    _freshCashBox = widget.cashBox;
    _selectedCurrency = widget.initialCurrency ?? 'YER';
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Refresh cash box data (non-fatal if this fails)
    try {
      final cashBoxMap = await locator<CashBoxService>().getCashBoxById(widget.cashBox.id!);
      if (cashBoxMap != null) {
        _freshCashBox = CashBox.fromMap(cashBoxMap);
      }
    } catch (e) {
      debugPrint('CashBoxDetailScreen._loadData [refreshCashBox]: $e');
    }

    // Load all movements (non-fatal — partial data is better than nothing)
    try {
      await _loadMovements();
    } catch (e) {
      debugPrint('CashBoxDetailScreen._loadData [loadMovements]: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء تحميل بعض البيانات'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMovements() async {
    final cashBoxId = widget.cashBox.id!;
    final movements = await locator<CashBoxService>().getCashBoxMovements(
      cashBoxId,
      currency: _selectedCurrency,
    );

    // Calculate running balance per currency
    final currencyRunBal = <String, double>{};
    for (final m in movements) {
      final currency = m['currency'] as String? ?? 'YER';
      final debit = MoneyHelper.readMoney(m['debit']);
      final credit = MoneyHelper.readMoney(m['credit']);
      currencyRunBal[currency] = (currencyRunBal[currency] ?? 0.0) + credit - debit;
      m['running_balance'] = currencyRunBal[currency];
    }

    _allMovements = movements;
    _applyFilters();
  }

  void _applyFilters() {
    // Deep copy maps to avoid mutating _allMovements when setting running_balance
    var filtered = _allMovements.map((m) => Map<String, dynamic>.from(m)).toList();

    // Apply tab filter
    final filterKey = _filterTabs[_selectedFilterIndex].key;
    if (filterKey == 'debit') {
      filtered = filtered.where((m) => (MoneyHelper.readMoney(m['debit'])) > 0).toList();
    } else if (filterKey == 'credit') {
      filtered = filtered.where((m) => (MoneyHelper.readMoney(m['credit'])) > 0).toList();
    } else if (filterKey != 'all') {
      filtered = filtered.where((m) => m['filter_key'] == filterKey).toList();
    }

    // Apply currency filter (mandatory — no 'All' option)
    if (_selectedCurrency != null && _selectedCurrency!.isNotEmpty) {
      filtered = filtered.where((m) => m['currency'] == _selectedCurrency).toList();
    }

    // Apply period filter
    if (_periodFilter != 3) {
      final now = DateTime.now();
      filtered = filtered.where((m) {
        final dateStr = m['date'] as String;
        try {
          final date = DateTime.parse(dateStr);
          switch (_periodFilter) {
            case 0: // يومي - today
              return date.year == now.year && date.month == now.month && date.day == now.day;
            case 1: // شهري - current month
              return date.year == now.year && date.month == now.month;
            case 2: // سنوي - current year
              return date.year == now.year;
            default:
              return true;
          }
        } catch (_) { return true; }
      }).toList();
    }

    // Apply date range filter
    if (_dateRange != null) {
      filtered = filtered.where((m) {
        final dateStr = m['date'] as String;
        try {
          final date = DateTime.parse(dateStr);
          return !date.isBefore(_dateRange!.start) && !date.isAfter(_dateRange!.end.add(const Duration(days: 1)));
        } catch (e) {
          debugPrint('CashBoxDetailScreen._applyFilters: $e');
          return true;
        }
      }).toList();
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered.where((m) {
        final desc = (m['description'] as String? ?? '').toLowerCase();
        final typeAr = (m['type_ar'] as String? ?? '').toLowerCase();
        return desc.contains(q) || typeAr.contains(q);
      }).toList();
    }

    // Apply sort order
    if (_sortDescending) {
      filtered = filtered.reversed.toList();
    }

    // Recalculate running balance for filtered movements
    final currencyRunBal = <String, double>{};
    for (final m in filtered) {
      final currency = m['currency'] as String? ?? 'YER';
      final debit = MoneyHelper.readMoney(m['debit']);
      final credit = MoneyHelper.readMoney(m['credit']);
      currencyRunBal[currency] = (currencyRunBal[currency] ?? 0.0) + credit - debit;
      m['running_balance'] = currencyRunBal[currency];
    }

    // Calculate totals from filtered movements
    double totalDebit = 0.0, totalCredit = 0.0;
    for (final m in filtered) {
      totalDebit += MoneyHelper.readMoney(m['debit']);
      totalCredit += MoneyHelper.readMoney(m['credit']);
    }

    // Compute net balance from ALL movements (for the selected currency), not just filtered
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

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _dateRange,
      locale: const Locale('ar'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.primary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
      _applyFilters();
    }
  }

  void _clearDateRange() {
    setState(() => _dateRange = null);
    _applyFilters();
  }

  // ── Currency symbol helper ──────────────────────────────────────
  String _currencySymbol(String? code) {
    switch (code) {
      case 'SAR': return 'ر.س';
      case 'USD': return r'$';
      case 'YER': default: return 'ر.ي';
    }
  }

  // ── Show filter popup ──────────────────────────────────────────
  void _showFilterPopup() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
                    Text('تصفية الحركات', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setSheetState(() => _selectedFilterIndex = 0);
                        setState(() => _selectedFilterIndex = 0);
                      },
                      child: Text('الكل', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // All filters as chips
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: List.generate(_filterTabs.length, (index) {
                    final isSelected = _selectedFilterIndex == index;
                    return ChoiceChip(
                      label: Text(_filterTabs[index].label),
                      selected: isSelected,
                      onSelected: (_) {
                        Navigator.pop(ctx);
                        setState(() => _selectedFilterIndex = index);
                        _applyFilters();
                      },
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? Colors.white : AppColors.textSecondary,
                      ),
                      backgroundColor: Theme.of(context).brightness == Brightness.light ? AppColors.surfaceVariant : AppColors.darkSurfaceVariant,
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

  // ── Add Voucher Dialog ──────────────────────────────────────────
  Future<void> _showAddVoucherDialog(String voucherType) async {
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    String selectedCurrency = _selectedCurrency ?? _freshCashBox?.currency ?? 'YER';
    bool isSaving = false;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(voucherType == 'receipt' ? 'سند قبض' : 'سند صرف'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Cash box name (read-only)
                    InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'الصندوق',
                        prefixIcon: Icon(
                          _freshCashBox?.isBank ?? false
                              ? Icons.account_balance
                              : Icons.account_balance_wallet,
                        ),
                      ),
                      child: Text(_freshCashBox?.name ?? ''),
                    ),
                    const SizedBox(height: 14),

                    // Amount
                    TextFormField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                      decoration: InputDecoration(
                        labelText: 'المبلغ',
                        prefixIcon: const Icon(Icons.attach_money),
                        suffixText: selectedCurrency,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Currency
                    DropdownButtonFormField<String>(
                      value: selectedCurrency,
                      decoration: const InputDecoration(
                        labelText: 'العملة',
                        prefixIcon: Icon(Icons.currency_exchange),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'YER', child: Text('ريال يمني (YER)')),
                        DropdownMenuItem(value: 'SAR', child: Text('ريال سعودي (SAR)')),
                        DropdownMenuItem(value: 'USD', child: Text('دولار أمريكي (USD)')),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          setDialogState(() => selectedCurrency = v);
                        }
                      },
                    ),
                    const SizedBox(height: 14),

                    // Description
                    TextFormField(
                      controller: descriptionController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: voucherType == 'receipt' ? 'بيان سند القبض' : 'بيان سند الصرف',
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
                          final amount = double.tryParse(amountController.text);
                          if (amount == null || amount <= 0) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('يرجى إدخال مبلغ صالح'), backgroundColor: AppColors.error),
                            );
                            return;
                          }
                          setDialogState(() => isSaving = true);

                          final now = DateTime.now();
                          final cashBoxService = locator<CashBoxService>();
                          final voucherNumber = await cashBoxService.getNextVoucherNumber(voucherType);

                          // Resolve the Cash & Banks account for the selected currency
                          final codeOffset = selectedCurrency == 'SAR' ? 1 : (selectedCurrency == 'USD' ? 2 : 0);
                          final cashBanksCode = (1100 + codeOffset).toString();
                          final journalService = locator<JournalService>();
                          final cashBanksAccount = await journalService.getAccountByCodeAndCurrency(
                            cashBanksCode, selectedCurrency,
                          );
                          final cashAccountId = cashBanksAccount?['id'] as int?;

                          // Resolve the Opening Balance Equity account as contra account
                          final obCode = (2901 + codeOffset).toString();
                          final obAccount = await journalService.getAccountByCodeAndCurrency(
                            obCode, selectedCurrency,
                          );
                          final obAccountId = obAccount?['id'] as int?;

                          if (cashAccountId == null) {
                            setDialogState(() => isSaving = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('لم يتم العثور على حساب الصناديق للعملة المحددة'), backgroundColor: AppColors.error),
                              );
                            }
                            return;
                          }

                          final voucherMap = {
                            'voucher_number': voucherNumber,
                            'voucher_type': voucherType,
                            'date': now.toIso8601String(),
                            'description': descriptionController.text.trim().isEmpty
                                ? '${voucherType == 'receipt' ? 'سند قبض' : 'سند صرف'} - ${_freshCashBox?.name}'
                                : descriptionController.text.trim(),
                            'currency': selectedCurrency,
                            'total_amount': amount,
                            'cash_box_id': widget.cashBox.id,
                            'is_posted': 1,
                            'created_at': now.toIso8601String(),
                            'updated_at': now.toIso8601String(),
                          };

                          List<Map<String, dynamic>> items = [];

                          if (voucherType == 'receipt') {
                            // Receipt: Debit Cash & Banks (cash in), Credit contra account
                            items.add({
                              'account_id': cashAccountId,
                              'debit': amount,
                              'credit': 0.0,
                              'description': 'سند قبض - ${_freshCashBox?.name}',
                            });
                            if (obAccountId != null) {
                              items.add({
                                'account_id': obAccountId,
                                'debit': 0.0,
                                'credit': amount,
                                'description': 'سند قبض - ${_freshCashBox?.name}',
                              });
                            }
                          } else {
                            // Payment: Debit contra account, Credit Cash & Banks (cash out)
                            if (obAccountId != null) {
                              items.add({
                                'account_id': obAccountId,
                                'debit': amount,
                                'credit': 0.0,
                                'description': 'سند صرف - ${_freshCashBox?.name}',
                              });
                            }
                            items.add({
                              'account_id': cashAccountId,
                              'debit': 0.0,
                              'credit': amount,
                              'description': 'سند صرف - ${_freshCashBox?.name}',
                            });
                          }

                          if (items.isNotEmpty) {
                            await cashBoxService.insertVoucher(voucherMap, items);
                          }

                          if (context.mounted) {
                            Navigator.pop(dialogContext);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(voucherType == 'receipt' ? 'تم إنشاء سند القبض بنجاح' : 'تم إنشاء سند الصرف بنجاح'),
                                backgroundColor: AppColors.success,
                              ),
                            );
                            _loadData();
                          }
                        },
                  child: isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(voucherType == 'receipt' ? 'إنشاء سند قبض' : 'إنشاء سند صرف'),
                ),
              ],
            );
          },
        );
      },
    );
    amountController.dispose();
    descriptionController.dispose();
  }

  // ── Print Report ─────────────────────────────────────────────
  void _printReport() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('خيارات الطباعة', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.picture_as_pdf, color: AppColors.primary),
                ),
                title: const Text('طباعة PDF', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('إنشاء ملف PDF لكشف حساب الصندوق'),
                trailing: const Icon(Icons.arrow_back_ios, size: 16),
                onTap: () { Navigator.pop(ctx); _generatePdfStatement(); },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _generatePdfStatement() async {
    final cashBox = _freshCashBox ?? widget.cashBox;
    try {
      await AccountStatementPdfGenerator.printAccountStatement(
        entityName: cashBox.name,
        entityType: 'cash_box',
        movements: _filteredMovements,
        totalDebit: _totalDebit,
        totalCredit: _totalCredit,
        netBalance: _netBalance,
        balanceLabel: _netBalance > 0 ? 'له' : (_netBalance < 0 ? 'عليه' : 'متساوي'),
        currency: _selectedCurrency ?? cashBox.currency,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء إنشاء كشف الحساب'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _exportToExcel() async {
    final cashBox = _freshCashBox ?? widget.cashBox;
    try {
      await ExcelExporter.exportAccountStatementToExcel(
        entityName: cashBox.name,
        entityType: 'صندوق',
        movements: _filteredMovements,
        totalDebit: _totalDebit,
        totalCredit: _totalCredit,
        netBalance: _netBalance,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء التصدير'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final cashBox = _freshCashBox ?? widget.cashBox;
    final isDebit = cashBox.balanceType == 'debit';
    final balanceDisplay = CurrencyFormatter.formatValue(cashBox.balance.abs());

    return Scaffold(
      appBar: AppBar(
        actions: [
          // Modern print button
          Container(
            margin: const EdgeInsets.only(left: 4, top: 8, bottom: 8),
            child: Material(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: _printReport,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.print_rounded, size: 18, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text('طباعة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Modern export button
          Container(
            margin: const EdgeInsets.only(left: 4, right: 8, top: 8, bottom: 8),
            child: Material(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: _exportToExcel,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sim_card_download_outlined, size: 18, color: AppColors.success),
                      const SizedBox(width: 4),
                      Text('تصدير', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Header Card ────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryGradientStart, AppColors.primaryGradientEnd],
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
                        cashBox.isBank ? Icons.account_balance : Icons.account_balance_wallet,
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
                        Text(
                          cashBox.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                                cashBox.typeAr,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            if (cashBox.isBank && cashBox.bankName != null && cashBox.bankName!.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.business, size: 12, color: Colors.white70),
                              const SizedBox(width: 4),
                              Text(
                                cashBox.bankName!,
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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '$balanceDisplay ${_currencySymbol(cashBox.currency)}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isDebit ? AppColors.error : AppColors.success).withOpacity(0.9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isDebit ? 'عليه' : (cashBox.balance > 0 ? 'له' : 'متساوي'),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Period Filter RadioButtons ──────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            color: isLight ? AppColors.surface : AppColors.darkSurface,
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textHint),
                const SizedBox(width: 8),
                _buildPeriodChip('اليوم', 0),
                const SizedBox(width: 6),
                _buildPeriodChip('هذا الشهر', 1),
                const SizedBox(width: 6),
                _buildPeriodChip('هذه السنة', 2),
                const SizedBox(width: 6),
                _buildPeriodChip('الكل', 3),
              ],
            ),
          ),

          // ── Toolbar: Search + Filters ──────────────────────────
          Container(
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
                      onChanged: (v) { setState(() => _searchQuery = v.trim()); _applyFilters(); },
                      decoration: InputDecoration(
                        hintText: 'بحث حركة...',
                        hintStyle: TextStyle(fontSize: 13, color: AppColors.textHint),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); _applyFilters(); })
                            : null,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Filter button
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
                      onTap: _showFilterPopup,
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

                // Date range button
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
                      onTap: _dateRange != null ? _clearDateRange : _pickDateRange,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_dateRange != null ? Icons.event_busy : Icons.date_range, size: 18,
                              color: _dateRange != null ? AppColors.primary : AppColors.textSecondary),
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

                // Currency dropdown
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
                    items: _currencyOptions.map((e) => DropdownMenuItem<String>(value: e.value, child: Text(e.key, style: const TextStyle(fontSize: 12)))).toList(),
                    onChanged: (v) { if (v != null && v.isNotEmpty) { setState(() => _selectedCurrency = v); _loadData(); } },
                  ),
                ),
                const SizedBox(width: 6),
                // Sort order toggle
                Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    border: Border.all(color: _sortDescending ? AppColors.primary : AppColors.border),
                    borderRadius: BorderRadius.circular(10),
                    color: _sortDescending ? AppColors.primary.withOpacity(0.08) : null,
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () {
                        setState(() => _sortDescending = !_sortDescending);
                        _applyFilters();
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Tooltip(
                        message: _sortDescending ? 'ترتيب تنازلي' : 'ترتيب تصاعدي',
                        child: Icon(
                          _sortDescending ? Icons.arrow_downward : Icons.arrow_upward,
                          size: 16,
                          color: _sortDescending ? AppColors.primary : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Active filter label ────────────────────────────────
          if (_selectedFilterIndex > 0)
            Container(
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
                        Text(_filterTabs[_selectedFilterIndex].label, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: () { setState(() => _selectedFilterIndex = 0); _applyFilters(); },
                          child: Icon(Icons.close, size: 14, color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text('${_filteredMovements.length} حركة', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
                ],
              ),
            ),

          // ── Action buttons row ──────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: isLight ? AppColors.surface : AppColors.darkSurface,
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showAddVoucherDialog('receipt'),
                    icon: const Icon(Icons.assignment_turned_in, size: 16),
                    label: const Text('سند قبض', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success, side: const BorderSide(color: AppColors.success),
                      padding: const EdgeInsets.symmetric(vertical: 6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showAddVoucherDialog('payment'),
                    icon: const Icon(Icons.assignment_return, size: 16),
                    label: const Text('سند صرف', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Movements List ─────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredMovements.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.account_balance_wallet, size: 64, color: AppColors.textHint.withOpacity(0.3)),
                            const SizedBox(height: 16),
                            Text('لا توجد حركات', style: theme.textTheme.titleMedium?.copyWith(color: AppColors.textHint)),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        color: AppColors.primary,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 80, top: 4),
                          itemCount: _filteredMovements.length,
                          itemBuilder: (context, index) {
                          final m = _filteredMovements[index];
                          return _MovementCard(
                            movement: m,
                            currencySymbol: _currencySymbol(m['currency']),
                            isLight: isLight,
                          );
                        },
                        )
                      ),
          ),
        ],
      ),

      // ── Bottom Balance Bar — Three separate fields: له / عليه / الرصيد ─
      bottomNavigationBar: Container(
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
                // ── له (Credit) ──────────────────────────────
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
                          '${_totalCredit.toStringAsFixed(2)} ${_currencySymbol(_selectedCurrency)}',
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

                // ── عليه (Debit) ─────────────────────────────
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
                          '${_totalDebit.toStringAsFixed(2)} ${_currencySymbol(_selectedCurrency)}',
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

                // ── الرصيد (Net Balance) — direction by color ─
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _netBalance >= 0
                            ? [AppColors.success.withOpacity(0.15), AppColors.success.withOpacity(0.05)]
                            : [AppColors.error.withOpacity(0.15), AppColors.error.withOpacity(0.05)],
                        begin: Alignment.centerRight,
                        end: Alignment.centerLeft,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _netBalance >= 0 ? AppColors.success.withOpacity(0.4) : AppColors.error.withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _netBalance >= 0 ? Icons.trending_up : Icons.trending_down,
                              size: 13,
                              color: _netBalance >= 0 ? AppColors.success : AppColors.error,
                            ),
                            const SizedBox(width: 4),
                            Text('الرصيد', style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: _netBalance >= 0 ? AppColors.success : AppColors.error,
                              fontSize: 12,
                            )),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_netBalance.abs().toStringAsFixed(2)} ${_currencySymbol(_selectedCurrency)}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: _netBalance >= 0 ? AppColors.success : AppColors.error,
                            fontSize: 13,
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
      ),
    );
  }

  // ── Period filter chip builder ───────────────────────────────
  Widget _buildPeriodChip(String label, int value) {
    final isSelected = _periodFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() => _periodFilter = value);
        _applyFilters();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : (Theme.of(context).brightness == Brightness.light ? AppColors.surfaceVariant : AppColors.darkSurfaceVariant),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected ? [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 2))] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected)
              Container(
                width: 8, height: 8,
                margin: const EdgeInsets.only(left: 4),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  FILTER TAB MODEL
// ═══════════════════════════════════════════════════════════════════
class _FilterTab {
  final String key;
  final String label;
  const _FilterTab({required this.key, required this.label});
}

// ═══════════════════════════════════════════════════════════════════
//  MOVEMENT CARD — Professional Design (matches customer _MovementCard)
// ═══════════════════════════════════════════════════════════════════
class _MovementCard extends StatelessWidget {
  final Map<String, dynamic> movement;
  final String currencySymbol;
  final bool isLight;

  const _MovementCard({required this.movement, required this.currencySymbol, required this.isLight});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = movement['icon'] as IconData;
    final color = movement['color'] as Color;
    final typeAr = movement['type_ar'] as String;
    final description = movement['description'] as String;
    final debit = MoneyHelper.readMoney(movement['debit']);
    final credit = MoneyHelper.readMoney(movement['credit']);
    final runningBalance = MoneyHelper.readMoney(movement['running_balance']);
    final dateStr = movement['date'] as String;

    // Format date
    String formattedDate;
    try {
      final date = DateTime.parse(dateStr);
      formattedDate = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (e) {
      debugPrint('CashBoxDetailScreen._MovementCard: $e');
      formattedDate = dateStr;
    }

    final balanceColor = runningBalance >= 0 ? AppColors.success : AppColors.error;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: isLight ? AppColors.surface : AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isLight ? AppColors.border.withOpacity(0.5) : AppColors.darkBorder.withOpacity(0.5), width: 0.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(isLight ? 0.03 : 0.15), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            // Icon
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),

            // Description + date + type
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(description, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(formattedDate, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text(typeAr, style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600, fontSize: 10)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 6),

            // Amount + running balance
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (debit > 0)
                  Text('${debit.toStringAsFixed(2)} $currencySymbol', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.error, fontWeight: FontWeight.w700))
                else if (credit > 0)
                  Text('${credit.toStringAsFixed(2)} $currencySymbol', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.success, fontWeight: FontWeight.w700))
                else
                  Text('0.00 $currencySymbol', style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textHint)),
                const SizedBox(height: 2),
                Text(
                  '${runningBalance.abs().toStringAsFixed(2)}',
                  style: theme.textTheme.labelSmall?.copyWith(color: balanceColor, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
