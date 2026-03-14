-- Story reactions + hidden stories

CREATE TABLE IF NOT EXISTS public.status_reactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  status_id UUID NOT NULL REFERENCES public.user_statuses(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  emoji TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_status_reactions_user
  ON public.status_reactions(status_id, user_id);

CREATE INDEX IF NOT EXISTS idx_status_reactions_status
  ON public.status_reactions(status_id);

ALTER TABLE public.status_reactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "status_reactions_select" ON public.status_reactions;
CREATE POLICY "status_reactions_select"
  ON public.status_reactions FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "status_reactions_insert" ON public.status_reactions;
CREATE POLICY "status_reactions_insert"
  ON public.status_reactions FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "status_reactions_update" ON public.status_reactions;
CREATE POLICY "status_reactions_update"
  ON public.status_reactions FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS public.user_hidden_statuses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status_id UUID NOT NULL REFERENCES public.user_statuses(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_hidden_statuses
  ON public.user_hidden_statuses(user_id, status_id);

CREATE INDEX IF NOT EXISTS idx_user_hidden_statuses_user
  ON public.user_hidden_statuses(user_id);

ALTER TABLE public.user_hidden_statuses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_hidden_statuses_select" ON public.user_hidden_statuses;
CREATE POLICY "user_hidden_statuses_select"
  ON public.user_hidden_statuses FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "user_hidden_statuses_insert" ON public.user_hidden_statuses;
CREATE POLICY "user_hidden_statuses_insert"
  ON public.user_hidden_statuses FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "user_hidden_statuses_delete" ON public.user_hidden_statuses;
CREATE POLICY "user_hidden_statuses_delete"
  ON public.user_hidden_statuses FOR DELETE
  USING (user_id = auth.uid());
