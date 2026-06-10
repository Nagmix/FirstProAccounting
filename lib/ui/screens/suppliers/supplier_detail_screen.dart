import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/utils/movement_sorter.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/supplier_repository.dart';
import '../../../data/datasources/database_helper.dart';
import '../../../data/datasources/services/cash_box_service.dart';
import '../../../data/datasources/services/voucher_auto_mapping_service.dart';
import '../../../data/models/supplier_model.dart';
import '../../../ui/widgets/entity_detail/entity_detail_state.dart';
import 'add_supplier_sheet.dart';

/// Supplier Detail / Ledger Screen
/// Displays all financial movements for a specific supplier with
/// filtering, search, statistics, and voucher creation capabilities.
class SupplierDetailScreen extends StatefulWidget {
  final Supplier supplier;

  const SupplierDetailScreen({super.key, required this.supplier});

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState
    extends EntityDetailState<SupplierDetailScreen> {
  // Supplier data (refreshable) — local field not in base class
  Supplier? _freshSupplier;

  // ─── Abstract Method Implementations ─────────────────────────────

  @override
  List<FilterTab> get filterTabs => const [
        FilterTab(key: 'all', label: 'جميع الحركات والفواتير'),
        FilterTab(key: 'opening_balance', label: 'رصيد افتتاحي'),
        FilterTab(key: 'debit', label: 'عليه'),
        FilterTab(key: 'credit', label: 'له'),
        FilterTab(key: 'payment_voucher', label: 'سند صرف'),
        FilterTab(key: 'receipt_voucher', label: 'سند قبض'),
        FilterTab(key: 'general_entry', label: 'قيد عام'),
        FilterTab(key: 'outgoing_transfer', label: 'حوالة صادرة'),
        FilterTab(key: 'incoming_transfer', label: 'حوالة وارده'),
        FilterTab(key: 'sales', label: 'مبيعات فقط'),
        FilterTab(key: 'purchases', label: 'مشتريات فقط'),
        FilterTab(key: 'returns', label: 'مرتجع'),
        FilterTab(key: 'compound_entry', label: 'قيد متعدد'),
      ];

  @override
  String get entityName => _freshSupplier?.name ?? widget.supplier.name;

  @override
  String get entityPhone => _freshSupplier?.phone ?? '';

  @override
  String get entityTypeName => VoucherAutoMappingService.entitySupplier;

  @override
  int? get entityId => _freshSupplier?.id ?? widget.supplier.id;

  @override
  IconData get entityIcon => Icons.local_shipping;

  @override
  String get entityLabel => 'المورد';

  @override
  IconData get entityLabelIcon => Icons.local_shipping;

  @override
  String get entityTypeAr => 'مورد';

  @override
  String get entityTypePdf => 'supplier';

  // ─── Lifecycle ───────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _freshSupplier = widget.supplier;
    loadData();
  }

  // ─── loadData ────────────────────────────────────────────────────

  @override
  Future<void> loadData() async {
    isLoading = true;

    try {
      final supplierMap = await locator<SupplierRepository>()
          .getSupplierById(widget.supplier.id!);
      if (supplierMap != null) {
        _freshSupplier = Supplier.fromMap(supplierMap);
      }
    } catch (e) {
      debugPrint('SupplierDetailScreen.loadData [refreshSupplier]: $e');
    }

    try {
      cashBoxes = await locator<CashBoxService>().getAllCashBoxes();
    } catch (e) {
      debugPrint('SupplierDetailScreen.loadData [cashBoxes]: $e');
    }

    try {
      await loadMovements();
    } catch (e) {
      debugPrint('SupplierDetailScreen.loadData [movements]: $e');
    }

    if (mounted) isLoading = false;
  }

  // ─── loadMovements — SUPPLIER-specific accounting logic ──────────

