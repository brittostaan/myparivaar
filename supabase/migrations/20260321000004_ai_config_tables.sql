-- AI Configuration Tables for multi-provider AI management
-- Creates: ai_providers, ai_provider_keys, ai_task_assignments

-- 1. AI Providers (OpenAI, Anthropic, Gemini)
CREATE TABLE IF NOT EXISTS app.ai_providers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  base_url TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE app.ai_providers ENABLE ROW LEVEL SECURITY;

-- 2. AI Provider Keys (encrypted API keys per provider)
CREATE TABLE IF NOT EXISTS app.ai_provider_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id UUID NOT NULL REFERENCES app.ai_providers(id) ON DELETE CASCADE,
  api_key TEXT NOT NULL,
  label TEXT NOT NULL DEFAULT 'default',
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE app.ai_provider_keys ENABLE ROW LEVEL SECURITY;

-- 3. AI Task Assignments (which model handles which task)
CREATE TABLE IF NOT EXISTS app.ai_task_assignments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_slug TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  description TEXT,
  provider_id UUID REFERENCES app.ai_providers(id) ON DELETE SET NULL,
  model_name TEXT,
  is_active BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE app.ai_task_assignments ENABLE ROW LEVEL SECURITY;

-- Seed the 3 providers
INSERT INTO app.ai_providers (name, display_name, base_url) VALUES
  ('openai', 'OpenAI', 'https://api.openai.com/v1'),
  ('anthropic', 'Anthropic', 'https://api.anthropic.com/v1'),
  ('gemini', 'Google Gemini', 'https://generativelanguage.googleapis.com/v1beta')
ON CONFLICT (name) DO NOTHING;

-- Seed the 8 predefined tasks
INSERT INTO app.ai_task_assignments (task_slug, display_name, description) VALUES
  ('financial_chat', 'Financial Chat', 'AI-powered chat for household financial queries'),
  ('weekly_summary', 'Weekly Summary', 'Auto-generated weekly financial summary'),
  ('expense_categorization', 'Expense Categorization', 'Automatic categorization of transactions'),
  ('budget_analysis', 'Budget Analysis', 'AI-driven budget optimization suggestions'),
  ('voice_processing', 'Voice Processing', 'Speech-to-text for voice transaction entry'),
  ('email_parsing', 'Email Parsing', 'Extract transaction data from bank emails'),
  ('anomaly_detection', 'Anomaly Detection', 'Detect unusual spending patterns'),
  ('financial_simulator', 'Financial Simulator', 'What-if scenario analysis for financial planning')
ON CONFLICT (task_slug) DO NOTHING;
