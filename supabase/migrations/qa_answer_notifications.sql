-- Q&A Answer Notifications System Migration

-- 1. Add asker_user_id to anonymous_questions table if not exists
DO $$ 
BEGIN
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'anonymous_questions') THEN
    ALTER TABLE anonymous_questions
    ADD COLUMN IF NOT EXISTS asker_user_id UUID REFERENCES users(id) ON DELETE CASCADE;

    CREATE INDEX IF NOT EXISTS idx_anonymous_questions_asker_user_id ON anonymous_questions(asker_user_id);
  END IF;
END $$;

-- 2. Create qa_answer_notifications table for tracking answered questions
CREATE TABLE IF NOT EXISTS qa_answer_notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  asker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  answerer_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  question_id UUID NOT NULL REFERENCES anonymous_questions(id) ON DELETE CASCADE,
  question_text TEXT NOT NULL,
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_qa_answer_notifications_asker_id ON qa_answer_notifications(asker_id);
CREATE INDEX IF NOT EXISTS idx_qa_answer_notifications_is_read ON qa_answer_notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_qa_answer_notifications_created_at ON qa_answer_notifications(created_at DESC);

-- Enable Row Level Security
ALTER TABLE qa_answer_notifications ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can view their own answer notifications
DROP POLICY IF EXISTS "Users can view their own answer notifications" ON qa_answer_notifications;
CREATE POLICY "Users can view their own answer notifications"
  ON qa_answer_notifications FOR SELECT
  USING (auth.uid() = asker_id);

-- RLS Policy: Users can mark their own notifications as read
DROP POLICY IF EXISTS "Users can update their own answer notifications" ON qa_answer_notifications;
CREATE POLICY "Users can update their own answer notifications"
  ON qa_answer_notifications FOR UPDATE
  USING (auth.uid() = asker_id);

-- RLS Policy: System can insert notifications
DROP POLICY IF EXISTS "System can insert answer notifications" ON qa_answer_notifications;
CREATE POLICY "System can insert answer notifications"
  ON qa_answer_notifications FOR INSERT
  WITH CHECK (TRUE);
