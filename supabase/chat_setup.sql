-- ══════════════════════════════════════════════════════════════════════════
--  ANONPRO — Chat / Messaging System SQL Setup
--  Run this entire script in your Supabase SQL Editor (one shot).
--  Safe to re-run: every object uses CREATE … IF NOT EXISTS or
--  CREATE OR REPLACE so nothing will break if tables already exist.
-- ══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- 1.  CONVERSATIONS TABLE
--     One row per chat thread (DM or group).
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.conversations (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name            TEXT        NOT NULL,
  is_group        BOOLEAN     NOT NULL DEFAULT FALSE,
  created_by      UUID        REFERENCES public.users(id) ON DELETE SET NULL,
  group_image_url TEXT,
  is_locked       BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Auto-update updated_at on any row change
CREATE OR REPLACE FUNCTION public.set_conversations_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_conversations_updated_at ON public.conversations;
CREATE TRIGGER trg_conversations_updated_at
  BEFORE UPDATE ON public.conversations
  FOR EACH ROW EXECUTE FUNCTION public.set_conversations_updated_at();


-- ─────────────────────────────────────────────────────────────────────────
-- 2.  CONVERSATION_PARTICIPANTS TABLE
--     Maps which users belong to which conversation.
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.conversation_participants (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id   UUID        NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id           UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role              TEXT        NOT NULL DEFAULT 'member',  -- 'admin' | 'member'
  joined_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_read_at      TIMESTAMPTZ,
  UNIQUE (conversation_id, user_id)
);

CREATE INDEX IF NOT EXISTS cp_conversation_id_idx ON public.conversation_participants (conversation_id);
CREATE INDEX IF NOT EXISTS cp_user_id_idx          ON public.conversation_participants (user_id);


-- ─────────────────────────────────────────────────────────────────────────
-- 3.  MESSAGES TABLE
--     All chat messages live here.
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.messages (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id  UUID        NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  sender_id        UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  content          TEXT        NOT NULL DEFAULT '',
  message_type     TEXT        NOT NULL DEFAULT 'text',   -- 'text' | 'image' | 'system'
  reply_to_id      UUID        REFERENCES public.messages(id) ON DELETE SET NULL,
  mentions         TEXT[]      DEFAULT '{}',
  is_deleted       BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS messages_conversation_id_idx ON public.messages (conversation_id);
CREATE INDEX IF NOT EXISTS messages_sender_id_idx       ON public.messages (sender_id);
CREATE INDEX IF NOT EXISTS messages_created_at_idx      ON public.messages (created_at DESC);

-- Bump conversations.updated_at whenever a new message is inserted
CREATE OR REPLACE FUNCTION public.update_conversation_on_message()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.conversations
    SET updated_at = NOW()
    WHERE id = NEW.conversation_id;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_message_updates_conversation ON public.messages;
CREATE TRIGGER trg_message_updates_conversation
  AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION public.update_conversation_on_message();


-- ─────────────────────────────────────────────────────────────────────────
-- 4.  MESSAGE_REACTIONS TABLE
--     Emoji reactions on individual messages.
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.message_reactions (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id  UUID        NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id     UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reaction    TEXT        NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (message_id, user_id, reaction)
);

CREATE INDEX IF NOT EXISTS reactions_message_id_idx ON public.message_reactions (message_id);


-- ─────────────────────────────────────────────────────────────────────────
-- 5.  COMPATIBILITY VIEW  ← THIS FIXES THE "relation chats does not exist" ERROR
--     Some old triggers / functions may reference "chats".
--     This view makes "chats" an alias for "conversations".
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW public.chats AS
  SELECT * FROM public.conversations;


-- ─────────────────────────────────────────────────────────────────────────
-- 6.  RLS POLICIES
-- ─────────────────────────────────────────────────────────────────────────

-- ── conversations ──
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "conversations_select" ON public.conversations;
CREATE POLICY "conversations_select" ON public.conversations
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.conversation_participants cp
      WHERE cp.conversation_id = id
        AND cp.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "conversations_insert" ON public.conversations;
CREATE POLICY "conversations_insert" ON public.conversations
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "conversations_update" ON public.conversations;
CREATE POLICY "conversations_update" ON public.conversations
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.conversation_participants cp
      WHERE cp.conversation_id = id
        AND cp.user_id = auth.uid()
        AND cp.role = 'admin'
    )
  );

