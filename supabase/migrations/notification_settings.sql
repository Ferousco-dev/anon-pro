-- Per-user notification preferences + expanded triggers

CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE TABLE IF NOT EXISTS public.notification_settings (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  notify_new_follower BOOLEAN DEFAULT TRUE,
  notify_new_post BOOLEAN DEFAULT TRUE,
  notify_post_like BOOLEAN DEFAULT TRUE,
  notify_post_comment BOOLEAN DEFAULT TRUE,
  notify_room_created BOOLEAN DEFAULT TRUE,
  notify_room_message BOOLEAN DEFAULT FALSE,
  notify_question_reply BOOLEAN DEFAULT TRUE,
  notify_streak_unlocked BOOLEAN DEFAULT TRUE,
  notify_dm_message BOOLEAN DEFAULT TRUE,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.notification_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "notification_settings_select" ON public.notification_settings;
CREATE POLICY "notification_settings_select"
  ON public.notification_settings FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "notification_settings_insert" ON public.notification_settings;
CREATE POLICY "notification_settings_insert"
  ON public.notification_settings FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "notification_settings_update" ON public.notification_settings;
CREATE POLICY "notification_settings_update"
  ON public.notification_settings FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.can_notify(p_user_id UUID, p_type TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  s public.notification_settings;
BEGIN
  SELECT * INTO s FROM public.notification_settings WHERE user_id = p_user_id;
  IF s.user_id IS NULL THEN
    INSERT INTO public.notification_settings (user_id) VALUES (p_user_id);
    SELECT * INTO s FROM public.notification_settings WHERE user_id = p_user_id;
  END IF;

  CASE p_type
    WHEN 'new_follower' THEN RETURN s.notify_new_follower;
    WHEN 'new_post' THEN RETURN s.notify_new_post;
    WHEN 'post_like' THEN RETURN s.notify_post_like;
    WHEN 'post_comment' THEN RETURN s.notify_post_comment;
    WHEN 'room_created' THEN RETURN s.notify_room_created;
    WHEN 'room_message' THEN RETURN s.notify_room_message;
    WHEN 'question_reply' THEN RETURN s.notify_question_reply;
    WHEN 'streak_unlocked' THEN RETURN s.notify_streak_unlocked;
    WHEN 'dm_message' THEN RETURN s.notify_dm_message;
    ELSE RETURN TRUE;
  END CASE;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_user(
  p_user_id UUID,
  p_type TEXT,
  p_title TEXT,
  p_body TEXT,
  p_data JSONB
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_token TEXT;
  v_base_url TEXT := 'https://mnfbdrdmqromgfnqetzh.supabase.co';
  v_anon_key TEXT := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1uZmJkcmRtcXJvbWdmbnFldHpoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzA3OTczOTIsImV4cCI6MjA4NjM3MzM5Mn0.roYKRHpKi9JrG_2LgGIztRMx_1fZF_0emcyRUd7F7Yg';
  v_payload JSONB;
  v_data JSONB;
  v_data_only BOOLEAN := FALSE;
BEGIN
  IF NOT public.can_notify(p_user_id, p_type) THEN
    RETURN;
  END IF;

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
      'authorization', 'Bearer ' || v_anon_key
    ),
    body := v_payload
  );
END;
$$;

-- Post like notification (anonymous safe)
CREATE OR REPLACE FUNCTION public.notify_post_like()
RETURNS TRIGGER AS $$
DECLARE
  v_owner_id UUID;
  v_owner_token TEXT;
  v_name TEXT;
  v_is_anonymous BOOLEAN;
BEGIN
  SELECT user_id, is_anonymous INTO v_owner_id, v_is_anonymous
  FROM public.posts WHERE id = NEW.post_id;

  IF v_owner_id = NEW.user_id THEN
    RETURN NEW;
  END IF;

  IF v_is_anonymous THEN
    v_name := 'Someone';
  ELSE
    SELECT COALESCE(display_name, alias) INTO v_name
    FROM public.users WHERE id = NEW.user_id;
  END IF;

  PERFORM public.notify_user(
    v_owner_id,
    'post_like',
    'New like',
    v_name || ' liked your post',
    jsonb_build_object('type', 'post_like', 'postId', NEW.post_id)
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_notify_post_like ON public.likes;
CREATE TRIGGER trg_notify_post_like
  AFTER INSERT ON public.likes
  FOR EACH ROW EXECUTE FUNCTION public.notify_post_like();

-- Post comment notification (anonymous safe)
CREATE OR REPLACE FUNCTION public.notify_post_comment()
RETURNS TRIGGER AS $$
DECLARE
  v_owner_id UUID;
  v_name TEXT;
  v_is_anonymous BOOLEAN;
BEGIN
  SELECT user_id, is_anonymous INTO v_owner_id, v_is_anonymous
  FROM public.posts WHERE id = NEW.post_id;

  IF v_owner_id = NEW.user_id THEN
    RETURN NEW;
  END IF;

  IF v_is_anonymous THEN
    v_name := 'Someone';
  ELSE
    SELECT COALESCE(display_name, alias) INTO v_name
    FROM public.users WHERE id = NEW.user_id;
  END IF;

  PERFORM public.notify_user(
    v_owner_id,
    'post_comment',
    'New comment',
    v_name || ' commented on your post',
    jsonb_build_object('type', 'post_comment', 'postId', NEW.post_id)
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_notify_post_comment ON public.comments;
CREATE TRIGGER trg_notify_post_comment
  AFTER INSERT ON public.comments
  FOR EACH ROW EXECUTE FUNCTION public.notify_post_comment();

-- DM message notification (notify other participants)
CREATE OR REPLACE FUNCTION public.notify_dm_message()
RETURNS TRIGGER AS $$
DECLARE
  v_participant RECORD;
  v_sender_name TEXT;
  v_preview TEXT;
  v_title TEXT;
  v_body TEXT;
BEGIN
  SELECT COALESCE(display_name, alias) INTO v_sender_name
  FROM public.users WHERE id = NEW.sender_id;

  v_preview := LEFT(COALESCE(NEW.content, ''), 120);
  v_title := 'New message';
  v_body := COALESCE(v_sender_name, 'Someone') || ': ' || v_preview;

  FOR v_participant IN
    SELECT user_id FROM public.conversation_participants
    WHERE conversation_id = NEW.conversation_id
      AND user_id <> NEW.sender_id
  LOOP
    PERFORM public.notify_user(
      v_participant.user_id,
      'dm_message',
      v_title,
      v_body,
      jsonb_build_object(
        'type',
        'dm',
        'conversationId',
        NEW.conversation_id,
        'senderId',
        NEW.sender_id,
        'title',
        v_title,
        'body',
        v_body,
        'data_only',
        true
      )
    );
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_notify_dm_message ON public.messages;
CREATE TRIGGER trg_notify_dm_message
  AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.notify_dm_message();

-- Room message notification (notify creator)
CREATE OR REPLACE FUNCTION public.notify_room_message()
RETURNS TRIGGER AS $$
DECLARE
  v_creator UUID;
BEGIN
  SELECT creator_id INTO v_creator FROM public.confession_rooms
  WHERE id = NEW.room_id;

  IF v_creator IS NOT NULL THEN
    PERFORM public.notify_user(
      v_creator,
      'room_message',
      'New room message',
      'New message in your confession room',
      jsonb_build_object('type', 'room_message', 'roomId', NEW.room_id)
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_notify_room_message ON public.room_messages;
CREATE TRIGGER trg_notify_room_message
  AFTER INSERT ON public.room_messages
  FOR EACH ROW EXECUTE FUNCTION public.notify_room_message();
