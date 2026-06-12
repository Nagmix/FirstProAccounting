import 'package:flutter/material.dart';
import 'package:firstpro/core/di/service_locator.dart';
import 'package:firstpro/data/datasources/repositories/reference_data_repository.dart';
import 'package:firstpro/data/datasources/services/base_currency_service.dart';

/// Centralized currency constants used across all screens.
class CurrencyConstants {
  CurrencyConstants._();

  /// Internal storage for dynamic currencies.
  static Map<String, Map<String, String>> _currencyInfo = {
    'YER': {'label': 'ريال يمني', 'symbol': 'ر.ي'},
    'SAR': {'label': 'ريال سعودي', 'symbol': 'ر.س'},
    'USD': {'label': 'دولار أمريكي', 'symbol': r'$'},
  };

  static List<String> _currencyOptions = ['YER', 'SAR', 'USD'];
  static String _defaultCurrencyCode = 'YER';

  /// Public getter for currency info.
  static Map<String, Map<String, String>> get currencyInfo => _currencyInfo;

  /// Public getter for currency options.
  static List<String> get currencyOptions => _currencyOptions;

  /// Get currency options with "All" (الكل) option.
  static List<String> get currencyOptionsWithAll => ['الكل', ..._currencyOptions];

  /// Get currency options as MapEntry list for dropdowns.
  static List<MapEntry<String, String>> get currencyMapEntries => 
    _currencyOptions.map((c) => MapEntry(c, c)).toList();

  /// Returns the default currency symbol.
  static String get defaultSymbol =>
      _currencyInfo[_defaultCurrencyCode]?['symbol'] ??
      _currencyInfo['YER']?['symbol'] ??
      'ر.ي';

  /// Returns the current default currency code.
  static String get defaultCode => _defaultCurrencyCode;

  /// Initialize and refresh currency data from the database.
  static Future<void> refresh() async {
    try {
      final refData = locator<ReferenceDataRepository>();
      final currencies = await refData.getAllCurrencies();

      if (currencies.isNotEmpty) {
        final Map<String, Map<String, String>> newInfo = {};
        final List<String> newOptions = [];
        String? defaultCode;

        for (final c in currencies) {
          final code = c['code'] as String;
          newInfo[code] = {
            'label': c['name_ar'] as String,
            'symbol': c['symbol'] as String,
          };
          newOptions.add(code);
          if ((c['is_default'] as int? ?? 0) == 1) {
            defaultCode = code;
          }
        }

        try {
          defaultCode = await locator<BaseCurrencyService>().getBaseCurrencyCode();
        } catch (_) {
          defaultCode ??= newOptions.contains('YER') ? 'YER' : newOptions.first;
        }

        _currencyInfo = newInfo;
        _currencyOptions = newOptions;
        _defaultCurrencyCode =
            newInfo.containsKey(defaultCode) ? defaultCode! : newOptions.first;
      }
    } catch (e) {
      // Fallback to defaults if DB fails
      debugPrint('Error refreshing CurrencyConstants: $e');
    }
  }

  /// Returns the display symbol for a currency code.
  static String currencySymbol(String? code) {
    return _currencyInfo[code]?['symbol'] ?? defaultSymbol;
  }

  /// Returns the display label for a currency code.
  static String currencyLabel(String? code) {
    return _currencyInfo[code]?['label'] ?? code ?? currencyLabel(defaultCode);
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
                                .withValues(alpha: 0.1)
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
