-- Notifications system: events + push triggers

CREATE EXTENSION IF NOT EXISTS pg_net;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS fcm_token TEXT;

CREATE TABLE IF NOT EXISTS public.notification_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notification_events_user
  ON public.notification_events(user_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.notify_user(
  p_user_id UUID,
  p_type TEXT,
  p_title TEXT,
  p_body TEXT,
  p_data JSONB
) RETURNS VOID AS $$
DECLARE
  v_token TEXT;
BEGIN
  INSERT INTO public.notification_events (user_id, type, title, body, data)
  VALUES (p_user_id, p_type, p_title, p_body, COALESCE(p_data, '{}'::jsonb));

  SELECT fcm_token INTO v_token
  FROM public.users
  WHERE id = p_user_id;

  IF v_token IS NULL OR v_token = '' THEN
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := 'https://mnfbdrdmqromgfnqetzh.supabase.co/functions/v1/send-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'token', v_token,
      'title', p_title,
      'body', p_body,
      'data', p_data,
      'sound', 'default'
    )
  );
END;
$$ LANGUAGE plpgsql;

-- New follower
CREATE OR REPLACE FUNCTION public.notify_new_follower()
RETURNS TRIGGER AS $$
DECLARE
  v_name TEXT;
BEGIN
  SELECT COALESCE(display_name, alias) INTO v_name
  FROM public.users WHERE id = NEW.follower_id;

  PERFORM public.notify_user(
    NEW.following_id,
    'new_follower',
    'New follower',
    '@' || v_name || ' followed you',
    jsonb_build_object('type', 'new_follower', 'userId', NEW.follower_id)
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_notify_new_follower ON public.follows;
CREATE TRIGGER trg_notify_new_follower
  AFTER INSERT ON public.follows
  FOR EACH ROW EXECUTE FUNCTION public.notify_new_follower();

-- Confession room created (notify followers of creator)
CREATE OR REPLACE FUNCTION public.notify_room_created()
RETURNS TRIGGER AS $$
DECLARE
  v_room_name TEXT;
  v_join_code TEXT;
  v_follower RECORD;
BEGIN
  v_room_name := NEW.room_name;
  v_join_code := NEW.join_code;

  FOR v_follower IN
    SELECT follower_id FROM public.follows WHERE following_id = NEW.creator_id
  LOOP
    PERFORM public.notify_user(
      v_follower.follower_id,
      'room_created',
      'New confession room',
      v_room_name || ' is open. Code: ' || COALESCE(v_join_code, ''),
      jsonb_build_object('type', 'room_created', 'roomId', NEW.id)
    );
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_notify_room_created ON public.confession_rooms;
CREATE TRIGGER trg_notify_room_created
  AFTER INSERT ON public.confession_rooms
  FOR EACH ROW EXECUTE FUNCTION public.notify_room_created();

-- Question answered (notify asker)
CREATE OR REPLACE FUNCTION public.notify_question_reply()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.answered = TRUE AND (OLD.answered IS DISTINCT FROM TRUE) THEN
    IF NEW.asker_user_id IS NOT NULL THEN
      PERFORM public.notify_user(
        NEW.asker_user_id,
        'question_reply',
        'Your question got a reply',
        'Tap to see the response',
        jsonb_build_object('type', 'question_reply', 'questionId', NEW.id)
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_notify_question_reply ON public.anonymous_questions;
CREATE TRIGGER trg_notify_question_reply
  AFTER UPDATE ON public.anonymous_questions
  FOR EACH ROW EXECUTE FUNCTION public.notify_question_reply();

-- Streak unlocked (verified)
CREATE OR REPLACE FUNCTION public.notify_streak_unlocked()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.milestone_type = 'verified_unlocked' THEN
    PERFORM public.notify_user(
      NEW.user_id,
      'streak_unlocked',
      'Streak unlocked',
      'You unlocked verified status 🎉',
      jsonb_build_object('type', 'streak_unlocked')
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_notify_streak_unlocked ON public.streak_milestones;
CREATE TRIGGER trg_notify_streak_unlocked
  AFTER INSERT ON public.streak_milestones
  FOR EACH ROW EXECUTE FUNCTION public.notify_streak_unlocked();

-- New post (notify followers, skip anonymous + scheduled future)
CREATE OR REPLACE FUNCTION public.notify_new_post()
RETURNS TRIGGER AS $$
DECLARE
  v_follower RECORD;
  v_name TEXT;
BEGIN
  IF NEW.is_anonymous = TRUE THEN
    RETURN NEW;
  END IF;
  IF NEW.scheduled_at IS NOT NULL AND NEW.scheduled_at > NOW() THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(display_name, alias) INTO v_name
  FROM public.users WHERE id = NEW.user_id;

  FOR v_follower IN
    SELECT follower_id FROM public.follows WHERE following_id = NEW.user_id
  LOOP
    PERFORM public.notify_user(
      v_follower.follower_id,
      'new_post',
      'New post',
      '@' || v_name || ' posted something new',
      jsonb_build_object('type', 'new_post', 'postId', NEW.id)
    );
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_notify_new_post ON public.posts;
CREATE TRIGGER trg_notify_new_post
  AFTER INSERT ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.notify_new_post();
