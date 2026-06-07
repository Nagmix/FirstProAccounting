import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/account_statement_pdf_generator.dart';
import '../../../core/utils/excel_exporter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/services/bluetooth_printer_service.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/supplier_repository.dart';
import '../../../data/datasources/services/cash_box_service.dart';
import '../../../data/datasources/services/voucher_auto_mapping_service.dart';
import '../../../data/models/supplier_model.dart';
import '../settings/bluetooth_printer_settings_screen.dart';

/// Supplier Detail / Ledger Screen
///
/// Displays a supplier's full financial history with filter tabs,
/// running balance, and quick actions for adding vouchers.
class SupplierDetailScreen extends StatefulWidget {
  final Supplier supplier;

  const SupplierDetailScreen({super.key, required this.supplier});

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _allMovements = [];
  List<Map<String, dynamic>> _filteredMovements = [];
  bool _isLoading = true;
  String _selectedCurrency = 'YER';
  DateTime? _startDate;
  DateTime? _endDate;

  // Cash boxes for voucher dialog
  List<Map<String, dynamic>> _cashBoxes = [];

  // Refreshable supplier data
  Supplier? _freshSupplier;

  // Filter tab definitions
  static const _tabs = [
    Tab(text: 'الكل'),
    Tab(text: 'عليه'),
    Tab(text: 'له'),
    Tab(text: 'سند صرف'),
    Tab(text: 'سند قبض'),
    Tab(text: 'قيد عام'),
    Tab(text: 'حوالة صادرة'),
    Tab(text: 'حوالة وارده'),
    Tab(text: 'مبيعات'),
    Tab(text: 'مشتريات'),
    Tab(text: 'مرتجع'),
    Tab(text: 'قيد متعدد'),
  ];

  @override
  void initState() {
    super.initState();
    _freshSupplier = widget.supplier;
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      _applyFilters();
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // Refresh supplier data
    final supplierMap = await locator<SupplierRepository>().getSupplierById(widget.supplier.id!);
    if (supplierMap != null) {
      _freshSupplier = Supplier.fromMap(supplierMap);
    }

    // Load cash boxes for voucher dialog
    _cashBoxes = await locator<CashBoxService>().getAllCashBoxes();

    // Load movements
    final movements = await locator<SupplierRepository>().getSupplierMovements(widget.supplier.id!);

    // ── Add Opening Balance as first movement ──
    // Query the transactions table for opening balance entries linked to this supplier
    final supplier = _freshSupplier ?? widget.supplier;
    final obTransactions = await locator<SupplierRepository>().getSupplierOpeningBalanceTransactions(widget.supplier.id!);

    for (final ob in obTransactions) {
      final debit = MoneyHelper.readMoney(ob['debit']);
      final credit = MoneyHelper.readMoney(ob['credit']);
      final dateStr = ob['date'] as String? ?? ob['created_at'] as String? ?? DateTime.now().toIso8601String();
      final description = ob['description'] as String? ?? 'رصيد افتتاحي';
      final obCurrency = ob['account_currency'] as String? ?? supplier.currency ?? 'YER';

      movements.insert(0, {
        ...Map<String, dynamic>.from(ob),
        '_source': 'opening_balance',
        '_sort_date': dateStr,
        'type': 'opening_balance',
        'type_ar': 'رصيد افتتاحي',
        'description': description,
        'debit': debit,
        'credit': credit,
        'currency': obCurrency,
        'voucher_type': null,
        'is_return': 0,
      });
    }

    setState(() {
      _allMovements = movements;
      _isLoading = false;
    });
    _applyFilters();
  }

  Future<void> _loadMovements() async {
    setState(() => _isLoading = true);
    final movements = await locator<SupplierRepository>().getSupplierMovements(widget.supplier.id!);

    // ── Add Opening Balance as first movement ──
    final supplier = _freshSupplier ?? widget.supplier;
    final obTransactions = await locator<SupplierRepository>().getSupplierOpeningBalanceTransactions(widget.supplier.id!);

    for (final ob in obTransactions) {
      final debit = MoneyHelper.readMoney(ob['debit']);
      final credit = MoneyHelper.readMoney(ob['credit']);
      final dateStr = ob['date'] as String? ?? ob['created_at'] as String? ?? DateTime.now().toIso8601String();
      final description = ob['description'] as String? ?? 'رصيد افتتاحي';
      final obCurrency = ob['account_currency'] as String? ?? supplier.currency ?? 'YER';

      movements.insert(0, {
        ...Map<String, dynamic>.from(ob),
        '_source': 'opening_balance',
        '_sort_date': dateStr,
        'type': 'opening_balance',
        'type_ar': 'رصيد افتتاحي',
        'description': description,
        'debit': debit,
        'credit': credit,
        'currency': obCurrency,
        'voucher_type': null,
        'is_return': 0,
      });
    }

    setState(() {
      _allMovements = movements;
      _isLoading = false;
    });
    _applyFilters();
  }

