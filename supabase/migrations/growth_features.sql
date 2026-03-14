-- Growth features: onboarding checklist, achievements, daily challenges

CREATE TABLE IF NOT EXISTS public.user_onboarding (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  completed_profile BOOLEAN DEFAULT FALSE,
  first_post BOOLEAN DEFAULT FALSE,
  first_follow BOOLEAN DEFAULT FALSE,
  first_dm BOOLEAN DEFAULT FALSE,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.user_onboarding ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_onboarding_select" ON public.user_onboarding;
CREATE POLICY "user_onboarding_select"
  ON public.user_onboarding FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_onboarding_insert" ON public.user_onboarding;
CREATE POLICY "user_onboarding_insert"
  ON public.user_onboarding FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_onboarding_update" ON public.user_onboarding;
CREATE POLICY "user_onboarding_update"
  ON public.user_onboarding FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.achievements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT UNIQUE NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  icon TEXT DEFAULT '🏆',
  is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS public.user_achievements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  achievement_id UUID NOT NULL REFERENCES public.achievements(id) ON DELETE CASCADE,
  unlocked_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_achievements
  ON public.user_achievements(user_id, achievement_id);

ALTER TABLE public.achievements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_achievements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "achievements_select" ON public.achievements;
CREATE POLICY "achievements_select"
  ON public.achievements FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "user_achievements_select" ON public.user_achievements;
CREATE POLICY "user_achievements_select"
  ON public.user_achievements FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_achievements_insert" ON public.user_achievements;
CREATE POLICY "user_achievements_insert"
  ON public.user_achievements FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE TABLE IF NOT EXISTS public.daily_challenges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  points INTEGER DEFAULT 10,
  is_active BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS public.user_daily_challenges (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  challenge_id UUID NOT NULL REFERENCES public.daily_challenges(id) ON DELETE CASCADE,
  challenge_date DATE NOT NULL DEFAULT CURRENT_DATE,
  completed_at TIMESTAMPTZ
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_daily_challenges
  ON public.user_daily_challenges(user_id, challenge_id, challenge_date);

ALTER TABLE public.daily_challenges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_daily_challenges ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "daily_challenges_select" ON public.daily_challenges;
CREATE POLICY "daily_challenges_select"
  ON public.daily_challenges FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "user_daily_challenges_select" ON public.user_daily_challenges;
CREATE POLICY "user_daily_challenges_select"
  ON public.user_daily_challenges FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_daily_challenges_insert" ON public.user_daily_challenges;
CREATE POLICY "user_daily_challenges_insert"
  ON public.user_daily_challenges FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "user_daily_challenges_update" ON public.user_daily_challenges;
CREATE POLICY "user_daily_challenges_update"
  ON public.user_daily_challenges FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
