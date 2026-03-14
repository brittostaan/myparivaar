# myParivaar — Bug Report

**Date:** 2026-03-14  
**Analyzer baseline:** 45 `info`-level warnings, 0 compile errors  
**Scope:** Full audit of `lib/` (all Dart files) + `supabase/functions/` directory listing  

---

## Severity Legend

| Label | Meaning |
|-------|---------|
| 🔴 Critical | App crash, data loss, or complete feature breakage |
| 🟠 High | Broken feature, repeated crash under normal use, or security concern |
| 🟡 Medium | Data inaccuracy, poor UX, or intermittent failure |
| 🔵 Low | Minor UI issue, dead code, or edge-case inconsistency |

---

## 🔴 Critical Bugs

### BUG-001 — `Expense.fromJson` Uses Hard Casts (No Null Safety)
**File:** `lib/models/expense.dart`  
**Lines:** `~37–47`

`Expense.fromJson` uses direct `as T` casts for every required field:
```dart
id:          json['id'] as String,
amount:      (json['amount'] as num).toDouble(),
category:    json['category'] as String,
description: json['description'] as String,
date:        DateTime.parse(json['date'] as String),
source:      json['source'] as String,
createdAt:   DateTime.parse(json['created_at'] as String),
updatedAt:   DateTime.parse(json['updated_at'] as String),
```
If **any** of these fields is missing or `null` in the API response, a `TypeError` is thrown at runtime and the entire expenses list or dashboard fails to load.

**Contrast:** Every other model (`AppUser`, `Budget`, `Household`) uses safe patterns like `json['x']?.toString() ?? ''`.

**Fix:** Mirror the safe approach from `AppUser.fromJson`:
```dart
id:       json['id']?.toString() ?? '',
amount:   (json['amount'] as num?)?.toDouble() ?? 0.0,
category: json['category']?.toString() ?? 'other',
// ... etc.
```

---

### BUG-002 — `Expense` Schema Mismatch: `is_approved` vs `status`
**Files:** `lib/models/expense.dart`, `lib/services/expense_service.dart`  
**Lines:** `expense.dart:~52`, `expense.dart:~66`

The database backend was updated to store transactions with a `status` field (`'pending'`, `'approved'`) instead of the old boolean `is_approved` column. However, the Dart model still reads and writes the old field:

- `fromJson` reads: `json['is_approved'] as bool? ?? true`  
- `toJson` writes: `'is_approved': isApproved`

**Impact:**
- All expenses will always appear as `isApproved: true` (the `?? true` default kicks in since `is_approved` no longer exists).
- Creating/updating expenses sends the wrong payload field, causing silent server-side errors or ignored fields.

**Fix:**
```dart
// fromJson
isApproved: (json['status']?.toString() == 'approved') || 
            (json['status']?.toString() != 'pending'),

// toJson
'status': isApproved ? 'approved' : 'pending',
```

---

### BUG-003 — `Member.fromJson` Hard Cast on Phone Field
**File:** `lib/models/member.dart`  
**Line:** `~39`

```dart
phone: (json['phone_number'] ?? json['phone']) as String,
```
If the Edge Function returns a member whose `phone_number` and `phone` are both `null` or absent, the `as String` cast throws a `TypeError`, crashing the entire Family Management screen.

**Fix:**
```dart
phone: (json['phone_number'] ?? json['phone'])?.toString() ?? '',
```

---

### BUG-004 — Budget Edge Functions Do Not Exist in Backend
**File:** `lib/services/budget_service.dart`  
**Backend:** `supabase/functions/` directory

`BudgetService` calls three Edge Functions that are **not deployed**:
- `budget-list`
- `budget-upsert`
- `budget-delete`

The deployed functions directory contains only: `expense-*`, `household-*`, `ai-*`, `email-*`, `auth-bootstrap`, `import-csv`, `user-update`.

**Impact:** Every action on the Budget screen fails with a `404 Not Found` or CORS error. The entire Budget feature is non-functional.

**Fix:** Either deploy the three missing Edge Functions, or add a clear "coming soon" placeholder to `BudgetScreen` that avoids calling `BudgetService`.

---

### BUG-005 — `NavigationShell` Stacks Routes on Every Tab Tap
**File:** `lib/widgets/navigation_shell.dart`  
**Line:** `~60`

```dart
Navigator.of(context).pushNamed(targetRoute);
```

Every time the user taps a bottom nav tab, a new route is **pushed** onto the navigation stack. After visiting 5 tabs, pressing the back button navigates back through every previously visited tab in reverse order instead of exiting the app.

