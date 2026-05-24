import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/design_system.dart';
import '../../../core/services/bluetooth_printer_service.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/customer_model.dart';
import '../settings/bluetooth_printer_settings_screen.dart';

/// Customer Detail / Ledger Screen
/// Displays all financial movements for a specific customer with
/// filtering, statistics, and voucher creation capabilities.
class CustomerDetailScreen extends StatefulWidget {
  final Customer customer;

  const CustomerDetailScreen({super.key, required this.customer});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
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

  // Customer data (refreshable)
  Customer? _freshCustomer;

  // Cash boxes for voucher dialog
  List<Map<String, dynamic>> _cashBoxes = [];

  static const List<_FilterTab> _filterTabs = [
    _FilterTab(key: 'all', label: 'جميع الحركات والفواتير'),
    _FilterTab(key: 'debit', label: 'عليه'),
    _FilterTab(key: 'credit', label: 'له'),
    _FilterTab(key: 'payment_voucher', label: 'سند صرف'),
    _FilterTab(key: 'receipt_voucher', label: 'سند قبض'),
    _FilterTab(key: 'general_entry', label: 'قيد عام'),
    _FilterTab(key: 'outgoing_transfer', label: 'حوالة صادرة'),
    _FilterTab(key: 'incoming_transfer', label: 'حوالة وارده'),
    _FilterTab(key: 'sales', label: 'مبيعات فقط'),
    _FilterTab(key: 'purchases', label: 'مشتريات فقط'),
    _FilterTab(key: 'returns', label: 'مرتجع'),
    _FilterTab(key: 'compound_entry', label: 'قيد متعدد'),
  ];

  static const List<MapEntry<String, String>> _currencyOptions = [
    MapEntry('الكل', ''),
    MapEntry('YER', 'YER'),
    MapEntry('SAR', 'SAR'),
    MapEntry('USD', 'USD'),
  ];

  @override
  void initState() {
    super.initState();
    _freshCustomer = widget.customer;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final dbHelper = DatabaseHelper();

    // Refresh customer data
    final customerMap = await dbHelper.getCustomerById(widget.customer.id!);
    if (customerMap != null) {
      _freshCustomer = Customer.fromMap(customerMap);
    }

    // Load cash boxes
    _cashBoxes = await dbHelper.getAllCashBoxes();

    // Load all movements
    await _loadMovements(dbHelper);

    setState(() => _isLoading = false);
  }

