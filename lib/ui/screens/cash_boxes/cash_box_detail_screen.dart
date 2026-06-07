import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_system.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/services/cash_box_service.dart';
import '../../../data/datasources/services/journal_service.dart';
import '../../../data/models/cash_box_model.dart';

/// Cash Box Detail / Ledger Screen
/// Displays all financial movements for a specific cash box with
/// filtering, statistics, and voucher creation capabilities.
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
      // Keep using the original cashBox data
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

    // Calculate running balance from movements (opening balance is now included as a movement)
    // No need to derive opening balance separately.
    double runningBalance = 0.0;
    double totalDebit = 0.0;
    double totalCredit = 0.0;

    for (final m in filtered) {
      final debit = MoneyHelper.readMoney(m['debit']);
      final credit = MoneyHelper.readMoney(m['credit']);
      runningBalance += credit - debit; // positive = له (credit), negative = عليه (debit)
      totalDebit += debit;
      totalCredit += credit;
      m['running_balance'] = runningBalance;
    }

    setState(() {
      _filteredMovements = filtered;
      _totalDebit = totalDebit;
      _totalCredit = totalCredit;
      _netBalance = runningBalance;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final cashBox = _freshCashBox ?? widget.cashBox;
    final isDebit = cashBox.balanceType == 'debit';
    final balanceDisplay = cashBox.balance.abs().toStringAsFixed(2);
    // ignore: unused_local_variable
    final balanceColor = isDebit ? AppColors.error : (cashBox.balance > 0 ? AppColors.success : AppColors.textSecondary);

    return Scaffold(
      appBar: AppBar(
        title: Text(cashBox.name),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white.withOpacity(0.2),
                        child: Icon(
                          cashBox.isBank ? Icons.account_balance : Icons.account_balance_wallet,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
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
                                const SizedBox(width: 8),
                                if (cashBox.isBank && cashBox.bankName != null && cashBox.bankName!.isNotEmpty) ...[
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
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$balanceDisplay ${_currencySymbol(cashBox.currency)}',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDebit ? AppColors.error.withOpacity(0.9) : AppColors.success.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isDebit ? 'عليه' : (cashBox.balance > 0 ? 'له' : 'متساوي'),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Action Buttons Row ────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isLight ? AppColors.surface : AppColors.darkSurface,
            child: Row(
              children: [
                // سند قبض (Receipt Voucher)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showAddVoucherDialog('receipt'),
                    icon: const Icon(Icons.assignment_turned_in, size: 18),
                    label: const Text('سند قبض'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.success,
                      side: const BorderSide(color: AppColors.success),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // سند صرف (Payment Voucher)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showAddVoucherDialog('payment'),
                    icon: const Icon(Icons.assignment_return, size: 18),
                    label: const Text('سند صرف'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Filter Tabs (horizontal scrollable) ────────────────
          Container(
            height: 44,
            color: isLight ? AppColors.surface : AppColors.darkSurface,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              itemCount: _filterTabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final isSelected = _selectedFilterIndex == index;
                return ChoiceChip(
                  label: Text(_filterTabs[index].label),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() => _selectedFilterIndex = index);
                    _applyFilters();
                  },
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                  ),
                  backgroundColor: isLight ? AppColors.surfaceVariant : AppColors.darkSurfaceVariant,
                  selectedColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                );
              },
            ),
          ),

          // ── Date & Currency Filters ────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isLight ? AppColors.surface : AppColors.darkSurface,
            child: Row(
              children: [
                // Date range picker
                Expanded(
                  child: InkWell(
                    onTap: _pickDateRange,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.date_range, size: 18, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _dateRange != null
                                  ? '${_dateRange!.start.day}/${_dateRange!.start.month} - ${_dateRange!.end.day}/${_dateRange!.end.month}'
                                  : 'الفترة',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _dateRange != null ? AppColors.primary : AppColors.textHint,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_dateRange != null)
                            GestureDetector(
                              onTap: _clearDateRange,
                              child: const Icon(Icons.close, size: 16, color: AppColors.error),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Currency dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButton<String>(
                    value: _selectedCurrency ?? 'YER',
                    underline: const SizedBox.shrink(),
                    icon: const Icon(Icons.arrow_drop_down, size: 20),
                    style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
                    items: _currencyOptions.map((e) {
                      return DropdownMenuItem<String>(
                        value: e.value,
                        child: Text(e.key),
                      );
                    }).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _selectedCurrency = v);
                        _loadData(); // Reload movements with new currency filter
                      }
                    },
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
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 80, top: 4),
                        itemCount: _filteredMovements.length,
                        itemBuilder: (context, index) {
                          final m = _filteredMovements[index];
                          return _MovementCard(movement: m, currencySymbol: _currencySymbol(m['currency']));
                        },
                      ),
          ),
        ],
      ),

      // ── Bottom Statistics Bar ──────────────────────────────────
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isLight ? AppColors.surface : AppColors.darkSurface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              offset: const Offset(0, -2),
              blurRadius: 8,
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                // له (credit)
                Expanded(
                  child: _StatItem(
                    label: 'له',
                    value: _totalCredit.toStringAsFixed(2),
                    color: AppColors.success,
                  ),
                ),
                Container(width: 1, height: 32, color: AppColors.divider),
                // عليه (debit)
                Expanded(
                  child: _StatItem(
                    label: 'عليه',
                    value: _totalDebit.toStringAsFixed(2),
                    color: AppColors.error,
                  ),
                ),
                Container(width: 1, height: 32, color: AppColors.divider),
                // الرصيد (net) with له/عليه label
                Expanded(
                  child: _StatItem(
                    label: _netBalance >= 0 ? 'له' : 'عليه',
                    value: _netBalance.abs().toStringAsFixed(2),
                    color: _netBalance >= 0 ? AppColors.success : AppColors.error,
                  ),
                ),
              ],
            ),
          ),
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
//  MOVEMENT CARD
// ═══════════════════════════════════════════════════════════════════
class _MovementCard extends StatelessWidget {
  final Map<String, dynamic> movement;
  final String currencySymbol;

  const _MovementCard({required this.movement, required this.currencySymbol});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isLight ? AppColors.divider : AppColors.darkBorder, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
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

            // Description + date + type
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(formattedDate, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          typeAr,
                          style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Debit / Credit + Running balance
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (debit > 0)
                  Text(
                    '${debit.toStringAsFixed(2)} $currencySymbol',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else if (credit > 0)
                  Text(
                    '${credit.toStringAsFixed(2)} $currencySymbol',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  Text(
                    '0.00 $currencySymbol',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textHint,
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  '${runningBalance.abs().toStringAsFixed(2)} $currencySymbol',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: balanceColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  STAT ITEM
// ═══════════════════════════════════════════════════════════════════
class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatItem({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
      ],
    );
  }
}
