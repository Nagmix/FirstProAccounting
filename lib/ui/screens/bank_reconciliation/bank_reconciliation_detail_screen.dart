import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/services/bank_reconciliation_service.dart';
import '../../../data/models/bank_reconciliation_model.dart';

class BankReconciliationDetailScreen extends StatefulWidget {
  final int reconciliationId;
  const BankReconciliationDetailScreen(
      {super.key, required this.reconciliationId});

  @override
  State<BankReconciliationDetailScreen> createState() =>
      _BankReconciliationDetailScreenState();
}

class _BankReconciliationDetailScreenState
    extends State<BankReconciliationDetailScreen> {
  BankReconciliation? _reconciliation;
  Map<String, dynamic>? _reconInfo;
  List<BankStatementLine> _bankLines = [];
  List<BankStatementLine> _bookLines = [];
  bool _isLoading = true;
  bool _isCompleting = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final service = locator<BankReconciliationService>();
      final reconInfo = await service.getReconciliationWithInfo(widget.reconciliationId);
      final recon = await service.getReconciliation(widget.reconciliationId);
      if (recon == null) {
        if (mounted) Navigator.pop(context);
        return;
      }

      final allLines = await service.getStatementLines(widget.reconciliationId);
      final bankLines = allLines.where((l) => !l.isBookEntry).toList();
      final bookLines = allLines.where((l) => l.isBookEntry).toList();

      if (mounted) {
        setState(() {
          _reconciliation = recon;
          _reconInfo = reconInfo;
          _bankLines = bankLines;
          _bookLines = bookLines;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _loadBookTransactions() async {
    if (_reconciliation == null) return;
    final service = locator<BankReconciliationService>();

    // Use statement date as end date, and 30 days before as start
    final endDate = _reconciliation!.statementDate;
    final startDate = endDate.subtract(const Duration(days: 30));

    await service.loadBookTransactionsAsStatementLines(
        widget.reconciliationId,
        _reconciliation!.cashBoxId,
        startDate,
        endDate);

    _loadData();
  }

  Future<void> _autoMatch() async {
    final count = await locator<BankReconciliationService>().autoMatch(widget.reconciliationId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم مطابقة $count بند تلقائياً'),
          backgroundColor: count > 0 ? AppColors.success : AppColors.warning,
        ),
      );
    }
    _loadData();
  }

  Future<void> _addBankStatementLine() async {
    final dateController = TextEditingController();
    final amountController = TextEditingController();
    final descController = TextEditingController();
    final refController = TextEditingController();
    String type = 'credit';
    DateTime selectedDate = DateTime.now();

    await showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('إضافة بند كشف بنكي'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('إيداع'),
                          value: 'credit',
                          groupValue: type,
                          onChanged: (v) => setDialogState(() => type = v!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('سحب'),
                          value: 'debit',
                          groupValue: type,
                          onChanged: (v) => setDialogState(() => type = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        locale: const Locale('ar'),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'التاريخ',
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(
                        '${selectedDate.day.toString().padLeft(2, '0')}/${selectedDate.month.toString().padLeft(2, '0')}/${selectedDate.year}',
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'المبلغ',
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: 'الوصف',
                      prefixIcon: Icon(Icons.description),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: refController,
                    decoration: const InputDecoration(
                      labelText: 'المرجع',
                      prefixIcon: Icon(Icons.tag),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: () async {
                  final amount = double.tryParse(amountController.text) ?? 0;
                  if (amount <= 0) return;
                  await locator<BankReconciliationService>().addStatementLine(BankStatementLine(
                    reconciliationId: widget.reconciliationId,
                    cashBoxId: _reconciliation!.cashBoxId,
                    transactionDate: selectedDate,
                    transactionType: type,
                    amount: amount,
                    description: descController.text.trim().isNotEmpty
                        ? descController.text.trim()
                        : null,
                    reference: refController.text.trim().isNotEmpty
                        ? refController.text.trim()
                        : null,
                  ));
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadData();
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white),
                child: const Text('إضافة'),
              ),
            ],
          ),
        ),
      ),
    );
    dateController.dispose();
    amountController.dispose();
    descController.dispose();
    refController.dispose();
  }

  Future<void> _calculateBalances() async {
    if (_reconciliation == null) return;
    final service = locator<BankReconciliationService>();
    final calculated = await service.calculateAdjustedBalances(_reconciliation!);
    await service.updateReconciliation(calculated);
    _loadData();
  }

  Future<void> _completeReconciliation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          icon: const Icon(Icons.check_circle, color: AppColors.success, size: 40),
          title: const Text('إكمال التسوية'),
          content: const Text('سيتم ترحيل القيود المحاسبية للتسوية (رسوم بنكية، فوائد). هل أنت متأكد؟'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success, foregroundColor: Colors.white),
              child: const Text('إكمال'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _isCompleting = true);
    try {
      await locator<BankReconciliationService>().completeReconciliation(widget.reconciliationId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إكمال التسوية وترحيل القيود بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
      }
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isCompleting = false);
    }
  }

  Future<void> _unmatchLine(int lineId) async {
    await locator<BankReconciliationService>().unmatchLine(lineId);
    _loadData();
  }

  Color _matchStatusColor(String status) {
    switch (status) {
      case 'matched':
        return AppColors.success;
      case 'unmatched':
        return AppColors.warning;
      case 'new_transaction':
        return AppColors.accentBlue;
      default:
        return AppColors.textHint;
    }
  }

  String _matchStatusAr(String status) {
    switch (status) {
      case 'matched':
        return 'مطابق';
      case 'unmatched':
        return 'غير مطابق';
      case 'new_transaction':
        return 'معاملة جديدة';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recon = _reconciliation;
    final bankName = _reconInfo?['bank_name'] as String? ??
        _reconInfo?['cash_box_name'] as String? ??
        '';

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(recon?.reconciliationNumber ?? 'التسوية البنكية'),
          actions: [
            if (recon != null && recon.status != 'completed')
              IconButton(
                onPressed: _calculateBalances,
                icon: const Icon(Icons.calculate),
                tooltip: 'حساب الأرصدة',
              ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : recon == null
                ? const Center(child: Text('لم يتم العثور على التسوية'))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Header Info Card ─────────────────────
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.account_balance,
                                        color: AppColors.primary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(bankName,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                  fontWeight: FontWeight.w700)),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: _statusColor(recon.status)
                                            .withOpacity(0.1),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: Text(recon.statusAr,
                                          style: theme.textTheme.labelSmall
                                              ?.copyWith(
                                            color:
                                                _statusColor(recon.status),
                                            fontWeight: FontWeight.w600,
                                          )),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _infoField(
                                          'تاريخ الكشف',
                                          _formatDate(
                                              recon.statementDate.toIso8601String())),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: _infoField(
                                          'رصيد كشف البنك',
                                          CurrencyFormatter.format(
                                              recon.statementBalance)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _infoField(
                                          'الرصيد الدفتري',
                                          CurrencyFormatter.format(
                                              recon.bookBalance)),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(child: Container()),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── Action buttons ─────────────────────
                        if (recon.status != 'completed') ...[
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _loadBookTransactions,
                                icon: const Icon(Icons.download, size: 18),
                                label: const Text('تحميل القيود الدفترية'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accentBlue,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _addBankStatementLine,
                                icon: const Icon(Icons.add, size: 18),
                                label: const Text('إضافة بند بنكي'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.success,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _autoMatch,
                                icon: const Icon(Icons.sync, size: 18),
                                label: const Text('مطابقة تلقائية'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.warning,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],

                        // ── Two panels side by side ────────────
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // LEFT: Bank Statement Lines
                            Expanded(
                              child: _linesPanel(
                                'بنود كشف الحساب البنكي',
                                Icons.account_balance,
                                _bankLines,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // RIGHT: Book Transactions
                            Expanded(
                              child: _linesPanel(
                                'قيود دفترية',
                                Icons.book,
                                _bookLines,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // ── Summary section ──────────────────
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          color: AppColors.primary.withOpacity(0.03),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.balance,
                                        color: AppColors.primary),
                                    const SizedBox(width: 8),
                                    Text('ملخص التسوية',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.primary)),
                                  ],
                                ),
                                const Divider(height: 20),
                                _summaryRow('رصيد كشف البنك',
                                    CurrencyFormatter.format(recon.statementBalance)),
                                _summaryRow('+ إيداعات تحت التسوية',
                                    CurrencyFormatter.format(recon.depositsInTransit)),
                                _summaryRow('- شيكات معلقة',
                                    CurrencyFormatter.format(recon.outstandingChecks)),
                                _summaryRow('= الرصيد المعدّل بنكي',
                                    CurrencyFormatter.format(recon.adjustedBankBalance),
                                    bold: true),
                                const Divider(height: 16),
                                _summaryRow('الرصيد الدفتري',
                                    CurrencyFormatter.format(recon.bookBalance)),
                                _summaryRow('+ فوائد بنكية',
                                    CurrencyFormatter.format(recon.interestEarned)),
                                _summaryRow('- رسوم بنكية',
                                    CurrencyFormatter.format(recon.bankCharges)),
                                _summaryRow('= الرصيد المعدّل دفتري',
                                    CurrencyFormatter.format(recon.adjustedBookBalance),
                                    bold: true),
                                const Divider(height: 16),
                                _summaryRow(
                                  'الفرق',
                                  CurrencyFormatter.format(recon.difference),
                                  bold: true,
                                  color: recon.isReconciled
                                      ? AppColors.success
                                      : AppColors.error,
                                ),
                                if (recon.isReconciled)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.check_circle,
                                            color: AppColors.success, size: 20),
                                        const SizedBox(width: 6),
                                        Text('التسوية متوازنة ✓',
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                              color: AppColors.success,
                                              fontWeight: FontWeight.w700,
                                            )),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── Complete button ──────────────────
                        if (recon.status != 'completed')
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: (recon.isReconciled && !_isCompleting)
                                  ? _completeReconciliation
                                  : null,
                              icon: _isCompleting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white),
                                    )
                                  : const Icon(Icons.check_circle, size: 20),
                              label: Text(_isCompleting
                                  ? 'جاري الإكمال...'
                                  : 'إكمال التسوية'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: recon.isReconciled
                                    ? AppColors.success
                                    : AppColors.textHint,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),

                        if (recon.status == 'completed')
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: AppColors.success.withOpacity(0.3)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.check_circle,
                                    color: AppColors.success),
                                const SizedBox(width: 8),
                                Text(
                                  'تم إكمال التسوية وترحيل القيود المحاسبية',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _linesPanel(String title, IconData icon, List<BankStatementLine> lines) {
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700, color: AppColors.primary)),
                ),
                Text('${lines.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.textHint)),
              ],
            ),
          ),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: lines.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('لا توجد بنود',
                          style: TextStyle(color: AppColors.textHint)),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: lines.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final line = lines[index];
                      return ListTile(
                        dense: true,
                        title: Text(
                          line.description ?? 'بند ${line.id}',
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${_formatDate(line.transactionDate.toIso8601String())} • ${line.transactionType == 'credit' ? 'إيداع' : 'سحب'}',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: AppColors.textHint),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              CurrencyFormatter.format(line.amount),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: line.transactionType == 'credit'
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
                            ),
                            GestureDetector(
                              onTap: line.isMatched && _reconciliation?.status != 'completed'
                                  ? () => _unmatchLine(line.id!)
                                  : null,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _matchStatusColor(line.matchStatus)
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _matchStatusAr(line.matchStatus),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: _matchStatusColor(line.matchStatus),
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _infoField(String label, String value) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: AppColors.textHint)),
        const SizedBox(height: 2),
        Text(value,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _summaryRow(String label, String value,
      {bool bold = false, Color? color}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color ?? AppColors.textSecondary,
                fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
              )),
          Text(value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color ?? AppColors.textPrimary,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              )),
        ],
      ),
    );
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

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (e) {
      debugPrint('BankReconciliationDetailScreen._formatDate: $e');
      return dateStr;
    }
  }
}
