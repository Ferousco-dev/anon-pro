-- Post tags: when users tag others with @username in posts
CREATE TABLE IF NOT EXISTS public.post_tags (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id    UUID NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  tagged_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (post_id, tagged_user_id)
);

CREATE INDEX IF NOT EXISTS post_tags_post_id_idx ON public.post_tags (post_id);
CREATE INDEX IF NOT EXISTS post_tags_tagged_user_id_idx ON public.post_tags (tagged_user_id);

ALTER TABLE public.post_tags ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "post_tags_select" ON public.post_tags;
CREATE POLICY "post_tags_select" ON public.post_tags
  FOR SELECT USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "post_tags_insert" ON public.post_tags;
CREATE POLICY "post_tags_insert" ON public.post_tags
  FOR INSERT WITH CHECK (
    auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.posts p
      WHERE p.id = post_id AND p.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "post_tags_delete" ON public.post_tags;
CREATE POLICY "post_tags_delete" ON public.post_tags
  FOR DELETE USING (
    auth.uid() IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.posts p
      WHERE p.id = post_id AND p.user_id = auth.uid()
    )
  );
