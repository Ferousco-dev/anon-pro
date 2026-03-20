-- Password reset OTPs (email-only)

CREATE TABLE IF NOT EXISTS public.password_reset_otps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  code_hash text NOT NULL,
  expires_at timestamptz NOT NULL,
  used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS password_reset_otps_user_id_idx
  ON public.password_reset_otps (user_id);

CREATE INDEX IF NOT EXISTS password_reset_otps_expires_at_idx
  ON public.password_reset_otps (expires_at);

ALTER TABLE public.password_reset_otps ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "password_reset_otps_service_role_all" ON public.password_reset_otps;
CREATE POLICY "password_reset_otps_service_role_all"
  ON public.password_reset_otps
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');
