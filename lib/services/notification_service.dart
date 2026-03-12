import 'dart:async';
import 'package:flutter/foundation.dart';

/// Mock notification service for MVP
/// In production, this would use flutter_local_notifications package
class NotificationService extends ChangeNotifier {
  final List<AppNotification> _notifications = [];
  bool _notificationsEnabled = true;
  
  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  bool get notificationsEnabled => _notificationsEnabled;
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  /// Initialize the notification service
  Future<void> initialize() async {
    // In a real app, would initialize local notifications
    // For MVP, just set up mock notifications
    await _loadMockNotifications();
  }

  /// Enable/disable notifications
  Future<void> setNotificationsEnabled(bool enabled) async {
    _notificationsEnabled = enabled;
    notifyListeners();
    
    if (!enabled) {
      // In a real app, would cancel all scheduled notifications
      debugPrint('Notifications disabled');
    }
  }

  /// Schedule a bill reminder notification
  Future<void> scheduleBillReminder({
    required String title,
    required String body,
    required DateTime scheduleDate,
    required String billId,
  }) async {
    if (!_notificationsEnabled) return;

    // In a real app, would use flutter_local_notifications
    debugPrint('Scheduled bill reminder: $title for $scheduleDate');
    
    // Add to notifications list for demo
    final notification = AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      body: body,
      type: NotificationType.billReminder,
      scheduledDate: scheduleDate,
      data: {'billId': billId},
      createdAt: DateTime.now(),
    );
    
    _notifications.insert(0, notification);
    notifyListeners();
  }

  /// Schedule an expense alert notification
  Future<void> scheduleExpenseAlert({
    required String title,
    required String body,
    required double amount,
    required String category,
  }) async {
    if (!_notificationsEnabled) return;

    debugPrint('Scheduled expense alert: $title');
    
    final notification = AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      body: body,
      type: NotificationType.expenseAlert,
      data: {
        'amount': amount.toString(),
        'category': category,
      },
      createdAt: DateTime.now(),
    );
    
    _notifications.insert(0, notification);
    notifyListeners();
  }

  /// Schedule a weekly report notification
  Future<void> scheduleWeeklyReport({
    required String title,
    required String body,
    required Map<String, dynamic> reportData,
  }) async {
    if (!_notificationsEnabled) return;

    debugPrint('Scheduled weekly report: $title');
    
    final notification = AppNotification(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      body: body,
      type: NotificationType.weeklyReport,
      data: reportData,
      createdAt: DateTime.now(),
    );
    
    _notifications.insert(0, notification);
    notifyListeners();
  }

  /// Mark a notification as read
  void markAsRead(String notificationId) {
    final index = _notifications.indexWhere((n) => n.id == notificationId);
    if (index != -1) {
      _notifications[index] = _notifications[index].copyWith(isRead: true);
      notifyListeners();
    }
  }

  /// Mark all notifications as read
  void markAllAsRead() {
    for (int i = 0; i < _notifications.length; i++) {
      _notifications[i] = _notifications[i].copyWith(isRead: true);
    }
    notifyListeners();
  }

  /// Clear a notification
  void clearNotification(String notificationId) {
    _notifications.removeWhere((n) => n.id == notificationId);
    notifyListeners();
  }

  /// Clear all notifications
  void clearAllNotifications() {
    _notifications.clear();
    notifyListeners();
  }

  /// Load mock notifications for demonstration
  Future<void> _loadMockNotifications() async {
    final mockNotifications = [
      AppNotification(
        id: '1',
        title: 'Electricity Bill Due',
        body: 'Your electricity bill of ₹2,500 is due in 3 days',
        type: NotificationType.billReminder,
        scheduledDate: DateTime.now().add(const Duration(days: 3)),
        data: {'billId': 'elec_001'},
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      AppNotification(
        id: '2',
        title: 'Budget Alert: Food',
        body: 'You\'ve spent 80% of your monthly food budget (₹8,000 of ₹10,000)',
        type: NotificationType.expenseAlert,
        data: {'amount': '8000', 'category': 'Food'},
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      AppNotification(
        id: '3',
        title: 'Weekly Report Ready',
        body: 'Your family spent ₹15,240 this week. View detailed breakdown.',
        type: NotificationType.weeklyReport,
        data: {'totalSpent': '15240', 'week': '2024-W12'},
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        isRead: true,
      ),
    ];

    _notifications.addAll(mockNotifications);
    notifyListeners();
  }

  /// Check for bill reminders (would run in background)
  Future<void> checkBillReminders() async {
    // In a real app, would check against a bills database
    // For MVP, simulate finding an upcoming bill
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    
    await scheduleBillReminder(
      title: 'Internet Bill Due Tomorrow',
      body: 'Your internet bill of ₹1,200 is due tomorrow',
      scheduleDate: tomorrow,
      billId: 'internet_001',
    );
  }

  /// Check for budget overages (would run after expense addition)
  Future<void> checkBudgetAlerts(double expenseAmount, String category) async {
    // Simulate budget checking
    final monthlyBudgets = {
      'Food': 10000.0,
      'Transport': 5000.0,
      'Shopping': 6000.0,
    };

    // Mock current spending (in real app, would query from database)
    final currentSpending = {
      'Food': 8500.0,
      'Transport': 4200.0,
      'Shopping': 5800.0,
    };

    final budget = monthlyBudgets[category];
    final current = (currentSpending[category] ?? 0.0) + expenseAmount;

    if (budget != null && current >= budget * 0.8) {
      final percentage = ((current / budget) * 100).round();
      await scheduleExpenseAlert(
        title: 'Budget Alert: $category',
        body: 'You\'ve spent $percentage% of your monthly $category budget (₹${current.toInt()} of ₹${budget.toInt()})',
        amount: current,
        category: category,
      );
    }
  }
}

enum NotificationType {
  billReminder,
  expenseAlert,
  weeklyReport,
  general,
}

class AppNotification {
  final String id;
  final String title;
  final String body;
  final NotificationType type;
  final DateTime createdAt;
  final DateTime? scheduledDate;
  final bool isRead;
  final Map<String, dynamic> data;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    this.scheduledDate,
    this.isRead = false,
    this.data = const {},
  });

  AppNotification copyWith({
    String? id,
    String? title,
    String? body,
    NotificationType? type,
    DateTime? createdAt,
    DateTime? scheduledDate,
    bool? isRead,
    Map<String, dynamic>? data,
  }) {
    return AppNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      type: type ?? this.type,
      createdAt: createdAt ?? this.createdAt,
      scheduledDate: scheduledDate ?? this.scheduledDate,
      isRead: isRead ?? this.isRead,
      data: data ?? this.data,
    );
  }

  String get formattedTime {
    final now = DateTime.now();
    final diff = now.difference(createdAt);

    if (diff.inDays > 0) {
      return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes} minute${diff.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }
}