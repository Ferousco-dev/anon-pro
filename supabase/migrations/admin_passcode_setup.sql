-- Admin Passcode Management (Supabase-backed)

CREATE TABLE IF NOT EXISTS public.admin_passcode (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  passcode TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now(),
  updated_by uuid REFERENCES auth.users(id),
  changed_count INTEGER DEFAULT 0,
  last_changed_by TEXT,
  last_changed_at TIMESTAMP
);

ALTER TABLE public.admin_passcode ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_passcode_select_admin" ON public.admin_passcode;
CREATE POLICY "admin_passcode_select_admin"
ON public.admin_passcode FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'
  )
);

DROP POLICY IF EXISTS "admin_passcode_update_admin" ON public.admin_passcode;
CREATE POLICY "admin_passcode_update_admin"
ON public.admin_passcode FOR UPDATE
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

-- Seed from DB setting if present (optional)
INSERT INTO public.admin_passcode (passcode, changed_count, last_changed_by)
SELECT current_setting('app.settings.admin_passcode', true), 0, 'system_init'
WHERE current_setting('app.settings.admin_passcode', true) IS NOT NULL
  AND current_setting('app.settings.admin_passcode', true) <> ''
  AND NOT EXISTS (SELECT 1 FROM public.admin_passcode)
ON CONFLICT DO NOTHING;

CREATE TABLE IF NOT EXISTS public.admin_passcode_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  changed_by TEXT NOT NULL,
  old_passcode TEXT NOT NULL,
  new_passcode TEXT NOT NULL,
  changed_at TIMESTAMP DEFAULT now(),
  reason TEXT
);

ALTER TABLE public.admin_passcode_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_passcode_audit_select_admin" ON public.admin_passcode_audit;
CREATE POLICY "admin_passcode_audit_select_admin"
ON public.admin_passcode_audit FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'
  )
);
