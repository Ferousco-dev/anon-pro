-- ══════════════════════════════════════════════════════════════════════════
--  ANONPRO — Notification System SQL Setup
--  Run this entire script in your Supabase SQL Editor (one shot).
-- ══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- 1.  FOLLOWS TABLE
--     Stores who follows whom. Already used by profile_screen.dart.
--     This is safe to run even if the table already exists.
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.follows (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  follower_id   UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  following_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (follower_id, following_id)
);

-- Index for fast "who follows me?" queries (used by the Activity tab)
CREATE INDEX IF NOT EXISTS follows_following_id_idx ON public.follows (following_id);
-- Index for fast "who am I following?" queries
CREATE INDEX IF NOT EXISTS follows_follower_id_idx  ON public.follows (follower_id);


-- ─────────────────────────────────────────────────────────────────────────
-- 2.  LIKES TABLE  (create if not already there)
--     The notification system reads: who liked MY posts?
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.likes (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id    UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (post_id, user_id)
);

CREATE INDEX IF NOT EXISTS likes_post_id_idx ON public.likes (post_id);
CREATE INDEX IF NOT EXISTS likes_user_id_idx ON public.likes (user_id);


-- ─────────────────────────────────────────────────────────────────────────
-- 3.  COMMENTS TABLE  (create if not already there)
--     The notification system reads: who commented on MY posts?
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.comments (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id    UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  content    TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS comments_post_id_idx ON public.comments (post_id);
CREATE INDEX IF NOT EXISTS comments_user_id_idx ON public.comments (user_id);


-- ─────────────────────────────────────────────────────────────────────────
-- 4.  AUTO-UPDATE followers_count / following_count ON users TABLE
--     Keeps the counters on the users row in sync automatically.
--     (Only needed if this trigger doesn't already exist.)
-- ─────────────────────────────────────────────────────────────────────────

-- Function called after INSERT or DELETE on follows
CREATE OR REPLACE FUNCTION public.update_follow_counts()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- increment follower's following_count
    UPDATE public.users
      SET following_count = following_count + 1
      WHERE id = NEW.follower_id;

    -- increment target's followers_count
    UPDATE public.users
      SET followers_count = followers_count + 1
      WHERE id = NEW.following_id;

  ELSIF TG_OP = 'DELETE' THEN
    -- decrement follower's following_count (never go below 0)
    UPDATE public.users
      SET following_count = GREATEST(following_count - 1, 0)
      WHERE id = OLD.follower_id;

    -- decrement target's followers_count (never go below 0)
    UPDATE public.users
      SET followers_count = GREATEST(followers_count - 1, 0)
      WHERE id = OLD.following_id;
  END IF;

  RETURN NULL;
END;
$$;

-- Attach the trigger (drop first to avoid duplicate trigger error)
DROP TRIGGER IF EXISTS trg_follow_counts ON public.follows;
CREATE TRIGGER trg_follow_counts
  AFTER INSERT OR DELETE ON public.follows
  FOR EACH ROW EXECUTE FUNCTION public.update_follow_counts();


-- ─────────────────────────────────────────────────────────────────────────
-- 5.  ROW LEVEL SECURITY (RLS)
-- ─────────────────────────────────────────────────────────────────────────

-- ── follows ──
ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;

-- Anyone logged in can see follows (needed to check follow status on profiles)
DROP POLICY IF EXISTS "follows_select" ON public.follows;
CREATE POLICY "follows_select" ON public.follows
  FOR SELECT USING (auth.role() = 'authenticated');

-- Users can only insert their own follow rows
DROP POLICY IF EXISTS "follows_insert" ON public.follows;
CREATE POLICY "follows_insert" ON public.follows
  FOR INSERT WITH CHECK (auth.uid() = follower_id);

-- Users can only delete their own follow rows
DROP POLICY IF EXISTS "follows_delete" ON public.follows;
CREATE POLICY "follows_delete" ON public.follows
  FOR DELETE USING (auth.uid() = follower_id);


-- ── likes ──
ALTER TABLE public.likes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "likes_select" ON public.likes;
CREATE POLICY "likes_select" ON public.likes
  FOR SELECT USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "likes_insert" ON public.likes;
CREATE POLICY "likes_insert" ON public.likes
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "likes_delete" ON public.likes;
CREATE POLICY "likes_delete" ON public.likes
  FOR DELETE USING (auth.uid() = user_id);


-- ── comments ──
ALTER TABLE public.comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "comments_select" ON public.comments;
CREATE POLICY "comments_select" ON public.comments
  FOR SELECT USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "comments_insert" ON public.comments;
CREATE POLICY "comments_insert" ON public.comments
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "comments_delete" ON public.comments;
CREATE POLICY "comments_delete" ON public.comments
  FOR DELETE USING (
    auth.uid() = user_id
    OR EXISTS (
      SELECT 1 FROM public.posts p
      WHERE p.id = post_id AND p.user_id = auth.uid()
    )
  );


-- ─────────────────────────────────────────────────────────────────────────
-- 6.  VERIFY  (optional — shows table counts to confirm setup worked)
-- ─────────────────────────────────────────────────────────────────────────
SELECT
  'follows'  AS tbl, COUNT(*) FROM public.follows
UNION ALL
SELECT 'likes',    COUNT(*) FROM public.likes
UNION ALL
SELECT 'comments', COUNT(*) FROM public.comments;
