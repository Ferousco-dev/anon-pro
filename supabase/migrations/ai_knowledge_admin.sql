-- Admin-managed AI knowledge entries (remote, lightweight)

CREATE TABLE IF NOT EXISTS public.ai_knowledge_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  topic TEXT NOT NULL,
  content TEXT NOT NULL,
  keywords TEXT[] DEFAULT '{}',
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID REFERENCES public.users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_ai_knowledge_entries_topic
  ON public.ai_knowledge_entries(topic);

ALTER TABLE public.ai_knowledge_entries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ai_knowledge_select_active" ON public.ai_knowledge_entries;
CREATE POLICY "ai_knowledge_select_active"
  ON public.ai_knowledge_entries FOR SELECT
  USING (
    is_active = TRUE OR EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

DROP POLICY IF EXISTS "ai_knowledge_insert_admin" ON public.ai_knowledge_entries;
CREATE POLICY "ai_knowledge_insert_admin"
  ON public.ai_knowledge_entries FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

DROP POLICY IF EXISTS "ai_knowledge_update_admin" ON public.ai_knowledge_entries;
CREATE POLICY "ai_knowledge_update_admin"
  ON public.ai_knowledge_entries FOR UPDATE
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

DROP POLICY IF EXISTS "ai_knowledge_delete_admin" ON public.ai_knowledge_entries;
CREATE POLICY "ai_knowledge_delete_admin"
  ON public.ai_knowledge_entries FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );
