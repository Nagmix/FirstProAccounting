import 'package:flutter/material.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/services/production_service.dart';
import 'package:firstpro/data/models/production_order_model.dart';

class ProductionOrdersScreen extends StatefulWidget {
  const ProductionOrdersScreen({
    super.key,
    this.onCreateDraft,
    this.onPostProduction,
  });

  final Future<void> Function(ProductionOrder order)? onCreateDraft;
  final Future<void> Function(String orderId)? onPostProduction;

  @override
  State<ProductionOrdersScreen> createState() => _ProductionOrdersScreenState();
}

class _ProductionOrdersScreenState extends State<ProductionOrdersScreen> {
  final _recipeController = TextEditingController();
  final _outputController = TextEditingController();
  final _quantityController = TextEditingController();
  final _notesController = TextEditingController();
  bool _loading = false;
  ProductionOrder? _draft;

  @override
  void dispose() {
    _recipeController.dispose();
    _outputController.dispose();
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _createDraft() async {
    final recipeId = int.tryParse(_recipeController.text.trim());
    final outputProductId = int.tryParse(_outputController.text.trim());
    final quantity = double.tryParse(_quantityController.text.trim());
    if (recipeId == null || outputProductId == null || recipeId <= 0 || outputProductId <= 0) {
      _showError('أدخل معرف الوصفة والمنتج التام بشكل صحيح');
      return;
    }
    if (quantity == null || !quantity.isFinite || quantity <= 0) {
      _showError('أدخل كمية إنتاج أكبر من صفر');
      return;
    }

    final now = DateTime.now();
    final id = 'PR-${now.millisecondsSinceEpoch}';
    final order = ProductionOrder(
      id: id,
      orderNumber: id,
      recipeId: recipeId,
      outputProductId: outputProductId,
      plannedQuantity: quantity,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      createdAt: now,
      updatedAt: now,
    );
    setState(() => _loading = true);
    try {
      final create = widget.onCreateDraft ??
          (ProductionOrder value) => locator<ProductionService>().createDraft(order: value);
      await create(order);
      if (!mounted) return;
      setState(() => _draft = order);
      _showSuccess('تم إنشاء مسودة أمر الإنتاج $id');
    } catch (error) {
      if (mounted) _showError('تعذر إنشاء مسودة الإنتاج: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _postProduction() async {
    final order = _draft;
    if (order == null) return;
    setState(() => _loading = true);
    try {
      final post = widget.onPostProduction ??
          (String value) => locator<ProductionService>().postProduction(orderId: value);
      await post(order.id);
      if (mounted) _showSuccess('تم ترحيل أمر الإنتاج ${order.orderNumber}');
    } catch (error) {
      if (mounted) _showError('تعذر ترحيل أمر الإنتاج: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return Scaffold(
      appBar: AppBar(title: const Text('الإنتاج والوصفات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'إنشاء أمر إنتاج',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'أنشئ مسودة أولاً، ثم راجعها قبل استهلاك الخام وإضافة المنتج التام.',
          ),
          const SizedBox(height: 16),
          _numberField(
            key: const Key('recipe-id'),
            controller: _recipeController,
            label: 'معرف الوصفة',
          ),
          const SizedBox(height: 12),
          _numberField(
            key: const Key('output-product-id'),
            controller: _outputController,
            label: 'معرف المنتج التام',
          ),
          const SizedBox(height: 12),
          _numberField(
            key: const Key('planned-quantity'),
            controller: _quantityController,
            label: 'الكمية المخططة',
            decimal: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'ملاحظات (اختياري)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('create-production-draft'),
            onPressed: _loading ? null : _createDraft,
            icon: const Icon(Icons.save_outlined),
            label: const Text('حفظ كمسودة'),
          ),
          if (draft != null) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'مسودة جاهزة للمراجعة',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('رقم الأمر: ${draft.orderNumber}'),
                    Text('الكمية: ${draft.plannedQuantity}'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('post-production'),
                      onPressed: _loading ? null : _postProduction,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('ترحيل الإنتاج'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _numberField({
    required Key key,
    required TextEditingController controller,
    required String label,
    bool decimal = false,
  }) {
    return TextField(
      key: key,
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    );
  }
}
