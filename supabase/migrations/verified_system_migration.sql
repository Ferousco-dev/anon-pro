-- ============================================================
-- ANONPRO: Verified User System Migration
-- Run this in your Supabase SQL Editor
-- ============================================================

-- ─── 1. Users table: verification & DM privacy ─────────────
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS verification_level TEXT DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS dm_privacy TEXT DEFAULT 'everyone',
  ADD COLUMN IF NOT EXISTS qa_enabled BOOLEAN DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_users_verification_level ON users (verification_level);
CREATE INDEX IF NOT EXISTS idx_users_is_verified ON users (is_verified);

-- ─── 2. Posts table: identity mode ──────────────────────────
ALTER TABLE posts
  ADD COLUMN IF NOT EXISTS post_identity_mode TEXT DEFAULT 'anonymous';

CREATE INDEX IF NOT EXISTS idx_posts_identity_mode ON posts (post_identity_mode);

-- ─── 3. Polls — drop and recreate to ensure correct schema ──

-- Drop old tables if they exist (cascade drops dependents)
DROP TABLE IF EXISTS poll_votes CASCADE;
DROP TABLE IF EXISTS poll_options CASCADE;
DROP TABLE IF EXISTS polls CASCADE;

CREATE TABLE polls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
  question TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE poll_options (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  poll_id UUID REFERENCES polls(id) ON DELETE CASCADE,
  option_text TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE poll_votes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  poll_id UUID REFERENCES polls(id) ON DELETE CASCADE,
  option_id UUID REFERENCES poll_options(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(poll_id, user_id)
);

CREATE INDEX idx_polls_post_id ON polls (post_id);
CREATE INDEX idx_poll_options_poll_id ON poll_options (poll_id);
CREATE INDEX idx_poll_votes_poll_id ON poll_votes (poll_id);
CREATE INDEX idx_poll_votes_user_id ON poll_votes (user_id);

-- ─── 4. Anonymous Q&A ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS anonymous_questions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  target_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  asker_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  question TEXT NOT NULL,
  answer TEXT,
  answered BOOLEAN DEFAULT FALSE,
  answered_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_anon_questions_target ON anonymous_questions (target_user_id);
CREATE INDEX IF NOT EXISTS idx_anon_questions_answered ON anonymous_questions (answered);

-- ─── 5. Confession Rooms ────────────────────────────────────
CREATE TABLE IF NOT EXISTS confession_rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id UUID REFERENCES users(id) ON DELETE SET NULL,
  room_name TEXT NOT NULL,
  description TEXT,
  max_participants INTEGER DEFAULT 50,
  expires_at TIMESTAMPTZ NOT NULL,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS room_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID REFERENCES confession_rooms(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  message TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_confession_rooms_active ON confession_rooms (is_active, expires_at);
CREATE INDEX IF NOT EXISTS idx_room_messages_room_id ON room_messages (room_id);

-- ─── 6. User Analytics ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS user_analytics (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  profile_views INTEGER DEFAULT 0,
  post_views INTEGER DEFAULT 0,
  likes_received INTEGER DEFAULT 0,
  comments_received INTEGER DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Auto-create analytics row when a user is created
CREATE OR REPLACE FUNCTION create_user_analytics()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO user_analytics (user_id) VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_create_user_analytics ON users;
CREATE TRIGGER trg_create_user_analytics
  AFTER INSERT ON users
  FOR EACH ROW EXECUTE FUNCTION create_user_analytics();

-- Backfill analytics for existing users
INSERT INTO user_analytics (user_id)
  SELECT id FROM users
  ON CONFLICT (user_id) DO NOTHING;

-- ─── 7. Ranked Feed Function ────────────────────────────────
CREATE OR REPLACE FUNCTION get_ranked_feed(user_uuid UUID, feed_limit INTEGER DEFAULT 50)
RETURNS SETOF posts AS $$
BEGIN
  RETURN QUERY
    SELECT p.*
    FROM posts p
    LEFT JOIN users u ON u.id = p.user_id
    ORDER BY
      (p.likes_count + p.comments_count + p.shares_count
       + CASE WHEN u.is_verified = TRUE THEN 20 ELSE 0 END
      ) DESC,
      p.created_at DESC
    LIMIT feed_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ─── 8. RLS Policies ────────────────────────────────────────

-- Polls
ALTER TABLE polls ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read polls" ON polls;
CREATE POLICY "Anyone can read polls" ON polls FOR SELECT USING (true);
DROP POLICY IF EXISTS "Authenticated can create polls" ON polls;
CREATE POLICY "Authenticated can create polls" ON polls FOR INSERT WITH CHECK (true);

ALTER TABLE poll_options ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read poll options" ON poll_options;
CREATE POLICY "Anyone can read poll options" ON poll_options FOR SELECT USING (true);
DROP POLICY IF EXISTS "Authenticated can create poll options" ON poll_options;
CREATE POLICY "Authenticated can create poll options" ON poll_options FOR INSERT WITH CHECK (true);

ALTER TABLE poll_votes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read poll votes" ON poll_votes;
CREATE POLICY "Anyone can read poll votes" ON poll_votes FOR SELECT USING (true);
DROP POLICY IF EXISTS "Authenticated can vote" ON poll_votes;
CREATE POLICY "Authenticated can vote" ON poll_votes FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Anonymous Questions
ALTER TABLE anonymous_questions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Target can read their questions" ON anonymous_questions;
CREATE POLICY "Target can read their questions" ON anonymous_questions FOR SELECT USING (target_user_id = auth.uid() OR answered = TRUE);
DROP POLICY IF EXISTS "Anyone can ask questions" ON anonymous_questions;
CREATE POLICY "Anyone can ask questions" ON anonymous_questions FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "Target can update their questions" ON anonymous_questions;
CREATE POLICY "Target can update their questions" ON anonymous_questions FOR UPDATE USING (target_user_id = auth.uid());

-- Confession Rooms
ALTER TABLE confession_rooms ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read active rooms" ON confession_rooms;
CREATE POLICY "Anyone can read active rooms" ON confession_rooms FOR SELECT USING (is_active = TRUE);
DROP POLICY IF EXISTS "Verified can create rooms" ON confession_rooms;
CREATE POLICY "Verified can create rooms" ON confession_rooms FOR INSERT WITH CHECK (true);

ALTER TABLE room_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read room messages" ON room_messages;
CREATE POLICY "Anyone can read room messages" ON room_messages FOR SELECT USING (true);
DROP POLICY IF EXISTS "Anyone can post room messages" ON room_messages;
CREATE POLICY "Anyone can post room messages" ON room_messages FOR INSERT WITH CHECK (true);

-- User Analytics
ALTER TABLE user_analytics ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can read own analytics" ON user_analytics;
CREATE POLICY "Users can read own analytics" ON user_analytics FOR SELECT USING (user_id = auth.uid());
DROP POLICY IF EXISTS "System can update analytics" ON user_analytics;
CREATE POLICY "System can update analytics" ON user_analytics FOR UPDATE USING (true);

-- ─── Done ───────────────────────────────────────────────────
