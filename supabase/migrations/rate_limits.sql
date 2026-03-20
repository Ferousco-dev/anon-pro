-- Server-side rate limiting for posts, messages, and rooms

ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS rate_limit_posts_per_minute INTEGER DEFAULT 5,
  ADD COLUMN IF NOT EXISTS rate_limit_messages_per_minute INTEGER DEFAULT 20,
  ADD COLUMN IF NOT EXISTS rate_limit_rooms_per_hour INTEGER DEFAULT 3;

CREATE TABLE IF NOT EXISTS public.rate_limits (
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  window_start TIMESTAMPTZ NOT NULL,
  count INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, action, window_start)
);

CREATE OR REPLACE FUNCTION public.apply_rate_limit(
  p_user_id UUID,
  p_action TEXT,
  p_limit INTEGER,
  p_window_seconds INTEGER
) RETURNS VOID AS $$
DECLARE
  v_window_start TIMESTAMPTZ;
  v_count INTEGER;
BEGIN
  v_window_start := to_timestamp(
    floor(extract(epoch from now()) / p_window_seconds) * p_window_seconds
  );

  INSERT INTO public.rate_limits (user_id, action, window_start, count)
  VALUES (p_user_id, p_action, v_window_start, 1)
  ON CONFLICT (user_id, action, window_start)
  DO UPDATE SET count = public.rate_limits.count + 1
  RETURNING count INTO v_count;

  IF v_count > p_limit THEN
    RAISE EXCEPTION 'Rate limit exceeded for %', p_action
      USING ERRCODE = 'P0001';
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.enforce_post_rate_limit()
RETURNS TRIGGER AS $$
DECLARE
  v_limit INTEGER;
BEGIN
  SELECT rate_limit_posts_per_minute INTO v_limit
  FROM public.app_settings WHERE id = 1;
  IF v_limit IS NULL THEN v_limit := 5; END IF;
  PERFORM public.apply_rate_limit(NEW.user_id, 'post', v_limit, 60);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_rate_limit_posts ON public.posts;
CREATE TRIGGER trg_rate_limit_posts
  BEFORE INSERT ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.enforce_post_rate_limit();

CREATE OR REPLACE FUNCTION public.enforce_message_rate_limit()
RETURNS TRIGGER AS $$
DECLARE
  v_limit INTEGER;
BEGIN
  SELECT rate_limit_messages_per_minute INTO v_limit
  FROM public.app_settings WHERE id = 1;
  IF v_limit IS NULL THEN v_limit := 20; END IF;
  PERFORM public.apply_rate_limit(NEW.sender_id, 'message', v_limit, 60);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_rate_limit_messages ON public.messages;
CREATE TRIGGER trg_rate_limit_messages
  BEFORE INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.enforce_message_rate_limit();

CREATE OR REPLACE FUNCTION public.enforce_room_rate_limit()
RETURNS TRIGGER AS $$
DECLARE
  v_limit INTEGER;
BEGIN
  SELECT rate_limit_rooms_per_hour INTO v_limit
  FROM public.app_settings WHERE id = 1;
  IF v_limit IS NULL THEN v_limit := 3; END IF;
  PERFORM public.apply_rate_limit(NEW.creator_id, 'room', v_limit, 3600);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_rate_limit_rooms ON public.confession_rooms;
CREATE TRIGGER trg_rate_limit_rooms
  BEFORE INSERT ON public.confession_rooms
  FOR EACH ROW EXECUTE FUNCTION public.enforce_room_rate_limit();
