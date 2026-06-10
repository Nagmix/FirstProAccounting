import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/product_repository.dart';
import '../../../data/datasources/repositories/reference_data_repository.dart';
import '../../../data/models/unit_model.dart';

/// Units Master screen - manages the library of measurement units.
///
/// Displays all units grouped by type (count, weight, liquid, packaging, pharmacy)
/// with CRUD operations. Units are used in product definitions for base unit,
/// purchase unit, and sale unit assignments.
class UnitsScreen extends StatefulWidget {
  const UnitsScreen({super.key});

  @override
  State<UnitsScreen> createState() => _UnitsScreenState();
}

class _UnitsScreenState extends State<UnitsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Unit> _allUnits = [];
  bool _isLoading = true;
  String _searchQuery = '';

  static const _tabTypes = ['all', 'count', 'weight', 'liquid', 'packaging', 'pharmacy'];
  static const _tabLabels = ['الكل', 'عد', 'وزن', 'سوائل', 'تغليف', 'صيدلية'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabTypes.length, vsync: this);
    _loadUnits();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUnits() async {
    setState(() => _isLoading = true);
    try {
      final rawUnits = await locator<ReferenceDataRepository>().getAllUnits();
      if (!mounted) return;
      setState(() {
        _allUnits = rawUnits.map((m) => Unit.fromMap(m)).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء تحميل البيانات'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  List<Unit> _filteredUnits(String type) {
    var filtered = _allUnits;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery;
      filtered = filtered.where((u) =>
        u.nameAr.contains(q) || u.nameEn.toLowerCase().contains(q.toLowerCase()) || u.abbreviation.contains(q)
      ).toList();
    }
    if (type != 'all') {
      filtered = filtered.where((u) => u.unitType == type).toList();
    }
    filtered.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return filtered;
  }

  Future<void> _showAddEditUnitDialog({Unit? existing}) async {
    final nameArController = TextEditingController(text: existing?.nameAr ?? '');
    final nameEnController = TextEditingController(text: existing?.nameEn ?? '');
    final abbrController = TextEditingController(text: existing?.abbreviation ?? '');
    final descController = TextEditingController(text: existing?.description ?? '');
    final orderController = TextEditingController(text: (existing?.displayOrder ?? 0).toString());

    String selectedType = existing?.unitType ?? 'count';
    bool isActive = existing?.isActive ?? true;
    bool isSellable = existing?.isSellable ?? true;
    bool isPurchasable = existing?.isPurchasable ?? true;
    bool isPackaging = existing?.isPackaging ?? false;
    bool isBaseUnit = existing?.isBaseUnit ?? false;

    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.straighten, color: AppColors.primary, size: 22),
                  const SizedBox(width: 8),
                  Text(existing != null ? 'تعديل وحدة' : 'إضافة وحدة جديدة', style: const TextStyle(fontSize: 18)),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Name Arabic
                      TextFormField(
                        controller: nameArController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'اسم الوحدة بالعربي *',
                          prefixIcon: Icon(Icons.text_fields),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'اسم الوحدة مطلوب' : null,
                      ),
                      const SizedBox(height: 12),

                      // Name English
                      TextFormField(
                        controller: nameEnController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'اسم الوحدة بالإنجليزي',
                          prefixIcon: Icon(Icons.text_fields),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Abbreviation
                      TextFormField(
                        controller: abbrController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'الاختصار',
                          hintText: 'مثال: كجم، حبة، ل',
                          prefixIcon: Icon(Icons.short_text),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Unit Type
                      DropdownButtonFormField<String>(
                        value: selectedType,
                        decoration: const InputDecoration(
                          labelText: 'نوع الوحدة *',
                          prefixIcon: Icon(Icons.category),
                        ),
                        items: Unit.unitTypeLabels.entries
                            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                            .toList(),
                        onChanged: (v) => setDialogState(() => selectedType = v ?? 'count'),
                      ),
                      const SizedBox(height: 12),

                      // Description
                      TextFormField(
                        controller: descController,
                        textInputAction: TextInputAction.next,
                        maxLines: 2,
                        minLines: 1,
                        decoration: const InputDecoration(
                          labelText: 'وصف (اختياري)',
                          prefixIcon: Icon(Icons.edit_note),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Display Order
                      TextFormField(
                        controller: orderController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'ترتيب العرض',
                          prefixIcon: Icon(Icons.sort),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Flags
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          FilterChip(
                            label: const Text('مفعلة'),
                            selected: isActive,
                            onSelected: (v) => setDialogState(() => isActive = v),
                            selectedColor: AppColors.successLight,
                          ),
                          FilterChip(
                            label: const Text('قابلة للبيع'),
                            selected: isSellable,
                            onSelected: (v) => setDialogState(() => isSellable = v),
                            selectedColor: AppColors.infoLight,
                          ),
                          FilterChip(
                            label: const Text('قابلة للشراء'),
                            selected: isPurchasable,
                            onSelected: (v) => setDialogState(() => isPurchasable = v),
                            selectedColor: AppColors.infoLight,
                          ),
                          FilterChip(
                            label: const Text('وحدة تغليف'),
                            selected: isPackaging,
                            onSelected: (v) => setDialogState(() => isPackaging = v),
                            selectedColor: AppColors.warningLight,
                          ),
                          FilterChip(
                            label: const Text('وحدة أساسية'),
                            selected: isBaseUnit,
                            onSelected: (v) => setDialogState(() => isBaseUnit = v),
                            selectedColor: AppColors.primaryLight.withValues(alpha: 0.2),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    Navigator.of(context).pop(true);
                  },
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(existing != null ? 'حفظ' : 'إضافة'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true) {
      final now = DateTime.now().toIso8601String();
      final unitMap = {
        'name_ar': nameArController.text.trim(),
        'name_en': nameEnController.text.trim(),
        'abbreviation': abbrController.text.trim(),
        'unit_type': selectedType,
        'description': descController.text.trim().isNotEmpty ? descController.text.trim() : null,
        'is_active': isActive ? 1 : 0,
        'is_sellable': isSellable ? 1 : 0,
        'is_purchasable': isPurchasable ? 1 : 0,
        'is_packaging': isPackaging ? 1 : 0,
        'is_base_unit': isBaseUnit ? 1 : 0,
        'display_order': int.tryParse(orderController.text) ?? 0,
        'updated_at': now,
      };

      try {
        final refRepo = locator<ReferenceDataRepository>();
        if (existing != null) {
          await refRepo.updateUnit(existing.id!, unitMap);
        } else {
          unitMap['created_at'] = now;
          await refRepo.insertUnit(unitMap);
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(existing != null ? 'تم تعديل الوحدة بنجاح' : 'تم إضافة الوحدة بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadUnits();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ غير متوقع'), backgroundColor: AppColors.error),
        );
      }
    }

    nameArController.dispose();
    nameEnController.dispose();
    abbrController.dispose();
    descController.dispose();
    orderController.dispose();
  }

  Future<void> _deleteUnit(Unit unit) async {
    // Pre-check: verify no products reference this unit before showing confirmation
    try {
      final productsWithUnit = await locator<ProductRepository>().getProductsByUnitId(unit.id!);
      if (productsWithUnit.isNotEmpty) {
        if (!mounted) return;
        final productNames = productsWithUnit.map((p) => p['name_ar'] as String? ?? '').join('، ');
        final extra = productsWithUnit.length > 5 ? ' وغيرها...' : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('لا يمكن حذف الوحدة "${unit.nameAr}" لأنها مستخدمة في الأصناف: $productNames$extra'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    } catch (e) {
      debugPrint('UnitsScreen._deleteUnit: $e');
      // If pre-check fails, let the actual delete handle it
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف الوحدة "${unit.nameAr}"؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await locator<ReferenceDataRepository>().deleteUnit(unit.id!);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف الوحدة'), backgroundColor: AppColors.success),
        );
        _loadUnits();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ غير متوقع'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الوحدات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'إضافة وحدة',
            onPressed: () => _showAddEditUnitDialog(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: _tabLabels.map((l) => Tab(text: l)).toList(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Search
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SearchBar(
                    hintText: 'بحث بالاسم أو الاختصار...',
                    leading: const Icon(Icons.search),
                    padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 16)),
                    onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  ),
                ),
                // Unit list
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: _tabTypes.map((type) {
                      final units = _filteredUnits(type);
                      if (units.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.straighten, size: 64, color: AppColors.textHint.withValues(alpha: 0.5)),
                              const SizedBox(height: 12),
                              Text('لا توجد وحدات', style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
                            ],
                          ),
                        );
                      }
                      return RefreshIndicator(
                        onRefresh: _loadUnits,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                          itemCount: units.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final unit = units[index];
                            return _UnitCard(
                              unit: unit,
                              onEdit: () => _showAddEditUnitDialog(existing: unit),
                              onDelete: () => _deleteUnit(unit),
                            );
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditUnitDialog(),
        tooltip: 'إضافة وحدة جديدة',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _UnitCard extends StatelessWidget {
  final Unit unit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _UnitCard({required this.unit, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Unit type icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _typeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_typeIcon, color: _typeColor, size: 22),
              ),
              const SizedBox(width: 14),
              // Name and details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(unit.nameAr, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                        if (unit.abbreviation.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(unit.abbreviation, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.primary)),
                          ),
                        ],
                        const SizedBox(width: 6),
                        Text(Unit.unitTypeLabels[unit.unitType] ?? '', style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textSecondary)),
                      ],
                    ),
                    if (unit.nameEn.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(unit.nameEn, style: theme.textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                    ],
                    const SizedBox(height: 4),
                    // Flags row
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: [
                        if (unit.isBaseUnit) _flagChip('أساسية', AppColors.primary),
                        if (unit.isSellable) _flagChip('بيع', AppColors.success),
                        if (unit.isPurchasable) _flagChip('شراء', AppColors.info),
                        if (unit.isPackaging) _flagChip('تغليف', AppColors.warning),
                        if (!unit.isActive) _flagChip('معطلة', AppColors.error),
                      ],
                    ),
                  ],
                ),
              ),
              // Actions
              IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: onEdit, tooltip: 'تعديل'),
              IconButton(icon: Icon(Icons.delete, size: 20, color: AppColors.error.withValues(alpha: 0.7)), onPressed: onDelete, tooltip: 'حذف'),
            ],
          ),
        ),
      ),
    );
  }

  Color get _typeColor {
    switch (unit.unitType) {
      case 'count': return AppColors.primary;
      case 'weight': return AppColors.secondary;
      case 'liquid': return AppColors.info;
      case 'packaging': return AppColors.warning;
      case 'pharmacy': return AppColors.accentPink;
      default: return AppColors.textSecondary;
    }
  }

  IconData get _typeIcon {
    switch (unit.unitType) {
      case 'count': return Icons.calculate;
      case 'weight': return Icons.monitor_weight;
      case 'liquid': return Icons.water_drop;
      case 'packaging': return Icons.inventory_2;
      case 'pharmacy': return Icons.medication;
      default: return Icons.straighten;
    }
  }

  Widget _flagChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
