-- Household-level AI settings (per-household overrides for AI features)
CREATE TABLE IF NOT EXISTS app.household_ai_settings (
  household_id UUID PRIMARY KEY REFERENCES app.households(id) ON DELETE CASCADE,
  ai_enabled BOOLEAN NOT NULL DEFAULT true,
  chat_queries_limit INT NOT NULL DEFAULT 5,
  weekly_summaries_limit INT NOT NULL DEFAULT 1,
  budget_analysis_limit INT NOT NULL DEFAULT 10,
  anomaly_detection_limit INT NOT NULL DEFAULT 5,
  simulator_limit INT NOT NULL DEFAULT 5,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Grant access to service role
GRANT ALL ON app.household_ai_settings TO service_role;