  void _applyFilters() {
    final tabIndex = _tabController.index;
    List<Map<String, dynamic>> result = List.from(_allMovements);

    // Tab filter
    switch (tabIndex) {
      case 0: // الكل - all movements
        break;
      case 1: // عليه (debit)
        result = result.where((m) => _getMovementDirection(m) == 'debit').toList();
        break;
      case 2: // له (credit)
        result = result.where((m) => _getMovementDirection(m) == 'credit').toList();
        break;
      case 3: // سند صرف (payment voucher)
        result = result.where((m) =>
            m['_source'] == 'voucher' && m['voucher_type'] == 'payment').toList();
        break;
      case 4: // سند قبض (receipt voucher)
        result = result.where((m) =>
            m['_source'] == 'voucher' && m['voucher_type'] == 'receipt').toList();
        break;
      case 5: // قيد عام (settlement/general)
        result = result.where((m) =>
            m['_source'] == 'voucher' && m['voucher_type'] == 'settlement').toList();
        break;
      case 6: // حوالة صادرة
        result = result.where((m) =>
            m['_source'] == 'voucher' && m['voucher_type'] == 'outgoing_transfer').toList();
        break;
      case 7: // حوالة وارده
        result = result.where((m) =>
            m['_source'] == 'voucher' && m['voucher_type'] == 'incoming_transfer').toList();
        break;
      case 8: // مبيعات فقط
        result = result.where((m) =>
            m['_source'] == 'invoice' && m['type'] == 'sale').toList();
        break;
      case 9: // مشتريات فقط
        result = result.where((m) =>
            m['_source'] == 'invoice' && m['type'] == 'purchase').toList();
        break;
      case 10: // مرتجع
        result = result.where((m) =>
            m['_source'] == 'invoice' &&
            (m['type'] == 'sale_return' || m['type'] == 'purchase_return' || m['is_return'] == 1)).toList();
        break;
      case 11: // قيد متعدد (compound)
        result = result.where((m) =>
            m['_source'] == 'voucher' && m['voucher_type'] == 'compound').toList();
        break;
    }

    // Currency filter (always apply since there is no "ALL" option)
    result = result.where((m) {
      final mCurrency = m['currency'] as String? ?? 'YER';
      return mCurrency == _selectedCurrency;
    }).toList();

    // Date filter
    if (_startDate != null) {
      result = result.where((m) {
        final dateStr = m['_sort_date'] as String? ?? '';
        if (dateStr.isEmpty) return true;
        try {
          final date = DateTime.parse(dateStr);
          return !date.isBefore(_startDate!);
        } catch (e) {
          debugPrint('SupplierDetailScreen._applyFilters: $e');
          return true;
        }
      }).toList();
    }
    if (_endDate != null) {
      result = result.where((m) {
        final dateStr = m['_sort_date'] as String? ?? '';
        if (dateStr.isEmpty) return true;
        try {
          final date = DateTime.parse(dateStr);
          return !date.isAfter(_endDate!);
        } catch (e) {
          debugPrint('SupplierDetailScreen._applyFilters: $e');
          return true;
        }
      }).toList();
    }

    setState(() {
      _filteredMovements = result;
    });
  }

  /// Determine the direction of a movement: 'debit' (عليه) or 'credit' (له).
  String _getMovementDirection(Map<String, dynamic> movement) {
    final source = movement['_source'] as String? ?? '';

    if (source == 'opening_balance') {
      // Opening balance: debit means عليه, credit means له
      final debit = MoneyHelper.readMoney(movement['debit']);
      final credit = MoneyHelper.readMoney(movement['credit']);
      return debit > credit ? 'debit' : 'credit';
    }

    if (source == 'invoice') {
      final type = movement['type'] as String? ?? '';
      final isReturn = (movement['is_return'] as num?)?.toInt() == 1;
      // Purchase invoice → we owe the supplier → debit (عليه)
      // Sale to supplier → supplier owes us → credit (له)
      // Returns flip the direction
      if (type == 'purchase' || type == 'purchase_return') {
        return isReturn || type == 'purchase_return' ? 'credit' : 'debit';
      } else {
        return isReturn || type == 'sale_return' ? 'debit' : 'credit';
      }
    }

    if (source == 'voucher') {
      final vType = movement['voucher_type'] as String? ?? '';
      // Payment voucher (سند صرف) → we pay the supplier → credit (له)
      // Receipt voucher (سند قبض) → supplier pays us → debit (عليه)
      switch (vType) {
        case 'payment':
          return 'credit';
        case 'receipt':
          return 'debit';
        default:
          return 'credit';
      }
    }

    return 'credit';
  }

  /// Computes net position for the supplier from all movements.
  /// The stored supplier.balance already includes all changes, so we should NOT
  /// add it again on top of movements (that would double-count).
  /// Instead, we compute net position purely from movements.
  double _computeNetPosition() {
    double creditTotal = 0;
    double debitTotal = 0;

    for (final m in _allMovements) {
      final direction = _getMovementDirection(m);
      final amount = _getMovementAmount(m);
      if (direction == 'credit') {
        creditTotal += amount;
      } else {
        debitTotal += amount;
      }
    }

    return creditTotal - debitTotal;
  }

  double _getMovementAmount(Map<String, dynamic> movement) {
    final source = movement['_source'] as String? ?? '';
    if (source == 'opening_balance') {
      final debit = MoneyHelper.readMoney(movement['debit']);
      final credit = MoneyHelper.readMoney(movement['credit']);
      return debit > credit ? debit : credit;
    }
    if (source == 'invoice') {
      return MoneyHelper.readMoney(movement['total']);
    }
    if (source == 'voucher') {
      return MoneyHelper.readMoney(movement['total_amount']);
    }
    return 0.0;
  }

