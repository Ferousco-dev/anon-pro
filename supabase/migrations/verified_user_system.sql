-- Verified User System Migration

-- 1. Add verification columns to users table (if table exists)
DO $$ 
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'users') THEN
    ALTER TABLE users
    ADD COLUMN IF NOT EXISTS is_verified BOOLEAN DEFAULT FALSE;

    ALTER TABLE users
    ADD COLUMN IF NOT EXISTS verified_at TIMESTAMP DEFAULT NULL;

    ALTER TABLE users
    ADD COLUMN IF NOT EXISTS verification_level TEXT DEFAULT 'none' CHECK (verification_level IN ('none', 'verified', 'premium_verified'));

    CREATE INDEX IF NOT EXISTS idx_users_is_verified ON users(is_verified);
    CREATE INDEX IF NOT EXISTS idx_users_verification_level ON users(verification_level);
  END IF;
END $$;

-- 2. Add dm_privacy setting to users table (if table exists)
DO $$ 
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'users') THEN
    ALTER TABLE users
    ADD COLUMN IF NOT EXISTS dm_privacy TEXT DEFAULT 'everyone' CHECK (dm_privacy IN ('everyone', 'verified_only', 'followers_only'));
  END IF;
END $$;

-- 3. Add post identity mode column (if table exists)
DO $$ 
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'posts') THEN
    ALTER TABLE posts
    ADD COLUMN IF NOT EXISTS post_identity_mode TEXT DEFAULT 'anonymous' CHECK (post_identity_mode IN ('anonymous', 'verified_anonymous', 'public'));

    CREATE INDEX IF NOT EXISTS idx_posts_identity_mode ON posts(post_identity_mode);
  END IF;
END $$;

-- 4. Create user_analytics table
CREATE TABLE IF NOT EXISTS user_analytics (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  profile_views INTEGER DEFAULT 0,
  post_views INTEGER DEFAULT 0,
  likes_received INTEGER DEFAULT 0,
  comments_received INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- 5. Create polls table (for anonymous polls in posts)
CREATE TABLE IF NOT EXISTS polls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
  question TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_polls_post_id ON polls(post_id);

-- 6. Create poll_options table
CREATE TABLE IF NOT EXISTS poll_options (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  poll_id UUID REFERENCES polls(id) ON DELETE CASCADE NOT NULL,
  option_text TEXT NOT NULL,
  vote_count INTEGER DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_poll_options_poll_id ON poll_options(poll_id);

-- 7. Create poll_votes table (track votes - one vote per user per poll)
CREATE TABLE IF NOT EXISTS poll_votes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  poll_id UUID REFERENCES polls(id) ON DELETE CASCADE NOT NULL,
  option_id UUID REFERENCES poll_options(id) ON DELETE CASCADE NOT NULL,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(poll_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_poll_votes_poll_id ON poll_votes(poll_id);
CREATE INDEX IF NOT EXISTS idx_poll_votes_user_id ON poll_votes(user_id);

-- 8. Create anonymous_questions table (for Q&A mode)
CREATE TABLE IF NOT EXISTS anonymous_questions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  target_user_id UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
  question TEXT NOT NULL,
  answer TEXT DEFAULT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  answered_at TIMESTAMP DEFAULT NULL,
  answered BOOLEAN DEFAULT FALSE,
  is_public BOOLEAN DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS idx_anonymous_questions_target_user_id ON anonymous_questions(target_user_id);

-- 9. Create confession_rooms table (for temporary anonymous chat rooms)
CREATE TABLE IF NOT EXISTS confession_rooms (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
  room_name TEXT NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT NOW(),
  is_active BOOLEAN DEFAULT TRUE
);

CREATE INDEX IF NOT EXISTS idx_confession_rooms_creator_id ON confession_rooms(creator_id);

-- 10. Create room_messages table (messages in confession rooms)
CREATE TABLE IF NOT EXISTS room_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id UUID REFERENCES confession_rooms(id) ON DELETE CASCADE NOT NULL,
  message TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_room_messages_room_id ON room_messages(room_id);

-- Enable Row Level Security on analytics table
ALTER TABLE user_analytics ENABLE ROW LEVEL SECURITY;
ALTER TABLE polls ENABLE ROW LEVEL SECURITY;
ALTER TABLE poll_options ENABLE ROW LEVEL SECURITY;
ALTER TABLE poll_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE anonymous_questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE confession_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE room_messages ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can view their own analytics
DO $$ 
BEGIN
  DROP POLICY IF EXISTS "Users can view their own analytics" ON user_analytics;
END $$;

CREATE POLICY "Users can view their own analytics"
  ON user_analytics FOR SELECT
  USING (auth.uid() = user_id);

-- RLS Policy: Polls are public read, but owned by post
DO $$ 
BEGIN
  DROP POLICY IF EXISTS "Polls readable by all" ON polls;
END $$;

CREATE POLICY "Polls readable by all"
  ON polls FOR SELECT
  USING (TRUE);

DO $$ 
BEGIN
  DROP POLICY IF EXISTS "Poll options readable by all" ON poll_options;
END $$;

CREATE POLICY "Poll options readable by all"
  ON poll_options FOR SELECT
  USING (TRUE);

-- RLS Policy: Users can see their own poll votes
DO $$ 
BEGIN
  DROP POLICY IF EXISTS "Users can view their own poll votes" ON poll_votes;
END $$;

CREATE POLICY "Users can view their own poll votes"
  ON poll_votes FOR SELECT
  USING (auth.uid() = user_id);

-- RLS Policy: Users can vote once
DO $$ 
BEGIN
  DROP POLICY IF EXISTS "Users can insert their own poll vote" ON poll_votes;
END $$;

CREATE POLICY "Users can insert their own poll vote"
  ON poll_votes FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- RLS Policy: Anonymous questions visible to target user
DO $$ 
BEGIN
  DROP POLICY IF EXISTS "Target user can view their questions" ON anonymous_questions;
END $$;

CREATE POLICY "Target user can view their questions"
  ON anonymous_questions FOR SELECT
  USING (auth.uid() = target_user_id);

-- RLS Policy: Anyone can insert questions to a user
DO $$ 
BEGIN
  DROP POLICY IF EXISTS "Anyone can insert anonymous questions" ON anonymous_questions;
END $$;

CREATE POLICY "Anyone can insert anonymous questions"
  ON anonymous_questions FOR INSERT
  WITH CHECK (TRUE);

-- RLS Policy: Confession rooms visible to members
DO $$ 
BEGIN
  DROP POLICY IF EXISTS "Confession room creator can view their room" ON confession_rooms;
END $$;

CREATE POLICY "Confession room creator can view their room"
  ON confession_rooms FOR SELECT
  USING (auth.uid() = creator_id);

-- RLS Policy: Room messages visible to room creator
DO $$ 
BEGIN
  DROP POLICY IF EXISTS "Room messages visible to creator" ON room_messages;
END $$;

CREATE POLICY "Room messages visible to creator"
  ON room_messages FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM confession_rooms
    WHERE confession_rooms.id = room_messages.room_id
    AND confession_rooms.creator_id = auth.uid()
  ));