  Future<void> _loadMovements(DatabaseHelper dbHelper) async {
    final db = await dbHelper.database;
    final customerId = widget.customer.id!;
    final movements = <Map<String, dynamic>>[];

    // 1. Load invoices for this customer
    final invoices = await db.rawQuery(
      'SELECT * FROM invoices WHERE customer_id = ? ORDER BY created_at ASC',
      [customerId],
    );

    for (final inv in invoices) {
      final type = inv['type'] as String? ?? 'sale';
      final isReturn = (inv['is_return'] as int? ?? 0) == 1;
      final total = (inv['total'] as num?)?.toDouble() ?? 0.0;
      final currency = inv['currency'] as String? ?? 'YER';
      final createdAt = inv['created_at'] as String? ?? DateTime.now().toIso8601String();

      String effectiveType;
      String typeAr;
      IconData icon;
      Color color;
      double debit = 0.0;
      double credit = 0.0;
      String filterKey;

      if (type == 'sale' && !isReturn) {
        effectiveType = 'sale';
        typeAr = 'فاتورة مبيعات';
        icon = Icons.receipt_long;
        color = AppColors.primary;
        // Sale invoice: customer owes us → debit (عليه)
        debit = total;
        filterKey = 'sales';
      } else if (type == 'sale' && isReturn) {
        effectiveType = 'sale_return';
        typeAr = 'مرتجع مبيعات';
        icon = Icons.keyboard_return;
        color = AppColors.warning;
        // Sale return: we owe customer → credit (له)
        credit = total;
        filterKey = 'returns';
      } else if (type == 'purchase' && !isReturn) {
        effectiveType = 'purchase';
        typeAr = 'فاتورة مشتريات';
        icon = Icons.shopping_cart;
        color = AppColors.accentOrange;
        // Purchase invoice: we owe supplier → credit (له)
        credit = total;
        filterKey = 'purchases';
      } else if (type == 'purchase' && isReturn) {
        effectiveType = 'purchase_return';
        typeAr = 'مرتجع مشتريات';
        icon = Icons.keyboard_return;
        color = AppColors.accentPink;
        debit = total;
        filterKey = 'returns';
      } else {
        effectiveType = type;
        typeAr = 'فاتورة';
        icon = Icons.receipt;
        color = AppColors.textSecondary;
        debit = total;
        filterKey = 'all';
      }

      final remaining = (inv['remaining'] as num?)?.toDouble() ?? 0.0;
      final desc = '$typeAr - ${inv['id'] ?? ''}${remaining > 0 ? ' (متبقي: ${remaining.toStringAsFixed(2)})' : ''}';

      movements.add({
        'id': inv['id'],
        'date': createdAt,
        'type': effectiveType,
        'type_ar': typeAr,
        'filter_key': filterKey,
        'icon': icon,
        'color': color,
        'description': desc,
        'debit': debit,
        'credit': credit,
        'currency': currency,
        'source': 'invoice',
        'voucher_type': null,
      });
    }

    // 2. Load voucher items for accounts linked to this customer
    // Find the customer's account in the chart of accounts
    final customerAccounts = await db.rawQuery(
      "SELECT id FROM accounts WHERE name_ar LIKE ? AND account_type = 'ASSET'",
      ['%العملاء%'],
    );

    // Also load vouchers directly linked through voucher items
    final vouchers = await dbHelper.getAllVouchers();
    for (final v in vouchers) {
      final voucherId = v['id'] as int?;
      final voucherType = v['voucher_type'] as String? ?? '';
      final totalAmount = (v['total_amount'] as num?)?.toDouble() ?? 0.0;
      final currency = v['currency'] as String? ?? 'YER';
      final dateStr = v['date'] as String? ?? v['created_at'] as String? ?? DateTime.now().toIso8601String();

      // Check if any voucher item references a customer account
      if (voucherId != null && customerAccounts.isNotEmpty) {
        final accountIds = customerAccounts.map((a) => a['id']).toList();
        final items = await dbHelper.getVoucherItems(voucherId);
        bool linkedToCustomer = false;
        for (final item in items) {
          final accountId = item['account_id'] as int?;
          if (accountId != null && accountIds.contains(accountId)) {
            linkedToCustomer = true;
            break;
          }
        }
        if (!linkedToCustomer) continue;
      } else {
        continue;
      }

      String typeAr;
      IconData icon;
      Color color;
      double debit = 0.0;
      double credit = 0.0;
      String filterKey;

      switch (voucherType) {
        case 'receipt':
          typeAr = 'سند قبض';
          icon = Icons.assignment_turned_in;
          color = AppColors.success;
          // Receipt: we receive money from customer → credit (له decreases)
          credit = totalAmount;
          filterKey = 'receipt_voucher';
          break;
        case 'payment':
          typeAr = 'سند صرف';
          icon = Icons.assignment_return;
          color = AppColors.error;
          // Payment: we pay money to customer → debit (عليه decreases)
          debit = totalAmount;
          filterKey = 'payment_voucher';
          break;
        case 'settlement':
          typeAr = 'قيد عام';
          icon = Icons.balance;
          color = AppColors.info;
          credit = totalAmount;
          filterKey = 'general_entry';
          break;
        case 'compound':
          typeAr = 'قيد متعدد';
          icon = Icons.dynamic_feed;
          color = AppColors.accentBlue;
          debit = totalAmount;
          filterKey = 'compound_entry';
          break;
        default:
          typeAr = 'سند';
          icon = Icons.description;
          color = AppColors.textSecondary;
          debit = totalAmount;
          filterKey = 'all';
      }

      final description = v['description'] as String? ?? '$typeAr - ${v['voucher_number'] ?? ''}';

      movements.add({
        'id': 'v_${v['id']}',
        'date': dateStr,
        'type': voucherType,
        'type_ar': typeAr,
        'filter_key': filterKey,
        'icon': icon,
        'color': color,
        'description': description,
        'debit': debit,
        'credit': credit,
        'currency': currency,
        'source': 'voucher',
        'voucher_type': voucherType,
      });
    }

    // Sort by date ascending for running balance
    movements.sort((a, b) {
      final dateA = a['date'] as String;
      final dateB = b['date'] as String;
      return dateA.compareTo(dateB);
    });

    _allMovements = movements;
    _applyFilters();
  }

