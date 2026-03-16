import 'package:flutter/material.dart';

/// Centralized icon constants for the MyParivaar app.
/// All icon references should use this class to ensure consistency.
/// 
/// SINGLE SOURCE OF TRUTH - DO NOT USE Icons.* DIRECTLY IN WIDGETS
class AppIcons {
  // ── Navigation Icons ────────────────────────────────────────────────────────
  
  static const IconData home = Icons.home;
  static const IconData homeOutlined = Icons.home_outlined;
  static const IconData wallet = Icons.account_balance_wallet;
  static const IconData walletOutlined = Icons.account_balance_wallet_outlined;
  static const IconData analytics = Icons.analytics;
  static const IconData analyticsOutlined = Icons.analytics_outlined;
  static const IconData settings = Icons.settings;
  static const IconData settingsOutlined = Icons.settings_outlined;
  
  // ── Category Icons ──────────────────────────────────────────────────────────
  
  static const IconData food = Icons.restaurant;
  static const IconData groceries = Icons.shopping_cart;
  static const IconData transport = Icons.directions_car;
  static const IconData shopping = Icons.shopping_bag;
  static const IconData utilities = Icons.home;
  static const IconData healthcare = Icons.local_hospital;
  static const IconData entertainment = Icons.movie;
  static const IconData gifts = Icons.card_giftcard;
  static const IconData income = Icons.payments;
  static const IconData education = Icons.school;
  static const IconData category = Icons.category;
  
  // ── Action Icons ────────────────────────────────────────────────────────────
  
  static const IconData add = Icons.add;
  static const IconData addCircle = Icons.add_circle_outline;
  static const IconData camera = Icons.camera_alt;
  static const IconData edit = Icons.edit;
  static const IconData delete = Icons.delete;
  static const IconData deleteForever = Icons.delete_forever;
  static const IconData save = Icons.save;
  static const IconData refresh = Icons.refresh;
  static const IconData send = Icons.send;
  static const IconData check = Icons.check;
  static const IconData copy = Icons.copy_outlined;
  static const IconData upload = Icons.upload_file;
  static const IconData cloudUpload = Icons.cloud_upload_outlined;
  static const IconData download = Icons.download;
  static const IconData sync = Icons.sync;
  
  // ── Status & Notification Icons ─────────────────────────────────────────────
  
  static const IconData error = Icons.error_outline;
  static const IconData warning = Icons.warning;
  static const IconData warningAmber = Icons.warning_amber_outlined;
  static const IconData checkCircle = Icons.check_circle_outline;
  static const IconData checkCircleFilled = Icons.check_circle;
  static const IconData info = Icons.info_outline;
  static const IconData notifications = Icons.notifications;
  static const IconData notificationsOutlined = Icons.notifications_outlined;
  static const IconData notificationsActive = Icons.notifications_active;
  static const IconData trendingUp = Icons.trending_up;
  static const IconData trendingDown = Icons.trending_down;
  
  // ── Communication Icons ─────────────────────────────────────────────────────
  
  static const IconData email = Icons.email;
  static const IconData emailOutlined = Icons.email_outlined;
  static const IconData mic = Icons.mic;
  static const IconData micOutlined = Icons.mic_outlined;
  static const IconData stop = Icons.stop;
  static const IconData chat = Icons.chat_bubble_outline;
  
  // ── User & People Icons ─────────────────────────────────────────────────────
  
  static const IconData person = Icons.person;
  static const IconData people = Icons.people;
  static const IconData groupOutlined = Icons.group_outlined;
  static const IconData personAdd = Icons.person_add_outlined;
  static const IconData personRemove = Icons.person_remove_outlined;
  static const IconData adminPanel = Icons.admin_panel_settings;
  
  // ── UI & Navigation Icons ───────────────────────────────────────────────────
  
  static const IconData arrowForward = Icons.arrow_forward_ios;
  static const IconData expandLess = Icons.expand_less;
  static const IconData expandMore = Icons.expand_more;
  static const IconData openInNew = Icons.open_in_new;
  static const IconData close = Icons.close;
  static const IconData calendar = Icons.calendar_today;
  
  // ── Device & View Mode Icons ────────────────────────────────────────────────
  
  static const IconData laptop = Icons.laptop;
  static const IconData tablet = Icons.tablet_mac;
  static const IconData phone = Icons.phone_iphone;
  static const IconData phoneOutlined = Icons.phone_outlined;
  
  // ── Finance & Transaction Icons ─────────────────────────────────────────────
  
  static const IconData receipt = Icons.receipt_long;
  static const IconData receiptOutlined = Icons.receipt_long_outlined;
  static const IconData pieChart = Icons.pie_chart_outline;
  static const IconData timeline = Icons.timeline;
  static const IconData swapHoriz = Icons.swap_horiz;
  static const IconData factCheck = Icons.fact_check_outlined;
  
  // ── AI & Insight Icons ─────────────────────────────────────────────────────
  
  static const IconData insights = Icons.insights;
  static const IconData smartToy = Icons.smart_toy;
  static const IconData summarize = Icons.summarize;
  
  // ── Security & Privacy Icons ────────────────────────────────────────────────
  
  static const IconData lock = Icons.lock;
  static const IconData privacyTip = Icons.privacy_tip;
  static const IconData link = Icons.link;
  static const IconData linkOff = Icons.link_off;
  
  // ── Other Icons ─────────────────────────────────────────────────────────────
  
  static const IconData document = Icons.description;
  static const IconData wifiOff = Icons.wifi_off_rounded;
  static const IconData markEmailRead = Icons.mark_email_read;
  static const IconData clearAll = Icons.clear_all;
  
  // ── Category Icon Helper ────────────────────────────────────────────────────
  
  /// Get icon for expense category
  static IconData getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'food':
      case 'groceries':
        return groceries;
      case 'transport':
      case 'transportation':
        return transport;
      case 'shopping':
        return shopping;
      case 'utilities':
        return utilities;
      case 'healthcare':
      case 'health':
        return healthcare;
      case 'entertainment':
        return entertainment;
      case 'gifts':
        return gifts;
      case 'income':
      case 'salary':
        return income;
      case 'education':
        return education;
      default:
        return AppIcons.category;
    }
  }
}
