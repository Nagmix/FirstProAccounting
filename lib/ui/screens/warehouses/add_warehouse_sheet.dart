import 'package:flutter/material.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/repositories/reference_data_repository.dart';

class AddWarehouseSheet extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const AddWarehouseSheet({super.key, this.existing});

  @override
  State<AddWarehouseSheet> createState() => _AddWarehouseSheetState();
}

class _AddWarehouseSheetState extends State<AddWarehouseSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  bool _isSaving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameController.text = widget.existing!['name'] as String? ?? '';
      _locationController.text = widget.existing!['location'] as String? ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final now = DateTime.now().toIso8601String();
    final warehouseMap = {
      'name': _nameController.text.trim(),
      'location': _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
      'is_active': 1,
      'updated_at': now,
    };

    final refRepo = locator<ReferenceDataRepository>();
    if (_isEdit) {
      await refRepo.updateWarehouse(
          widget.existing!['id'] as int, warehouseMap);
    } else {
      warehouseMap['created_at'] = now;
      await refRepo.insertWarehouse(warehouseMap);
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'تم ${_isEdit ? 'تعديل' : 'إضافة'} "${_nameController.text}" بنجاح'),
        backgroundColor: AppColors.success,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                _isEdit ? 'تعديل المستودع' : 'إضافة مستودع',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Name field
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'اسم المستودع',
                  prefixIcon: Icon(Icons.warehouse),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'اسم المستودع مطلوب'
                    : null,
              ),
              const SizedBox(height: 14),

              // Location field
              TextFormField(
                controller: _locationController,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'الموقع (اختياري)',
                  prefixIcon: Icon(Icons.location_on),
                ),
              ),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check, size: 20),
                      label: Text(_isSaving ? 'جاري الحفظ...' : 'حفظ'),
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
                      onPressed:
                          _isSaving ? null : () => Navigator.of(context).pop(),
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
    );
  }
}
