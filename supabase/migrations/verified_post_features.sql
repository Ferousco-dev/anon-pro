-- Verified-only post categories/tags + profile link/highlight

ALTER TABLE public.posts
  ADD COLUMN IF NOT EXISTS post_category TEXT,
  ADD COLUMN IF NOT EXISTS post_custom_tags TEXT;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS profile_link TEXT,
  ADD COLUMN IF NOT EXISTS highlight_post_id UUID;

CREATE INDEX IF NOT EXISTS idx_posts_post_category ON public.posts(post_category);
CREATE INDEX IF NOT EXISTS idx_users_highlight_post_id ON public.users(highlight_post_id);
