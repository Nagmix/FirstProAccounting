import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/di/service_locator.dart';
import '../../../data/datasources/repositories/reference_data_repository.dart';

/// A simple notification center screen that displays notifications from the DB.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final notifications = await locator<ReferenceDataRepository>().getAllNotifications();

      if (mounted) {
        setState(() {
          _notifications = notifications;
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

  Future<void> _markAsRead(int id) async {
    await locator<ReferenceDataRepository>().markNotificationAsRead(id);
    _loadNotifications();
  }

  Future<void> _markAllAsRead() async {
    await locator<ReferenceDataRepository>().markAllNotificationsAsRead();
    _loadNotifications();
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'stock_alert':
        return Icons.inventory_2;
      case 'invoice':
        return Icons.receipt;
      case 'payment':
        return Icons.payment;
      case 'expense':
        return Icons.money_off;
      case 'system':
        return Icons.info;
      default:
        return Icons.notifications;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'stock_alert':
        return Colors.orange;
      case 'invoice':
        return AppColors.primary;
      case 'payment':
        return AppColors.success;
      case 'expense':
        return AppColors.error;
      case 'system':
        return Colors.blue;
      default:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        actions: [
          if (_notifications.any((n) => n['is_read'] == 0))
            TextButton.icon(
              onPressed: _markAllAsRead,
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('قراءة الكل'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.notifications_none,
                        size: 64,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'لا توجد إشعارات',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: isDark ? AppColors.darkTextSecondary : AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadNotifications,
                  child: ListView.builder(
                    itemCount: _notifications.length,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemBuilder: (context, index) {
                      final notif = _notifications[index];
                      final isRead = notif['is_read'] == 1;
                      final type = notif['type'] as String? ?? 'general';
                      final title = notif['title'] as String? ?? '';
                      final body = notif['body'] as String? ?? '';
                      // ignore: unused_local_variable
                      final createdAt = notif['created_at'] as String? ?? '';

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _colorForType(type).withValues(alpha: 0.15),
                          child: Icon(
                            _iconForType(type),
                            color: _colorForType(type),
                            size: 20,
                          ),
                        ),
                        title: Text(
                          title,
                          style: TextStyle(
                            fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: isRead
                            ? null
                            : Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                        onTap: isRead ? null : () => _markAsRead(notif['id'] as int),
                      );
                    },
                  ),
                ),
    );
  }
}