**Fix:** Use `pushReplacementNamed` (or `pushNamedAndRemoveUntil`) so each tab replaces the current route:
```dart
Navigator.of(context).pushReplacementNamed(targetRoute);
```

---

## 🟠 High Bugs

### BUG-006 — `BuildContext` Used Across Async Gaps (5 Files)
**Files / Lines (as reported by `flutter analyze`):**
- `lib/main.dart:211`
- `lib/screens/admin_settings_screen.dart:240`
- `lib/screens/email_settings_screen.dart:222`
- `lib/screens/expense_management_screen.dart:111`
- `lib/screens/user_settings_screen.dart:129`

In all five locations, `context` (or a `context`-dependent call like `Provider.of<AuthService>(context)` or `ScaffoldMessenger.of(context)`) is used **after** an `await` without first checking `if (!mounted) return`. If the widget is disposed during the async gap (e.g., user navigates away), this causes a crash: `"Looking up a deactivated widget's ancestor is unsafe"`.

**Fix pattern:**
```dart
final authService = Provider.of<AuthService>(context, listen: false); // capture before await
final token = await authService.getIdToken();
if (!mounted) return; // guard after every await
```

---

### BUG-007 — `EmailService` Uses Wrong HTTP Methods for Edge Functions
**File:** `lib/services/email_service.dart`  
**Lines:** `getEmailAccounts (~55)`, `disconnectEmailAccount (~97)`

```dart
// getEmailAccounts — uses GET
final response = await http.get(
  Uri.parse('$supabaseUrl/functions/v1/email-accounts'), ...
);

// disconnectEmailAccount — uses DELETE
final response = await http.delete(
  Uri.parse('$supabaseUrl/functions/v1/email-accounts/$accountId'), ...
);
```

Supabase Edge Functions only handle `POST` (and `OPTIONS` for CORS). A `GET` or `DELETE` request will return `405 Method Not Allowed` or be blocked by the CORS preflight.

**Fix:** Convert both calls to `http.post`, encoding the intent in the request body:
```dart
// getEmailAccounts
await http.post(..., body: jsonEncode({'action': 'list'}));

// disconnectEmailAccount
await http.post(..., body: jsonEncode({'action': 'delete', 'account_id': accountId}));
```
(Alternatively, update the `email-accounts` Edge Function to accept `GET`/`DELETE`, but POST is standard for Supabase Edge Functions.)

---

### BUG-008 — `EmailService.syncEmails` Sends POST Without a Body
**File:** `lib/services/email_service.dart`  
**Line:** `~112`

```dart
final response = await http.post(
  Uri.parse('$supabaseUrl/functions/v1/email-syncNow'),
  headers: { 'Authorization': 'Bearer $idToken', 'Content-Type': 'application/json' },
  // ← no body argument
);
```

The `Content-Type: application/json` header is set but no body is sent. Deno's `request.json()` in the Edge Function will throw a JSON parse error, causing the sync to always fail.

**Fix:**
```dart
body: jsonEncode({}),
```

---

### BUG-009 — `_looksLikeTerminalAuthError` Is Overly Broad (Silent Auto-Logout)
**File:** `lib/services/auth_service.dart`  
**Lines:** `~238–243`

```dart
bool _looksLikeTerminalAuthError(String message) {
  final m = message.toLowerCase();
  return m.contains('auth') || m.contains('jwt') || m.contains('token');
}
```

Any exception whose `.toString()` contains the substrings `'auth'`, `'jwt'`, or `'token'` triggers an automatic `signOut()`. This is dangerously broad:

- A network error like `"Failed to authenticate proxy"` signs the user out.
- A Supabase error like `"auth-bootstrap returned 503"` signs the user out.
- Any HTTP response body mentioning "token" in an error description signs the user out.

**Impact:** Users are randomly logged out on transient network errors with no explanation.

**Fix:** Match on specific, well-known terminal auth error codes/messages rather than free-text substrings, or remove the auto-signout from the `refreshSession` catch block entirely and let callers decide.

---

### BUG-010 — `VoiceExpenseScreen` Has No Registered Route (Unreachable)
**File:** `lib/screens/voice_expense_screen.dart`  
**Cross-reference:** `lib/main.dart` (`_onGenerateRoute`)

`VoiceExpenseScreen` is defined but:
1. Never imported in `main.dart`
2. Has no route entry in `_onGenerateRoute`
3. No `Navigator.pushNamed('/voice-expense')` call exists anywhere in the app