DROP POLICY IF EXISTS "conversations_delete" ON public.conversations;
CREATE POLICY "conversations_delete" ON public.conversations
  FOR DELETE USING (created_by = auth.uid());


-- ── conversation_participants ──
-- Function to check if user is participant (bypasses RLS recursion)
CREATE OR REPLACE FUNCTION public.is_conversation_participant(conv_id UUID, usr_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.conversation_participants
    WHERE conversation_id = conv_id AND user_id = usr_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_conversation_participant(UUID, UUID) TO authenticated;

ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cp_select" ON public.conversation_participants;
CREATE POLICY "cp_select" ON public.conversation_participants
  FOR SELECT USING (
    user_id = auth.uid()
    OR public.is_conversation_participant(conversation_id, auth.uid())
  );

DROP POLICY IF EXISTS "cp_insert" ON public.conversation_participants;
CREATE POLICY "cp_insert" ON public.conversation_participants
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "cp_update" ON public.conversation_participants;
CREATE POLICY "cp_update" ON public.conversation_participants
  FOR UPDATE USING (user_id = auth.uid());

DROP POLICY IF EXISTS "cp_delete" ON public.conversation_participants;
CREATE POLICY "cp_delete" ON public.conversation_participants
  FOR DELETE USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.conversation_participants cp_admin
      WHERE cp_admin.conversation_id = conversation_id
        AND cp_admin.user_id = auth.uid()
        AND cp_admin.role = 'admin'
    )
  );


-- ── messages ──
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "messages_select" ON public.messages;
CREATE POLICY "messages_select" ON public.messages
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.conversation_participants cp
      WHERE cp.conversation_id = conversation_id
        AND cp.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "messages_insert" ON public.messages;
