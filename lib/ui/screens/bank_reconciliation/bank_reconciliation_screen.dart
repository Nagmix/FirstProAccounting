import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/money_helper.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/bank_reconciliation_model.dart';
import 'bank_reconciliation_detail_screen.dart';

class BankReconciliationScreen extends StatefulWidget {
  const BankReconciliationScreen({super.key});

  @override
  State<BankReconciliationScreen> createState() =>
      _BankReconciliationScreenState();
}

class _BankReconciliationScreenState extends State<BankReconciliationScreen> {
  List<Map<String, dynamic>> _reconciliations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReconciliations();
  }

  Future<void> _loadReconciliations() async {
    setState(() => _isLoading = true);
    try {
      final db = DatabaseHelper();
      final data = await db.bankReconciliation.getAllReconciliationsWithInfo();
      if (mounted) {
        setState(() {
          _reconciliations = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('حدث خطأ أثناء تحميل البيانات'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _createNewReconciliation() async {
    final db = DatabaseHelper();
    final bankCashBoxes = await db.bankReconciliation.getBankCashBoxes();

    if (bankCashBoxes.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا يوجد حساب بنكي. قم بإنشاء حساب بنكي أولاً من شاشة الصناديق والبنوك.'),
            backgroundColor: AppColors.warning,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _NewReconciliationDialog(bankCashBoxes: bankCashBoxes),
    );

    if (result != null) {
      try {
        final reconNumber =
            await db.bankReconciliation.getNextReconciliationNumber();
        final cashBoxId = result['cashBoxId'] as int;
        final statementDate = result['statementDate'] as DateTime;
        final statementBalance = result['statementBalance'] as double;

        final bookBalance =
            await db.bankReconciliation.getBookBalance(cashBoxId);

        final recon = BankReconciliation(
          reconciliationNumber: reconNumber,
          cashBoxId: cashBoxId,
          statementDate: statementDate,
          statementBalance: statementBalance,
          bookBalance: bookBalance,
        );

        final id = await db.bankReconciliation.createReconciliation(recon);
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  BankReconciliationDetailScreen(reconciliationId: id),
            ),
          ).then((_) => _loadReconciliations());
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('حدث خطأ: $e'),
                backgroundColor: AppColors.error),
          );
        }
      }
    }
  }

  void _openDetail(int id) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            BankReconciliationDetailScreen(reconciliationId: id),
      ),
    ).then((_) => _loadReconciliations());
  }

  Future<void> _deleteReconciliation(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning, color: AppColors.error, size: 40),
        title: const Text('حذف التسوية'),
        content: const Text('هل أنت متأكد من حذف هذه التسوية؟ لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirmed == true) {
      await DatabaseHelper().bankReconciliation.deleteReconciliation(id);
      _loadReconciliations();
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'draft':
        return Colors.grey;
      case 'in_progress':
        return AppColors.accentBlue;
      case 'completed':
        return AppColors.success;
      case 'posted':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _statusAr(String status) {
    switch (status) {
      case 'draft':
        return 'مسودة';
      case 'in_progress':
        return 'قيد التنفيذ';
      case 'completed':
        return 'مكتملة';
      case 'posted':
        return 'مرحّلة';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('التسوية البنكية'),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _reconciliations.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.account_balance,
                            size: 64,
                            color: AppColors.textHint.withOpacity(0.5)),
                        const SizedBox(height: 16),
                        Text('لا توجد تسويات بنكية',
                            style: theme.textTheme.titleMedium?.copyWith(
                                color: AppColors.textSecondary)),
                        const SizedBox(height: 8),
                        Text('اضغط على + لإنشاء تسوية جديدة',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.textHint)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _reconciliations.length,
                    itemBuilder: (context, index) {
                      final r = _reconciliations[index];
                      final status = r['status'] as String? ?? 'draft';
                      final difference =
                          MoneyHelper.readMoney(r['difference']);
                      final bankName =
                          r['bank_name'] as String? ?? r['cash_box_name'] as String? ?? '';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        child: InkWell(
                          onTap: () => _openDetail(r['id'] as int),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        r['reconciliation_number'] as String? ??
                                            '',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _statusColor(status)
                                            .withOpacity(0.1),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                        border: Border.all(
                                            color:
                                                _statusColor(status)),
                                      ),
                                      child: Text(
                                        _statusAr(status),
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: _statusColor(status),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    if (status == 'draft') ...[
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.delete,
                                            size: 20, color: AppColors.error),
                                        onPressed: () =>
                                            _deleteReconciliation(
                                                r['id'] as int),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.account_balance,
                                        size: 16,
                                        color: AppColors.textSecondary),
                                    const SizedBox(width: 6),
                                    Text(bankName,
                                        style: theme.textTheme.bodyMedium),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(Icons.calendar_today,
                                        size: 16,
                                        color: AppColors.textSecondary),
                                    const SizedBox(width: 6),
                                    Text(
                                      _formatDate(r['statement_date'] as String?),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                                const Divider(height: 20),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    _infoChip(
                                        'رصيد الكشف',
                                        CurrencyFormatter.format(
                                            MoneyHelper.readMoney(
                                                r['statement_balance']))),
                                    _infoChip(
                                        'الفرق',
                                        CurrencyFormatter.format(difference),
                                        color: difference.abs() < 0.005
                                            ? AppColors.success
                                            : AppColors.error),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
        floatingActionButton: FloatingActionButton(
          onPressed: _createNewReconciliation,
          backgroundColor: AppColors.primary,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Widget _infoChip(String label, String value, {Color? color}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: AppColors.textHint)),
        const SizedBox(height: 2),
        Text(value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: color ?? AppColors.textPrimary,
            )),
      ],
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (_) {
      return dateStr;
    }
  }
}

class _NewReconciliationDialog extends StatefulWidget {
  final List<Map<String, dynamic>> bankCashBoxes;
  const _NewReconciliationDialog({required this.bankCashBoxes});

  @override
  State<_NewReconciliationDialog> createState() =>
      _NewReconciliationDialogState();
}

class _NewReconciliationDialogState
    extends State<_NewReconciliationDialog> {
  int? _selectedCashBoxId;
  DateTime _statementDate = DateTime.now();
  final _statementBalanceController = TextEditingController();

  @override
  void dispose() {
    _statementBalanceController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _statementDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('ar'),
    );
    if (picked != null) {
      setState(() => _statementDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('تسوية بنكية جديدة'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                value: _selectedCashBoxId,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'الحساب البنكي',
                  prefixIcon: Icon(Icons.account_balance),
                ),
                items: widget.bankCashBoxes
                    .map((cb) => DropdownMenuItem<int>(
                          value: cb['id'] as int,
                          child: Text(cb['bank_name'] as String? ??
                              cb['name'] as String? ??
                              ''),
                        ))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _selectedCashBoxId = v),
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'تاريخ كشف الحساب',
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    '${_statementDate.day.toString().padLeft(2, '0')}/${_statementDate.month.toString().padLeft(2, '0')}/${_statementDate.year}',
                  ),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _statementBalanceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'رصيد كشف البنك',
                  prefixIcon: Icon(Icons.attach_money),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              if (_selectedCashBoxId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('يرجى اختيار الحساب البنكي'),
                      backgroundColor: AppColors.error),
                );
                return;
              }
              Navigator.pop(context, {
                'cashBoxId': _selectedCashBoxId,
                'statementDate': _statementDate,
                'statementBalance':
                    double.tryParse(_statementBalanceController.text) ??
                        0.0,
              });
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white),
            child: const Text('إنشاء'),
          ),
        ],
      ),
    );
  }
}
