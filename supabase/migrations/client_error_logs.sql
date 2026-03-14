-- Client-side error reporting

CREATE TABLE IF NOT EXISTS public.client_error_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  message TEXT NOT NULL,
  stack TEXT,
  context TEXT,
  platform TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.client_error_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "client_error_logs_insert" ON public.client_error_logs;
CREATE POLICY "client_error_logs_insert"
  ON public.client_error_logs FOR INSERT
  WITH CHECK (true);

DROP POLICY IF EXISTS "client_error_logs_select_admin" ON public.client_error_logs;
CREATE POLICY "client_error_logs_select_admin"
  ON public.client_error_logs FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );
