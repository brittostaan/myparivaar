import subprocess, time

REPO = "brittostaan/myparivaar"

issues = [
    {
        "title": "BUG-001: Expense.fromJson uses hard casts - crashes on any null field",
        "labels": "bug,priority: critical",
        "body": """**File:** `lib/models/expense.dart` (~lines 37-47)

`Expense.fromJson` uses direct `as T` casts for every required field. If **any** field is missing or `null` in the API response, a `TypeError` is thrown and the entire expenses list / dashboard fails to load.

**Affected fields:** id, amount, category, description, date, source, createdAt, updatedAt

**Fix:** Use safe null-fallback patterns matching `AppUser.fromJson`:
- `json['id']?.toString() ?? ''`
- `(json['amount'] as num?)?.toDouble() ?? 0.0`
- `json['category']?.toString() ?? 'other'`

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-002: Expense schema mismatch - is_approved vs status field",
        "labels": "bug,priority: critical",
        "body": """**Files:** `lib/models/expense.dart`, `lib/services/expense_service.dart`

The backend was updated to use a `status` field ('pending'/'approved') but the Dart model still reads/writes `is_approved`.

**Impact:**
- All expenses always appear approved (`?? true` default fires since field no longer exists)
- Creating/updating expenses sends wrong payload causing silent server-side errors

**Fix:**
- fromJson: `isApproved: json['status']?.toString() == 'approved'`
- toJson: `'status': isApproved ? 'approved' : 'pending'`

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-003: Member.fromJson hard cast on phone field - crash if null",
        "labels": "bug,priority: critical",
        "body": """**File:** `lib/models/member.dart` (~line 39)

`phone: (json['phone_number'] ?? json['phone']) as String`

If both fields are null/absent the `as String` cast throws a `TypeError`, crashing the entire Family Management screen.

**Fix:** `phone: (json['phone_number'] ?? json['phone'])?.toString() ?? ''`

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-004: Budget Edge Functions missing - Budget feature completely broken",
        "labels": "bug,priority: critical",
        "body": """**File:** `lib/services/budget_service.dart`

BudgetService calls three Edge Functions that are **not deployed**:
- `budget-list`
- `budget-upsert`
- `budget-delete`

Every action on the Budget screen fails with 404 Not Found or a CORS error. The entire Budget feature is non-functional.

**Fix:** Deploy the three missing Edge Functions, or replace BudgetScreen with a 'coming soon' placeholder until they exist.

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-005: NavigationShell stacks routes on every tab tap - broken back button",
        "labels": "bug,priority: critical",
        "body": """**File:** `lib/widgets/navigation_shell.dart` (~line 60)

`Navigator.of(context).pushNamed(targetRoute)` pushes a new route on every tab tap. After visiting multiple tabs, the back button walks the full tab history instead of exiting the app.

**Fix:** Use `pushReplacementNamed` so each tab replaces the current route:
```dart
Navigator.of(context).pushReplacementNamed(targetRoute);
```

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-006: BuildContext used across async gaps in 5 files - crash after widget dispose",
        "labels": "bug,priority: high",
        "body": """**Files affected:**
- `lib/main.dart:211`
- `lib/screens/admin_settings_screen.dart:240`
- `lib/screens/email_settings_screen.dart:222`
- `lib/screens/expense_management_screen.dart:111`
- `lib/screens/user_settings_screen.dart:129`

Context is used after an `await` without checking `if (!mounted) return`. If the widget is disposed during the async gap the app crashes with: _"Looking up a deactivated widget's ancestor is unsafe"_.

**Fix pattern:**
```dart
final authService = Provider.of<AuthService>(context, listen: false); // capture before await
final token = await authService.getIdToken();
if (!mounted) return; // guard after every await
```

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-007: EmailService uses wrong HTTP methods (GET/DELETE) for Edge Functions",
        "labels": "bug,priority: high",
        "body": """**File:** `lib/services/email_service.dart`

- `getEmailAccounts` uses `http.get` -> returns 405 Method Not Allowed
- `disconnectEmailAccount` uses `http.delete` -> blocked by CORS preflight

Supabase Edge Functions only accept POST (and OPTIONS for CORS).

**Fix:** Convert both calls to `http.post`, encoding the intent in the body:
- getEmailAccounts: `body: jsonEncode({'action': 'list'})`
- disconnectEmailAccount: `body: jsonEncode({'action': 'delete', 'account_id': accountId})`

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-008: EmailService.syncEmails sends POST without a body - Edge Function parse error",
        "labels": "bug,priority: high",
        "body": """**File:** `lib/services/email_service.dart` (~line 112)

Content-Type is set to `application/json` but no body is provided. Deno's `request.json()` throws a JSON parse error, causing email sync to always fail.

**Fix:** Add `body: jsonEncode({})` to the `syncEmails` POST call.

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-009: _looksLikeTerminalAuthError too broad - random silent auto-logout",
        "labels": "bug,priority: high",
        "body": """**File:** `lib/services/auth_service.dart` (~lines 238-243)

The method matches any error string containing 'auth', 'jwt', or 'token' and triggers automatic `signOut()`. This is dangerously broad:
- "Failed to authenticate proxy" -> signs user out
- "auth-bootstrap returned 503" -> signs user out

**Impact:** Users are randomly logged out on transient network errors with no explanation.

**Fix:** Match only specific known terminal auth error codes, or remove the auto-signout from `refreshSession` entirely and let callers decide.

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-010: VoiceExpenseScreen has no registered route - screen completely unreachable",
        "labels": "bug,priority: high",
        "body": """**File:** `lib/screens/voice_expense_screen.dart`

VoiceExpenseScreen is defined but:
1. Never imported in `main.dart`
2. Has no route entry in `_onGenerateRoute`
3. No `pushNamed('/voice-expense')` call exists anywhere

MoreScreen (the intended entry point) shows only "Content coming soon..."

**Fix:** Register `/voice-expense` in `_onGenerateRoute` and add navigation entries in `MoreScreen`.

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-011: NotificationService.checkBudgetAlerts uses hardcoded budget/spending data",
        "labels": "bug,priority: medium",
        "body": """**File:** `lib/services/notification_service.dart` (~lines 143-172)

`monthlyBudgets` and `currentSpending` are hardcoded with fictional values and never updated from real service data. Budget alerts fire based on made-up numbers regardless of the user's actual budgets and spending.

**Fix:** Inject `BudgetService` and `ExpenseService` with real data, or remove `checkBudgetAlerts` until live data integration is built.

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-012: NotificationService.checkBillReminders creates duplicate notifications on every call",
        "labels": "bug,priority: medium",
        "body": """**File:** `lib/services/notification_service.dart` (~lines 174-182)

`checkBillReminders` unconditionally creates a new notification every time it is called with no deduplication by `billId`. Multiple calls flood the notification list with identical entries.

**Fix:** Check for existing notifications before inserting:
```dart
final exists = _notifications.any((n) => n.data['billId'] == billId);
if (exists) return;
```

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-013: StateError thrown in main() before runApp() - blank screen on bad config",
        "labels": "bug,priority: medium",
        "body": """**File:** `lib/main.dart` (~line 73)

`_validateSupabaseConfig()` throws a `StateError` before `runApp()` is called. There is no Flutter widget tree to display an error, so the user sees a blank screen.

**Fix:** Wrap the validate call in try/catch and call `runApp(MaterialApp(...))` with a human-readable error message on failure.

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-014: Dashboard double API fetch on stats fallback - unnecessary latency",
        "labels": "bug,priority: medium",
        "body": """**File:** `lib/screens/dashboard_screen.dart` (~lines 57-78)

When `expense-stats` fails, the fallback re-fetches ALL expenses (no limit) to compute `totalBalance`, discarding the already-fetched `limit:10` list. Every dashboard load makes 2 API calls when stats is unavailable.

**Fix:** Reuse the already-fetched `expenses` list in the fallback calculation. No second API call is needed.

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-015: BalanceCard label says 'Expense vs Budget' but displays total balance",
        "labels": "bug,priority: medium",
        "body": """**File:** `lib/widgets/balance_card.dart` (~line 72)

The card title is hardcoded as "Expense vs Budget" but the value shown is `totalBalance` (income minus expenses). This is a misleading label that will confuse users.

**Fix:** Change label to 'Total Balance' or make it a configurable widget parameter.

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-016: EmailSettingsScreen._connectEmailAccount async gap after showDialog - context use-after-dispose",
        "labels": "bug,priority: medium",
        "body": """**File:** `lib/screens/email_settings_screen.dart` (~lines 75-82)

`showDialog` is called without `await`, then `Provider.of(context)` and `getIdToken()` are called after an `await`. If the widget is unmounted during this gap, the app crashes.

**Fix:** Capture `authService` before showing any dialog. Add `if (!mounted) return` after every `await`.

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-017: ImportResult.fromJson hard casts on RowError fields - crash on null",
        "labels": "bug,priority: medium",
        "body": """**File:** `lib/models/import_result.dart` (~lines 14-16)

`RowError.fromJson` uses hard `as int` / `as String` casts. Any null/missing field from the Edge Function throws a `TypeError`, crashing the CSV import preview flow.

**Fix:**
```dart
row:     (json['row'] as int?) ?? 0,
field:   json['field']?.toString() ?? '',
message: json['message']?.toString() ?? 'Unknown error',
```

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-018: QuickActionsGrid renders ghost cell when actions.length == 1",
        "labels": "bug,priority: low",
        "body": """**File:** `lib/widgets/quick_actions_grid.dart` (~line 46)

`crossAxisCount: actions.length.clamp(2, 4)` never allows 1 column. A single action renders in a 2-column grid, leaving an empty ghost cell.

**Fix:** `crossAxisCount: actions.length.clamp(1, 4)`

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-019: _ResponsiveWrapper hardcodes Colors.white - dark mode incompatible",
        "labels": "bug,priority: low",
        "body": """**File:** `lib/main.dart` (~lines 753-757)

The responsive wrapper always uses `Colors.white`. When dark mode is added this creates a white border mismatch around the constrained viewport.

**Fix:** Use `Theme.of(context).scaffoldBackgroundColor` instead of `Colors.white`.

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-020: VoiceService.parseExpenseFromVoice regex captures first number not the amount",
        "labels": "bug,priority: low",
        "body": """**File:** `lib/services/voice_service.dart` (~lines 67-72)

`firstMatch` grabs the first number in the text. Input like "bought 2 coffees at 150 rupees" returns `amount=2`, not `150`.

**Fix:** Use `lastMatch` or find the match closest to the currency keyword.

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-021: AppUser.supabaseUserId returns empty string instead of null on missing field",
        "labels": "bug,priority: low",
        "body": """**File:** `lib/models/app_user.dart` (~line 50)

`supabaseUserId: json['firebase_uid']?.toString() ?? ''`

An empty string silently passes through downstream callers (admin checks, API calls) instead of signalling that the value is not set.

**Fix:** Type the field as `String?` and return `null` when missing, or assert non-empty in debug builds.

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-022: Expense date parsing ignores timezone - potential off-by-one-day for IST users",
        "labels": "bug,priority: low",
        "body": """**File:** `lib/models/expense.dart` (~line 43)

`DateTime.parse(json['date'] as String)` treats date-only strings as UTC midnight. For IST users (UTC+5:30) edge cases near midnight can display the previous day.

**Fix:** `DateTime.parse('${json['date']}T00:00:00').toLocal()`

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-023: DashboardScreen race condition on concurrent pull-to-refresh",
        "labels": "bug,priority: low",
        "body": """**File:** `lib/screens/dashboard_screen.dart` (~lines 38-95)

If the user pulls to refresh while an initial load is in progress, two concurrent calls to `_loadDashboardData` run simultaneously. The slower one may resolve last and display stale data.

**Fix:** Add an `_isFetching` bool guard - skip the new call if one is already in flight.

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-024: MoreScreen is a non-functional placeholder - secondary features unreachable",
        "labels": "bug,priority: low",
        "body": """**File:** `lib/screens/more_screen.dart`

The `/more` bottom-nav slot shows only "Content coming soon...". AI chat, Voice expense, CSV import, and Notifications screens all exist and work but are not linked from MoreScreen. Users have no path to these features.

**Fix:** Add a proper menu in MoreScreen with navigation to all implemented secondary screens.

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
    {
        "title": "BUG-025: SocketException catch in _withRetry is dead code on Flutter Web",
        "labels": "bug,priority: low",
        "body": """**File:** `lib/services/auth_service.dart` (~lines 255-258)

Flutter Web never throws `dart:io`'s `SocketException` - it throws `http.ClientException`. The `SocketException` catch block and `import 'dart:io'` are dead code on the web target (the primary target of this app).

**Fix:** Remove `import 'dart:io'` and the `SocketException` catch branch, or guard with `if (!kIsWeb)`.

See [Docs/BUG_REPORT.md](../Docs/BUG_REPORT.md) for full details.""",
    },
]

for i, issue in enumerate(issues, 1):
    print(f"Creating issue {i}/25: {issue['title'][:60]}...")
    result = subprocess.run(
        ["gh", "issue", "create",
         "--repo", REPO,
         "--title", issue["title"],
         "--label", issue["labels"],
         "--body", issue["body"]],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        print(f"  OK: {result.stdout.strip()}")
    else:
        print(f"  FAILED: {result.stderr.strip()}")
    time.sleep(0.5)

print("\nDone!")
