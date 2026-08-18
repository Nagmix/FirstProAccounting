import 'package:flutter/material.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/services/inventory_adjustment_service.dart';

class InventoryAdjustmentScreen extends StatefulWidget {
  const InventoryAdjustmentScreen({
    super.key,
    this.onCreateDraft,
    this.onConfirm,
  });

  final Future<int> Function(InventoryAdjustmentDraft draft)? onCreateDraft;
  final Future<void> Function(int voucherId)? onConfirm;

  @override
  State<InventoryAdjustmentScreen> createState() =>
      _InventoryAdjustmentScreenState();
}

class _InventoryAdjustmentScreenState extends State<InventoryAdjustmentScreen> {
  final _voucherController = TextEditingController();
  final _productController = TextEditingController();
  final _quantityController = TextEditingController();
  final _factorController = TextEditingController(text: '1');
  final _unitCostController = TextEditingController();
  final _notesController = TextEditingController();
  bool _loading = false;
  int? _voucherId;

  @override
  void dispose() {
    _voucherController.dispose();
    _productController.dispose();
    _quantityController.dispose();
    _factorController.dispose();
    _unitCostController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _createDraft() async {
    final voucherNumber = _voucherController.text.trim();
    final productId = int.tryParse(_productController.text.trim());
    final countedQuantity = double.tryParse(_quantityController.text.trim());
    final factor = double.tryParse(_factorController.text.trim());
    final unitCost = double.tryParse(_unitCostController.text.trim());
    if (voucherNumber.isEmpty || productId == null || productId <= 0) {
      _showError('أدخل رقم السند ومعرف الصنف بشكل صحيح');
      return;
    }
    if (countedQuantity == null || !countedQuantity.isFinite || countedQuantity < 0) {
      _showError('الكمية الفعلية لا يمكن أن تكون سالبة');
      return;
    }
    if (factor == null || !factor.isFinite || factor <= 0) {
      _showError('معامل التحويل يجب أن يكون أكبر من صفر');
      return;
    }
    if (unitCost == null || !unitCost.isFinite || unitCost < 0) {
      _showError('أدخل تكلفة وحدة صحيحة');
      return;
    }

    final draft = InventoryAdjustmentDraft(
      voucherNumber: voucherNumber,
      date: DateTime.now().toIso8601String(),
      description: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      lines: [
        InventoryAdjustmentLine(
          productId: productId,
          actualQuantity: countedQuantity,
          conversionFactor: factor,
          unitCost: unitCost,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        ),
      ],
    );
    setState(() => _loading = true);
    try {
      final create = widget.onCreateDraft ??
          (InventoryAdjustmentDraft value) =>
              locator<InventoryAdjustmentService>().createDraft(value);
      final id = await create(draft);
      if (!mounted) return;
      setState(() => _voucherId = id);
      _showSuccess('تم إنشاء مسودة تسوية الجرد ${draft.voucherNumber}');
    } catch (error) {
      if (mounted) _showError('تعذر إنشاء مسودة الجرد: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    final id = _voucherId;
    if (id == null) return;
    setState(() => _loading = true);
    try {
      final confirm = widget.onConfirm ??
          (int value) => locator<InventoryAdjustmentService>().confirm(value);
      await confirm(id);
      if (mounted) _showSuccess('تم اعتماد تسوية الجرد رقم $id');
    } catch (error) {
      if (mounted) _showError('تعذر اعتماد تسوية الجرد: $error');
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
    return Scaffold(
      appBar: AppBar(title: const Text('تسوية وجرد المخزون')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'تسوية جرد جديدة',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'أدخل الكمية بوحدة البيع ومعامل التحويل. سيحفظ النظام الكمية الأساسية قبل الاعتماد.',
          ),
          const SizedBox(height: 16),
          _field(const Key('voucher-number'), _voucherController, 'رقم سند الجرد'),
          const SizedBox(height: 12),
          _field(const Key('product-id'), _productController, 'معرف الصنف', number: true),
          const SizedBox(height: 12),
          _field(
            const Key('actual-quantity'),
            _quantityController,
            'الكمية الفعلية بوحدة البيع',
            number: true,
            decimal: true,
          ),
          const SizedBox(height: 12),
          _field(
            const Key('conversion-factor'),
            _factorController,
            'معامل التحويل إلى الوحدة الأساسية',
            number: true,
            decimal: true,
          ),
          const SizedBox(height: 12),
          _field(
            const Key('unit-cost'),
            _unitCostController,
            'تكلفة الوحدة الأساسية',
            number: true,
            decimal: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'سبب التسوية أو ملاحظات',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('create-inventory-draft'),
            onPressed: _loading ? null : _createDraft,
            icon: const Icon(Icons.save_outlined),
            label: const Text('حفظ كمسودة'),
          ),
          if (_voucherId != null) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'المسودة جاهزة للاعتماد',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('رقم السند الداخلي: $_voucherId'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('confirm-inventory-adjustment'),
                      onPressed: _loading ? null : _confirm,
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('اعتماد التسوية'),
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

  Widget _field(
    Key key,
    TextEditingController controller,
    String label, {
    bool number = false,
    bool decimal = false,
  }) {
    return TextField(
      key: key,
      controller: controller,
      keyboardType: number
          ? TextInputType.numberWithOptions(decimal: decimal)
          : TextInputType.text,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    );
  }
}
