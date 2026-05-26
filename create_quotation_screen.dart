
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/database_helper.dart';

class CreateQuotationScreen extends StatefulWidget {
  const CreateQuotationScreen({super.key});
  @override
  State<CreateQuotationScreen> createState() => _CreateQuotationScreenState();
}

class _CreateQuotationScreenState extends State<CreateQuotationScreen> {
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('إنشاء عرض سعر')),
        body: const Center(child: Text('إنشاء عرض سعر جديد')),
      ),
    );
  }
}

