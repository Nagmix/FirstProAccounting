import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';

class SalesOrdersScreen extends StatefulWidget {
  const SalesOrdersScreen({super.key});

  @override
  State<SalesOrdersScreen> createState() => _SalesOrdersScreenState();
}

class _SalesOrdersScreenState extends State<SalesOrdersScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('طلبات البيع'),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(PhosphorIconsRegular.plus),
            tooltip: 'طلب بيع جديد',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsRegular.receipt,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد طلبات بيع',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'سيتم إضافة طلبات البيع هنا',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
