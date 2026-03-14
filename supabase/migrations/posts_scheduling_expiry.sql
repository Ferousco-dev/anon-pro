-- Add scheduling and expiry for temporary posts

ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS scheduled_at TIMESTAMP,
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP,
  ADD COLUMN IF NOT EXISTS is_temporary BOOLEAN DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_posts_scheduled_at ON public.posts(scheduled_at);
CREATE INDEX IF NOT EXISTS idx_posts_expires_at ON public.posts(expires_at);
