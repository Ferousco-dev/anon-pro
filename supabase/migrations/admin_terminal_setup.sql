-- Admin Terminal Setup (logs + app settings guardrails)

CREATE TABLE IF NOT EXISTS public.failed_admin_access_logs (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id     TEXT,
  entered_passkey TEXT NOT NULL,
  ip_address    TEXT,
  user_id       UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS failed_admin_access_logs_created_at_idx
  ON public.failed_admin_access_logs (created_at DESC);

CREATE INDEX IF NOT EXISTS failed_admin_access_logs_device_id_idx
  ON public.failed_admin_access_logs (device_id);

ALTER TABLE public.failed_admin_access_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "failed_access_logs_insert" ON public.failed_admin_access_logs;
CREATE POLICY "failed_access_logs_insert" ON public.failed_admin_access_logs
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "failed_access_logs_select" ON public.failed_admin_access_logs;
CREATE POLICY "failed_access_logs_select" ON public.failed_admin_access_logs
  FOR SELECT USING (
    auth.role() = 'authenticated'
    AND EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS app_shutdown BOOLEAN DEFAULT FALSE;

INSERT INTO public.app_settings (id)
  VALUES (1)
  ON CONFLICT DO NOTHING;