  void _applyFilters() {
    var filtered = List<Map<String, dynamic>>.from(_allMovements);

    // Apply tab filter
    final filterKey = _filterTabs[_selectedFilterIndex].key;
    if (filterKey == 'debit') {
      filtered = filtered.where((m) => ((m['debit'] as num?)?.toDouble() ?? 0.0) > 0).toList();
    } else if (filterKey == 'credit') {
      filtered = filtered.where((m) => ((m['credit'] as num?)?.toDouble() ?? 0.0) > 0).toList();
    } else if (filterKey != 'all') {
      filtered = filtered.where((m) => m['filter_key'] == filterKey).toList();
    }

    // Apply currency filter
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
        } catch (_) {
          return true;
        }
      }).toList();
    }

    // Calculate running balance and totals
    double runningBalance = 0.0;
    double totalDebit = 0.0;
    double totalCredit = 0.0;

    for (final m in filtered) {
      final debit = (m['debit'] as num?)?.toDouble() ?? 0.0;
      final credit = (m['credit'] as num?)?.toDouble() ?? 0.0;
      runningBalance += credit - debit; // positive = له (credit), negative = عليه (debit)
      totalDebit += debit;
      totalCredit += credit;
      m['running_balance'] = runningBalance;
    }

    setState(() {
      _filteredMovements = filtered;
      _totalDebit = totalDebit;
      _totalCredit = totalCredit;
      _netBalance = totalCredit - totalDebit;
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

  // ── Add Voucher Dialog ──────────────────────────────────────────
  Future<void> _showAddVoucherDialog(String voucherType) async {
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    int? selectedCashBoxId;
    String selectedCurrency = _freshCustomer?.currency ?? 'YER';
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
                    // Customer name (read-only)
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'العميل',
                        prefixIcon: Icon(Icons.person),
                      ),
                      child: Text(_freshCustomer?.name ?? ''),
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
                          child: Text('${cb['name']} (${cb['currency'] ?? 'YER'})'),
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
                          setDialogState(() => isSaving = true);

                          final dbHelper = DatabaseHelper();
                          final db = await dbHelper.database;
                          final now = DateTime.now();
                          final voucherNumber = await dbHelper.getNextVoucherNumber(voucherType);

                          // Find the customer's account
                          final customerAccounts = await db.rawQuery(
                            "SELECT id FROM accounts WHERE name_ar LIKE ? AND account_type = 'ASSET' AND currency = ?",
                            ['%العملاء%', selectedCurrency],
                          );
                          final customerAccountId = customerAccounts.isNotEmpty
                              ? customerAccounts.first['id'] as int
                              : null;

                          // Find the cash box account
                          int? cashBoxAccountId;
                          if (selectedCashBoxId != null) {
                            final cbData = await dbHelper.getCashBoxById(selectedCashBoxId!);
                            if (cbData != null) {
                              cashBoxAccountId = cbData['linked_account_id'] as int?;
                            }
                          }

                          final voucherMap = {
                            'voucher_number': voucherNumber,
                            'voucher_type': voucherType,
                            'date': now.toIso8601String(),
                            'description': descriptionController.text.trim().isEmpty
                                ? '${voucherType == 'receipt' ? 'سند قبض' : 'سند صرف'} - ${_freshCustomer?.name}'
                                : descriptionController.text.trim(),
                            'currency': selectedCurrency,
                            'total_amount': amount,
                            'cash_box_id': selectedCashBoxId,
                            'is_posted': 1,
                            'created_at': now.toIso8601String(),
                            'updated_at': now.toIso8601String(),
                          };

                          List<Map<String, dynamic>> items = [];

                          if (voucherType == 'receipt') {
                            // Receipt: Debit cash box, Credit customer account
                            if (cashBoxAccountId != null) {
                              items.add({
                                'account_id': cashBoxAccountId,
                                'debit': amount,
                                'credit': 0.0,
                                'description': 'سند قبض من ${_freshCustomer?.name}',
                              });
                            }
                            if (customerAccountId != null) {
                              items.add({
                                'account_id': customerAccountId,
                                'debit': 0.0,
                                'credit': amount,
                                'description': 'سند قبض من ${_freshCustomer?.name}',
                              });
                            }
                          } else {
                            // Payment: Debit customer account, Credit cash box
                            if (customerAccountId != null) {
                              items.add({
                                'account_id': customerAccountId,
                                'debit': amount,
                                'credit': 0.0,
                                'description': 'سند صرف إلى ${_freshCustomer?.name}',
                              });
                            }
                            if (cashBoxAccountId != null) {
                              items.add({
                                'account_id': cashBoxAccountId,
                                'debit': 0.0,
                                'credit': amount,
                                'description': 'سند صرف إلى ${_freshCustomer?.name}',
                              });
                            }
                          }

                          if (items.isNotEmpty) {
                            await dbHelper.insertVoucher(voucherMap, items);
                          }

                          // Update customer balance
                          if (_freshCustomer?.id != null) {
                            final currentBalance = _freshCustomer?.balance ?? 0.0;
                            final currentType = _freshCustomer?.balanceType ?? 'credit';
                            double newBalance;
                            if (voucherType == 'receipt') {
                              // Receipt from customer reduces what they owe us
                              if (currentType == 'debit') {
                                newBalance = currentBalance - amount;
                                final newType = newBalance < 0 ? 'credit' : 'debit';
                                await dbHelper.updateCustomer(_freshCustomer!.id!, {
                                  'balance': newBalance.abs(),
                                  'balance_type': newType,
                                  'updated_at': now.toIso8601String(),
                                });
                              } else {
                                newBalance = currentBalance + amount;
                                await dbHelper.updateCustomer(_freshCustomer!.id!, {
                                  'balance': newBalance,
                                  'balance_type': 'credit',
                                  'updated_at': now.toIso8601String(),
                                });
                              }
                            } else {
                              // Payment to customer increases what they owe us
                              if (currentType == 'debit') {
                                newBalance = currentBalance + amount;
                                await dbHelper.updateCustomer(_freshCustomer!.id!, {
                                  'balance': newBalance,
                                  'balance_type': 'debit',
                                  'updated_at': now.toIso8601String(),
                                });
                              } else {
                                newBalance = currentBalance - amount;
                                final newType = newBalance < 0 ? 'debit' : 'credit';
                                await dbHelper.updateCustomer(_freshCustomer!.id!, {
                                  'balance': newBalance.abs(),
                                  'balance_type': newType,
                                  'updated_at': now.toIso8601String(),
                                });
                              }
                            }
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
  }

  // ── Print / Export placeholders ─────────────────────────────────
  void _printReport() {
    // Show print options bottom sheet
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
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.print, color: AppColors.primary),
                ),
                title: const Text('طباعة PDF', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('إنشاء ملف PDF للمتابعة'),
                trailing: const Icon(Icons.arrow_back_ios, size: 16),
                onTap: () {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('جاري تحضير التقرير للطباعة...'), backgroundColor: AppColors.info),
                  );
                },
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.accentBlue.withValues(alpha: 0.1),
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

  /// Print customer statement via Bluetooth thermal printer.
  Future<void> _printBluetoothStatement() async {
    final printerService = BluetoothPrinterService.instance;
    final customer = _freshCustomer ?? widget.customer;

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
        'name': customer.name,
        'balance': customer.balance,
        'balance_type': customer.balanceType,
        'currency': customer.currency,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إرسال كشف الحساب للطابعة الحرارية'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on PrinterException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _exportToExcel() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري تصدير البيانات إلى إكسل...'), backgroundColor: AppColors.info),
    );
    // TODO: Implement Excel export using syncfusion or excel package
  }

  // ── Currency symbol helper ──────────────────────────────────────
  String _currencySymbol(String? code) {
    switch (code) {
      case 'SAR': return 'ر.س';
      case 'USD': return r'$';
      case 'YER': default: return 'ر.ي';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    final customer = _freshCustomer ?? widget.customer;
    final isDebit = customer.balanceType == 'debit';
    final balanceDisplay = customer.balance.abs().toStringAsFixed(2);
    final balanceColor = isDebit ? AppColors.error : (customer.balance > 0 ? AppColors.success : AppColors.textSecondary);

    return Scaffold(
      appBar: AppBar(
        title: Text(customer.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'طباعة',
            onPressed: _printReport,
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: 'تصدير إكسل',
            onPressed: _exportToExcel,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        child: Text(
                          customer.name.isNotEmpty ? customer.name[0] : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 22,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customer.name,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (customer.phone != null && customer.phone!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.phone, size: 14, color: Colors.white70),
                                  const SizedBox(width: 4),
                                  Text(
                                    customer.phone!,
                                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$balanceDisplay ${_currencySymbol(customer.currency)}',
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: isDebit ? AppColors.error.withValues(alpha: 0.9) : AppColors.success.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isDebit ? 'عليه' : (customer.balance > 0 ? 'له' : 'متساوي'),
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
                    value: _selectedCurrency ?? '',
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
                      setState(() => _selectedCurrency = (v?.isEmpty ?? true) ? null : v);
                      _applyFilters();
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
                            Icon(Icons.receipt_long, size: 64, color: AppColors.textHint.withValues(alpha: 0.3)),
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

      // ── Add Voucher FAB ────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showVoucherTypeChooser(),
        icon: const Icon(Icons.add_card),
        label: const Text('إضافة سند'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),

      // ── Bottom Statistics Bar ──────────────────────────────────
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isLight ? AppColors.surface : AppColors.darkSurface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
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
                // الرصيد (net)
                Expanded(
                  child: _StatItem(
                    label: 'الرصيد',
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

  void _showVoucherTypeChooser() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('إضافة سند', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 20),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.assignment_turned_in, color: AppColors.success),
                  ),
                  title: const Text('سند قبض', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('استلام مبلغ من العميل'),
                  onTap: () {
                    Navigator.pop(context);
                    _showAddVoucherDialog('receipt');
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.assignment_return, color: AppColors.error),
                  ),
                  title: const Text('سند صرف', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('دفع مبلغ للعميل'),
                  onTap: () {
                    Navigator.pop(context);
                    _showAddVoucherDialog('payment');
                  },
                ),
              ],
            ),
          ),
        );
      },
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
    final debit = (movement['debit'] as num?)?.toDouble() ?? 0.0;
    final credit = (movement['credit'] as num?)?.toDouble() ?? 0.0;
    final runningBalance = (movement['running_balance'] as num?)?.toDouble() ?? 0.0;
    final dateStr = movement['date'] as String;

    // Format date
    String formattedDate;
    try {
      final date = DateTime.parse(dateStr);
      formattedDate = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (_) {
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
                color: color.withValues(alpha: 0.1),
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
                          color: color.withValues(alpha: 0.1),
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
