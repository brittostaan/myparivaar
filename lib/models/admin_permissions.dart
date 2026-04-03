class AdminPermissions {
  const AdminPermissions._();

  static const viewDashboard = 'view_dashboard';
  static const viewHouseholds = 'view_households';
  static const manageHouseholds = 'manage_households';
  static const viewUsers = 'view_users';
  static const manageUsers = 'manage_users';
  static const moderateContent = 'moderate_content';
  static const manageSupportTickets = 'manage_support_tickets';
  static const manageStaff = 'manage_staff';
  static const manageFeatures = 'manage_features';
  static const viewAuditLogs = 'view_audit_logs';
  static const viewAnalytics = 'view_analytics';
  static const exportReports = 'export_reports';
  static const manageSecurity = 'manage_security';

  static const all = <String>{
    viewDashboard,
    viewHouseholds,
    manageHouseholds,
    viewUsers,
    manageUsers,
    moderateContent,
    manageSupportTickets,
    manageStaff,
    manageFeatures,
    viewAuditLogs,
    viewAnalytics,
    exportReports,
    manageSecurity,
  };

  static const superAdminDefaults = <String>{
    viewDashboard,
    viewHouseholds,
    manageHouseholds,
    viewUsers,
    manageUsers,
    moderateContent,
    manageSupportTickets,
    manageStaff,
    manageFeatures,
    viewAuditLogs,
    viewAnalytics,
    exportReports,
    manageSecurity,
  };

  static const supportAdminDefaults = <String>{
    viewDashboard,
    viewHouseholds,
    viewUsers,
    moderateContent,
    manageSupportTickets,
    viewAuditLogs,
    viewAnalytics,
  };

  static const customerServiceDefaults = <String>{
    viewDashboard,
    viewUsers,
    manageUsers,
    viewHouseholds,
    manageSupportTickets,
    viewAuditLogs,
  };

  static const readerDefaults = <String>{
    viewDashboard,
    viewUsers,
    viewHouseholds,
    viewAnalytics,
    viewAuditLogs,
  };

  static const billingServiceDefaults = <String>{
    viewDashboard,
    viewUsers,
    viewAnalytics,
  };

  static Set<String> defaultsForRole(String? staffRole) {
    switch (staffRole) {
      case 'super_admin':
        return superAdminDefaults;
      case 'support_staff':
        return supportAdminDefaults;
      case 'customer_service':
        return customerServiceDefaults;
      case 'reader':
        return readerDefaults;
      case 'billing_service':
        return billingServiceDefaults;
      default:
        return <String>{};
    }
  }
}