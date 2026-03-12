import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late NotificationService _notificationService;

  @override
  void initState() {
    super.initState();
    _notificationService = NotificationService();
    _notificationService.initialize();
  }

  @override
  void dispose() {
    _notificationService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _notificationService,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          actions: [
            Consumer<NotificationService>(
              builder: (context, service, child) {
                if (service.notifications.isEmpty) return const SizedBox.shrink();
                
                return PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'mark_all_read':
                        service.markAllAsRead();
                        break;
                      case 'clear_all':
                        _confirmClearAll();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    if (service.unreadCount > 0)
                      const PopupMenuItem(
                        value: 'mark_all_read',
                        child: Row(
                          children: [
                            Icon(Icons.mark_email_read),
                            SizedBox(width: 8),
                            Text('Mark all as read'),
                          ],
                        ),
                      ),
                    const PopupMenuItem(
                      value: 'clear_all',
                      child: Row(
                        children: [
                          Icon(Icons.clear_all),
                          SizedBox(width: 8),
                          Text('Clear all'),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
        body: Consumer<NotificationService>(
          builder: (context, service, child) {
            return _buildBody(service);
          },
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showTestNotificationDialog,
          icon: const Icon(Icons.notifications_active),
          label: const Text('Test Notification'),
          backgroundColor: Theme.of(context).primaryColor,
        ),
      ),
    );
  }

  Widget _buildBody(NotificationService service) {
    if (service.notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No Notifications',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'You\'ll see bill reminders, budget alerts, and weekly reports here.',
              style: TextStyle(color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await service.checkBillReminders();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: service.notifications.length,
        itemBuilder: (context, index) {
          final notification = service.notifications[index];
          return _buildNotificationItem(notification, service);
        },
      ),
    );
  }

  Widget _buildNotificationItem(AppNotification notification, NotificationService service) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      elevation: notification.isRead ? 1 : 3,
      color: notification.isRead ? null : Theme.of(context).primaryColor.withValues(alpha: 0.05),
      child: ListTile(
        leading: _getNotificationIcon(notification.type),
        title: Text(
          notification.title,
          style: TextStyle(
            fontWeight: notification.isRead ? FontWeight.normal : FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notification.body),
            const SizedBox(height: 4),
            Text(
              notification.formattedTime,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'mark_read':
                if (!notification.isRead) {
                  service.markAsRead(notification.id);
                }
                break;
              case 'delete':
                service.clearNotification(notification.id);
                break;
            }
          },
          itemBuilder: (context) => [
            if (!notification.isRead)
              const PopupMenuItem(
                value: 'mark_read',
                child: Row(
                  children: [
                    Icon(Icons.mark_email_read),
                    SizedBox(width: 8),
                    Text('Mark as read'),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete),
                  SizedBox(width: 8),
                  Text('Delete'),
                ],
              ),
            ),
          ],
        ),
        onTap: () {
          if (!notification.isRead) {
            service.markAsRead(notification.id);
          }
          _showNotificationDetails(notification);
        },
      ),
    );
  }

  Widget _getNotificationIcon(NotificationType type) {
    IconData icon;
    Color color;

    switch (type) {
      case NotificationType.billReminder:
        icon = Icons.receipt_long;
        color = Colors.orange;
        break;
      case NotificationType.expenseAlert:
        icon = Icons.warning;
        color = Colors.red;
        break;
      case NotificationType.weeklyReport:
        icon = Icons.analytics;
        color = Colors.blue;
        break;
      case NotificationType.general:
        icon = Icons.notifications;
        color = Colors.grey;
        break;
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color),
    );
  }

  void _showNotificationDetails(AppNotification notification) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(notification.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notification.body),
            const SizedBox(height: 16),
            Text(
              'Received: ${notification.formattedTime}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
            if (notification.scheduledDate != null) ...[
              const SizedBox(height: 4),
              Text(
                'Scheduled for: ${_formatDate(notification.scheduledDate!)}',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
            if (notification.data.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Details:',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              ...notification.data.entries.map((entry) => Text(
                '${entry.key}: ${entry.value}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              )),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Notifications'),
        content: const Text('Are you sure you want to clear all notifications? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _notificationService.clearAllNotifications();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  void _showTestNotificationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Test Notification'),
        content: const Text('Choose a type of notification to test:'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _notificationService.scheduleBillReminder(
                title: 'Test Bill Reminder',
                body: 'This is a test bill reminder notification',
                scheduleDate: DateTime.now(),
                billId: 'test_bill',
              );
            },
            child: const Text('Bill Reminder'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _notificationService.scheduleExpenseAlert(
                title: 'Test Budget Alert',
                body: 'This is a test budget alert notification',
                amount: 5000.0,
                category: 'Food',
              );
            },
            child: const Text('Budget Alert'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _notificationService.scheduleWeeklyReport(
                title: 'Test Weekly Report',
                body: 'This is a test weekly report notification',
                reportData: {'totalSpent': '12500', 'week': '2024-W12'},
              );
            },
            child: const Text('Weekly Report'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}