  @override
  Future<void> loadMovements() async {
    final supplierId = widget.supplier.id!;
    final supplierRepo = locator<SupplierRepository>();
    final movements = <Map<String, dynamic>>[];

    // 1. Load invoices for this supplier
    try {
      final invoices = await supplierRepo.getSupplierInvoices(supplierId);
      for (final inv in invoices) {
        final type = inv['type'] as String? ?? 'purchase';
        final isReturn = (inv['is_return'] as int? ?? 0) == 1;
        final total = MoneyHelper.readMoney(inv['total']);
        final currency = inv['currency'] as String? ?? 'YER';
        final createdAt =
            inv['created_at'] as String? ?? DateTime.now().toIso8601String();

        String effectiveType, typeAr, filterKey;
        IconData icon;
        Color color;
        double debit = 0.0, credit = 0.0;

        // Supplier accounting rules (liability account):
        //   Purchase → we owe supplier more → credit (له)
        //   Purchase return → we owe less → debit (عليه)
        //   Sale → supplier owes us → debit (عليه)
        //   Sale return → we owe more → credit (له)
        if (type == 'purchase' && !isReturn) {
          effectiveType = 'purchase';
          typeAr = 'فاتورة مشتريات';
          icon = Icons.shopping_cart;
          color = AppColors.secondary;
          credit = total;
          filterKey = 'purchases';
        } else if (type == 'purchase' && isReturn) {
          effectiveType = 'purchase_return';
          typeAr = 'مرتجع مشتريات';
          icon = Icons.keyboard_return;
          color = AppColors.accentPink;
          debit = total;
          filterKey = 'returns';
        } else if (type == 'sale' && !isReturn) {
          effectiveType = 'sale';
          typeAr = 'فاتورة مبيعات';
          icon = Icons.receipt_long;
          color = AppColors.primary;
          debit = total;
          filterKey = 'sales';
        } else if (type == 'sale' && isReturn) {
          effectiveType = 'sale_return';
          typeAr = 'مرتجع مبيعات';
          icon = Icons.keyboard_return;
          color = AppColors.warning;
          credit = total;
          filterKey = 'returns';
        } else {
          effectiveType = type;
          typeAr = 'فاتورة';
          icon = Icons.receipt;
          color = AppColors.textSecondary;
          credit = total;
          filterKey = 'all';
        }

        final remaining = MoneyHelper.readMoney(inv['remaining']);
        final desc =
            '$typeAr - ${inv['id'] ?? ''}${remaining > 0 ? ' (متبقي: ${remaining.toStringAsFixed(2)})' : ''}';

        movements.add({
          'id': inv['id'],
          'date': createdAt,
          'type': effectiveType,
          'type_ar': typeAr,
          'filter_key': filterKey,
          'icon': icon,
          'color': color,
          'description': desc,
          'debit': debit,
          'credit': credit,
          'currency': currency,
          'source': 'invoice',
          'voucher_type': null,
          'created_at': inv['created_at'] as String? ?? createdAt,
        });
      }
    } catch (e) {
      debugPrint('SupplierDetailScreen.loadMovements [invoices]: $e');
    }

    // 2. Load vouchers
    try {
      final voucherRows = await supplierRepo.getSupplierVouchers(supplierId);

      // Discover unlinked vouchers across ALL currencies (supplier is
      // multi-currency, so we must check payable accounts for all).
      final allSupplierAccounts =
          await supplierRepo.getSupplierPayableAccountsAllCurrencies();
      final supplierAccountIds =
          allSupplierAccounts.map((a) => a['id']).toList();

      if (supplierAccountIds.isNotEmpty) {
        // Get all vouchers without a supplier_id
        final db = await locator<DatabaseHelper>().database;
        final unlinkedVouchers = await db.query(
          'vouchers',
          where: 'supplier_id IS NULL',
          orderBy: 'date DESC',
        );
        for (final v in unlinkedVouchers) {
          final voucherId = v['id'] as int?;
          if (voucherId == null) continue;
          try {
            final items =
                await locator<CashBoxService>().getVoucherItems(voucherId);
            for (final item in items) {
              final accountId = item['account_id'] as int?;
              if (accountId != null && supplierAccountIds.contains(accountId)) {
                final desc = v['description'] as String? ?? '';
                final supplierName =
                    _freshSupplier?.name ?? widget.supplier.name;
                if (desc.contains(supplierName)) {
                  voucherRows.add(v);
                }
                break;
              }
            }
          } catch (_) {}
        }
      }

      for (final v in voucherRows) {
        final voucherType = v['voucher_type'] as String? ?? '';
        final totalAmount = MoneyHelper.readMoney(v['total_amount']);
        final currency = v['currency'] as String? ?? 'YER';
        final dateStr = v['date'] as String? ??
            v['created_at'] as String? ??
            DateTime.now().toIso8601String();

        String typeAr, filterKey;
        IconData icon;
        Color color;
        double debit = 0.0, credit = 0.0;

        // Supplier voucher accounting:
        //   Payment voucher → we pay supplier → debit (عليه)
        //   Receipt voucher → supplier pays us → credit (له)
        switch (voucherType) {
          case 'receipt':
            typeAr = 'سند قبض';
            icon = Icons.assignment_turned_in;
            color = AppColors.success;
            credit = totalAmount;
            filterKey = 'receipt_voucher';
            break;
          case 'payment':
            typeAr = 'سند صرف';
            icon = Icons.assignment_return;
            color = AppColors.error;
            debit = totalAmount;
            filterKey = 'payment_voucher';
            break;
          case 'settlement':
          case 'compound':
            // For settlement/compound vouchers, the debit/credit direction
            // depends on the voucher_items. Look up the actual effect on the
            // supplier's payable account (code 21xx).
            typeAr = voucherType == 'settlement' ? 'قيد عام' : 'قيد متعدد';
            icon = voucherType == 'settlement'
                ? Icons.balance
                : Icons.dynamic_feed;
            color = voucherType == 'settlement'
                ? AppColors.info
                : AppColors.accentBlue;
            filterKey = voucherType == 'settlement'
                ? 'general_entry'
                : 'compound_entry';
            // Determine direction from voucher_items
            final vId = v['id'];
            try {
              final vItems =
                  await locator<CashBoxService>().getVoucherItems(vId as int);
              for (final vi in vItems) {
                final viAccountId = vi['account_id'] as int?;
                if (viAccountId != null &&
                    supplierAccountIds.contains(viAccountId)) {
                  final viDebit = MoneyHelper.readMoney(vi['debit']);
                  final viCredit = MoneyHelper.readMoney(vi['credit']);
                  debit += viDebit;
                  credit += viCredit;
                }
              }
            } catch (_) {
              credit = totalAmount;
            }
            break;
          case 'outgoing_transfer':
            typeAr = 'حوالة صادرة';
            icon = Icons.send;
            color = AppColors.secondary;
            debit = totalAmount;
            filterKey = 'outgoing_transfer';
            break;
          case 'incoming_transfer':
            typeAr = 'حوالة وارده';
            icon = Icons.call_received;
            color = AppColors.accentBlue;
            credit = totalAmount;
            filterKey = 'incoming_transfer';
            break;
          default:
            typeAr = 'سند';
            icon = Icons.description;
            color = AppColors.textSecondary;
            debit = totalAmount;
            filterKey = 'all';
        }

        final description = v['description'] as String? ??
            '$typeAr - ${v['voucher_number'] ?? ''}';
        movements.add({
          'id': 'v_${v['id']}',
          'date': dateStr,
          'type': voucherType,
          'type_ar': typeAr,
          'filter_key': filterKey,
          'icon': icon,
          'color': color,
          'description': description,
          'debit': debit,
          'credit': credit,
          'currency': currency,
          'source': 'voucher',
          'voucher_type': voucherType,
          'created_at': v['created_at'] as String? ?? dateStr,
        });
      }
    } catch (e) {
      debugPrint('SupplierDetailScreen.loadMovements [vouchers]: $e');
    }

    // 3. Opening balance transactions
    try {
      final supplier = _freshSupplier ?? widget.supplier;
      final obTransactions = await locator<SupplierRepository>()
          .getSupplierOpeningBalanceTransactions(supplierId);

      for (final ob in obTransactions) {
        final debit = MoneyHelper.readMoney(ob['debit']);
        final credit = MoneyHelper.readMoney(ob['credit']);
        final dateStr = ob['date'] as String? ??
            ob['created_at'] as String? ??
            DateTime.now().toIso8601String();
        final description = ob['description'] as String? ?? 'رصيد افتتاحي';
        final obCurrency =
            ob['account_currency'] as String? ?? supplier.currency;

        movements.add({
          'id': 'ob_${ob['id']}',
          'date': dateStr,
          'type': 'opening_balance',
          'type_ar': 'رصيد افتتاحي',
          'filter_key': 'opening_balance',
          'icon': Icons.account_balance_wallet,
          'color': AppColors.accentBlue,
          'description': description,
          'debit': debit,
          'credit': credit,
          'currency': obCurrency,
          'source': 'opening_balance',
          'voucher_type': null,
          'created_at': ob['created_at'] as String? ?? dateStr,
        });
      }

      // Fallback for legacy data
      if (obTransactions.isEmpty &&
          (supplier.balance != 0.0 || supplier.currency.isNotEmpty)) {
        // Only sum movements in the supplier's stored currency to avoid
        // mixing different currencies (multi-currency environment).
        double allDebit = 0.0, allCredit = 0.0;
        for (final m in movements) {
          final mCurrency = m['currency'] as String? ?? 'YER';
          if (mCurrency != supplier.currency) continue; // Skip other currencies
          allDebit += MoneyHelper.readMoney(m['debit']);
          allCredit += MoneyHelper.readMoney(m['credit']);
        }
        final supplierSignedBalance = supplier.balanceType == 'credit'
            ? supplier.balance
            : -supplier.balance;
        final openingAmount = supplierSignedBalance - (allCredit - allDebit);

        if (openingAmount.abs() >= 0.005) {
          final obCurrency = supplier.currency;
          final isCredit = openingAmount > 0;
          movements.insert(0, {
            'id': 'opening_balance',
            'date': supplier.createdAt.toIso8601String(),
            'type': 'opening_balance',
            'type_ar': 'رصيد افتتاحي',
            'filter_key': 'opening_balance',
            'icon': Icons.account_balance_wallet,
            'color': AppColors.accentBlue,
            'description': 'رصيد افتتاحي (${isCredit ? "له" : "عليه"})',
            'debit': isCredit ? 0.0 : openingAmount.abs(),
            'credit': isCredit ? openingAmount.abs() : 0.0,
            'currency': obCurrency,
            'source': 'opening_balance',
            'voucher_type': null,
            'created_at': supplier.createdAt.toIso8601String(),
          });
        }
      }
    } catch (e) {
      debugPrint('SupplierDetailScreen.loadMovements [opening_balance]: $e');
    }

    // Sort chronologically (oldest first) via the unified sorter —
    // handles mixed date formats (day-only vs full timestamp). B-1 fix.
    MovementSorter.sortChronologically(movements);

    // Calculate running balance for ALL movements chronologically, per currency
    final currencyRunBal = <String, double>{};
    for (final m in movements) {
      final currency = m['currency'] as String? ?? 'YER';
      final debit = MoneyHelper.readMoney(m['debit']);
      final credit = MoneyHelper.readMoney(m['credit']);
      currencyRunBal[currency] =
          (currencyRunBal[currency] ?? 0.0) + credit - debit;
      m['running_balance'] = currencyRunBal[currency];
    }

    allMovements = movements;
    applyFilters();
  }

  // ─── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(actions: buildAppBarActions()),
      body: buildBody(),
      bottomNavigationBar: buildBottomBar(),
    );
  }

  // ─── Extra AppBar Actions (edit button) ──────────────────────────

  @override
  List<Widget> buildExtraAppBarActions() {
    return [
      Container(
        margin: const EdgeInsets.only(left: 4, top: 8, bottom: 8),
        child: Material(
          color: AppColors.accentBlue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () async {
              await showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (context) => AddSupplierSheet(
                    supplier: _freshSupplier ?? widget.supplier),
              );
              if (mounted) loadData();
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_rounded,
                      size: 18, color: AppColors.accentBlue),
                  const SizedBox(width: 4),
                  Text('تعديل',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accentBlue)),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }
}
