-- Add AI task assignments for new expense AI info cards
INSERT INTO app.ai_task_assignments (task_slug, display_name, description) VALUES
  ('subscription_drain', 'Subscription Drain', 'Tracks recurring subscriptions that add little value or are unused'),
  ('impulse_spend', 'Impulse Spend', 'Detects unplanned or emotionally driven expenses like late-night food orders'),
  ('silent_expenses', 'Silent Expenses', 'Identifies small repeated spends users don''t notice that add up significantly'),
  ('lifestyle_creep', 'Lifestyle Creep', 'Detects gradual increase in spending as income rises over quarters'),
  ('budget_drift', 'Budget Drift', 'Shows slow deviation from budget before overspend happens'),
  ('category_overshoot', 'Category Overshoot', 'Category-wise early warnings for unusually high spending'),
  ('spend_volatility', 'Spend Volatility', 'Flags unstable or erratic spending patterns between weekdays and weekends'),
  ('smart_saving', 'Smart Saving Opportunity', 'Suggests where money could be saved based on spending patterns'),
  ('good_spend_ratio', 'Good Spend Ratio', 'Reinforces healthy behavior by tracking essential vs discretionary spend ratio'),
  ('avoided_spend', 'Avoided Spend', 'Celebrates restraint by comparing impulse spending to previous periods')
ON CONFLICT (task_slug) DO NOTHING;
