-- Ensure user_analytics exists for create_user_analytics trigger

CREATE TABLE IF NOT EXISTS public.user_analytics (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  profile_views INTEGER DEFAULT 0,
  post_views INTEGER DEFAULT 0,
  likes_received INTEGER DEFAULT 0,
  comments_received INTEGER DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.user_analytics ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own analytics" ON public.user_analytics;
CREATE POLICY "Users can read own analytics"
  ON public.user_analytics FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "System can update analytics" ON public.user_analytics;
CREATE POLICY "System can update analytics"
  ON public.user_analytics FOR UPDATE
  USING (true);