CREATE POLICY "messages_insert" ON public.messages
  FOR INSERT WITH CHECK (
    sender_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.conversation_participants cp
      WHERE cp.conversation_id = conversation_id
        AND cp.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "messages_delete" ON public.messages;
CREATE POLICY "messages_delete" ON public.messages
  FOR DELETE USING (sender_id = auth.uid());


-- ── message_reactions ──
ALTER TABLE public.message_reactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "reactions_select" ON public.message_reactions;
CREATE POLICY "reactions_select" ON public.message_reactions
  FOR SELECT USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "reactions_insert" ON public.message_reactions;
CREATE POLICY "reactions_insert" ON public.message_reactions
  FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "reactions_delete" ON public.message_reactions;
CREATE POLICY "reactions_delete" ON public.message_reactions
  FOR DELETE USING (user_id = auth.uid());


-- ─────────────────────────────────────────────────────────────────────────
-- 7.  get_user_conversations_optimized  RPC
--     Called from InboxScreen to fetch the conversation list with metadata.
--     Recreating it here ensures it references "conversations" correctly.
-- ─────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.get_user_conversations_optimized(UUID);
CREATE OR REPLACE FUNCTION public.get_user_conversations_optimized(user_uuid UUID)
RETURNS TABLE (
  conversation_id          UUID,
  conversation_name        TEXT,
  is_group                 BOOLEAN,
  last_message_content     TEXT,
  last_message_time        TIMESTAMPTZ,
  unread_count             BIGINT,
  other_user_id            UUID,
  other_user_alias         TEXT,
  other_user_display_name  TEXT,
  other_user_profile_image_url TEXT,
  participant_ids          UUID[],
  created_at               TIMESTAMPTZ,
  updated_at               TIMESTAMPTZ,
  group_image_url          TEXT,
  is_locked                BOOLEAN,
  current_user_role        TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH my_convos AS (
    -- All conversations the requesting user participates in
    SELECT
      cp.conversation_id,
      cp.last_read_at,
      cp.role AS current_user_role
    FROM public.conversation_participants cp
    WHERE cp.user_id = user_uuid
  ),
  last_msgs AS (
    -- Most recent message per conversation
    SELECT DISTINCT ON (m.conversation_id)
      m.conversation_id,
      m.content        AS last_message_content,
      m.created_at     AS last_message_time
    FROM public.messages m
    WHERE m.conversation_id IN (SELECT mc.conversation_id FROM my_convos mc)
    ORDER BY m.conversation_id, m.created_at DESC
  ),
  unread AS (
    -- Count of messages after the user's last_read_at
    SELECT
      m.conversation_id,
      COUNT(*)::BIGINT AS unread_count
    FROM public.messages m
    JOIN my_convos mc ON mc.conversation_id = m.conversation_id
    WHERE (mc.last_read_at IS NULL OR m.created_at > mc.last_read_at)
      AND m.sender_id <> user_uuid
    GROUP BY m.conversation_id
  ),
  participants AS (
    -- Aggregate participant UUIDs and pick the "other" user for DMs
    SELECT
      cp2.conversation_id,
      ARRAY_AGG(cp2.user_id)               AS participant_ids,
      -- The other participant's id (NULL for groups)
      MIN(CASE WHEN cp2.user_id <> user_uuid THEN cp2.user_id END) AS other_user_id
    FROM public.conversation_participants cp2
    GROUP BY cp2.conversation_id
  ),
  other_user_info AS (
    SELECT
      p.conversation_id,
      u.id             AS other_user_id,
      u.alias          AS other_user_alias,
      u.display_name   AS other_user_display_name,
      u.profile_image_url AS other_user_profile_image_url
    FROM participants p
    JOIN public.users u ON u.id = p.other_user_id
  )
  SELECT
    c.id                                        AS conversation_id,
    c.name                                      AS conversation_name,
    c.is_group,
    lm.last_message_content,
    lm.last_message_time,
    COALESCE(ur.unread_count, 0)                AS unread_count,
    oui.other_user_id,
    oui.other_user_alias,
    oui.other_user_display_name,
    oui.other_user_profile_image_url,
    p.participant_ids,
    c.created_at,
    c.updated_at,
    c.group_image_url,
    c.is_locked,
    mc.current_user_role
  FROM my_convos mc
  JOIN public.conversations c   ON c.id  = mc.conversation_id
  LEFT JOIN last_msgs lm        ON lm.conversation_id = c.id
  LEFT JOIN unread ur           ON ur.conversation_id = c.id
  LEFT JOIN participants p      ON p.conversation_id  = c.id
  LEFT JOIN other_user_info oui ON oui.conversation_id = c.id
  ORDER BY COALESCE(lm.last_message_time, c.created_at) DESC;
END;
$$;

-- Grant execution to authenticated users
GRANT EXECUTE ON FUNCTION public.get_user_conversations_optimized(UUID)
  TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 8.  BLOCKED_USERS & USER_REPORTS tables (used by conversation_screen.dart)
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.blocked_users (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  blocker_id  UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  blocked_id  UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (blocker_id, blocked_id)
);

ALTER TABLE public.blocked_users ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "blocked_users_select" ON public.blocked_users;
CREATE POLICY "blocked_users_select" ON public.blocked_users
  FOR SELECT USING (blocker_id = auth.uid());

DROP POLICY IF EXISTS "blocked_users_insert" ON public.blocked_users;
CREATE POLICY "blocked_users_insert" ON public.blocked_users
  FOR INSERT WITH CHECK (blocker_id = auth.uid());

DROP POLICY IF EXISTS "blocked_users_delete" ON public.blocked_users;
CREATE POLICY "blocked_users_delete" ON public.blocked_users
  FOR DELETE USING (blocker_id = auth.uid());


CREATE TABLE IF NOT EXISTS public.user_reports (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id  UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reported_id  UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reason       TEXT        NOT NULL,
  description  TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.user_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_reports_insert" ON public.user_reports;
CREATE POLICY "user_reports_insert" ON public.user_reports
  FOR INSERT WITH CHECK (reporter_id = auth.uid());


-- ─────────────────────────────────────────────────────────────────────────
-- 9.  VERIFY  (shows table row counts so you can confirm setup worked)
-- ─────────────────────────────────────────────────────────────────────────
SELECT 'conversations'            AS tbl, COUNT(*) FROM public.conversations
UNION ALL
SELECT 'conversation_participants',        COUNT(*) FROM public.conversation_participants
UNION ALL
SELECT 'messages',                         COUNT(*) FROM public.messages
UNION ALL
SELECT 'message_reactions',                COUNT(*) FROM public.message_reactions
UNION ALL
SELECT 'blocked_users',                    COUNT(*) FROM public.blocked_users
UNION ALL
SELECT 'user_reports',                     COUNT(*) FROM public.user_reports;
