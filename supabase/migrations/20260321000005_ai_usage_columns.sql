-- Add usage counter columns for new AI tasks
ALTER TABLE app.ai_usage ADD COLUMN IF NOT EXISTS budget_analysis_count INT NOT NULL DEFAULT 0;
ALTER TABLE app.ai_usage ADD COLUMN IF NOT EXISTS anomaly_count INT NOT NULL DEFAULT 0;
ALTER TABLE app.ai_usage ADD COLUMN IF NOT EXISTS simulator_count INT NOT NULL DEFAULT 0;
