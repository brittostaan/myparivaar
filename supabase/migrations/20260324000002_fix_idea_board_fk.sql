-- Migration: Fix idea_board FK references
-- Created: 2026-03-24
--
-- The created_by columns were referencing auth.users(id) but edge functions
-- insert app.users.id. Change FK to reference app.users(id).

-- ── Fix ideas.created_by ─────────────────────────────────────────────────────

ALTER TABLE app.ideas
  DROP CONSTRAINT IF EXISTS ideas_created_by_fkey;

ALTER TABLE app.ideas
  ADD CONSTRAINT ideas_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES app.users(id) ON DELETE CASCADE;

-- ── Fix idea_comments.created_by ─────────────────────────────────────────────

ALTER TABLE app.idea_comments
  DROP CONSTRAINT IF EXISTS idea_comments_created_by_fkey;

ALTER TABLE app.idea_comments
  ADD CONSTRAINT idea_comments_created_by_fkey
  FOREIGN KEY (created_by) REFERENCES app.users(id) ON DELETE CASCADE;
