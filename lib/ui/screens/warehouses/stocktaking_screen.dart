import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/reference_data_repository.dart';
import '../../../data/datasources/repositories/product_repository.dart';
import '../../../data/datasources/services/stock_service.dart';

/// شاشة جرد المخازن - مقارنة المخزون الفعلي بالنظام
class StocktakingScreen extends StatefulWidget {
  const StocktakingScreen({super.key});

  @override
  State<StocktakingScreen> createState() => _StocktakingScreenState();
}

class _StocktakingScreenState extends State<StocktakingScreen> {
  List<Map<String, dynamic>> _warehouses = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;
  bool _isStarting = false;
  bool _isSaving = false;

  int? _selectedWarehouseId;
  Map<int, TextEditingController> _actualQuantityControllers = {};
  String _searchQuery = '';
  final _searchController = TextEditingController();
  final _sessionNotesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _sessionNotesController.dispose();
    for (final c in _actualQuantityControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final warehouses = await locator<ReferenceDataRepository>().getAllWarehouses();
    if (!mounted) return;
    final sessions = await locator<StockService>().getStocktakingSessions();
    if (!mounted) return;
    final products = await locator<ProductRepository>().getAllProducts(activeOnly: true);
    if (!mounted) return;

    setState(() {
      _warehouses = warehouses;
      _sessions = sessions;
      _products = products;
      _isLoading = false;
    });
  }

  List<Map<String, dynamic>> get _filteredProducts {
    var filtered = _products;
    if (_selectedWarehouseId != null) {
      filtered = filtered.where((p) => p['warehouse_id'] == _selectedWarehouseId).toList();
    }
    if (_searchQuery.isEmpty) return filtered;
    final q = _searchQuery.toLowerCase();
    return filtered.where((p) {
      final nameAr = (p['name_ar'] as String? ?? '').toLowerCase();
      return nameAr.contains(q);
    }).toList();
  }

  int get _matchedCount {
    int count = 0;
    for (final p in _filteredProducts) {
      final systemQty = (p['current_stock'] as num?)?.toDouble() ?? 0.0;
      final controller = _actualQuantityControllers[p['id'] as int];
      if (controller != null) {
        final actualQty = double.tryParse(controller.text);
        if (actualQty != null && (actualQty - systemQty).abs() < 0.005) {
          count++;
        }
      }
    }
    return count;
  }

  int get _mismatchedCount {
    int count = 0;
    for (final p in _filteredProducts) {
      final systemQty = (p['current_stock'] as num?)?.toDouble() ?? 0.0;
      final controller = _actualQuantityControllers[p['id'] as int];
      if (controller != null) {
        final actualQty = double.tryParse(controller.text);
        if (actualQty != null && (actualQty - systemQty).abs() >= 0.005) {
          count++;
        }
      }
    }
    return count;
  }

  int get _filledCount {
    int count = 0;
    for (final p in _filteredProducts) {
      final controller = _actualQuantityControllers[p['id'] as int];
      if (controller != null && controller.text.isNotEmpty) {
        count++;
      }
    }
    return count;
  }

  Future<void> _startStocktaking() async {
    setState(() => _isStarting = true);

    // إنشاء أدوات التحكم للكميات الفعلية
    for (final c in _actualQuantityControllers.values) {
      c.dispose();
    }
    _actualQuantityControllers = {};

    for (final product in _filteredProducts) {
      final id = product['id'] as int;
      final systemQty = (product['current_stock'] as num?)?.toDouble() ?? 0.0;
      _actualQuantityControllers[id] = TextEditingController(
        text: systemQty.toStringAsFixed(2),
      );
    }

    setState(() => _isStarting = false);
  }

  /// بناء قائمة عناصر الجرد مع حساب الفرق
  List<Map<String, dynamic>> _buildStocktakingItems() {
    final items = <Map<String, dynamic>>[];
    for (final product in _filteredProducts) {
      final id = product['id'] as int;
      final systemQty = (product['current_stock'] as num?)?.toDouble() ?? 0.0;
      final controller = _actualQuantityControllers[id];
      final actualQty = controller != null ? (double.tryParse(controller.text) ?? systemQty) : systemQty;
      final variance = actualQty - systemQty;

      items.add({
        'product_id': id,
        'product_name': product['name_ar'] as String? ?? '',
        'cost_price': MoneyHelper.readMoney(product['cost_price']),
        'system_quantity': systemQty,
        'actual_quantity': actualQty,
        'difference': variance,
        'variance': variance,
      });
    }
    return items;
  }

