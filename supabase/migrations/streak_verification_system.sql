-- Streak & Auto-Verification System Migration

-- 1. Create user_streaks table
CREATE TABLE IF NOT EXISTS user_streaks (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  current_streak INTEGER DEFAULT 0,
  total_posts INTEGER DEFAULT 0,
  posts_with_engagement INTEGER DEFAULT 0,
  last_post_date DATE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_streaks_current_streak ON user_streaks(current_streak);
CREATE INDEX IF NOT EXISTS idx_user_streaks_posts_engagement ON user_streaks(posts_with_engagement);

-- 2. Create streak_milestones table (track achievements)
CREATE TABLE IF NOT EXISTS streak_milestones (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
  milestone_type TEXT NOT NULL CHECK (milestone_type IN ('verified_unlocked', 'consecutive_posts', 'high_engagement')),
  description TEXT,
  verified_date TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_streak_milestones_user_id ON streak_milestones(user_id);
CREATE INDEX IF NOT EXISTS idx_streak_milestones_milestone_type ON streak_milestones(milestone_type);

-- 3. Create verification_notifications table
CREATE TABLE IF NOT EXISTS verification_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES users(id) ON DELETE CASCADE NOT NULL,
  notification_type TEXT DEFAULT 'verified_unlocked',
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_verification_notifications_user_id ON verification_notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_verification_notifications_is_read ON verification_notifications(is_read);

-- Enable RLS
ALTER TABLE user_streaks ENABLE ROW LEVEL SECURITY;
ALTER TABLE streak_milestones ENABLE ROW LEVEL SECURITY;
ALTER TABLE verification_notifications ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view their own streaks"
  ON user_streaks FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can view their own notifications"
  ON verification_notifications FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can mark notifications as read"
  ON verification_notifications FOR UPDATE
  USING (auth.uid() = user_id);
