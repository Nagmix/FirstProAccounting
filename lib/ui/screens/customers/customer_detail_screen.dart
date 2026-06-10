import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/money_helper.dart';
import '../../../core/utils/movement_sorter.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/customer_repository.dart';
import '../../../data/datasources/services/cash_box_service.dart';
import '../../../data/datasources/services/voucher_auto_mapping_service.dart';
import '../../../data/models/customer_model.dart';
import '../../../ui/widgets/entity_detail/entity_detail_state.dart';
import 'edit_customer_sheet.dart';

/// Customer Detail / Ledger Screen — Modern Professional Design
/// Displays all financial movements for a specific customer with
/// filtering, search, statistics, and voucher creation capabilities.
class CustomerDetailScreen extends StatefulWidget {
  final Customer customer;

  const CustomerDetailScreen({super.key, required this.customer});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState
    extends EntityDetailState<CustomerDetailScreen> {
  // Customer data (refreshable)
  Customer? _freshCustomer;

  // ─── Abstract method implementations ─────────────────────────────

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
  String get entityName => _freshCustomer?.name ?? widget.customer.name;

  @override
  String get entityPhone =>
      _freshCustomer?.phone ?? widget.customer.phone ?? '';

  @override
  String get entityTypeName => VoucherAutoMappingService.entityCustomer;

  @override
  int? get entityId => _freshCustomer?.id ?? widget.customer.id;

  @override
  IconData get entityIcon => Icons.person;

  @override
  String get entityLabel => 'العميل';

  @override
  IconData get entityLabelIcon => Icons.person;

  @override
  String get entityTypeAr => 'عميل';

  @override
  String get entityTypePdf => 'customer';

  @override
  void onEditPressed() => _showEditCustomerSheet();

  // ─── Lifecycle ───────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _freshCustomer = widget.customer;
    loadData();
  }

  // ─── Data Loading ────────────────────────────────────────────────

  @override
  Future<void> loadData() async {
    isLoading = true;

    try {
      final customerMap = await locator<CustomerRepository>()
          .getCustomerById(widget.customer.id!);
      if (customerMap != null) {
        _freshCustomer = Customer.fromMap(customerMap);
      }
    } catch (e) {
      debugPrint('CustomerDetailScreen.loadData [refreshCustomer]: $e');
    }

    try {
      cashBoxes = await locator<CashBoxService>().getAllCashBoxes();
    } catch (e) {
      debugPrint('CustomerDetailScreen.loadData [cashBoxes]: $e');
    }

    try {
      await loadMovements();
    } catch (e) {
      debugPrint('CustomerDetailScreen.loadData [movements]: $e');
    }

    if (mounted) isLoading = false;
  }