The screen is completely **unreachable** at runtime. The `MoreScreen` (the intended entry point) is a placeholder displaying "Content coming soon..." — all secondary features (voice, AI, CSV import from More, notifications) are inaccessible unless the user knows the route string.

**Fix:** Register the route in `_onGenerateRoute` and add entries in `MoreScreen`.

---

## 🟡 Medium Bugs

### BUG-011 — `NotificationService.checkBudgetAlerts` Uses Hardcoded Data
**File:** `lib/services/notification_service.dart`  
**Lines:** `~143–172`

```dart
final monthlyBudgets = {
  'Food': 10000.0,
  'Transport': 5000.0,
  'Shopping': 6000.0,
};

final currentSpending = {
  'Food': 8500.0,
  'Transport': 4200.0,
  'Shopping': 5800.0,
};
```

These hardcoded values are never updated from actual `BudgetService` or `ExpenseService` data. Budget alerts will fire based on fictional numbers regardless of the user's actual budgets and spending, making them meaningless.

**Fix:** Inject `BudgetService` and `ExpenseService` and fetch real data, or remove `checkBudgetAlerts` until live data integration is built.

---

### BUG-012 — `NotificationService.checkBillReminders` Creates Duplicate Notifications
**File:** `lib/services/notification_service.dart`  
**Lines:** `~174–182`

```dart
Future<void> checkBillReminders() async {
  final now = DateTime.now();
  final tomorrow = DateTime(now.year, now.month, now.day + 1);

  await scheduleBillReminder(
    title: 'Internet Bill Due Tomorrow',
    body: '...',
    scheduleDate: tomorrow,
    billId: 'internet_001',
  );
}
```

`checkBillReminders` unconditionally creates a new notification **every time it is called** with no deduplication by `billId`. Multiple calls (e.g., from background refresh or screen re-entry) flood the notification list with identical entries.

**Fix:** Before inserting, check if a notification for `billId` already exists:
```dart
final exists = _notifications.any((n) => n.data['billId'] == billId);
if (exists) return;
```

---

