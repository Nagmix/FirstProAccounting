import 'package:flutter/material.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/helpers/currency_constants.dart';
import 'package:firstpro/core/utils/currency_formatter.dart';
import 'package:firstpro/core/utils/date_formatter.dart';
import 'package:firstpro/core/utils/money_helper.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/services/recurring_invoice_service.dart';

/// F-03: Recurring invoices management screen.
///
/// Lists all recurring invoice templates (active + paused), allows
/// creating/editing/deleting/pausing/resuming, and manually triggering
/// the generation of due invoices.
class RecurringInvoicesScreen extends StatefulWidget {
  const RecurringInvoicesScreen({super.key});

  @override
  State<RecurringInvoicesScreen> createState() =>
      _RecurringInvoicesScreenState();
}

class _RecurringInvoicesScreenState extends State<RecurringInvoicesScreen> {
  final _service = locator<RecurringInvoiceService>();
  List<Map<String, dynamic>> _templates = [];
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    setState(() => _isLoading = true);
    try {
      _templates = await _service.getAllTemplates();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('خطأ في تحميل القوالب: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _processDueNow() async {
    setState(() => _isProcessing = true);
    try {
      final result = await _service.processDueTemplates();
      if (!mounted) return;
      final msg = result.generated > 0
          ? 'تم توليد ${result.generated} فاتورة متكررة.'
          : 'لا توجد فواتير مستحقة الآن.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor:
              result.generated > 0 ? AppColors.success : AppColors.info,
        ),
      );
      await _loadTemplates();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('فشل المعالجة: $e'),
            backgroundColor: AppColors.error),
      );
    }
    if (mounted) setState(() => _isProcessing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الفواتير المتكررة'),
          actions: [
            IconButton(
              icon: _isProcessing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_circle),
              onPressed: _isProcessing ? null : _processDueNow,
              tooltip: 'توليد الفواتير المستحقة',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isLoading ? null : _loadTemplates,
              tooltip: 'تحديث',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _templates.isEmpty
                ? _buildEmptyState(theme)
                : RefreshIndicator(
                    onRefresh: _loadTemplates,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _templates.length,
                      itemBuilder: (context, index) =>
                          _buildTemplateCard(_templates[index], theme),
                    ),
                  ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showEditDialog(null),
          icon: const Icon(Icons.add),
          label: const Text('قالب جديد'),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.repeat, size: 64, color: AppColors.textHint),
          const SizedBox(height: 16),
          Text('لا توجد فواتير متكررة', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
              'أنشئ قوالب للفواتير المتكررة (إيجار، اشتراك، إلخ) لتُولَّد تلقائياً.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: AppColors.textHint)),
        ],
      ),
    );
  }

  Widget _buildTemplateCard(Map<String, dynamic> template, ThemeData theme) {
    final id = template['id'] as int;
    final name = template['name'] as String? ?? '—';
    final status = template['status'] as String? ?? 'active';
    final frequency = template['frequency'] as String? ?? 'monthly';
    final interval = (template['interval_value'] as num?)?.toInt() ?? 1;
    final nextRun = template['next_run_date'] as String? ?? '—';
    final generatedCount = (template['generated_count'] as num?)?.toInt() ?? 0;
    final currency = template['currency'] as String? ?? 'YER';
    final invoiceType = template['invoice_type'] as String? ?? 'sale';
    final paymentMechanism = template['payment_mechanism'] as String? ?? 'credit';
    final isActive = status == 'active';
    final discountAmount = MoneyHelper.readMoney(template['discount_amount']);

    final frequencyLabel = _frequencyLabel(frequency, interval);
    final typeLabel = _invoiceTypeLabel(invoiceType);
    final paymentLabel = paymentMechanism == 'cash' ? 'نقدي' : 'آجل';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Icon(
          isActive ? Icons.play_circle : Icons.pause_circle,
          color: isActive ? AppColors.success : AppColors.textHint,
        ),
        title: Text(name, style: theme.textTheme.titleSmall),
        subtitle: Text(
          '$typeLabel • $paymentLabel • كل $frequencyLabel',
          style: theme.textTheme.bodySmall,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow('التنفيذ التالي', _formatDate(nextRun), theme),
                _detailRow('تكرار التوليد', 'كل $frequencyLabel', theme),
                _detailRow('العملة', currency, theme),
                _detailRow('الخصم',
                    CurrencyFormatter.format(discountAmount,
                        symbol: CurrencyConstants.currencySymbol(currency)),
                    theme),
                _detailRow('عدد الفواتير المُولَّدة', '$generatedCount', theme),
                if (template['last_generated_invoice_id'] != null)
                  _detailRow('آخر فاتورة',
                      template['last_generated_invoice_id'] as String, theme),
                _detailRow('الحالة', isActive ? 'نشط' : 'متوقف', theme),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (isActive)
                      TextButton.icon(
                        onPressed: () async {
                          await _service.pauseTemplate(id);
                          await _loadTemplates();
                        },
                        icon: const Icon(Icons.pause, size: 18),
                        label: const Text('إيقاف'),
                      )
                    else
                      TextButton.icon(
                        onPressed: () async {
                          await _service.resumeTemplate(id);
                          await _loadTemplates();
                        },
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: const Text('تفعيل'),
                      ),
                    TextButton.icon(
                      onPressed: () => _showEditDialog(template),
                      icon: const Icon(Icons.edit, size: 18),
                      label: const Text('تعديل'),
                    ),
                    TextButton.icon(
                      onPressed: () => _confirmDelete(id, name),
                      icon: Icon(Icons.delete, size: 18, color: AppColors.error),
                      label: Text('حذف', style: TextStyle(color: AppColors.error)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(value,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _frequencyLabel(String frequency, int interval) {
    final unit = switch (frequency) {
      'daily' => interval == 1 ? 'يوم' : 'أيام',
      'weekly' => interval == 1 ? 'أسبوع' : 'أسابيع',
      'monthly' => interval == 1 ? 'شهر' : 'أشهر',
      'yearly' => interval == 1 ? 'سنة' : 'سنوات',
      _ => 'دورة',
    };
    return interval == 1 ? unit : '$interval $unit';
  }

  String _invoiceTypeLabel(String type) {
    return switch (type) {
      'sale' => 'فاتورة بيع',
      'pos' => 'POS',
      'purchase' => 'فاتورة شراء',
      _ => type,
    };
  }

  String _formatDate(String dateStr) {
    if (dateStr.length >= 10) {
      try {
        return DateFormatter.formatDate(DateTime.parse(dateStr.substring(0, 10)));
      } catch (_) {}
    }
    return dateStr;
  }

  void _showEditDialog(Map<String, dynamic>? existing) {
    final isEdit = existing != null;
    final nameController =
        TextEditingController(text: existing?['name'] as String? ?? '');
    final amountController = TextEditingController(text: '0.00');
    var frequency = existing?['frequency'] as String? ?? 'monthly';
    var interval = (existing?['interval_value'] as num?)?.toInt() ?? 1;
    var invoiceType = existing?['invoice_type'] as String? ?? 'sale';
    var paymentMechanism = existing?['payment_mechanism'] as String? ?? 'credit';
    var currency = existing?['currency'] as String? ?? 'YER';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? 'تعديل القالب' : 'قالب فاتورة متكررة'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'اسم القالب (مثل: إيجار المحل)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: invoiceType,
                      decoration: const InputDecoration(
                        labelText: 'نوع الفاتورة',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'sale', child: Text('فاتورة بيع')),
                        DropdownMenuItem(value: 'purchase', child: Text('فاتورة شراء')),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialogState(() => invoiceType = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: paymentMechanism,
                      decoration: const InputDecoration(
                        labelText: 'آلية الدفع',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'credit', child: Text('آجل')),
                        DropdownMenuItem(value: 'cash', child: Text('نقدي')),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialogState(() => paymentMechanism = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: currency,
                      decoration: const InputDecoration(
                        labelText: 'العملة',
                        border: OutlineInputBorder(),
                      ),
                      items: CurrencyConstants.currencyOptions
                          .map((c) => DropdownMenuItem(
                                value: c,
                                child: Text(
                                    '${CurrencyConstants.currencyLabel(c)} ($c)'),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDialogState(() => currency = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: frequency,
                      decoration: const InputDecoration(
                        labelText: 'التكرار',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'daily', child: Text('يومي')),
                        DropdownMenuItem(value: 'weekly', child: Text('أسبوعي')),
                        DropdownMenuItem(value: 'monthly', child: Text('شهري')),
                        DropdownMenuItem(value: 'yearly', child: Text('سنوي')),
                      ],
                      onChanged: (v) {
                        if (v != null) setDialogState(() => frequency = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'المبلغ الإجمالي',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: interval,
                      decoration: const InputDecoration(
                        labelText: 'كل (فترة)',
                        border: OutlineInputBorder(),
                      ),
                      items: [1, 2, 3, 6, 12]
                          .map((n) => DropdownMenuItem(
                                value: n,
                                child: Text('$n'),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDialogState(() => interval = v);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;
                    final amount = double.tryParse(amountController.text) ?? 0.0;
                    final now = DateTime.now();
                    final template = <String, dynamic>{
                      'name': name,
                      'invoice_type': invoiceType,
                      'payment_mechanism': paymentMechanism,
                      'frequency': frequency,
                      'interval_value': interval,
                      'next_run_date': now.toIso8601String().substring(0, 10),
                      'currency': currency,
                      'exchange_rate': 1.0,
                      'vat_rate': 0.0,
                      'discount_amount': 0,
                      'transport_charges': 0,
                      'notes': null,
                    };
                    final items = <Map<String, dynamic>>[
                      {
                        'product_name': name,
                        'quantity': 1.0,
                        'unit_price': amount,
                        'total_price': amount,
                        'unit_name': 'وحدة',
                        'conversion_factor': 1.0,
                        'base_quantity': 1.0,
                      }
                    ];
                    try {
                      if (isEdit) {
                        await _service.updateTemplate(
                          existing!['id'] as int,
                          template: template,
                          items: items,
                        );
                      } else {
                        await _service.createTemplate(
                          template: template,
                          items: items,
                        );
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _loadTemplates();
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('خطأ: $e'),
                              backgroundColor: AppColors.error),
                        );
                      }
                    }
                  },
                  child: Text(isEdit ? 'حفظ' : 'إنشاء'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDelete(int id, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('حذف القالب "$name"؟ لا يمكن التراجع.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () async {
              await _service.deleteTemplate(id);
              if (ctx.mounted) Navigator.pop(ctx);
              await _loadTemplates();
            },
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
