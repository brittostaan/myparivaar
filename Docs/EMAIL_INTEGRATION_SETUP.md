# Email Integration Setup (Outlook + Gmail)

This setup enables inbox transaction screening in the app with:
- Outlook first (Microsoft Graph)
- Gmail second (Google Gmail API)
- Admin Center controls for sender filters, keyword filters, and sync scope (days/months)

> **Status as of 2026-03-22:**
> - ✅ Step 1 — DB migration applied
> - ⏳ Step 2 — OAuth secrets required (see below)
> - ⏳ Step 3 — Azure Portal app registration required
> - ⏳ Step 4 — Google Cloud credentials required
> - ✅ Step 5 — All 5 Edge Functions deployed

## 1) Deploy Database Change ✅ DONE

Migration `20260322000001_add_email_screening_fields.sql` applied to live DB.

Table `public.email_accounts` created with cross-schema FKs to `app.households` / `app.users`:
- `screening_sender_filters` (`text[]`)
- `screening_keyword_filters` (`text[]`)
- `screening_scope_unit` (`days|months`)
- `screening_scope_value` (`int`, 1–365)

## 2) Configure OAuth Secrets In Supabase ⏳ ACTION REQUIRED

You must obtain real client ID/secret values from Azure Portal and Google Cloud Console first (steps 3–4), then set them:

```powershell
# Use the local binary — global 'supabase' is not installed on this machine
$sb = "$env:TEMP\supabase.exe"
& $sb secrets set `
  GOOGLE_CLIENT_ID="<paste-google-client-id>" `
  GOOGLE_CLIENT_SECRET="<paste-google-client-secret>" `
  MICROSOFT_CLIENT_ID="<paste-azure-app-client-id>" `
  MICROSOFT_CLIENT_SECRET="<paste-azure-app-client-secret>"
```

Required callback URL for both providers (already configured in deployed functions):
```
https://qimqakfjryptyhxmrjsj.supabase.co/functions/v1/email-oauthCallback
```

## 3) Azure Portal — Outlook App Registration ⏳ ACTION REQUIRED

1. Go to https://portal.azure.com → **Azure Active Directory** → **App registrations** → **New registration**
2. Name: `MyParivaar Email`; Supported account types: **Accounts in any organizational directory and personal Microsoft accounts**
3. Redirect URI: **Web** → `https://qimqakfjryptyhxmrjsj.supabase.co/functions/v1/email-oauthCallback`
4. After creation → **Certificates & secrets** → **New client secret** → copy the **Value** (this is `MICROSOFT_CLIENT_SECRET`)
5. Copy the **Application (client) ID** from the Overview page (this is `MICROSOFT_CLIENT_ID`)
6. Go to **API permissions** → **Add a permission** → **Microsoft Graph** → **Delegated** → add:
   - `Mail.Read`
   - `User.Read`
   - `offline_access`
7. Click **Grant admin consent**

## 4) Google Cloud — Gmail OAuth Credentials ⏳ ACTION REQUIRED

1. Go to https://console.cloud.google.com → select or create a project
2. **APIs & Services** → **Enable APIs** → enable **Gmail API**
3. **APIs & Services** → **OAuth consent screen**:
   - User type: **External**; fill in app name, support email, developer email
   - Scopes: add `gmail.readonly` and `userinfo.email`
4. **APIs & Services** → **Credentials** → **Create credentials** → **OAuth client ID**:
   - Application type: **Web application**
   - Authorized redirect URI: `https://qimqakfjryptyhxmrjsj.supabase.co/functions/v1/email-oauthCallback`
5. Copy the **Client ID** (`GOOGLE_CLIENT_ID`) and **Client secret** (`GOOGLE_CLIENT_SECRET`)

## 5) Deploy Updated Edge Functions ✅ DONE

All 5 functions were deployed on 2026-03-22:

| Function | Purpose |
|---|---|
| `email-connectUrl` | Generates Gmail/Outlook OAuth authorization URL |
| `email-oauthCallback` | Handles OAuth redirect, stores `public.email_accounts` row |
| `email-accounts` | Lists and disconnects connected accounts |
| `email-syncNow` | Syncs emails respecting per-account screening rules |
| `admin-email-config` | Admin-only: list accounts + update screening config |

To redeploy if needed:
```powershell
$sb = "$env:TEMP\supabase.exe"
& $sb functions deploy email-connectUrl
& $sb functions deploy email-oauthCallback
& $sb functions deploy email-accounts
& $sb functions deploy email-syncNow
& $sb functions deploy admin-email-config
```

## 6) App Feature Flow

1. Users connect Outlook/Gmail from **Email Settings** screen (tap **Connect Gmail** or **Connect Outlook**).
2. The `email-connectUrl` function generates an OAuth authorization URL.
3. After user grants access, `email-oauthCallback` handles the redirect and inserts/updates a row in `public.email_accounts`.
4. Admin opens **Admin Center → Email tab** (tab 11).
5. Admin configures per-account:
   - Sender email filters (chips — only emails from these senders are processed)
   - Keyword filters (chips — subject/body must contain at least one)
   - Scope unit/value (`7 days`, `1 month`, etc.)
   - Active/inactive toggle
6. Email sync (`email-syncNow`) applies these rules automatically before parsing transactions.

## 7) Validation Checklist

After completing steps 2–4:

- [ ] `email-connectUrl` returns a valid `auth_url` for both `gmail` and `outlook` (no "OAuth not configured" error)
- [ ] Completing OAuth flow creates/updates a row in `public.email_accounts`
- [ ] Admin Center → Email tab loads connected accounts list
- [ ] Saving filters in Admin Center persists values and writes audit log entry with action `update_email_screening`
- [ ] `email-syncNow` only processes messages within configured scope and matching sender/keyword filters