### BUG-013 — `StateError` Thrown in `main()` Before `runApp()`
**File:** `lib/main.dart`  
**Line:** `~73`

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _validateSupabaseConfig(); // ← throws StateError if invalid
  ...
  runApp(...);
}
```

If `_validateSupabaseConfig()` throws, it happens before `runApp()`, so there is no Flutter widget tree to display an error. The user sees a blank screen or a raw platform error with no actionable message.

**Fix:** Wrap the validation inside a `try/catch` and call `runApp(ErrorApp(...))` with a human-readable message on failure:
```dart
try {
  _validateSupabaseConfig();
} catch (e) {
  runApp(MaterialApp(home: Scaffold(body: Center(child: Text('$e')))));
  return;
}
```

---

### BUG-014 — Dashboard Double API Fetch on Stats Fallback
**File:** `lib/screens/dashboard_screen.dart`  
**Lines:** `~57–78`

When `expense-stats` fails, the code immediately makes a second API call to fetch **all** expenses (no limit) to manually compute `totalBalance`:

```dart
try {
  final stats = await _expenseService.getExpenseStats(...);
  ...
} catch (statsError) {
  // Falls back to re-fetching ALL expenses without a limit
  final allExpenses = await _expenseService.getExpenses(
    supabaseUrl: supabaseUrl,
    idToken: idToken,
    // ← no limit parameter
  );
  ...
}
```

If `expense-stats` is unavailable indefinitely, every dashboard load makes **2 API calls** and discards the result of the initial `limit: 10` fetch. This is wasteful and adds latency.

**Fix:** If the stats fallback is needed, reuse the already-fetched `expenses` list. The full refetch is unnecessary.

---

### BUG-015 — `BalanceCard` Label Says "Expense vs Budget" but Shows Total Balance
**File:** `lib/widgets/balance_card.dart`  
**Line:** `~72`

```dart
Text('Expense vs Budget', style: AppTextStyles.cardSubtitle(...)),
```

The card title always reads "Expense vs Budget" but the large number displayed is `totalBalance` (total income minus total expenses). This is a misleading label that will confuse users.

**Fix:** Change label to `'Total Balance'` or pass it as a widget parameter.

---

### BUG-016 — `EmailSettingsScreen._connectEmailAccount` — Async Gap After Dialog
**File:** `lib/screens/email_settings_screen.dart`  
**Line:** `~75–82`

```dart
showDialog(...); // ← not awaited
final authService = Provider.of<AuthService>(context, listen: false);
final authUrl = await _emailService.getEmailConnectUrl(
  idToken: await authService.getIdToken(),
  ...
);
```

`showDialog` is called without `await`, then `Provider.of(context)` and `getIdToken()` are called while the loading dialog is open and after an `await`. If the widget is unmounted, this crashes. Additionally, without `await` on `showDialog`, the UI may not appear before the provider call.

**Fix:** Capture `authService` before showing any dialog, and add `if (!mounted) return` after every `await`.

---

### BUG-017 — `ImportResult.fromJson` Hard Casts on `RowError` Fields
**File:** `lib/models/import_result.dart`  
**Lines:** `~14–16`

```dart
factory RowError.fromJson(Map<String, dynamic> json) => RowError(
  row:     json['row']     as int,
  field:   json['field']   as String,
  message: json['message'] as String,
);
```

If the Edge Function returns any row-error object with a missing or null field, this throws a `TypeError`, crashing the CSV import preview flow.

**Fix:**
```dart
row:     (json['row'] as int?) ?? 0,
field:   json['field']?.toString() ?? '',
message: json['message']?.toString() ?? 'Unknown error',
```

---

## 🔵 Low / Style Bugs

### BUG-018 — `QuickActionsGrid` Renders Ghost Cell When `actions.length == 1`
**File:** `lib/widgets/quick_actions_grid.dart`  
**Line:** `~46`

```dart
crossAxisCount: actions.length.clamp(2, 4),
```

`clamp(2, 4)` never allows 1 column. A single action renders in a 2-column grid, leaving an empty cell that looks like a broken layout.

**Fix:** `crossAxisCount: actions.length.clamp(1, 4)`

---

### BUG-019 — `_ResponsiveWrapper` Hardcodes `Colors.white` (Dark Mode Incompatible)
**File:** `lib/main.dart`  
**Lines:** `~753–757`

```dart
Container(
  color: Colors.white,       // ← hardcoded
  child: Center(
    child: Container(
      decoration: BoxDecoration(color: Colors.white, ...),
```

The outer wrapper is always white, so enabling dark mode in the future would show mismatched white borders around the constrained viewport. Should use `Theme.of(context).scaffoldBackgroundColor`.

---

### BUG-020 — `VoiceService.parseExpenseFromVoice` — Regex Captures First Number
**File:** `lib/services/voice_service.dart`  
**Lines:** `~67–72`

```dart
RegExp amountRegex = RegExp(r'(\d+(?:\.\d{1,2})?)\s*(?:rupees?|rs\.?|inr)?');
final amountMatch = amountRegex.firstMatch(text);
```

`firstMatch` grabs the **first** number in the text. For input like `"bought 2 coffees at 150 rupees"`, the captured amount is `2`, not `150`.

**Fix:** Prefer `lastMatch` when no currency word immediately follows, or find the match closest to the currency keyword.

---

### BUG-021 — `AppUser.supabaseUserId` Returns `''` Instead of Failing Explicitly
**File:** `lib/models/app_user.dart`  
**Line:** `~50`

```dart
supabaseUserId: json['firebase_uid']?.toString() ?? '',
```

An empty string `''` silently passes through wherever the user ID is used, instead of indicating "not set". Downstream callers (e.g., admin checks, API calls) may silently act on an empty string user ID without error.

**Fix:** Return `null` and type the field as `String?`, or assert the value is non-empty in debug builds.

---

### BUG-022 — `Expense` Date Parsing Ignores Timezone
**File:** `lib/models/expense.dart`  
**Line:** `~43`

```dart
date: DateTime.parse(json['date'] as String),
```

When the API returns a date-only string like `"2026-03-01"`, Dart's `DateTime.parse` treats it as **UTC midnight**. For users in UTC+5:30 (IST), `2026-03-01 UTC` displayed in local time becomes `2026-03-01 05:30 IST` — still on the 1st — but edge cases near midnight can show the **previous day**.

**Fix:**
```dart
date: DateTime.parse('${json['date']}T00:00:00').toLocal(),
// or store as UTC and display with DateFormat in local timezone
```

---

### BUG-023 — `DashboardScreen` Race Condition on Concurrent Refresh
**File:** `lib/screens/dashboard_screen.dart`  
**Lines:** `~38–95`

If the user pulls to refresh while the initial load is still in progress, two concurrent calls to `_loadDashboardData()` run simultaneously. Both eventually call `setState`, and the last to complete wins — which may be the earlier (slower) call, leading to briefly stale data being displayed.

**Fix:** Add an `_isFetching` guard or cancel the previous request before starting a new one.

---

### BUG-024 — `MoreScreen` Is a Non-Functional Placeholder
**File:** `lib/screens/more_screen.dart`

The `/more` route, which occupies a permanent bottom-nav slot, shows only "Content coming soon...". Features like AI chat, voice expense entry, CSV import, and notifications are not linked from `MoreScreen` even though their screens exist and are functional. Users have no discoverability path to these features via the "More" tab.

---

### BUG-025 — `SocketException` Catch in `_withRetry` Is Dead Code on Web
**File:** `lib/services/auth_service.dart`  
**Lines:** `~255–258`

```dart
import 'dart:io';
...
on SocketException catch (e) {
  lastError = e;
}
```

Flutter Web does not throw `dart:io`'s `SocketException`; it throws `http.ClientException`. On the web target (the primary target of this app), this catch block is never reached. The `dart:io` import and `SocketException` handling are dead code for web.

**Fix:** Remove `import 'dart:io'` and the `SocketException` catch branch, or guard with `if (!kIsWeb)`.

---

## Summary Table

| ID | Severity | File | Description |
|----|----------|------|-------------|
| BUG-001 | 🔴 Critical | `models/expense.dart` | Hard casts in `fromJson` crash on any null field |
| BUG-002 | 🔴 Critical | `models/expense.dart` | `is_approved` field vs backend `status` mismatch |
| BUG-003 | 🔴 Critical | `models/member.dart` | `phone` hard cast — crash if both fields null |
| BUG-004 | 🔴 Critical | `services/budget_service.dart` | Budget Edge Functions missing — entire feature broken |
| BUG-005 | 🔴 Critical | `widgets/navigation_shell.dart` | `pushNamed` stacks routes — back button walks tab history |
| BUG-006 | 🟠 High | 5 files | `BuildContext` across async gaps — crash after dispose |
| BUG-007 | 🟠 High | `services/email_service.dart` | `http.get` / `http.delete` — wrong method for Edge Functions |
| BUG-008 | 🟠 High | `services/email_service.dart` | `syncEmails` sends no body — Edge Function parse error |
| BUG-009 | 🟠 High | `services/auth_service.dart` | `_looksLikeTerminalAuthError` too broad — silent auto-logout |
| BUG-010 | 🟠 High | `screens/voice_expense_screen.dart` | No route registered — screen unreachable |
| BUG-011 | 🟡 Medium | `services/notification_service.dart` | Hardcoded budget/spending data — alerts always inaccurate |
| BUG-012 | 🟡 Medium | `services/notification_service.dart` | No dedup in `checkBillReminders` — duplicate notifications |
| BUG-013 | 🟡 Medium | `main.dart` | `StateError` before `runApp` — blank screen on bad config |
| BUG-014 | 🟡 Medium | `screens/dashboard_screen.dart` | Double API fetch on stats fallback |
| BUG-015 | 🟡 Medium | `widgets/balance_card.dart` | "Expense vs Budget" label on total-balance value |
| BUG-016 | 🟡 Medium | `screens/email_settings_screen.dart` | Async gap after `showDialog` — context use-after-dispose |
| BUG-017 | 🟡 Medium | `models/import_result.dart` | Hard casts in `RowError.fromJson` crash on null field |
| BUG-018 | 🔵 Low | `widgets/quick_actions_grid.dart` | `clamp(2,4)` renders ghost cell for single action |
| BUG-019 | 🔵 Low | `main.dart` | `Colors.white` hardcoded in responsive wrapper |
| BUG-020 | 🔵 Low | `services/voice_service.dart` | Regex captures first number, not the amount |
| BUG-021 | 🔵 Low | `models/app_user.dart` | `supabaseUserId` defaults to `''` instead of null |
| BUG-022 | 🔵 Low | `models/expense.dart` | Date parsing ignores timezone — potential off-by-one-day |
| BUG-023 | 🔵 Low | `screens/dashboard_screen.dart` | Race condition on concurrent refresh |
| BUG-024 | 🔵 Low | `screens/more_screen.dart` | `MoreScreen` is placeholder — features unreachable |
| BUG-025 | 🔵 Low | `services/auth_service.dart` | `SocketException` catch is dead code on Flutter Web |

---

**Total:** 5 Critical · 5 High · 7 Medium · 8 Low = **25 bugs**

---

*Generated by GitHub Copilot static analysis pass — 2026-03-14*
