# Product Requirements Document (PRD)
## myparivaar – AI‑First Family Finance App

---

## 1. Product Overview

**Product Name:** myparivaar  
**Meaning:** “My Family”  
**Target Market:** Consumers in India (Primary focus: Women)  
**Platforms:** Android, iOS (Primary), Web (Secondary)  
**Authentication:** SMS OTP only  
**Business Model:** Free tier (with controlled AI usage), future paid plans  

**Vision:**  
myparivaar is an AI‑first personal finance management app designed for Indian families to manage their **spending, budgets, savings, and bills in one place**, with simple voice interaction and privacy‑first design.

---

## 2. Goals & Success Criteria (MVP)

### Goals
1. Enable families to manage finances together under one account.
2. Provide a mobile‑first, high‑quality experience.
3. Capture financial data from **manual entry, email, and CSV uploads**.
4. Deliver **AI insights only** (no financial advice).
5. Keep operating costs low for a sustainable free tier.

### Success Metrics
- Successful SMS login rate
- Household creation completion
- At least 10 expenses logged/imported per household
- CSV import success rate
- Weekly AI summary usage
- Zero security incidents

---

## 3. In‑Scope Features (MVP)

### 3.1 User & Family Model
- One **Admin** per family (creator)
- Up to **7 family members**
- Each member has:
  - Own phone number login
  - Own settings
- All financial data is **family‑shared**
- Role based:
  - Admin: manage family members
  - Member: add/view data

---

### 3.2 Authentication
- **SMS OTP only**
- Provider:
  - Firebase Phone Authentication
- No passwords
- No email login

---

### 3.3 Core Finance Features

#### Expenses
- Manual entry
- CSV import
- Email‑based ingestion (Gmail / Outlook)
- Category‑based
- Household‑visible

#### Budgets
- Monthly budget per category
- CSV import supported
- Replace existing budgets on import

#### Savings
- Savings goals
- Target amount and date
- Contributions tracked manually or via CSV

#### Bills
- Recurring bills
- Due dates
- Mobile local notifications

---

### 3.4 CSV Import (Mandatory)
- CSV upload supported
- Import types:
  - Expenses
  - Budgets
- Preview and validation before import
- Imported data is visible to all family members
- Import batches tracked

---

### 3.5 Email Ingestion
- Gmail & Outlook via OAuth
- Parse:
  - Bank debit/credit alerts
  - UPI receipts
  - E‑commerce invoices
  - Bills
  - Travel receipts
- Suggested transactions require user approval before confirmation

---

### 3.6 AI Features (Insights‑Only)
- Weekly summary per family (cached)
- AI chat queries limited:
  - Free tier: 5 queries / month / family
- AI provides:
  - Spend summaries
  - Trends
  - Observations
- AI **must NOT**:
  - Recommend financial products
  - Predict outcomes
  - Claim guarantees

---

### 3.7 Voice (In‑App Only)
- Supported on mobile
- Use cases:
  - Add expense
  - Query spend
- Always requires confirmation
- No OS‑level assistant integration in MVP

---

### 3.8 Settings
**User Settings**
- Language (English in MVP)
- Notifications toggle
- Voice toggle
- Logout

**Admin Settings**
- Family name
- Invite / remove members

---

### 3.9 Super Admin (Platform Owner)
- Platform‑level role
- Can:
  - View all households
  - Assign plans
  - Enforce limits
  - Suspend households
  - Monitor AI usage

---

## 4. Platform Support Matrix

| Feature | Android | iOS | Web |
|------|------|------|------|
| SMS Login | ✅ | ✅ | ✅ |
| Family Accounts | ✅ | ✅ | ✅ |
| Expenses / Budgets | ✅ | ✅ | ✅ |
| CSV Import | ✅ | ✅ | ✅ |
| Email Ingestion | ✅ | ✅ | ✅ |
| AI Insights | ✅ | ✅ | ✅ |
| Voice | ✅ | ✅ | ⚠️ (limited) |
| Local Notifications | ✅ | ✅ | ❌ |

---

## 5. Out of Scope (MVP)

- Bank account linking (Account Aggregator)
- Investments (buy/sell)
- Credit score
- Tax filing
- Ads
- Multiple languages (post‑MVP)
- Daily AI summaries

---

## 6. Technical Architecture

### Frontend
- Flutter (single codebase)
- Android, iOS, Web

### Authentication
- Firebase Phone Authentication (SMS)

### Backend
- Supabase
  - PostgreSQL
  - Edge Functions (API layer)
  - Service role access ONLY
- No direct DB access from client

### AI
- External LLM
- Strict quotas and caching

---

## 7. Security & Privacy

- Automatic Row Level Security enabled
- Database accessed only via Edge Functions
- OAuth tokens stored in private schema
- No selling or sharing user data
- Soft deletes for safety

---

## 8. Free Tier Limits (MVP)

| Item | Limit |
|----|----|
| Family members | 8 |
| AI weekly summary | 1 / week |
| AI chat | 5 / month |
| CSV import | Unlimited |
| Email ingestion | Enabled |

---

## 9. Milestones

### MVP (2 Days)
- SMS login
- Family creation
- Expenses, budgets, savings, bills
- CSV import
- Email ingestion (basic)
- AI weekly summary
- Super admin basics

---

## 10. Guiding Principles
- Mobile‑first
- Privacy‑first
- Simplicity over complexity
- AI as assistive, not advisory
- Ship fast, scale safely