import 'package:flutter/material.dart';
import 'package:firstpro/core/theme/app_colors.dart';
import 'package:firstpro/core/utils/currency_formatter.dart';
import 'package:firstpro/core/utils/money_helper.dart';

/// Journal entry preview card for a completed currency exchange.
///
/// Extracted from CurrencyExchangeScreen._buildJournalEntryCard (U-05)
/// to reduce the parent screen's size. This widget is purely presentational:
/// it receives the exchange map and a currency-symbol resolver, then
/// renders the debit/credit table showing how the exchange was posted
/// to the journal (Cash&Banks for both currencies, plus a gain/loss row
/// if applicable).
///
/// The parent passes:
/// - [exchange]: the exchange row from the currency_exchanges table
///   (must contain from_amount, to_amount, gain_loss, gain_loss_type,
///   from_currency, to_currency, exchange_number).
/// - [theme]: the current ThemeData (for text styles).
/// - [currencySymbol]: a callback that resolves a currency code to its
///   display symbol (e.g. 'SAR' → 'ر.س'). The parent owns this logic
///   because it depends on CurrencyConstants which is loaded from DB.
class ExchangeJournalEntryCard extends StatelessWidget {
  final Map<String, dynamic> exchange;
  final ThemeData theme;
  final String Function(String currencyCode) currencySymbol;

  const ExchangeJournalEntryCard({
    super.key,
    required this.exchange,
    required this.theme,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    final ex = exchange;
    final fromAmount = MoneyHelper.readMoney(ex['from_amount']);
    final toAmount = MoneyHelper.readMoney(ex['to_amount']);
    final gainLoss = MoneyHelper.readMoney(ex['gain_loss']);
    final gainLossType = ex['gain_loss_type'] as String?;
    final fromCur = ex['from_currency'] as String;
    final toCur = ex['to_currency'] as String;
    final exchangeNum = ex['exchange_number'] as String? ?? '';

    return Card(
      elevation: 2,
      color: AppColors.primary.withValues(alpha: 0.03),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.menu_book,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'القيد المحاسبي',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  exchangeNum,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Table header
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'الحساب',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'مدين',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'دائن',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Debit: Cash&Banks (to_currency) ← receives money
            _JournalRow(
              theme: theme,
              account: 'الصناديق والبنوك (${currencySymbol(toCur)})',
              debit: toAmount,
              credit: 0,
            ),
            const SizedBox(height: 4),

            // Credit: Cash&Banks (from_currency) ← sends money
            _JournalRow(
              theme: theme,
              account: 'الصناديق والبنوك (${currencySymbol(fromCur)})',
              debit: 0,
              credit: fromAmount,
            ),

            // Gain/Loss row
            if (gainLossType != null && gainLoss > 0) ...[
              const SizedBox(height: 4),
              _JournalRow(
                theme: theme,
                account:
                    gainLossType == 'gain' ? 'أرباح صرافة' : 'خسائر صرافة',
                debit: gainLossType == 'loss' ? gainLoss : 0,
                credit: gainLossType == 'gain' ? gainLoss : 0,
                isGainLoss: true,
                gainLossType: gainLossType,
              ),
            ],

            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 6),

            // Summary
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 16,
                    color: AppColors.success,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${CurrencyFormatter.format(fromAmount)} ${currencySymbol(fromCur)} ← ${CurrencyFormatter.format(toAmount)} ${currencySymbol(toCur)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.success,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single debit/credit row in the journal entry table.
class _JournalRow extends StatelessWidget {
  final ThemeData theme;
  final String account;
  final double debit;
  final double credit;
  final bool isGainLoss;
  final String? gainLossType;

  const _JournalRow({
    required this.theme,
    required this.account,
    required this.debit,
    required this.credit,
    this.isGainLoss = false,
    this.gainLossType,
  });

  @override
  Widget build(BuildContext context) {
    final rowColor = isGainLoss
        ? (gainLossType == 'gain' ? AppColors.success : AppColors.error)
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(
        color: rowColor?.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              account,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: rowColor,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              debit > 0 ? CurrencyFormatter.format(debit) : '',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: debit > 0 ? AppColors.primary : null,
              ),
              textDirection: TextDirection.ltr,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              credit > 0 ? CurrencyFormatter.format(credit) : '',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: credit > 0 ? AppColors.error : null,
              ),
              textDirection: TextDirection.ltr,
            ),
          ),
        ],
      ),
    );
  }
}
