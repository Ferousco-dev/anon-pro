-- Group join requests + pinned messages

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS is_private BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS pinned_message TEXT,
  ADD COLUMN IF NOT EXISTS pinned_by UUID REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS pinned_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS public.group_join_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_group_join_requests
  ON public.group_join_requests(conversation_id, user_id);

CREATE INDEX IF NOT EXISTS idx_group_join_requests_convo
  ON public.group_join_requests(conversation_id);

ALTER TABLE public.group_join_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "group_join_requests_insert" ON public.group_join_requests;
CREATE POLICY "group_join_requests_insert"
  ON public.group_join_requests FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "group_join_requests_select_own" ON public.group_join_requests;
CREATE POLICY "group_join_requests_select_own"
  ON public.group_join_requests FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "group_join_requests_select_admin" ON public.group_join_requests;
CREATE POLICY "group_join_requests_select_admin"
  ON public.group_join_requests FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.conversation_participants p
      WHERE p.conversation_id = conversation_id
        AND p.user_id = auth.uid()
        AND p.role = 'admin'
    )
  );

DROP POLICY IF EXISTS "group_join_requests_update_admin" ON public.group_join_requests;
CREATE POLICY "group_join_requests_update_admin"
  ON public.group_join_requests FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.conversation_participants p
      WHERE p.conversation_id = conversation_id
        AND p.user_id = auth.uid()
        AND p.role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.conversation_participants p
      WHERE p.conversation_id = conversation_id
        AND p.user_id = auth.uid()
        AND p.role = 'admin'
    )
  );
