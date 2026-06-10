import 'package:flutter/material.dart';

import 'package:firstpro/ui/screens/products/widgets/product_form_helpers.dart';

// ═══════════════════════════════════════════════════════════════════
//  Step 7 – إعدادات البيع
// ═══════════════════════════════════════════════════════════════════

class ProductSalesSettingsStep extends StatelessWidget {
  // Values
  final bool isSellable;
  final bool isPurchasable;
  final bool allowNegative;
  final bool sellRetail;
  final bool showInPos;

  // Callbacks
  final ValueChanged<bool> onSellableChanged;
  final ValueChanged<bool> onPurchasableChanged;
  final ValueChanged<bool> onAllowNegativeChanged;
  final ValueChanged<bool> onSellRetailChanged;
  final ValueChanged<bool> onShowInPosChanged;

  const ProductSalesSettingsStep({
    super.key,
    required this.isSellable,
    required this.isPurchasable,
    required this.allowNegative,
    required this.sellRetail,
    required this.showInPos,
    required this.onSellableChanged,
    required this.onPurchasableChanged,
    required this.onAllowNegativeChanged,
    required this.onSellRetailChanged,
    required this.onShowInPosChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepTitle(title: 'إعدادات البيع', icon: Icons.storefront),
        ProductSwitchTile(
          title: 'يباع؟',
          subtitle: isSellable ? 'نعم' : 'لا',
          value: isSellable,
          onChanged: onSellableChanged,
        ),
        const Divider(height: 1),
        ProductSwitchTile(
          title: 'يشترى؟',
          subtitle: isPurchasable ? 'نعم' : 'لا',
          value: isPurchasable,
          onChanged: onPurchasableChanged,
        ),
        const Divider(height: 1),
        ProductSwitchTile(
          title: 'يسمح بالسالب؟',
          subtitle: allowNegative ? 'نعم' : 'لا',
          value: allowNegative,
          onChanged: onAllowNegativeChanged,
        ),
        const Divider(height: 1),
        ProductSwitchTile(
          title: 'يباع بالتجزئة؟',
          subtitle: sellRetail ? 'نعم' : 'لا',
          value: sellRetail,
          onChanged: onSellRetailChanged,
        ),
        const Divider(height: 1),
        ProductSwitchTile(
          title: 'يظهر في الكاشير؟',
          subtitle: showInPos ? 'نعم' : 'لا',
          value: showInPos,
          onChanged: onShowInPosChanged,
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}