  /// عرض مربع حوار المعاينة والتأكيد قبل حفظ الجرد
  Future<bool> _showPreviewDialog() async {
    final items = _buildStocktakingItems();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // حساب الإحصائيات
    final adjustedItems = items.where((i) => (i['variance'] as double).abs() >= 0.005).toList();
    final matchedItems = items.where((i) => (i['variance'] as double).abs() < 0.005).toList();
    final positiveVariance = adjustedItems.where((i) => (i['variance'] as double) > 0).toList();
    final negativeVariance = adjustedItems.where((i) => (i['variance'] as double) < 0).toList();

    double totalPositiveQty = positiveVariance.fold(0.0, (sum, i) => sum + (i['variance'] as double));
    double totalNegativeQty = negativeVariance.fold(0.0, (sum, i) => sum + (i['variance'] as double));
    double totalAdjustmentValue = adjustedItems.fold(0.0, (sum, i) {
      final variance = i['variance'] as double;
      final cost = i['cost_price'] as double;
      return sum + (variance * cost);
    });

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(Icons.fact_check, color: AppColors.primary, size: 28),
                const SizedBox(width: 10),
                Text(
                  'معاينة تعديلات الجرد',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            content: SizedBox(
              width: math.max(MediaQuery.of(ctx).size.width * 0.85, 400),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ملخص إجمالي
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.info.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.info.withOpacity(0.2)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _DialogSummaryChip(
                                  label: 'إجمالي',
                                  value: '${items.length}',
                                  color: AppColors.info,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _DialogSummaryChip(
                                  label: 'مطابق',
                                  value: '${matchedItems.length}',
                                  color: AppColors.textTertiary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _DialogSummaryChip(
                                  label: 'معدّل',
                                  value: '${adjustedItems.length}',
                                  color: AppColors.warning,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _DialogSummaryChip(
                                  label: 'زيادة',
                                  value: '+${totalPositiveQty.toStringAsFixed(1)}',
                                  color: AppColors.success,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _DialogSummaryChip(
                                  label: 'نقص',
                                  value: totalNegativeQty.toStringAsFixed(1),
                                  color: AppColors.error,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _DialogSummaryChip(
                                  label: 'قيمة التعديل',
                                  value: totalAdjustmentValue.toStringAsFixed(0),
                                  color: totalAdjustmentValue >= 0 ? AppColors.success : AppColors.error,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ترويسة الجدول
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                      ),
                      child: Row(
                        children: [
                          Expanded(flex: 3, child: Text('المنتج', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                          SizedBox(
                            width: 55,
                            child: Text('النظام', textAlign: TextAlign.center, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                          ),
                          SizedBox(
                            width: 55,
                            child: Text('الفعلي', textAlign: TextAlign.center, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                          ),
                          SizedBox(
                            width: 60,
                            child: Text('الفرق', textAlign: TextAlign.center, style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                          ),
                        ],
                      ),
                    ),

                    // قائمة المنتجات مع الفرق
                    ...items.map((item) {
                      final variance = item['variance'] as double;
                      final isMatch = variance.abs() < 0.005;
                      final isPositive = variance > 0;
                      final isNegative = variance < 0;

                      // تحديد اللون حسب نوع الفرق
                      Color varianceColor;
                      Color rowBgColor;
                      if (isMatch) {
                        varianceColor = AppColors.textTertiary;
                        rowBgColor = Colors.transparent;
                      } else if (isPositive) {
                        varianceColor = AppColors.success;
                        rowBgColor = AppColors.successLight.withOpacity(isDark ? 0.1 : 0.4);
                      } else {
                        varianceColor = AppColors.error;
                        rowBgColor = AppColors.errorLight.withOpacity(isDark ? 0.1 : 0.4);
                      }

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: rowBgColor,
                          border: Border(
                            bottom: BorderSide(color: AppColors.divider.withOpacity(0.3), width: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                item['product_name'] as String,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: isMatch ? FontWeight.normal : FontWeight.w700,
                                  color: isMatch ? AppColors.textSecondary : AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(
                              width: 55,
                              child: Text(
                                (item['system_quantity'] as double).toStringAsFixed(1),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            SizedBox(
                              width: 55,
                              child: Text(
                                (item['actual_quantity'] as double).toStringAsFixed(1),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            SizedBox(
                              width: 60,
                              child: Text(
                                isMatch ? '0' : (variance > 0 ? '+${variance.toStringAsFixed(1)}' : variance.toStringAsFixed(1)),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: varianceColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    const SizedBox(height: 16),

                    // تحذير
                    if (adjustedItems.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.warning.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'سيتم تعديل مخزون ${adjustedItems.length} منتج بشكل نهائي. هل أنت متأكد من المتابعة؟',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.warning,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.of(ctx).pop(false),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text('إلغاء'),
                style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(ctx).pop(true),
                icon: const Icon(Icons.check_circle, size: 18),
                label: const Text('تأكيد وتطبيق'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        );
      },
    );

    return confirmed ?? false;
  }

  Future<void> _saveStocktaking() async {
    if (_filledCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يرجى إدخال الكميات الفعلية'), backgroundColor: AppColors.warning),
      );
      return;
    }

    // عرض معاينة التعديلات والتأكيد
    final confirmed = await _showPreviewDialog();
    if (!confirmed) return;

    setState(() => _isSaving = true);

    final now = DateTime.now();

    // توليد رقم الجرد
    final sessionNumber = 'SK-${(_sessions.length + 1).toString().padLeft(4, '0')}';

    final sessionMap = {
      'session_number': sessionNumber,
      'warehouse_id': _selectedWarehouseId,
      'date': now.toIso8601String().substring(0, 10),
      'total_items': _filteredProducts.length,
      'matched_items': _matchedCount,
      'mismatched_items': _mismatchedCount,
      'status': 'draft',
      'notes': _sessionNotesController.text.trim().isEmpty ? null : _sessionNotesController.text.trim(),
      'created_at': now.toIso8601String(),
    };

    // بناء عناصر الجرد مع الفرق
    final items = _buildStocktakingItems().map((item) => {
      'product_id': item['product_id'],
      'system_quantity': item['system_quantity'],
      'actual_quantity': item['actual_quantity'],
      'difference': item['difference'],
      'variance': item['variance'],
    }).toList();

    final sessionId = await locator<StockService>().createStocktakingSession(sessionMap, items);

    // إكمال الجرد وتحديث المخزون
    await locator<StockService>().completeStocktakingSession(sessionId);

    if (mounted) {
      setState(() {
        _isSaving = false;
        _actualQuantityControllers = {};
        _sessionNotesController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ الجرد وتحديث المخزون بنجاح'), backgroundColor: AppColors.success),
      );

      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasActiveStocktaking = _actualQuantityControllers.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('جرد المخازن'),
        actions: [
          if (hasActiveStocktaking)
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'حفظ الجرد',
              onPressed: _isSaving ? null : _saveStocktaking,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // اختيار المخزن
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'بدء جرد جديد',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<int>(
                            value: _selectedWarehouseId,
                            decoration: InputDecoration(
                              labelText: 'اختر المخزن (اختياري - الكل إذا لم يتم الاختيار)',
                              prefixIcon: const Icon(Icons.warehouse, size: 20),
                              filled: true,
                              fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            items: [
                              const DropdownMenuItem<int>(
                                value: null,
                                child: Text('جميع المستودعات'),
                              ),
                              ..._warehouses.map((w) => DropdownMenuItem<int>(
                                    value: w['id'] as int,
                                    child: Text(w['name'] as String),
                                  )),
                            ],
                            onChanged: (v) => setState(() => _selectedWarehouseId = v),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _sessionNotesController,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'ملاحظات الجرد (اختياري)',
                              prefixIcon: Icon(Icons.note),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _isStarting ? null : _startStocktaking,
                              icon: _isStarting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.play_arrow, size: 22),
                              label: const Text('بدء الجرد'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ملخص الجرد
                  if (hasActiveStocktaking) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.info.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.info.withOpacity(0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ملخص الجرد',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.info,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _SummaryChip(
                                label: 'إجمالي',
                                value: '${_filteredProducts.length}',
                                color: AppColors.info,
                              ),
                              const SizedBox(width: 8),
                              _SummaryChip(
                                label: 'مطابق',
                                value: '$_matchedCount',
                                color: AppColors.success,
                              ),
                              const SizedBox(width: 8),
                              _SummaryChip(
                                label: 'مختلف',
                                value: '$_mismatchedCount',
                                color: AppColors.error,
                              ),
                              const SizedBox(width: 8),
                              _SummaryChip(
                                label: 'مكتمل',
                                value: '$_filledCount',
                                color: AppColors.primary,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // بحث في المنتجات
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'بحث عن منتج...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                    const SizedBox(height: 12),

                    // قائمة المنتجات للجرد
                    ..._filteredProducts.map((product) {
                      final id = product['id'] as int;
                      final nameAr = product['name_ar'] as String? ?? '';
                      final systemQty = (product['current_stock'] as num?)?.toDouble() ?? 0.0;
                      final controller = _actualQuantityControllers[id];
                      if (controller == null) return const SizedBox.shrink();

                      final actualQty = double.tryParse(controller.text) ?? systemQty;
                      final difference = actualQty - systemQty;
                      final isMatch = difference.abs() < 0.005;

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        color: isMatch
                            ? AppColors.successLight.withOpacity(isDark ? 0.15 : 1.0)
                            : (difference < 0 ? AppColors.errorLight.withOpacity(isDark ? 0.15 : 1.0) : AppColors.warningLight.withOpacity(isDark ? 0.15 : 1.0)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  nameAr,
                                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // الكمية بالنظام
                              SizedBox(
                                width: 60,
                                child: Column(
                                  children: [
                                    Text('النظام', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
                                    Text(
                                      systemQty.toStringAsFixed(1),
                                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              // الكمية الفعلية
                              SizedBox(
                                width: 80,
                                child: TextFormField(
                                  controller: controller,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: isMatch ? AppColors.success : AppColors.error,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: isMatch ? AppColors.success : AppColors.error,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: BorderSide(
                                        color: isMatch ? AppColors.success : AppColors.error,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // الفرق
                              SizedBox(
                                width: 60,
                                child: Column(
                                  children: [
                                    Text('الفرق', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textHint)),
                                    Text(
                                      difference >= 0 ? '+${difference.toStringAsFixed(1)}' : difference.toStringAsFixed(1),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: isMatch ? AppColors.success : AppColors.error,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                    // زر حفظ الجرد
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveStocktaking,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check_circle, size: 22),
                        label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ الجرد وتحديث المخزون'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // جلسات الجرد السابقة
                  Text(
                    'جلسات الجرد السابقة',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_sessions.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.fact_check, size: 48, color: AppColors.textHint),
                            const SizedBox(height: 8),
                            Text(
                              'لا توجد جلسات جرد',
                              style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textHint),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._sessions.take(10).map((session) => _SessionCard(session: session, isDark: isDark)),
                ],
              ),
            ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: color),
            ),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// شريحة ملخص داخل مربع الحوار
class _DialogSummaryChip extends StatelessWidget {
  const _DialogSummaryChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: color),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.isDark,
  });

  final Map<String, dynamic> session;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessionNumber = session['session_number'] as String? ?? '';
    final warehouseName = session['warehouse_name'] as String? ?? 'جميع المستودعات';
    final date = session['date'] as String? ?? '';
    final status = session['status'] as String? ?? 'draft';
    final totalItems = (session['total_items'] as num?)?.toInt() ?? 0;
    final matched = (session['matched_items'] as num?)?.toInt() ?? 0;
    final mismatched = (session['mismatched_items'] as num?)?.toInt() ?? 0;
    final isCompleted = status == 'completed';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (isCompleted ? AppColors.success : AppColors.warning).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isCompleted ? Icons.check_circle : Icons.pending,
                color: isCompleted ? AppColors.success : AppColors.warning,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$sessionNumber - $warehouseName',
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'التاريخ: $date | مطابق: $matched | مختلف: $mismatched',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (isCompleted ? AppColors.success : AppColors.warning).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isCompleted ? 'مكتمل' : 'مسودة',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isCompleted ? AppColors.success : AppColors.warning,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