  @override
  Future<void> loadMovements() async {
    final customerId = widget.customer.id!;
    final customerRepo = locator<CustomerRepository>();
    final movements = <Map<String, dynamic>>[];

    // 1. Load invoices for this customer
    try {
      final invoices = await customerRepo.getCustomerInvoices(customerId);
      for (final inv in invoices) {
        final type = inv['type'] as String? ?? 'sale';
        final isReturn = (inv['is_return'] as int? ?? 0) == 1;
        final total = MoneyHelper.readMoney(inv['total']);
        final currency = inv['currency'] as String? ?? 'YER';
        final createdAt =
            inv['created_at'] as String? ?? DateTime.now().toIso8601String();

        String effectiveType, typeAr, filterKey;
        IconData icon;
        Color color;
        double debit = 0.0, credit = 0.0;

        if (type == 'sale' && !isReturn) {
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
        } else if (type == 'purchase' && !isReturn) {
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
        } else {
          effectiveType = type;
          typeAr = 'فاتورة';
          icon = Icons.receipt;
          color = AppColors.textSecondary;
          debit = total;
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
      debugPrint('CustomerDetailScreen.loadMovements [invoices]: $e');
    }

    // 2. Load vouchers
    try {
      final voucherRows = await customerRepo.getCustomerVouchers(customerId);

      // Discover unlinked vouchers across ALL currencies (customer is
      // multi-currency, so we must check receivable accounts for all).
      final allCustomerAccounts =
          await customerRepo.getCustomerReceivableAccountsAllCurrencies();
      final customerAccountIds =
          allCustomerAccounts.map((a) => a['id']).toList();

      if (customerAccountIds.isNotEmpty) {
        final unlinkedVouchers = await customerRepo.getUnlinkedVouchers();
        for (final v in unlinkedVouchers) {
          final voucherId = v['id'] as int?;
          if (voucherId == null) continue;
          try {
            final items =
                await locator<CashBoxService>().getVoucherItems(voucherId);
            for (final item in items) {
              final accountId = item['account_id'] as int?;
              if (accountId != null && customerAccountIds.contains(accountId)) {
                final desc = v['description'] as String? ?? '';
                final customerName =
                    _freshCustomer?.name ?? widget.customer.name;
                if (desc.contains(customerName)) {
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
          case 'outgoing_transfer':
            typeAr = 'حوالة صادرة';
            icon = Icons.send;
            color = AppColors.warning;
            debit = totalAmount;
            filterKey = 'outgoing_transfer';
            break;
          case 'incoming_transfer':
            typeAr = 'حوالة وارده';
            icon = Icons.download;
            color = AppColors.info;
            credit = totalAmount;
            filterKey = 'incoming_transfer';
            break;
          case 'settlement':
          case 'compound':
            // For settlement/compound vouchers, the debit/credit direction
            // depends on the voucher_items. Look up the actual effect on the
            // customer's receivable account (code 12xx).
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
                    customerAccountIds.contains(viAccountId)) {
                  final viDebit = MoneyHelper.readMoney(vi['debit']);
                  final viCredit = MoneyHelper.readMoney(vi['credit']);
                  debit += viDebit;
                  credit += viCredit;
                }
              }
            } catch (_) {
              // Fallback: assume credit (له) as default direction
              credit = totalAmount;
            }
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
      debugPrint('CustomerDetailScreen.loadMovements [vouchers]: $e');
    }

    // 3. Opening balance transactions
    try {
      final customer = _freshCustomer ?? widget.customer;
      final obTransactions = await locator<CustomerRepository>()
          .getCustomerOpeningBalanceTransactions(customerId);

      for (final ob in obTransactions) {
        final debit = MoneyHelper.readMoney(ob['debit']);
        final credit = MoneyHelper.readMoney(ob['credit']);
        final dateStr = ob['date'] as String? ??
            ob['created_at'] as String? ??
            DateTime.now().toIso8601String();
        final description = ob['description'] as String? ?? 'رصيد افتتاحي';
        final obCurrency =
            ob['account_currency'] as String? ?? customer.currency ?? 'YER';

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
          (customer.balance != 0.0 ||
              (customer.currency?.isNotEmpty ?? false))) {
        double allDebit = 0.0, allCredit = 0.0;
        for (final m in movements) {
          allDebit += MoneyHelper.readMoney(m['debit']);
          allCredit += MoneyHelper.readMoney(m['credit']);
        }
        final customerSignedBalance = customer.balanceType == 'credit'
            ? customer.balance
            : -customer.balance;
        final openingAmount = customerSignedBalance - (allCredit - allDebit);

        if (openingAmount.abs() >= 0.005) {
          final obCurrency = customer.currency ?? 'YER';
          final isCredit = openingAmount > 0;
          movements.insert(0, {
            'id': 'opening_balance',
            'date': customer.createdAt.toIso8601String(),
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
            'created_at': customer.createdAt.toIso8601String(),
          });
        }
      }
    } catch (e) {
      debugPrint('CustomerDetailScreen.loadMovements [opening_balance]: $e');
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

  // ─── Edit Customer ───────────────────────────────────────────────

  Future<void> _showEditCustomerSheet() async {
    final customer = _freshCustomer ?? widget.customer;
    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => EditCustomerSheet(customer: customer),
    );
    // If the edit was successful, reload data
    if (result == true) {
      if (mounted) loadData();
    }
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
}
