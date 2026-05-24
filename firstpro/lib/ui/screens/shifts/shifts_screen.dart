
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/database_helper.dart';

class ShiftsScreen extends StatefulWidget {
  const ShiftsScreen({super.key});
  @override
  State<ShiftsScreen> createState() => _ShiftsScreenState();
}

class _ShiftsScreenState extends State<ShiftsScreen> {
  List<Map<String, dynamic>> _shifts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = DatabaseHelper();
    final shifts = await db.getAllShifts();
    setState(() { _shifts = shifts; _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الورديات')),
        body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _shifts.isEmpty
            ? const Center(child: Text('لا توجد ورديات'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _shifts.length,
                itemBuilder: (ctx, i) => _buildShiftCard(_shifts[i]),
              ),
      ),
    );
  }

  Widget _buildShiftCard(Map<String, dynamic> shift) {
    final isOpen = shift['status'] == 'open';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(isOpen ? Icons.lock_open : Icons.lock,
          color: isOpen ? AppColors.success : AppColors.textHint),
        title: Text(shift['shift_number'] ?? ''),
        subtitle: Text(isOpen ? 'مفتوحة' : 'مغلقة'),
        trailing: Text('${shift['opening_amount'] ?? 0}'),
      ),
    );
  }
}

