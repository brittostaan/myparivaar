import 'package:flutter/material.dart';

enum PlannerItemType {
  birthday,
  anniversary,
  vacation,
  event,
  reminder,
  task,
}

enum PlannerPriority {
  low,
  medium,
  high,
}

class PlannerItem {
  final String id;
  final PlannerItemType type;
  final String title;
  final String? description;
  final DateTime startDate;
  final DateTime? endDate;
  final bool isAllDay;
  final bool isCompleted;
  final bool isRecurringYearly;
  final PlannerPriority priority;
  final String? location;
  final String? createdBy;
  final DateTime createdAt;

  const PlannerItem({
    required this.id,
    required this.type,
    required this.title,
    this.description,
    required this.startDate,
    this.endDate,
    required this.isAllDay,
    required this.isCompleted,
    required this.isRecurringYearly,
    required this.priority,
    this.location,
    this.createdBy,
    required this.createdAt,
  });

  int get daysUntil {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(startDate.year, startDate.month, startDate.day);
    return target.difference(today).inDays;
  }

  bool get isUpcoming => !isCompleted && daysUntil >= 0;
  bool get isOverdue => !isCompleted && daysUntil < 0;
  bool get isToday => daysUntil == 0;

  factory PlannerItem.fromJson(Map<String, dynamic> json) {
    return PlannerItem(
      id: json['id'] as String? ?? '',
      type: _parseType(json['item_type'] as String?),
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      startDate: json['start_date'] != null
          ? DateTime.tryParse(json['start_date'] as String) ?? DateTime.now()
          : DateTime.now(),
      endDate: json['end_date'] != null
          ? DateTime.tryParse(json['end_date'] as String)
          : null,
      isAllDay: json['is_all_day'] as bool? ?? true,
      isCompleted: json['is_completed'] as bool? ?? false,
      isRecurringYearly: json['is_recurring_yearly'] as bool? ?? false,
      priority: _parsePriority(json['priority'] as String?),
      location: json['location'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  static PlannerItemType _parseType(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'birthday':
        return PlannerItemType.birthday;
      case 'anniversary':
        return PlannerItemType.anniversary;
      case 'vacation':
        return PlannerItemType.vacation;
      case 'event':
        return PlannerItemType.event;
      case 'reminder':
        return PlannerItemType.reminder;
      case 'task':
        return PlannerItemType.task;
      default:
        return PlannerItemType.event;
    }
  }

  static PlannerPriority _parsePriority(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'low':
        return PlannerPriority.low;
      case 'high':
        return PlannerPriority.high;
      default:
        return PlannerPriority.medium;
    }
  }

  static String typeKey(PlannerItemType type) {
    switch (type) {
      case PlannerItemType.birthday:
        return 'birthday';
      case PlannerItemType.anniversary:
        return 'anniversary';
      case PlannerItemType.vacation:
        return 'vacation';
      case PlannerItemType.event:
        return 'event';
      case PlannerItemType.reminder:
        return 'reminder';
      case PlannerItemType.task:
        return 'task';
    }
  }

  static String priorityKey(PlannerPriority priority) {
    switch (priority) {
      case PlannerPriority.low:
        return 'low';
      case PlannerPriority.medium:
        return 'medium';
      case PlannerPriority.high:
        return 'high';
    }
  }

  static String typeLabel(PlannerItemType type) {
    switch (type) {
      case PlannerItemType.birthday:
        return 'Birthday';
      case PlannerItemType.anniversary:
        return 'Anniversary';
      case PlannerItemType.vacation:
        return 'Vacation';
      case PlannerItemType.event:
        return 'Event';
      case PlannerItemType.reminder:
        return 'Reminder';
      case PlannerItemType.task:
        return 'Task';
    }
  }

  static String priorityLabel(PlannerPriority priority) {
    switch (priority) {
      case PlannerPriority.low:
        return 'Low';
      case PlannerPriority.medium:
        return 'Medium';
      case PlannerPriority.high:
        return 'High';
    }
  }

  static IconData iconForType(PlannerItemType type) {
    switch (type) {
      case PlannerItemType.birthday:
        return Icons.cake_outlined;
      case PlannerItemType.anniversary:
        return Icons.favorite_border_rounded;
      case PlannerItemType.vacation:
        return Icons.beach_access_outlined;
      case PlannerItemType.event:
        return Icons.event_outlined;
      case PlannerItemType.reminder:
        return Icons.notifications_active_outlined;
      case PlannerItemType.task:
        return Icons.checklist_rtl_outlined;
    }
  }

  static Color colorForType(PlannerItemType type) {
    switch (type) {
      case PlannerItemType.birthday:
        return const Color(0xFFEC4899);
      case PlannerItemType.anniversary:
        return const Color(0xFFEF4444);
      case PlannerItemType.vacation:
        return const Color(0xFF0EA5E9);
      case PlannerItemType.event:
        return const Color(0xFF7C3AED);
      case PlannerItemType.reminder:
        return const Color(0xFFF59E0B);
      case PlannerItemType.task:
        return const Color(0xFF10B981);
    }
  }
}
