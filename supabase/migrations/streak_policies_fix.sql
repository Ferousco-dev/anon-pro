-- Fix RLS policies for streak/verification tables used by client

-- Allow users to create and update their own streak rows
CREATE POLICY "Users can insert their own streaks"
  ON user_streaks FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own streaks"
  ON user_streaks FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Allow users to insert their own milestones (client-side unlock)
CREATE POLICY "Users can insert their own streak milestones"
  ON streak_milestones FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Allow users to insert their own verification notifications
CREATE POLICY "Users can insert their own verification notifications"
  ON verification_notifications FOR INSERT
  WITH CHECK (auth.uid() = user_id);
