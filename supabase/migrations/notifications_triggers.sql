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
  v_base_url TEXT := 'https://mnfbdrdmqromgfnqetzh.supabase.co';
  v_anon_key TEXT := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1uZmJkcmRtcXJvbWdmbnFldHpoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA3OTczOTIsImV4cCI6MjA4NjM3MzM5Mn0.roYKRHpKi9JrG_2LgGIztRMx_1fZF_0emcyRUd7F7Yg';
  v_payload JSONB;
  v_data JSONB;
  v_data_only BOOLEAN := FALSE;
BEGIN
  INSERT INTO public.notification_events (user_id, type, title, body, data)
  VALUES (p_user_id, p_type, p_title, p_body, COALESCE(p_data, '{}'::jsonb));

  SELECT fcm_token INTO v_token
  FROM public.users
  WHERE id = p_user_id;

  IF v_token IS NULL OR v_token = '' THEN
    RETURN;
  END IF;

  v_data := COALESCE(p_data, '{}'::jsonb) - 'data_only';
  IF p_data ? 'data_only' THEN
    v_data_only := (p_data->>'data_only')::boolean;
  END IF;

  v_payload := jsonb_build_object(
    'token', v_token,
    'title', p_title,
    'body', p_body,
    'data', v_data,
    'sound', 'default'
  );

  IF v_data_only THEN
    v_payload := v_payload || jsonb_build_object(
      'data_only', true
    );
  END IF;

  PERFORM net.http_post(
    url := v_base_url || '/functions/v1/send-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    ),
    body := v_payload
  );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.notify_topic(
  p_topic TEXT,
  p_title TEXT,
  p_body TEXT,
  p_data JSONB,
  p_sound TEXT DEFAULT NULL,
  p_channel_id TEXT DEFAULT NULL,
  p_image TEXT DEFAULT NULL
) RETURNS VOID AS $$
DECLARE
  v_base_url TEXT := 'https://mnfbdrdmqromgfnqetzh.supabase.co';
  v_anon_key TEXT := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1uZmJkcmRtcXJvbWdmbnFldHpoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA3OTczOTIsImV4cCI6MjA4NjM3MzM5Mn0.roYKRHpKi9JrG_2LgGIztRMx_1fZF_0emcyRUd7F7Yg';
  v_payload JSONB;
  v_data JSONB;
  v_data_only BOOLEAN := FALSE;
BEGIN
  IF p_topic IS NULL OR btrim(p_topic) = '' THEN
    RETURN;
  END IF;

  v_data := COALESCE(p_data, '{}'::jsonb) - 'data_only';
  IF p_data ? 'data_only' THEN
    v_data_only := (p_data->>'data_only')::boolean;
  END IF;

  v_payload := jsonb_build_object(
    'topic', btrim(p_topic),
    'title', p_title,
    'body', p_body,
    'data', v_data,
    'sound', 'default'
  );

  IF v_data_only THEN
    v_payload := v_payload || jsonb_build_object(
      'data_only', true
    );
  END IF;

  IF p_sound IS NOT NULL AND btrim(p_sound) <> '' THEN
    v_payload := v_payload || jsonb_build_object(
      'sound', btrim(p_sound)
    );
  END IF;

  IF p_channel_id IS NOT NULL AND btrim(p_channel_id) <> '' THEN
    v_payload := v_payload || jsonb_build_object(
      'channel_id', btrim(p_channel_id)
    );
  END IF;

  IF p_image IS NOT NULL AND btrim(p_image) <> '' THEN
    v_payload := v_payload || jsonb_build_object(
      'image', btrim(p_image)
    );
  END IF;

  PERFORM net.http_post(
    url := v_base_url || '/functions/v1/send-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_anon_key,
      'Authorization', 'Bearer ' || v_anon_key
    ),
    body := v_payload
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
  v_name TEXT;
  v_topic TEXT;
  v_title TEXT;
  v_body TEXT;
  v_data JSONB;
  v_snippet TEXT;
  v_image TEXT;
BEGIN
  IF NEW.scheduled_at IS NOT NULL AND NEW.scheduled_at > NOW() THEN
    RETURN NEW;
  END IF;

  v_snippet := LEFT(COALESCE(NEW.content, ''), 120);
  IF btrim(v_snippet) = '' THEN
    IF NEW.image_url IS NOT NULL AND NEW.image_url <> '' THEN
      v_snippet := 'Shared a photo';
    ELSE
      v_snippet := 'Shared a post';
    END IF;
  END IF;
  v_image := NULLIF(NEW.image_url, '');

  IF NEW.is_anonymous = TRUE THEN
    v_topic := 'all_users';
    v_title := 'Anonymous';
    v_body := v_snippet;
    v_data := jsonb_build_object(
      'type', 'new_post',
      'postId', NEW.id,
      'isAnonymous', true,
      'title', v_title,
      'body', v_body,
      'snippet', v_snippet,
      'imageUrl', v_image
    );
  ELSE
    SELECT COALESCE(display_name, alias, 'Someone') INTO v_name
    FROM public.users WHERE id = NEW.user_id;

    v_topic := 'followers_' || NEW.user_id;
    v_title := '@' || v_name;
    v_body := v_snippet;
    v_data := jsonb_build_object(
      'type', 'new_post',
      'postId', NEW.id,
      'userId', NEW.user_id,
      'isAnonymous', false,
      'title', v_title,
      'body', v_body,
      'snippet', v_snippet,
      'imageUrl', v_image
    );
  END IF;

  PERFORM public.notify_topic(
    v_topic,
    v_title,
    v_body,
    v_data,
    'bamboo.m4r',
    'new_posts',
    v_image
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_notify_new_post ON public.posts;
CREATE TRIGGER trg_notify_new_post
  AFTER INSERT ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.notify_new_post();
