-- Add streak requirement settings to app_settings

ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS streak_required_posts INTEGER DEFAULT 12,
  ADD COLUMN IF NOT EXISTS streak_required_engaged_posts INTEGER DEFAULT 5,
  ADD COLUMN IF NOT EXISTS streak_required_total_engagement INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS streak_required_avg_likes DOUBLE PRECISION DEFAULT 0;

UPDATE public.app_settings
SET streak_required_posts = COALESCE(streak_required_posts, 12),
    streak_required_engaged_posts = COALESCE(streak_required_engaged_posts, 5),
    streak_required_total_engagement = COALESCE(streak_required_total_engagement, 0),
    streak_required_avg_likes = COALESCE(streak_required_avg_likes, 0)
WHERE id = 1;
