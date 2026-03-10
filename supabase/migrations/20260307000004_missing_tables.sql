-- Migration: Add missing tables for email ingestion, plans, and subscriptions
-- Created: 2026-03-07

-- ======================================================================
-- CREATE PRIVATE SCHEMA FOR EMAIL DATA
-- ======================================================================

-- Create private schema for sensitive data
CREATE SCHEMA IF NOT EXISTS private;

-- ======================================================================
-- EMAIL ACCOUNTS TABLE (private schema)
-- ======================================================================

-- Drop and recreate to ensure proper schema
DROP TABLE IF EXISTS private.email_accounts CASCADE;

CREATE TABLE private.email_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID NOT NULL REFERENCES app.households(id) ON DELETE CASCADE,
    provider TEXT NOT NULL CHECK (provider IN ('gmail', 'outlook')),
    email_address TEXT NOT NULL,
    access_token TEXT NOT NULL,
    refresh_token TEXT,
    token_expires_at TIMESTAMPTZ,
    scopes TEXT[] NOT NULL DEFAULT '{}',
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    
    -- Constraints
    UNIQUE(household_id, email_address),
    CHECK (char_length(email_address) >= 5 AND char_length(email_address) <= 100),
    CHECK (char_length(access_token) >= 10),
    CHECK (provider = 'gmail' OR provider = 'outlook')
);

-- Enable RLS on email accounts
ALTER TABLE private.email_accounts ENABLE ROW LEVEL SECURITY;

-- Create policy to deny direct access (access only via Edge Functions)
CREATE POLICY "deny_direct_access" 
ON private.email_accounts
FOR ALL 
TO anon, authenticated 
USING (false);

-- ======================================================================
-- PLANS TABLE (proper implementation)
-- ======================================================================

-- Drop and recreate to ensure proper schema
DROP TABLE IF EXISTS app.plans CASCADE;

CREATE TABLE app.plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE CHECK (name IN ('free', 'paid')),
    display_name TEXT NOT NULL,
    description TEXT,
    price_monthly DECIMAL(10,2) NOT NULL DEFAULT 0,
    price_yearly DECIMAL(10,2) NOT NULL DEFAULT 0,
    currency TEXT NOT NULL DEFAULT 'INR',
    
    -- Feature limits  
    max_family_members INTEGER NOT NULL DEFAULT 8,
    ai_weekly_summaries INTEGER NOT NULL DEFAULT 1, -- per week
    ai_chat_queries INTEGER NOT NULL DEFAULT 5, -- per month
    csv_import_enabled BOOLEAN NOT NULL DEFAULT true,
    email_ingestion_enabled BOOLEAN NOT NULL DEFAULT true,
    voice_features_enabled BOOLEAN NOT NULL DEFAULT true,
    
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Constraints
    CHECK (char_length(name) >= 2 AND char_length(name) <= 20),
    CHECK (char_length(display_name) >= 2 AND char_length(display_name) <= 50),
    CHECK (price_monthly >= 0 AND price_monthly <= 9999.99),
    CHECK (price_yearly >= 0 AND price_yearly <= 99999.99),
    CHECK (max_family_members > 0 AND max_family_members <= 50),
    CHECK (ai_weekly_summaries >= 0 AND ai_weekly_summaries <= 100),
    CHECK (ai_chat_queries >= 0 AND ai_chat_queries <= 1000)
);

-- Enable RLS
ALTER TABLE app.plans ENABLE ROW LEVEL SECURITY;

-- Create deny-all policy
CREATE POLICY "deny_direct_access" 
ON app.plans
FOR ALL 
TO anon, authenticated 
USING (false);

-- ======================================================================
-- SUBSCRIPTIONS TABLE
-- ======================================================================

-- Drop and recreate to ensure proper schema
DROP TABLE IF EXISTS app.subscriptions CASCADE;

CREATE TABLE app.subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID NOT NULL REFERENCES app.households(id) ON DELETE CASCADE,
    plan_id UUID NOT NULL REFERENCES app.plans(id),
    
    -- Subscription lifecycle
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'cancelled', 'expired', 'suspended')),
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    
    -- Billing information
    billing_cycle TEXT NOT NULL DEFAULT 'monthly' CHECK (billing_cycle IN ('monthly', 'yearly')),
    amount_paid DECIMAL(10,2) NOT NULL DEFAULT 0,
    currency TEXT NOT NULL DEFAULT 'INR',
    payment_method TEXT CHECK (payment_method IN ('card', 'upi', 'netbanking', 'wallet')),
    
    -- External references (payment gateway)
    external_subscription_id TEXT,
    external_customer_id TEXT,
    
    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ,
    
    -- Constraints
    CHECK (expires_at IS NULL OR expires_at > started_at),
    CHECK (cancelled_at IS NULL OR cancelled_at >= started_at),
    CHECK (amount_paid >= 0 AND amount_paid <= 99999.99),
    CHECK (char_length(currency) = 3)
);

-- Enable RLS
ALTER TABLE app.subscriptions ENABLE ROW LEVEL SECURITY;

-- Create deny-all policy  
CREATE POLICY "deny_direct_access"
ON app.subscriptions
FOR ALL
TO anon, authenticated
USING (false);

-- ======================================================================
-- INDEXES FOR PERFORMANCE 
-- ======================================================================

-- Email accounts indexes
CREATE INDEX IF NOT EXISTS idx_email_accounts_household_id ON private.email_accounts(household_id);
CREATE INDEX IF NOT EXISTS idx_email_accounts_provider ON private.email_accounts(provider);
CREATE INDEX IF NOT EXISTS idx_email_accounts_active ON private.email_accounts(is_active) WHERE is_active = true;

