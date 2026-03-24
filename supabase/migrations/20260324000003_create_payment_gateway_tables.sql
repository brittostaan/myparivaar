-- Payment Gateway Configuration & Subscription Tables
-- Stores payment gateway credentials (Stripe, Razorpay, PhonePe) managed by admins.
-- Tracks household subscriptions and payment history.

-- ── 1. Payment Gateway Configs (Admin-managed) ─────────────────────────────

CREATE TABLE IF NOT EXISTS app.payment_gateway_configs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  gateway TEXT NOT NULL UNIQUE CHECK (gateway IN ('stripe', 'razorpay', 'phonepe')),
  display_name TEXT NOT NULL,
  api_key TEXT NOT NULL,
  api_secret TEXT NOT NULL,
  webhook_secret TEXT,
  is_active BOOLEAN NOT NULL DEFAULT false,
  is_test_mode BOOLEAN NOT NULL DEFAULT true,
  config_json JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID REFERENCES app.users(id)
);

ALTER TABLE app.payment_gateway_configs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access on payment_gateway_configs"
  ON app.payment_gateway_configs
  FOR ALL
  USING (true)
  WITH CHECK (true);

-- ── 2. Subscription Plans (reuses existing app.plans if available) ──────────

-- ── 3. Household Subscriptions ──────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS app.household_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES app.households(id),
  plan_id UUID NOT NULL REFERENCES app.plans(id),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'past_due', 'cancelled', 'expired', 'trialing')),
  gateway TEXT NOT NULL CHECK (gateway IN ('stripe', 'razorpay', 'phonepe', 'manual')),
  gateway_subscription_id TEXT,
  current_period_start TIMESTAMPTZ,
  current_period_end TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_by UUID REFERENCES app.users(id)
);

ALTER TABLE app.household_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access on household_subscriptions"
  ON app.household_subscriptions
  FOR ALL
  USING (true)
  WITH CHECK (true);

CREATE INDEX idx_household_subscriptions_household ON app.household_subscriptions(household_id);
CREATE INDEX idx_household_subscriptions_status ON app.household_subscriptions(status);

-- ── 4. Payment History ──────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS app.payment_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  household_id UUID NOT NULL REFERENCES app.households(id),
  subscription_id UUID REFERENCES app.household_subscriptions(id),
  gateway TEXT NOT NULL CHECK (gateway IN ('stripe', 'razorpay', 'phonepe', 'manual')),
  gateway_payment_id TEXT,
  amount_cents INTEGER NOT NULL,
  currency TEXT NOT NULL DEFAULT 'INR',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'succeeded', 'failed', 'refunded')),
  description TEXT,
  receipt_url TEXT,
  error_message TEXT,
  metadata JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE app.payment_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access on payment_history"
  ON app.payment_history
  FOR ALL
  USING (true)
  WITH CHECK (true);

CREATE INDEX idx_payment_history_household ON app.payment_history(household_id);
CREATE INDEX idx_payment_history_subscription ON app.payment_history(subscription_id);

-- ── 5. Updated-at triggers ──────────────────────────────────────────────────

CREATE TRIGGER set_payment_gateway_configs_updated_at
  BEFORE UPDATE ON app.payment_gateway_configs
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

CREATE TRIGGER set_household_subscriptions_updated_at
  BEFORE UPDATE ON app.household_subscriptions
  FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();