  /// Compute running balance from all movements + opening balance.
  List<double> _computeRunningBalances() {
    final netPosition = _computeNetPosition();
    // Build running balance from bottom (earliest) to top (latest)
    final reversed = _filteredMovements.reversed.toList();
    final runningBalances = <double>[];
    double running = netPosition;

    for (int i = 0; i < reversed.length; i++) {
      runningBalances.add(running);
      final m = reversed[i];
      final direction = _getMovementDirection(m);
      final amount = _getMovementAmount(m);
      // Subtract the current amount since we're going backwards
      if (direction == 'credit') {
        running -= amount;
      } else {
        running += amount;
      }
    }

    // Reverse to match original order
    final result = runningBalances.reversed.toList();
    return result;
  }

  // ── Opening balance (separate from movements) ────────────────
  double get _openingBalance {
    return widget.supplier.balance;
  }

  String get _openingBalanceLabel {
    return widget.supplier.balanceType == 'credit' ? 'له' : 'عليه';
  }

  // ── Totals for bottom statistics (movements only, no opening balance) ──
  double get _totalCredit {
    double total = 0;
    for (final m in _allMovements) {
      if (_getMovementDirection(m) == 'credit') {
        total += _getMovementAmount(m);
      }
    }
    return total;
  }

  double get _totalDebit {
    double total = 0;
    for (final m in _allMovements) {
      if (_getMovementDirection(m) == 'debit') {
        total += _getMovementAmount(m);
      }
    }
    return total;
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
      _applyFilters();
    }
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() => _endDate = picked);
      _applyFilters();
    }
  }

  void _clearDateFilters() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
    _applyFilters();
  }

  // ── Inline Voucher Dialog (same as customer) ──────────────────
  Future<void> _showAddVoucherDialog(String voucherType) async {
    final supplier = _freshSupplier ?? widget.supplier;
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    int? selectedCashBoxId;
    String selectedCurrency = supplier.currency;
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
                    // Supplier name (read-only)
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'المورد',
                        prefixIcon: Icon(Icons.local_shipping),
                      ),
                      child: Text(supplier.name),
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

                    // Cash Box
                    DropdownButtonFormField<int?>(
                      value: selectedCashBoxId,
                      decoration: const InputDecoration(
                        labelText: 'الصندوق',
                        prefixIcon: Icon(Icons.account_balance_wallet),
                      ),
                      items: _cashBoxes.map((cb) {
                        return DropdownMenuItem<int?>(
                          value: cb['id'] as int?,
                          child: Text('${cb['name']}'),
                        );
                      }).toList(),
                      onChanged: (v) {
                        setDialogState(() => selectedCashBoxId = v);
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
                          if (selectedCashBoxId == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('يرجى اختيار الصندوق'), backgroundColor: AppColors.error),
                            );
                            return;
                          }
                          setDialogState(() => isSaving = true);

                          try {
                            final autoMappingService = locator<VoucherAutoMappingService>();
                            final now = DateTime.now();
                            final dateStr = now.toIso8601String().split('T').first;

                            await autoMappingService.createReceiptPaymentVoucher(
                              voucherType: voucherType,
                              entityType: VoucherAutoMappingService.entitySupplier,
                              entityId: supplier.id ?? 0,
                              cashBoxId: selectedCashBoxId,
                              amount: amount,
                              currency: selectedCurrency,
                              date: dateStr,
                              description: descriptionController.text.trim().isEmpty
                                  ? '${voucherType == 'receipt' ? 'سند قبض' : 'سند صرف'} - ${supplier.name}'
                                  : descriptionController.text.trim(),
                            );

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
                          } catch (e) {
                            if (context.mounted) {
                              final msg = e.toString().replaceFirst('Exception: ', '');
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(msg.isNotEmpty ? msg : 'حدث خطأ أثناء الحفظ'),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                            }
                            setDialogState(() => isSaving = false);
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

  // ── Print / Export ────────────────────────────────────────────
  void _printReport() {
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
              Text('خيارات الطباعة', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.picture_as_pdf, color: AppColors.primary),
                ),
                title: const Text('طباعة PDF', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('إنشاء ملف PDF لكشف الحساب'),
                trailing: const Icon(Icons.arrow_back_ios, size: 16),
                onTap: () {
                  Navigator.pop(ctx);
                  _generatePdfStatement();
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accentBlue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bluetooth, color: AppColors.accentBlue),
                ),
                title: const Text('طباعة حرارية بلوتوث', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('طباعة كشف حساب على طابعة حرارية'),
                trailing: const Icon(Icons.arrow_back_ios, size: 16),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _printBluetoothStatement();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Generate PDF account statement for the supplier.
  Future<void> _generatePdfStatement() async {
    final supplier = _freshSupplier ?? widget.supplier;
    try {
      // Convert supplier movements to the format expected by the PDF generator
      final movements = _filteredMovements.map((m) {
        final source = m['_source'] as String? ?? '';
        double debit = 0.0;
        double credit = 0.0;
        String typeAr = '';
        String dateStr = '';
        String description = '';

        if (source == 'invoice') {
          final type = m['type'] as String? ?? '';
          final isReturn = (m['is_return'] as num?)?.toInt() == 1;
          final total = MoneyHelper.readMoney(m['total']);
          dateStr = m['created_at'] as String? ?? '';
          description = _getInvoiceTypeAr(type, isReturn);
          typeAr = description;

          if (type == 'purchase' && !isReturn) {
            debit = total;
          } else if (type == 'sale' && !isReturn) {
            credit = total;
          } else if (isReturn) {
            if (type == 'purchase') credit = total;
            else debit = total;
          } else {
            debit = total;
          }
        } else if (source == 'opening_balance') {
          debit = MoneyHelper.readMoney(m['debit']);
          credit = MoneyHelper.readMoney(m['credit']);
          dateStr = m['_sort_date'] as String? ?? m['date'] as String? ?? m['created_at'] as String? ?? '';
          description = m['description'] as String? ?? 'رصيد افتتاحي';
          typeAr = 'رصيد افتتاحي';
        } else if (source == 'voucher') {
          final vType = m['voucher_type'] as String? ?? '';
          final totalAmount = MoneyHelper.readMoney(m['total_amount']);
          dateStr = m['date'] as String? ?? m['created_at'] as String? ?? '';
          description = m['description'] as String? ?? _getVoucherTypeAr(vType);
          typeAr = _getVoucherTypeAr(vType);

          switch (vType) {
            case 'payment': credit = totalAmount; break;
            case 'receipt': debit = totalAmount; break;
            default: credit = totalAmount;
          }
        }

        return {
          'date': dateStr,
          'type_ar': typeAr,
          'description': description,
          'debit': debit,
          'credit': credit,
        };
      }).toList();

      await AccountStatementPdfGenerator.printAccountStatement(
        entityName: supplier.name,
        entityType: 'supplier',
        movements: movements,
        totalDebit: _totalDebit,
        totalCredit: _totalCredit,
        netBalance: _computeNetPosition(),
        balanceLabel: Supplier.getDynamicBalanceLabel(_computeNetPosition(), supplier.balanceType),
        phone: supplier.phone,
        currency: supplier.currency,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء إنشاء كشف الحساب'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  /// Print supplier statement via Bluetooth thermal printer.
  Future<void> _printBluetoothStatement() async {
    final printerService = BluetoothPrinterService.instance;
    final supplier = _freshSupplier ?? widget.supplier;

    if (!printerService.isConnected) {
      final connected = await printerService.autoConnect();
      if (!connected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('الطابعة غير متصلة. يرجى الذهاب إلى الإعدادات لتوصيلها'),
              backgroundColor: AppColors.warning,
              action: SnackBarAction(
                label: 'الإعدادات',
                textColor: Colors.white,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BluetoothPrinterSettingsScreen()),
                  );
                },
              ),
            ),
          );
        }
        return;
      }
    }

    try {
      await printerService.printCustomerStatement({
        'name': supplier.name,
        'balance': _computeNetPosition().abs(),
        'balance_type': _computeNetPosition() >= 0 ? 'credit' : 'debit',
        'currency': supplier.currency,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إرسال كشف الحساب للطابعة الحرارية'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('حدث خطأ غير متوقع'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _exportToExcel() async {
    final supplier = _freshSupplier ?? widget.supplier;
    try {
      // Convert supplier movements to the format expected by ExcelExporter
      final movements = _filteredMovements.map((m) {
        final source = m['_source'] as String? ?? '';
        double debit = 0.0;
        double credit = 0.0;
        String typeAr = '';
        String dateStr = '';
        String description = '';

        if (source == 'invoice') {
          final type = m['type'] as String? ?? '';
          final isReturn = (m['is_return'] as num?)?.toInt() == 1;
          final total = MoneyHelper.readMoney(m['total']);
          dateStr = m['created_at'] as String? ?? '';
          description = _getInvoiceTypeAr(type, isReturn);
          typeAr = description;

          if (type == 'purchase' && !isReturn) {
            debit = total;
          } else if (type == 'sale' && !isReturn) {
            credit = total;
          } else if (isReturn) {
            if (type == 'purchase') credit = total;
            else debit = total;
          } else {
            debit = total;
          }
        } else if (source == 'opening_balance') {
          debit = MoneyHelper.readMoney(m['debit']);
          credit = MoneyHelper.readMoney(m['credit']);
          dateStr = m['_sort_date'] as String? ?? m['date'] as String? ?? m['created_at'] as String? ?? '';
          description = m['description'] as String? ?? 'رصيد افتتاحي';
          typeAr = 'رصيد افتتاحي';
        } else if (source == 'voucher') {
          final vType = m['voucher_type'] as String? ?? '';
          final totalAmount = MoneyHelper.readMoney(m['total_amount']);
          dateStr = m['date'] as String? ?? m['created_at'] as String? ?? '';
          description = m['description'] as String? ?? _getVoucherTypeAr(vType);
          typeAr = _getVoucherTypeAr(vType);

          switch (vType) {
            case 'payment': credit = totalAmount; break;
            case 'receipt': debit = totalAmount; break;
            default: credit = totalAmount;
          }
        }

        return {
          'date': dateStr,
          'type_ar': typeAr,
          'description': description,
          'debit': debit,
          'credit': credit,
        };
      }).toList();

      await ExcelExporter.exportAccountStatementToExcel(
        entityName: supplier.name,
        entityType: 'مورد',
        movements: movements,
        totalDebit: _totalDebit,
        totalCredit: _totalCredit,
        netBalance: _computeNetPosition(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء التصدير'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  String _getInvoiceTypeAr(String type, bool isReturn) {
    if (type == 'purchase' && !isReturn) return 'فاتورة مشتريات';
    if (type == 'purchase' && isReturn) return 'مرتجع مشتريات';
    if (type == 'sale' && !isReturn) return 'فاتورة مبيعات';
    if (type == 'sale' && isReturn) return 'مرتجع مبيعات';
    return 'فاتورة';
  }

  String _getVoucherTypeAr(String vType) {
    switch (vType) {
      case 'receipt': return 'سند قبض';
      case 'payment': return 'سند صرف';
      case 'settlement': return 'قيد عام';
      case 'compound': return 'قيد متعدد';
      default: return 'سند';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // ignore: unused_local_variable
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final netPosition = _computeNetPosition();
    final balanceLabel = Supplier.getDynamicBalanceLabel(
      netPosition, widget.supplier.balanceType,
    );
    final isCreditBalance = balanceLabel == 'له';
    final isEven = balanceLabel == 'متساوي';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.supplier.name),
          actions: [
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'طباعة',
              onPressed: _printReport,
            ),
            IconButton(
              icon: const Icon(Icons.table_chart),
              tooltip: 'تصدير Excel',
              onPressed: _exportToExcel,
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: _tabs,
            isScrollable: true,
            labelColor: isDark ? Colors.white : AppColors.primary,
            unselectedLabelColor: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabAlignment: TabAlignment.start,
            labelStyle: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            unselectedLabelStyle: theme.textTheme.bodySmall,
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // ── Supplier Header ─────────────────────────────
                  _SupplierHeader(
                    supplier: widget.supplier,
                    netPosition: netPosition,
                    balanceLabel: balanceLabel,
                    isCreditBalance: isCreditBalance,
                    isEven: isEven,
                    isDark: isDark,
                  ),

                  // ── Date & Currency Filters ────────────────────
                  _FilterBar(
                    startDate: _startDate,
                    endDate: _endDate,
                    selectedCurrency: _selectedCurrency,
                    onPickStart: _pickStartDate,
                    onPickEnd: _pickEndDate,
                    onClearDates: _clearDateFilters,
                    onCurrencyChanged: (v) {
                      setState(() => _selectedCurrency = v);
                      _applyFilters();
                    },
                    isDark: isDark,
                  ),

                  // ── Movements List ─────────────────────────────
                  Expanded(
                    child: _filteredMovements.isEmpty
                        ? _buildEmptyState(theme)
                        : RefreshIndicator(
                            onRefresh: _loadMovements,
                            child: _buildMovementsList(isDark),
                          ),
                  ),

                  // ── Bottom Statistics ───────────────────────────
                  _BottomStats(
                    totalCredit: _totalCredit,
                    totalDebit: _totalDebit,
                    netPosition: netPosition,
                    balanceLabel: balanceLabel,
                    openingBalance: _openingBalance,
                    openingBalanceLabel: _openingBalanceLabel,
                    isDark: isDark,
                  ),
                ],
              ),
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 72), // Lift above bottom stats bar
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingActionButton.small(
                heroTag: 'receipt',
                onPressed: () => _showAddVoucherDialog('receipt'),
                backgroundColor: AppColors.success,
                tooltip: 'سند قبض',
                child: const Icon(Icons.assignment_turned_in, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'payment',
                onPressed: () => _showAddVoucherDialog('payment'),
                backgroundColor: AppColors.error,
                tooltip: 'سند صرف',
                child: const Icon(Icons.assignment_return, color: Colors.white, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.local_shipping,
                  size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد حركات',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'لم يتم تسجيل أي حركات مالية لهذا المورد بعد',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textHint,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMovementsList(bool isDark) {
    final runningBalances = _computeRunningBalances();

    return ListView.builder(
      padding: EdgeInsets.only(
        bottom: 80 + MediaQuery.of(context).padding.bottom,
      ),
      itemCount: _filteredMovements.length,
      itemBuilder: (context, index) {
        final movement = _filteredMovements[index];
        final running = index < runningBalances.length
            ? runningBalances[index]
            : 0.0;
        return _MovementCard(
          movement: movement,
          runningBalance: running,
          supplier: widget.supplier,
          isDark: isDark,
          isLast: index == _filteredMovements.length - 1,
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  Supplier Header Widget
// ═══════════════════════════════════════════════════════════════════════

class _SupplierHeader extends StatelessWidget {
  final Supplier supplier;
  final double netPosition;
  final String balanceLabel;
  final bool isCreditBalance;
  final bool isEven;
  final bool isDark;

  const _SupplierHeader({
    required this.supplier,
    required this.netPosition,
    required this.balanceLabel,
    required this.isCreditBalance,
    required this.isEven,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final balanceColor = isEven
        ? (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary)
        : isCreditBalance
            ? AppColors.success
            : AppColors.error;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: balanceColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: balanceColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: balanceColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.local_shipping,
                  color: balanceColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supplier.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: balanceColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (supplier.phone != null) ...[
                          Icon(Icons.phone,
                              size: 14,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            supplier.phone!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: balanceColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            balanceLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: balanceColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'الرصيد الحالي',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                CurrencyFormatter.format(netPosition.abs()),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: balanceColor,
                ),
              ),
            ],
          ),
          if (supplier.debtCeiling > 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'سقف المدينية',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                  ),
                ),
                Text(
                  CurrencyFormatter.format(supplier.debtCeiling),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: netPosition.abs() > supplier.debtCeiling
                        ? AppColors.error
                        : AppColors.success,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  Filter Bar Widget
// ═══════════════════════════════════════════════════════════════════════

class _FilterBar extends StatelessWidget {
  final DateTime? startDate;
  final DateTime? endDate;
  final String selectedCurrency;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onClearDates;
  final ValueChanged<String> onCurrencyChanged;
  final bool isDark;

  const _FilterBar({
    this.startDate,
    this.endDate,
    required this.selectedCurrency,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onClearDates,
    required this.onCurrencyChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Start date
          GestureDetector(
            onTap: onPickStart,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: startDate != null
                    ? AppColors.primary.withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: startDate != null
                      ? AppColors.primary.withOpacity(0.3)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today,
                      size: 14,
                      color: startDate != null
                          ? AppColors.primary
                          : AppColors.textHint),
                  const SizedBox(width: 4),
                  Text(
                    startDate != null
                        ? DateFormatter.formatDate(startDate!)
                        : 'من',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: startDate != null
                          ? AppColors.primary
                          : AppColors.textHint,
                      fontWeight: startDate != null
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),

          // End date
          GestureDetector(
            onTap: onPickEnd,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: endDate != null
                    ? AppColors.primary.withOpacity(0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: endDate != null
                      ? AppColors.primary.withOpacity(0.3)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today,
                      size: 14,
                      color: endDate != null
                          ? AppColors.primary
                          : AppColors.textHint),
                  const SizedBox(width: 4),
                  Text(
                    endDate != null
                        ? DateFormatter.formatDate(endDate!)
                        : 'إلى',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: endDate != null
                          ? AppColors.primary
                          : AppColors.textHint,
                      fontWeight: endDate != null
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (startDate != null || endDate != null) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.clear, size: 16),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: onClearDates,
            ),
          ],

          const Spacer(),

          // Currency filter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.border,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<String>(
              value: selectedCurrency,
              underline: const SizedBox.shrink(),
              isDense: true,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              items: const [
                DropdownMenuItem(value: 'YER', child: Text('ر.ي')),
                DropdownMenuItem(value: 'SAR', child: Text('ر.س')),
                DropdownMenuItem(value: 'USD', child: Text('\$')),
              ],
              onChanged: (v) {
                if (v != null) onCurrencyChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  Movement Card Widget
// ═══════════════════════════════════════════════════════════════════════

class _MovementCard extends StatelessWidget {
  final Map<String, dynamic> movement;
  final double runningBalance;
  final Supplier supplier;
  final bool isDark;
  final bool isLast;

  const _MovementCard({
    required this.movement,
    required this.runningBalance,
    required this.supplier,
    required this.isDark,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = movement['_source'] as String? ?? '';
    final direction = _getDirection();

    if (source == 'invoice') {
      return _buildInvoiceCard(theme, direction);
    } else if (source == 'opening_balance') {
      return _buildOpeningBalanceCard(theme, direction);
    } else {
      return _buildVoucherCard(theme, direction);
    }
  }

  String _getDirection() {
    final source = movement['_source'] as String? ?? '';
    if (source == 'opening_balance') {
      final debit = MoneyHelper.readMoney(movement['debit']);
      final credit = MoneyHelper.readMoney(movement['credit']);
      return debit > credit ? 'debit' : 'credit';
    }
    if (source == 'invoice') {
      final type = movement['type'] as String? ?? '';
      final isReturn = (movement['is_return'] as num?)?.toInt() == 1;
      if (type == 'purchase' || type == 'purchase_return') {
        return isReturn || type == 'purchase_return' ? 'credit' : 'debit';
      } else {
        return isReturn || type == 'sale_return' ? 'debit' : 'credit';
      }
    }
    if (source == 'voucher') {
      final vType = movement['voucher_type'] as String? ?? '';
      switch (vType) {
        case 'payment':
          return 'credit';
        case 'receipt':
          return 'debit';
        default:
          return 'credit';
      }
    }
    return 'credit';
  }

  double _getAmount() {
    final source = movement['_source'] as String? ?? '';
    if (source == 'opening_balance') {
      final debit = MoneyHelper.readMoney(movement['debit']);
      final credit = MoneyHelper.readMoney(movement['credit']);
      return debit > credit ? debit : credit;
    }
    if (source == 'invoice') {
      return MoneyHelper.readMoney(movement['total']);
    }
    return MoneyHelper.readMoney(movement['total_amount']);
  }

  Widget _buildInvoiceCard(ThemeData theme, String direction) {
    final amount = _getAmount();
    final type = movement['type'] as String? ?? '';
    final isReturn = (movement['is_return'] as num?)?.toInt() == 1;
    final dateStr = movement['created_at'] as String? ?? '';
    final currency = movement['currency'] as String? ?? 'YER';
    final isDebit = direction == 'debit';

    DateTime? txDate;
    try { txDate = DateTime.parse(dateStr); } catch (_) {}

    final typeAr = _getInvoiceTypeAr(type, isReturn);
    final typeColor = _getInvoiceTypeColor(type, isReturn);
    final typeIcon = _getInvoiceTypeIcon(type, isReturn);

    String currencySymbol;
    switch (currency) {
      case 'SAR': currencySymbol = 'ر.س'; break;
      case 'USD': currencySymbol = r'$'; break;
      default: currencySymbol = 'ر.ي';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Type badge + Running balance
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(typeIcon, size: 14, color: typeColor),
                    const SizedBox(width: 4),
                    Text(
                      typeAr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: typeColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Date
              if (txDate != null)
                Text(
                  DateFormatter.formatDate(txDate),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                    fontFamily: 'Cairo',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Row 2: Direction + Amount
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDebit
                        ? AppColors.error.withOpacity(0.08)
                        : AppColors.success.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        isDebit ? 'عليه' : 'له',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDebit ? AppColors.error : AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        CurrencyFormatter.format(amount, symbol: currencySymbol),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDebit ? AppColors.error : AppColors.success,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 3: Running balance
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'الرصيد: ',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                CurrencyFormatter.format(runningBalance.abs()),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: runningBalance.abs() < 0.005
                      ? (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary)
                      : runningBalance > 0
                          ? AppColors.success
                          : AppColors.error,
                  fontFamily: 'Cairo',
                ),
              ),
              const SizedBox(width: 4),
              Text(
                Supplier.getDynamicBalanceLabel(runningBalance, supplier.balanceType),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: runningBalance.abs() < 0.005
                      ? (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary)
                      : runningBalance > 0
                          ? AppColors.success
                          : AppColors.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOpeningBalanceCard(ThemeData theme, String direction) {
    final amount = _getAmount();
    final dateStr = movement['_sort_date'] as String? ?? movement['date'] as String? ?? movement['created_at'] as String? ?? '';
    final description = movement['description'] as String? ?? 'رصيد افتتاحي';
    final currency = movement['currency'] as String? ?? 'YER';
    final isDebit = direction == 'debit';

    DateTime? txDate;
    try { txDate = DateTime.parse(dateStr); } catch (_) {}

    String currencySymbol;
    switch (currency) {
      case 'SAR': currencySymbol = 'ر.س'; break;
      case 'USD': currencySymbol = r'$'; break;
      default: currencySymbol = 'ر.ي';
    }

    const typeAr = 'رصيد افتتاحي';
    const typeColor = AppColors.accentOrange;
    const typeIcon = Icons.account_balance;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: typeColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Type badge + date
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(typeIcon, size: 14, color: typeColor),
                    const SizedBox(width: 4),
                    Text(
                      typeAr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: typeColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (txDate != null)
                Text(
                  DateFormatter.formatDate(txDate),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                    fontFamily: 'Cairo',
                  ),
                ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.article, size: 14, color: AppColors.textHint),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),

          // Row 2: Direction + Amount
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDebit
                        ? AppColors.error.withOpacity(0.08)
                        : AppColors.success.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        isDebit ? 'عليه' : 'له',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDebit ? AppColors.error : AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        CurrencyFormatter.format(amount, symbol: currencySymbol),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDebit ? AppColors.error : AppColors.success,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 3: Running balance
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'الرصيد: ',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                CurrencyFormatter.format(runningBalance.abs()),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: runningBalance.abs() < 0.005
                      ? (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary)
                      : runningBalance > 0
                          ? AppColors.success
                          : AppColors.error,
                  fontFamily: 'Cairo',
                ),
              ),
              const SizedBox(width: 4),
              Text(
                Supplier.getDynamicBalanceLabel(runningBalance, supplier.balanceType),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: runningBalance.abs() < 0.005
                      ? (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary)
                      : runningBalance > 0
                          ? AppColors.success
                          : AppColors.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVoucherCard(ThemeData theme, String direction) {
    final amount = _getAmount();
    final vType = movement['voucher_type'] as String? ?? '';
    final dateStr = movement['date'] as String? ?? movement['created_at'] ?? '';
    final description = movement['description'] as String? ?? '';
    final number = movement['voucher_number'] as String? ?? '';
    final currency = movement['currency'] as String? ?? 'YER';
    final isDebit = direction == 'debit';

    DateTime? txDate;
    try { txDate = DateTime.parse(dateStr); } catch (_) {}

    final typeAr = _getVoucherTypeAr(vType);
    final typeColor = _getVoucherTypeColor(vType);
    final typeIcon = _getVoucherTypeIcon(vType);

    String currencySymbol;
    switch (currency) {
      case 'SAR': currencySymbol = 'ر.س'; break;
      case 'USD': currencySymbol = r'$'; break;
      default: currencySymbol = 'ر.ي';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Type badge + number + date
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(typeIcon, size: 14, color: typeColor),
                    const SizedBox(width: 4),
                    Text(
                      typeAr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: typeColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (number.isNotEmpty)
                Text(
                  number,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.textPrimary,
                  ),
                ),
              const Spacer(),
              if (txDate != null)
                Text(
                  DateFormatter.formatDate(txDate),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                    fontFamily: 'Cairo',
                  ),
                ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.article, size: 14, color: AppColors.textHint),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),

          // Row 2: Direction + Amount
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDebit
                        ? AppColors.error.withOpacity(0.08)
                        : AppColors.success.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        isDebit ? 'عليه' : 'له',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDebit ? AppColors.error : AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        CurrencyFormatter.format(amount, symbol: currencySymbol),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDebit ? AppColors.error : AppColors.success,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 3: Running balance
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'الرصيد: ',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                CurrencyFormatter.format(runningBalance.abs()),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: runningBalance.abs() < 0.005
                      ? (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary)
                      : runningBalance > 0
                          ? AppColors.success
                          : AppColors.error,
                  fontFamily: 'Cairo',
                ),
              ),
              const SizedBox(width: 4),
              Text(
                Supplier.getDynamicBalanceLabel(runningBalance, supplier.balanceType),
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: runningBalance.abs() < 0.005
                      ? (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary)
                      : runningBalance > 0
                          ? AppColors.success
                          : AppColors.error,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Invoice type helpers ──────────────────────────────────────
  String _getInvoiceTypeAr(String type, bool isReturn) {
    if (isReturn) {
      switch (type) {
        case 'sale': return 'مرتجع مبيعات';
        case 'purchase': return 'مرتجع مشتريات';
        default: return 'فاتورة مرتجع';
      }
    }
    switch (type) {
      case 'sale': return 'فاتورة مبيعات';
      case 'purchase': return 'فاتورة مشتريات';
      case 'sale_return': return 'مرتجع مبيعات';
      case 'purchase_return': return 'مرتجع مشتريات';
      default: return 'فاتورة';
    }
  }

  Color _getInvoiceTypeColor(String type, bool isReturn) {
    if (isReturn) return AppColors.warning;
    switch (type) {
      case 'sale': return AppColors.success;
      case 'purchase': return AppColors.info;
      default: return AppColors.primary;
    }
  }

  IconData _getInvoiceTypeIcon(String type, bool isReturn) {
    if (isReturn) return Icons.keyboard_return;
    switch (type) {
      case 'sale': return Icons.point_of_sale;
      case 'purchase': return Icons.shopping_cart;
      default: return Icons.receipt;
    }
  }

  // ── Voucher type helpers ──────────────────────────────────────
  String _getVoucherTypeAr(String type) {
    switch (type) {
      case 'receipt': return 'سند قبض';
      case 'payment': return 'سند صرف';
      case 'settlement': return 'قيد عام';
      case 'compound': return 'قيد متعدد';
      default: return type;
    }
  }

  Color _getVoucherTypeColor(String type) {
    switch (type) {
      case 'receipt': return AppColors.success;
      case 'payment': return AppColors.error;
      case 'settlement': return AppColors.info;
      case 'compound': return AppColors.accentOrange;
      default: return AppColors.primary;
    }
  }

  IconData _getVoucherTypeIcon(String type) {
    switch (type) {
      case 'receipt': return Icons.arrow_downward;
      case 'payment': return Icons.arrow_upward;
      case 'settlement': return Icons.swap_horiz;
      case 'compound': return Icons.compare_arrows;
      default: return Icons.receipt;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
//  Bottom Statistics Widget
// ═══════════════════════════════════════════════════════════════════════

class _BottomStats extends StatelessWidget {
  final double totalCredit;
  final double totalDebit;
  final double netPosition;
  final String balanceLabel;
  final double openingBalance;
  final String openingBalanceLabel;
  final bool isDark;

  const _BottomStats({
    required this.totalCredit,
    required this.totalDebit,
    required this.netPosition,
    required this.balanceLabel,
    required this.openingBalance,
    required this.openingBalanceLabel,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.border,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Opening balance row (only if non-zero)
          if (openingBalance.abs() > 0.005)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _StatItem(
                      label: 'رصيد افتتاحي ($openingBalanceLabel)',
                      value: CurrencyFormatter.format(openingBalance),
                      color: openingBalanceLabel == 'له' ? AppColors.success : AppColors.error,
                      icon: Icons.account_balance,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              // له
              Expanded(
                child: _StatItem(
                  label: 'له',
                  value: CurrencyFormatter.format(totalCredit),
                  color: AppColors.success,
                  icon: Icons.south_east,
                ),
              ),
              Container(
                width: 1,
                height: 36,
                color: isDark ? AppColors.darkDivider : AppColors.divider,
              ),
              // عليه
              Expanded(
                child: _StatItem(
                  label: 'عليه',
                  value: CurrencyFormatter.format(totalDebit),
                  color: AppColors.error,
                  icon: Icons.north_west,
                ),
              ),
              Container(
                width: 1,
                height: 36,
                color: isDark ? AppColors.darkDivider : AppColors.divider,
              ),
              // الرصيد
              Expanded(
                child: _StatItem(
                  label: 'الرصيد ($balanceLabel)',
                  value: CurrencyFormatter.format(netPosition.abs()),
                  color: netPosition.abs() < 0.005
                      ? (isDark ? AppColors.darkTextSecondary : AppColors.textSecondary)
                      : netPosition > 0
                          ? AppColors.success
                          : AppColors.error,
                  icon: Icons.balance,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _StatItem({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
