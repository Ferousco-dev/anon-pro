-- Create user_statuses table if it doesn't exist
CREATE TABLE IF NOT EXISTS user_statuses (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  media_path TEXT NOT NULL,
  media_type TEXT NOT NULL DEFAULT 'image',
  caption TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  expires_at TIMESTAMP WITH TIME ZONE DEFAULT (NOW() + INTERVAL '24 hours'),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_user_statuses_user_id ON user_statuses(user_id);
CREATE INDEX IF NOT EXISTS idx_user_statuses_created_at ON user_statuses(created_at);
CREATE INDEX IF NOT EXISTS idx_user_statuses_expires_at ON user_statuses(expires_at);

-- Enable RLS
ALTER TABLE user_statuses ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can view statuses from users they follow" ON user_statuses
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM follows
      WHERE follows.follower_id = auth.uid()
      AND follows.following_id = user_statuses.user_id
    ) OR user_statuses.user_id = auth.uid()
  );

CREATE POLICY "Users can insert their own statuses" ON user_statuses
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own statuses" ON user_statuses
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own statuses" ON user_statuses
  FOR DELETE USING (auth.uid() = user_id);

-- Create the RPC function
DROP FUNCTION IF EXISTS get_user_status_feed(UUID);
CREATE OR REPLACE FUNCTION get_user_status_feed(user_uuid UUID)
RETURNS TABLE(
  status_id UUID,
  user_id UUID,
  alias TEXT,
  display_name TEXT,
  profile_image_url TEXT,
  media_path TEXT,
  media_type TEXT,
  caption TEXT,
  created_at TIMESTAMP WITH TIME ZONE,
  expires_at TIMESTAMP WITH TIME ZONE,
  has_viewed BOOLEAN,
  views_count INTEGER,
  likes_count INTEGER,
  has_liked BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    us.id as status_id,
    us.user_id,
    u.alias,
    u.display_name,
    u.profile_image_url,
    us.media_path,
    us.media_type,
    us.caption,
    us.created_at,
    us.expires_at,
    -- For now, simplified - no views/likes tracking yet
    FALSE as has_viewed,
    0 as views_count,
    0 as likes_count,
    FALSE as has_liked
  FROM user_statuses us
  JOIN users u ON us.user_id = u.id
  WHERE us.expires_at > NOW()
  -- Temporarily return all statuses for debugging
  -- AND (
  --   EXISTS (
  --     SELECT 1 FROM follows
  --     WHERE follows.follower_id = user_uuid
  --     AND follows.following_id = us.user_id
  --   ) OR us.user_id = user_uuid
  -- )
  ORDER BY us.created_at DESC;
END;
$$;
