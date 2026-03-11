-- Activity logs table for admin actions (verify, ban, delete post, etc.)
-- Run this in Supabase SQL Editor
--
-- If you get "Could not find admin_id column", the table exists with wrong schema.
-- Option A: Drop and recreate (loses existing logs):
--   DROP TABLE IF EXISTS public.activity_logs CASCADE;
-- Then run the rest of this script.
--
-- Option B: Add missing column (keeps data, if table has id/action/details/created_at):
--   ALTER TABLE public.activity_logs ADD COLUMN IF NOT EXISTS admin_id UUID REFERENCES public.users(id) ON DELETE SET NULL;
--   (Then run the index and policy parts below)
--
CREATE TABLE IF NOT EXISTS public.activity_logs (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id   UUID REFERENCES public.users(id) ON DELETE SET NULL,
  action     TEXT NOT NULL,
  details    JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS activity_logs_admin_id_idx ON public.activity_logs (admin_id);
CREATE INDEX IF NOT EXISTS activity_logs_created_at_idx ON public.activity_logs (created_at DESC);

ALTER TABLE public.activity_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "activity_logs_select" ON public.activity_logs;
CREATE POLICY "activity_logs_select" ON public.activity_logs
  FOR SELECT USING (
    auth.role() = 'authenticated'
    AND EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

DROP POLICY IF EXISTS "activity_logs_insert" ON public.activity_logs;
CREATE POLICY "activity_logs_insert" ON public.activity_logs
  FOR INSERT WITH CHECK (
    auth.uid() IS NOT NULL
    AND admin_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );
