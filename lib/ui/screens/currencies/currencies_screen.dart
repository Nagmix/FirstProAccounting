import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/currency_model.dart';

/// Currency management screen for the FirstPro accounting app.
///
/// Features:
/// - List all currencies with exchange rates
/// - Add/edit currency
/// - Set default currency
/// - Toggle active/inactive
class CurrenciesScreen extends StatefulWidget {
  const CurrenciesScreen({super.key});

  @override
  State<CurrenciesScreen> createState() => _CurrenciesScreenState();
}

class _CurrenciesScreenState extends State<CurrenciesScreen> {
  List<Currency> _currencies = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrencies();
  }

  Future<void> _loadCurrencies() async {
    setState(() => _isLoading = true);
    try {
      final db = DatabaseHelper();
      final maps = await db.getAllCurrencies();
      if (mounted) {
        setState(() {
          _currencies = maps.map((m) => Currency.fromMap(m)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء تحميل البيانات'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _setDefault(Currency currency) async {
    final db = DatabaseHelper();
    await db.setDefaultCurrency(currency.id!);
    _loadCurrencies();
  }

  Future<void> _toggleActive(Currency currency) async {
    final db = DatabaseHelper();
    await db.updateCurrency(currency.id!, {
      'is_active': currency.isActive ? 0 : 1,
    });
    _loadCurrencies();
  }

  Future<void> _showAddEditSheet({Currency? existing}) async {
    final codeController = TextEditingController(text: existing?.code ?? '');
    final nameArController = TextEditingController(text: existing?.nameAr ?? '');
    final nameEnController = TextEditingController(text: existing?.nameEn ?? '');
    final symbolController = TextEditingController(text: existing?.symbol ?? '');
    final rateController = TextEditingController(
      text: existing?.exchangeRate.toStringAsFixed(4) ?? '1.0000',
    );
    final isEdit = existing != null;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isEdit ? 'تعديل العملة' : 'إضافة عملة جديدة',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: codeController,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'رمز العملة',
                    prefixIcon: Icon(Icons.attach_money),
                    hintText: 'USD',
                  ),
                  enabled: !isEdit,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: nameArController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'الاسم بالعربية',
                    prefixIcon: Icon(Icons.text_fields),
                    hintText: 'دولار أمريكي',
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: nameEnController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'الاسم بالإنجليزية',
                    prefixIcon: Icon(Icons.text_fields),
                    hintText: 'US Dollar',
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: symbolController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'الرمز',
                    prefixIcon: Icon(Icons.paid),
                    hintText: 'USD',
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: rateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,6}')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'سعر الصرف (إلى العملة الأساسية)',
                    prefixIcon: Icon(Icons.swap_horiz),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final code = codeController.text.trim().toUpperCase();
                          final nameAr = nameArController.text.trim();
                          final nameEn = nameEnController.text.trim();
                          final symbol = symbolController.text.trim();
                          final rate = double.tryParse(rateController.text) ?? 1.0;

                          if (code.isEmpty || nameAr.isEmpty || nameEn.isEmpty || symbol.isEmpty) {
                            return;
                          }

                          final db = DatabaseHelper();
                          if (isEdit) {
                            await db.updateCurrency(existing.id!, {
                              'name_ar': nameAr,
                              'name_en': nameEn,
                              'symbol': symbol,
                              'exchange_rate': rate,
                            });
                          } else {
                            await db.insertCurrency({
                              'code': code,
                              'name_ar': nameAr,
                              'name_en': nameEn,
                              'symbol': symbol,
                              'exchange_rate': rate,
                              'is_default': 0,
                              'is_active': 1,
                              'created_at': DateTime.now().toIso8601String(),
                            });
                          }

                          if (ctx.mounted) Navigator.pop(ctx);
                          _loadCurrencies();
                        },
                        icon: const Icon(Icons.check, size: 20),
                        label: const Text('حفظ'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('إلغاء'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    _loadCurrencies();
  }

  Future<void> _deleteCurrency(Currency currency) async {
    if (currency.isDefault) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكن حذف العملة الافتراضية'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning, color: AppColors.error, size: 40),
        title: const Text('حذف العملة'),
        content: Text('هل أنت متأكد من حذف "${currency.nameAr}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final db = DatabaseHelper();
      await db.deleteCurrency(currency.id!);
      _loadCurrencies();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة العملات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'إضافة عملة',
            onPressed: () => _showAddEditSheet(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currencies.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.attach_money,
                          size: 72, color: AppColors.textHint),
                      const SizedBox(height: 16),
                      Text('لا توجد عملات',
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text('أضف عملة جديدة للبدء',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: _currencies.length,
                  itemBuilder: (context, index) {
                    final currency = _currencies[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: InkWell(
                        onTap: () => _showAddEditSheet(existing: currency),
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              // ── Icon ────────────────────────────
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: currency.isDefault
                                      ? AppColors.primary.withOpacity(0.12)
                                      : (isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    currency.symbol,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: currency.isDefault
                                          ? AppColors.primary
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),

                              // ── Info ────────────────────────────
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          currency.nameAr,
                                          style: theme.textTheme.bodyLarge?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: currency.isDefault
                                                ? AppColors.primary.withOpacity(0.1)
                                                : AppColors.surfaceVariant,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            currency.code,
                                            style: theme.textTheme.labelSmall?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: currency.isDefault
                                                  ? AppColors.primary
                                                  : null,
                                            ),
                                          ),
                                        ),
                                        if (currency.isDefault) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.successLight,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'افتراضية',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.success,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'سعر الصرف: ${currency.exchangeRate.toStringAsFixed(4)}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: isDark
                                            ? AppColors.darkTextSecondary
                                            : AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // ── Actions ────────────────────────
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!currency.isDefault)
                                    IconButton(
                                      icon: Icon(
                                        Icons.star,
                                        size: 20,
                                        color: AppColors.textHint,
                                      ),
                                      tooltip: 'تعيين كافتراضية',
                                      onPressed: () => _setDefault(currency),
                                    ),
                                  Switch(
                                    value: currency.isActive,
                                    activeColor: AppColors.primary,
                                    onChanged: (_) => _toggleActive(currency),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.delete,
                                      size: 20,
                                      color: currency.isDefault
                                          ? AppColors.textDisabled
                                          : AppColors.error,
                                    ),
                                    tooltip: 'حذف',
                                    onPressed: currency.isDefault
                                        ? null
                                        : () => _deleteCurrency(currency),
                                  ),
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
        onPressed: () => _showAddEditSheet(),
        tooltip: 'إضافة عملة',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}
