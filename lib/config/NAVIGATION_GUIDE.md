# Centralized Navigation System

## Overview
The app now has a **centralized, context-aware bottom navigation system** that automatically applies to all screens based on configuration.

## Architecture

### 1. Navigation Configuration (`lib/config/navigation_config.dart`)
Central file that defines which navigation items appear on each screen.

**Key Components:**
- `NavigationItem` - Model for a single nav item (label, icon, routeName)
- `NavigationConfig` - Main configuration map: route → list of nav items
- Helper methods to query nav items for any route

**Current Configuration:**
- `/home`, `/expenses`, `/ai`, `/user-settings` → Standard 4-tab nav (Home, Wallet, Analytics, Settings)
- `/admin-settings` → Home, Settings, Admin
- `/family` → Home, Family, Settings  
- `/email-settings` → Home, Email, Settings
- `/voice-expense` → Home, Voice, Expenses
- `/notifications` → Home, Notifications, Settings
- `/csv-import` → Home, Import, Expenses

### 2. Navigation Shell (`lib/widgets/navigation_shell.dart`)
Wrapper widget that adds bottom navigation to any screen.

**How it works:**
1. Queries `NavigationConfig` for the current route's nav items
2. Shows bottom navigation if items are configured
3. Highlights active tab based on current route
4. Handles tab taps by navigating to target route 5. Returns child unwrapped if no navigation configured

### 3. Enhanced Bottom Navigation Bar (`lib/widgets/app_bottom_navigation_bar.dart`)
Existing component now enhanced with:
- Theme integration using `AppColors`
- Consistent typography and spacing
- Active/inactive state colors

### 4. Route Integration (`lib/main.dart`)
All authenticated routes automatically wrapped with `NavigationShell`:
- `/home`, `/expenses`, `/ai`, `/user-settings` ✅
- `/admin-settings`, `/family`, `/email-settings` ✅
- `/voice-expense`, `/notifications`, `/csv-import` ✅
- Auth screens (`/login`, `/household-setup`) excluded ✅

## Adding Navigation to New Screens

**It's automatic!** Just add one entry to the configuration map:

```dart
// In lib/config/navigation_config.dart

static final Map<String, List<NavigationItem>> _routeNavigationMap = {
  // ... existing routes ...
  
  '/my-new-screen': [
    NavigationItem(
      label: 'Home',
      icon: AppIcons.homeOutlined,
      filledIcon: AppIcons.home,
      routeName: '/home',
    ),
    NavigationItem(
      label: 'My Screen',
      icon: AppIcons.someIcon,
      routeName: '/my-new-screen',
    ),
    // Add more nav items as needed
  ],
};
```

Then create your route in `lib/main.dart`:

```dart
case '/my-new-screen':
  return MaterialPageRoute(
    settings: settings,
    builder: (_) => NavigationShell(
      currentRoute: routeName,
      child: const MyNewScreen(),
    ),
  );
```

**That's it!** The NavigationShell automatically applies the navigation.

## Modifying Navigation for Existing Screens

Simply edit the configuration map in [lib/config/navigation_config.dart](lib/config/navigation_config.dart):

```dart
// Change nav items for a screen
'/expenses': [
  NavigationItem(label: 'Home', icon: AppIcons.homeOutlined, routeName: '/home'),
  NavigationItem(label: 'Budget', icon: AppIcons.pieChart, routeName: '/budget'),
  NavigationItem(label: 'Reports', icon: AppIcons.insights, routeName: '/reports'),
],
```

## Removing Navigation from a Screen

Remove the route entry from `_routeNavigationMap`, or wrap with regular MaterialPageRoute without NavigationShell.

## Available Icons

All icons are defined in [lib/theme/app_icons.dart](lib/theme/app_icons.dart). Common patterns:
- `AppIcons.home` / `AppIcons.homeOutlined`
- `AppIcons.settings` / `AppIcons.settingsOutlined`
- `AppIcons.notifications` / `AppIcons.notificationsOutlined`
- `AppIcons.wallet`, `Analytics`, `mic`, `email`, `receipt`, etc.

Use outlined versions for unselected state, filled for selected (if available).

## Key Benefits

✅ **Single source of truth** - All navigation config in one file
✅ **Automatic application** - No need to add navigation code to each screen
✅ **Flexible configuration** - Each screen can have different nav items
✅ **Type-safe** - Compile-time checking of routes and icons
✅ **Consistent styling** - Uses centralized theme colors and spacing
✅ **Easy to modify** - Change navigation for any screen in one place
✅ **Future-proof** - New screens automatically get navigation with one config entry

## Migration Complete

**Cleaned up:**
- Removed manual navigation from `DashboardScreen`
- Removed `_currentNavIndex` state variable
- Removed `_onNavItemTapped` method
- Removed `bottomNavigationBar` property from Scaffold

**All navigation now managed centrally by NavigationShell + NavigationConfig.**
