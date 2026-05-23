import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/supplier_model.dart';
import '../../widgets/empty_state.dart';
import 'add_supplier_sheet.dart';

/// Professional suppliers management screen for the FirstPro accounting app.
///
/// Features:
/// - Search bar for filtering by name or phone.
/// - Supplier list with avatar, name, phone, and balance.
/// - FAB for adding a new supplier via [AddSupplierSheet].
/// - Tap to edit, long press to delete with confirmation.
/// - Empty state when no suppliers exist.
class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<Supplier> _suppliers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim());
    });
    _loadSuppliers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Load suppliers from database ──────────────────────────────
  Future<void> _loadSuppliers() async {
    setState(() => _isLoading = true);
    final db = DatabaseHelper();
    final maps = await db.getAllSuppliers();
    setState(() {
      _suppliers = maps.map((m) => Supplier.fromMap(m)).toList();
      _isLoading = false;
    });
  }

  // ── Filter logic ──────────────────────────────────────────────
  List<Supplier> get _filteredSuppliers {
    var filtered = _suppliers;

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery;
      filtered = filtered.where((s) {
        final nameMatch = s.name.contains(q);
        final phoneMatch = s.phone?.contains(q) ?? false;
        return nameMatch || phoneMatch;
      }).toList();
    }

    return filtered;
  }

  // ── Open add-supplier bottom sheet ────────────────────────────
  Future<void> _showAddSupplierSheet({Supplier? supplier}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => AddSupplierSheet(supplier: supplier),
    );
    _loadSuppliers();
  }

  // ── Delete supplier ───────────────────────────────────────────
  Future<void> _deleteSupplier(Supplier supplier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning,
            color: AppColors.error, size: 40),
        title: const Text('حذف المورد'),
        content: Text('هل أنت متأكد من حذف المورد "${supplier.name}"؟'),
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
      await db.deleteSupplier(supplier.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حذف المورد "${supplier.name}"'),
            backgroundColor: AppColors.success,
          ),
        );
      }
      _loadSuppliers();
    }
  }

  // ── Avatar color based on name ────────────────────────────────
  static const List<Color> _avatarColors = [
    Color(0xFF1A237E),
    Color(0xFF0D47A1),
    Color(0xFF4A148C),
    Color(0xFFB71C1C),
    Color(0xFFE65100),
    Color(0xFF006064),
    Color(0xFF1B5E20),
    Color(0xFF33691E),
  ];

  Color _avatarColor(String name) {
    final hash = name.codeUnits.fold<int>(0, (prev, e) => prev + e);
    return _avatarColors[hash % _avatarColors.length];
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredSuppliers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('قائمة الموردين'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'بحث',
            onPressed: () {
              FocusScope.of(context).unfocus();
            },
          ),
          IconButton(
            icon: const Icon(Icons.local_shipping),
            tooltip: 'إضافة مورد',
            onPressed: () => _showAddSupplierSheet(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Search bar ────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: SearchBar(
                    controller: _searchController,
                    hintText: 'بحث عن مورد...',
                    leading: const Icon(Icons.search),
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),

                // ── Supplier list ─────────────────────────────────────
                Expanded(
                  child: filtered.isEmpty
                      ? EmptyState(
                          icon: Icons.local_shipping,
                          title: _searchQuery.isNotEmpty
                              ? 'لا توجد نتائج'
                              : 'لا يوجد موردين',
                          subtitle: _searchQuery.isNotEmpty
                              ? 'لم يتم العثور على نتائج مطابقة للبحث'
                              : 'قم بإضافة موردين جدد لبدء إدارة حساباتك',
                          actionLabel:
                              _searchQuery.isEmpty ? 'إضافة مورد' : null,
                          onAction:
                              _searchQuery.isEmpty ? _showAddSupplierSheet : null,
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final supplier = filtered[index];
                            return _SupplierCard(
                              supplier: supplier,
                              avatarColor: _avatarColor(supplier.name),
                              onTap: () => _showAddSupplierSheet(
                                  supplier: supplier),
                              onDelete: () => _deleteSupplier(supplier),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSupplierSheet(),
        tooltip: 'إضافة مورد',
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.local_shipping),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
//  SUPPLIER CARD
// ═══════════════════════════════════════════════════════════════════
class _SupplierCard extends StatelessWidget {
  const _SupplierCard({
    required this.supplier,
    required this.avatarColor,
    this.onTap,
    this.onDelete,
  });

  final Supplier supplier;
  final Color avatarColor;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    // For suppliers: 'debit' (عليه) means we owe them → positive liability
    // 'credit' (له) means they owe us
    final isDebit = supplier.balanceType == 'debit' && supplier.balance > 0;
    final isCredit = supplier.balanceType == 'credit' && supplier.balance > 0;
    final balanceColor = isDebit
        ? AppColors.error
        : isCredit
            ? AppColors.success
            : isLight
                ? AppColors.textSecondary
                : AppColors.darkTextSecondary;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // ── Avatar ───────────────────────────────────────
              CircleAvatar(
                radius: 26,
                backgroundColor: avatarColor.withValues(alpha: 0.15),
                child: Text(
                  supplier.name.isNotEmpty ? supplier.name[0] : '?',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: avatarColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // ── Name, phone ──────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supplier.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.phone,
                          size: 14,
                          color: isLight
                              ? AppColors.textHint
                              : AppColors.darkTextSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          supplier.phone ?? '—',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isLight
                                ? AppColors.textSecondary
                                : AppColors.darkTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Balance ──────────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${supplier.balance.abs().toStringAsFixed(2)} ${AppConstants.currency}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: balanceColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    supplier.balanceType == 'debit' ? 'عليه' : 'له',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: balanceColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),

              // ── Arrow icon (RTL – points left visually) ─────
              Icon(
                Icons.arrow_back_ios,
                size: 16,
                color: isLight
                    ? AppColors.textHint
                    : AppColors.darkTextSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
