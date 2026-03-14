-- User activity tracking + admin analytics RPC

CREATE TABLE IF NOT EXISTS public.user_activity (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS user_activity_last_seen_idx
  ON public.user_activity (last_seen_at DESC);

ALTER TABLE public.user_activity ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_activity_select_admin" ON public.user_activity;
CREATE POLICY "user_activity_select_admin"
  ON public.user_activity FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

DROP POLICY IF EXISTS "user_activity_insert_own" ON public.user_activity;
CREATE POLICY "user_activity_insert_own"
  ON public.user_activity FOR INSERT
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "user_activity_update_own" ON public.user_activity;
CREATE POLICY "user_activity_update_own"
  ON public.user_activity FOR UPDATE
  USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.admin_user_stats()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  is_admin BOOLEAN;
  daily_new JSONB;
  weekly_active JSONB;
  monthly_totals JSONB;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'
  ) INTO is_admin;

  IF NOT is_admin THEN
    RAISE EXCEPTION 'not authorized';
  END IF;

  SELECT jsonb_agg(row_to_json(t) ORDER BY t.day)
  INTO daily_new
  FROM (
    SELECT d::date AS day,
           COUNT(u.id)::int AS count
    FROM generate_series(
      date_trunc('day', NOW()) - INTERVAL '13 days',
      date_trunc('day', NOW()),
      INTERVAL '1 day'
    ) d
    LEFT JOIN public.users u
      ON u.created_at >= d AND u.created_at < d + INTERVAL '1 day'
    GROUP BY d
    ORDER BY d
  ) t;

  SELECT jsonb_agg(row_to_json(t) ORDER BY t.week_start)
  INTO weekly_active
  FROM (
    SELECT w::date AS week_start,
           COUNT(DISTINCT ua.user_id)::int AS count
    FROM generate_series(
      date_trunc('week', NOW()) - INTERVAL '6 weeks',
      date_trunc('week', NOW()),
      INTERVAL '1 week'
    ) w
    LEFT JOIN public.user_activity ua
      ON ua.last_seen_at >= w AND ua.last_seen_at < w + INTERVAL '1 week'
    GROUP BY w
    ORDER BY w
  ) t;

  SELECT jsonb_agg(row_to_json(t) ORDER BY t.month_start)
  INTO monthly_totals
  FROM (
    SELECT m::date AS month_start,
           COUNT(u.id)::int AS count
    FROM generate_series(
      date_trunc('month', NOW()) - INTERVAL '5 months',
      date_trunc('month', NOW()),
      INTERVAL '1 month'
    ) m
    LEFT JOIN public.users u
      ON u.created_at >= m AND u.created_at < m + INTERVAL '1 month'
    GROUP BY m
    ORDER BY m
  ) t;

  RETURN jsonb_build_object(
    'active_24h', (SELECT COUNT(*)::int FROM public.user_activity WHERE last_seen_at >= NOW() - INTERVAL '24 hours'),
    'active_7d', (SELECT COUNT(*)::int FROM public.user_activity WHERE last_seen_at >= NOW() - INTERVAL '7 days'),
    'dormant_30d', (
      SELECT COUNT(*)::int
      FROM public.users u
      LEFT JOIN public.user_activity ua ON ua.user_id = u.id
      WHERE ua.last_seen_at IS NULL OR ua.last_seen_at < NOW() - INTERVAL '30 days'
    ),
    'total_users', (SELECT COUNT(*)::int FROM public.users),
    'daily_new_users', COALESCE(daily_new, '[]'::jsonb),
    'weekly_active_users', COALESCE(weekly_active, '[]'::jsonb),
    'monthly_total_users', COALESCE(monthly_totals, '[]'::jsonb)
  );
END;
$$;
