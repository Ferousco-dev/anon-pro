-- Moderation: keyword filters, auto-flagging, strike system

ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS strike_limit INTEGER DEFAULT 3,
  ADD COLUMN IF NOT EXISTS auto_ban_on_strike BOOLEAN DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS public.moderation_keywords (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  keyword TEXT NOT NULL,
  severity TEXT DEFAULT 'medium',
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_moderation_keywords
  ON public.moderation_keywords(keyword);

ALTER TABLE public.moderation_keywords ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "moderation_keywords_select" ON public.moderation_keywords;
CREATE POLICY "moderation_keywords_select"
  ON public.moderation_keywords FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "moderation_keywords_admin_write" ON public.moderation_keywords;
CREATE POLICY "moderation_keywords_admin_write"
  ON public.moderation_keywords FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

CREATE TABLE IF NOT EXISTS public.content_flags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content_type TEXT NOT NULL,
  content_id UUID NOT NULL,
  user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  matched_keyword TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_content_flags_content
  ON public.content_flags(content_type, content_id);

ALTER TABLE public.content_flags ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "content_flags_select_admin" ON public.content_flags;
CREATE POLICY "content_flags_select_admin"
  ON public.content_flags FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

DROP POLICY IF EXISTS "content_flags_insert_system" ON public.content_flags;
CREATE POLICY "content_flags_insert_system"
  ON public.content_flags FOR INSERT
  WITH CHECK (true);

CREATE TABLE IF NOT EXISTS public.user_strikes (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  strikes_count INTEGER DEFAULT 0,
  last_strike_at TIMESTAMPTZ
);

ALTER TABLE public.user_strikes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_strikes_select_admin" ON public.user_strikes;
CREATE POLICY "user_strikes_select_admin"
  ON public.user_strikes FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

DROP POLICY IF EXISTS "user_strikes_update_admin" ON public.user_strikes;
CREATE POLICY "user_strikes_update_admin"
  ON public.user_strikes FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

CREATE OR REPLACE FUNCTION public.apply_strike(p_user_id UUID)
RETURNS VOID AS $$
DECLARE
  v_strikes INTEGER;
  v_limit INTEGER;
BEGIN
  INSERT INTO public.user_strikes (user_id, strikes_count, last_strike_at)
  VALUES (p_user_id, 1, NOW())
  ON CONFLICT (user_id) DO UPDATE
  SET strikes_count = public.user_strikes.strikes_count + 1,
      last_strike_at = NOW()
  RETURNING strikes_count INTO v_strikes;

  SELECT strike_limit INTO v_limit FROM public.app_settings WHERE id = 1;
  IF v_limit IS NULL THEN v_limit := 3; END IF;

  IF v_strikes >= v_limit THEN
    IF EXISTS (
      SELECT 1 FROM public.app_settings
      WHERE id = 1 AND auto_ban_on_strike = TRUE
    ) THEN
      UPDATE public.users SET is_banned = TRUE WHERE id = p_user_id;
    END IF;
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.flag_content_by_keywords(
  p_content_type TEXT,
  p_content_id UUID,
  p_user_id UUID,
  p_text TEXT
) RETURNS VOID AS $$
DECLARE
  v_keyword TEXT;
BEGIN
  SELECT keyword INTO v_keyword
  FROM public.moderation_keywords
  WHERE is_active = TRUE
    AND p_text ILIKE '%' || keyword || '%'
  LIMIT 1;

  IF v_keyword IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO public.content_flags (content_type, content_id, user_id, matched_keyword)
  VALUES (p_content_type, p_content_id, p_user_id, v_keyword);

  PERFORM public.apply_strike(p_user_id);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.flag_post_keywords()
RETURNS TRIGGER AS $$
BEGIN
  PERFORM public.flag_content_by_keywords('post', NEW.id, NEW.user_id, NEW.content);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_flag_post_keywords ON public.posts;
CREATE TRIGGER trg_flag_post_keywords
  AFTER INSERT ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.flag_post_keywords();

CREATE OR REPLACE FUNCTION public.flag_comment_keywords()
RETURNS TRIGGER AS $$
BEGIN
  PERFORM public.flag_content_by_keywords('comment', NEW.id, NEW.user_id, NEW.content);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_flag_comment_keywords ON public.comments;
CREATE TRIGGER trg_flag_comment_keywords
  AFTER INSERT ON public.comments
  FOR EACH ROW EXECUTE FUNCTION public.flag_comment_keywords();
