import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/models/supplier_model.dart';
import '../../widgets/empty_state.dart';
import 'add_supplier_sheet.dart';
import 'supplier_detail_screen.dart';

/// Professional suppliers management screen for the FirstPro accounting app.
///
/// Features:
/// - Search bar for filtering by name or phone.
/// - Supplier list with avatar, name, phone, and balance.
/// - FAB for adding a new supplier via [AddSupplierSheet].
/// - Tap to navigate to detail/ledger screen.
/// - Long press for Edit/Delete options.
/// - Dynamic balance display based on actual financial position.
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
    try {
      final db = DatabaseHelper();
      final maps = await db.getAllSuppliers();
      if (mounted) {
        setState(() {
          _suppliers = maps.map((m) => Supplier.fromMap(m)).toList();
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

  // ── Navigate to supplier detail/ledger ────────────────────────
  Future<void> _navigateToDetail(Supplier supplier) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SupplierDetailScreen(supplier: supplier),
      ),
    );
    _loadSuppliers();
  }

  // ── Show long-press menu (Edit / Delete) ──────────────────────
  void _showContextMenu(Supplier supplier) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                supplier.name,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit, color: AppColors.primary),
              title: const Text('تعديل'),
              onTap: () {
                Navigator.pop(ctx);
                _showAddSupplierSheet(supplier: supplier);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: AppColors.error),
              title: const Text('حذف',
                  style: TextStyle(color: AppColors.error)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteSupplier(supplier);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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
                              onTap: () => _navigateToDetail(supplier),
                              onLongPress: () => _showContextMenu(supplier),
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
    this.onLongPress,
  });

  final Supplier supplier;
  final Color avatarColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;

    // Dynamic balance: compute the label based on actual financial position
    // For the card, we use the stored balance as the net position
    // since we don't have movement data here.
    // balance is always positive; balanceType tells us the direction.
    // When balance is 0, show "متساوي" regardless of balanceType.
    final balanceLabel = supplier.balance.abs() < 0.005
        ? 'متساوي'
        : Supplier.getDynamicBalanceLabel(
            supplier.balance,
            supplier.balanceType,
          );

    final balanceColor = balanceLabel == 'متساوي'
        ? (isLight ? AppColors.textSecondary : AppColors.darkTextSecondary)
        : balanceLabel == 'له'
            ? AppColors.success
            : AppColors.error;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // ── Avatar ───────────────────────────────────────
              CircleAvatar(
                radius: 26,
                backgroundColor: avatarColor.withOpacity(0.15),
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
                          supplier.contactMethod == 'whatsapp'
                              ? Icons.chat
                              : Icons.phone_in_talk,
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
                    balanceLabel,
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
