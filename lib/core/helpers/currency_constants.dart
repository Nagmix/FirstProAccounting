import 'package:flutter/material.dart';

/// Centralized currency constants used across all screens.
///
/// Previously, [_currencyInfo], [_currencyOptions], [_currencySymbol()],
/// and [_showCurrencyFilterPopup()] were duplicated in 7+ screen files.
/// This class provides a single source of truth.
class CurrencyConstants {
  CurrencyConstants._();

  /// Currency display info: code → {label, symbol}.
  static const Map<String, Map<String, String>> currencyInfo = {
    'YER': {'label': 'ريال يمني', 'symbol': 'ر.ي'},
    'SAR': {'label': 'ريال سعودي', 'symbol': 'ر.س'},
    'USD': {'label': 'دولار أمريكي', 'symbol': '\$'},
  };

  /// Currency filter options in display order.
  static const List<String> currencyOptions = ['YER', 'SAR', 'USD'];

  /// Returns the display symbol for a currency code.
  static String currencySymbol(String? code) {
    switch (code) {
      case 'SAR':
        return 'ر.س';
      case 'USD':
        return r'$';
      case 'YER':
      default:
        return 'ر.ي';
    }
  }

  /// Returns the display label for a currency code.
  static String currencyLabel(String? code) {
    return currencyInfo[code]?['label'] ?? code ?? 'ريال يمني';
  }

  /// Shows a currency filter bottom sheet and returns the selected currency
  /// via the [onSelected] callback.
  static void showCurrencyFilterPopup({
    required BuildContext context,
    required String selectedCurrency,
    required ValueChanged<String> onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'تصفية حسب العملة',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              ...currencyOptions.map((option) {
                final isSelected = selectedCurrency == option;
                final label = currencyInfo[option]?['label'] ?? option;
                final symbol = currencyInfo[option]?['symbol'] ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      onSelected(option);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.1)
                            : Colors.transparent,
                        border: Border.all(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).dividerColor,
                          width: isSelected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).hintColor,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '$label ($option)',
                              style: TextStyle(
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.color,
                              ),
                            ),
                          ),
                          Text(
                            symbol,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}
