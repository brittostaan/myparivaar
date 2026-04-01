-- Add AI task assignments for Projected Expense & Spend Leakage sections
INSERT INTO app.ai_task_assignments (task_slug, display_name, description) VALUES
  ('expense_projection', 'Expense Projection', 'AI-powered end-of-month expense projection based on historical spending patterns and budgets'),
  ('spend_leakage', 'Spend Leakage', 'AI-driven identification of spending leaks including over-budget categories, impulse spending, and disproportionate expenditures')
ON CONFLICT (task_slug) DO NOTHING;
