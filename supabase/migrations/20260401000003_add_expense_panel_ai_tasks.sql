-- Add 3 new AI task assignments for expense page inline panels
INSERT INTO app.ai_task_assignments (task_slug, display_name, description) VALUES
  ('historical_performance', 'Historical Performance', 'AI-powered historical spending trend analysis and month-over-month comparisons'),
  ('spending_analytics', 'Spending Analytics', 'AI-driven category breakdown, daily averages, and budget utilization insights'),
  ('ai_insights', 'AI Insights', 'Real-time AI budget analysis and interactive financial chat assistant')
ON CONFLICT (task_slug) DO NOTHING;
