-- Migration: Create idea_board tables
-- Created: 2026-03-24
--
-- Local-storage backed idea board for admin use.
-- Data is stored in the app schema following existing conventions.

-- ── Ideas table ──────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS app.ideas (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    created_by      UUID          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    title           TEXT          NOT NULL CHECK (char_length(title) >= 1 AND char_length(title) <= 300),
    description     TEXT,
    feature_tag     TEXT          NOT NULL DEFAULT 'general',
    status          TEXT          NOT NULL DEFAULT 'open' CHECK (status IN (
      'open', 'in_progress', 'done', 'rejected', 'parked'
    )),
    priority        TEXT          NOT NULL DEFAULT 'medium' CHECK (priority IN (
      'low', 'medium', 'high', 'critical'
    )),
    is_pinned       BOOLEAN       NOT NULL DEFAULT false,
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    deleted_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS ideas_created_by_idx   ON app.ideas (created_by);
CREATE INDEX IF NOT EXISTS ideas_status_idx       ON app.ideas (status);
CREATE INDEX IF NOT EXISTS ideas_feature_tag_idx  ON app.ideas (feature_tag);
CREATE INDEX IF NOT EXISTS ideas_deleted_at_idx   ON app.ideas (deleted_at) WHERE deleted_at IS NULL;

DROP TRIGGER IF EXISTS ideas_set_updated_at ON app.ideas;
CREATE TRIGGER ideas_set_updated_at
    BEFORE UPDATE ON app.ideas
    FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

ALTER TABLE app.ideas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "deny_direct_access" ON app.ideas;
CREATE POLICY "deny_direct_access" ON app.ideas
    FOR ALL TO anon, authenticated
    USING (false);

-- ── Idea comments table ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS app.idea_comments (
    id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    idea_id         UUID          NOT NULL REFERENCES app.ideas(id) ON DELETE CASCADE,
    created_by      UUID          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    body            TEXT          NOT NULL CHECK (char_length(body) >= 1),
    created_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idea_comments_idea_id_idx ON app.idea_comments (idea_id);

DROP TRIGGER IF EXISTS idea_comments_set_updated_at ON app.idea_comments;
CREATE TRIGGER idea_comments_set_updated_at
    BEFORE UPDATE ON app.idea_comments
    FOR EACH ROW EXECUTE FUNCTION app.set_updated_at();

ALTER TABLE app.idea_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "deny_direct_access" ON app.idea_comments;
CREATE POLICY "deny_direct_access" ON app.idea_comments
    FOR ALL TO anon, authenticated
    USING (false);