-- Plans indexes
CREATE INDEX IF NOT EXISTS idx_plans_name ON app.plans(name);
CREATE INDEX IF NOT EXISTS idx_plans_active ON app.plans(is_active) WHERE is_active = true;

-- Subscriptions indexes  
CREATE INDEX IF NOT EXISTS idx_subscriptions_household_id ON app.subscriptions(household_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_plan_id ON app.subscriptions(plan_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON app.subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_subscriptions_expires_at ON app.subscriptions(expires_at) WHERE expires_at IS NOT NULL;

-- ======================================================================
-- TRIGGERS FOR UPDATED_AT
-- ======================================================================

-- Create updated_at trigger function if it doesn't exist
CREATE OR REPLACE FUNCTION handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Add updated_at triggers
CREATE TRIGGER handle_email_accounts_updated_at
    BEFORE UPDATE ON private.email_accounts
    FOR EACH ROW
    EXECUTE PROCEDURE handle_updated_at();

CREATE TRIGGER handle_plans_updated_at
    BEFORE UPDATE ON app.plans
    FOR EACH ROW
    EXECUTE PROCEDURE handle_updated_at();

CREATE TRIGGER handle_subscriptions_updated_at
    BEFORE UPDATE ON app.subscriptions
    FOR EACH ROW
    EXECUTE PROCEDURE handle_updated_at();

-- ======================================================================
-- INSERT DEFAULT PLAN DATA
-- ======================================================================

-- Insert default plans (free and paid)
INSERT INTO app.plans (name, display_name, description, price_monthly, price_yearly, max_family_members, ai_weekly_summaries, ai_chat_queries)
VALUES 
    ('free', 'Free Plan', 'Basic family finance management with limited AI features', 0, 0, 8, 1, 5),
    ('paid', 'Premium Plan', 'Full-featured family finance management with unlimited AI', 299.00, 2999.00, 8, 99, 500)
ON CONFLICT (name) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    price_monthly = EXCLUDED.price_monthly,
    price_yearly = EXCLUDED.price_yearly,
    max_family_members = EXCLUDED.max_family_members,
    ai_weekly_summaries = EXCLUDED.ai_weekly_summaries,
    ai_chat_queries = EXCLUDED.ai_chat_queries,
    updated_at = now();

-- ======================================================================
-- AI SUMMARIES TABLE
-- ======================================================================

CREATE TABLE IF NOT EXISTS app.ai_summaries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID NOT NULL REFERENCES app.households(id) ON DELETE CASCADE,
    summary_type TEXT NOT NULL CHECK (summary_type IN ('weekly', 'monthly', 'custom')),
    summary TEXT NOT NULL,
    data_from DATE NOT NULL,
    data_to DATE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Constraints
    CHECK (char_length(summary) >= 10 AND char_length(summary) <= 2000),
    CHECK (data_to >= data_from),
    UNIQUE(household_id, summary_type, data_from, data_to)
);

-- Enable RLS
ALTER TABLE app.ai_summaries ENABLE ROW LEVEL SECURITY;
CREATE POLICY "deny_direct_access" ON app.ai_summaries FOR ALL TO anon, authenticated USING (false);

-- ======================================================================
-- AI CHAT HISTORY TABLE
-- ======================================================================

CREATE TABLE IF NOT EXISTS app.ai_chat_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id UUID NOT NULL REFERENCES app.households(id) ON DELETE CASCADE,
    user_message TEXT NOT NULL,
    ai_response TEXT NOT NULL,
    created_by UUID NOT NULL REFERENCES app.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Constraints
    CHECK (char_length(user_message) >= 1 AND char_length(user_message) <= 500),
    CHECK (char_length(ai_response) >= 1 AND char_length(ai_response) <= 1000)
);

-- Enable RLS
ALTER TABLE app.ai_chat_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "deny_direct_access" ON app.ai_chat_history FOR ALL TO anon, authenticated USING (false);

-- ======================================================================
-- ADDITIONAL INDEXES
-- ======================================================================

-- AI summaries indexes
CREATE INDEX IF NOT EXISTS idx_ai_summaries_household_id ON app.ai_summaries(household_id);
CREATE INDEX IF NOT EXISTS idx_ai_summaries_type_date ON app.ai_summaries(household_id, summary_type, data_from);

-- AI chat history indexes
CREATE INDEX IF NOT EXISTS idx_ai_chat_household_id ON app.ai_chat_history(household_id);
CREATE INDEX IF NOT EXISTS idx_ai_chat_created_at ON app.ai_chat_history(created_at);

-- ======================================================================
-- UPDATE HOUSEHOLDS TABLE TO REFERENCE PLANS
-- ======================================================================

-- Add foreign key reference from households to plans (if not exists)
DO $$
BEGIN
    -- Check if the column exists and is not a foreign key
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'app' AND table_name = 'households' AND column_name = 'plan'
    ) AND NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
        WHERE tc.table_schema = 'app' AND tc.table_name = 'households' 
        AND kcu.column_name = 'plan' AND tc.constraint_type = 'FOREIGN KEY'
    ) THEN
        -- First update existing data to use plan UUIDs
        UPDATE app.households 
        SET plan = (SELECT id::text FROM app.plans WHERE name = households.plan)::uuid
        WHERE plan IN ('free', 'paid');
        
        -- Change column type to UUID and add foreign key
        ALTER TABLE app.households 
        ALTER COLUMN plan TYPE UUID USING plan::uuid;
        
        ALTER TABLE app.households
        ADD CONSTRAINT fk_households_plan 
        FOREIGN KEY (plan) REFERENCES app.plans(id);
    END IF;
END $$;