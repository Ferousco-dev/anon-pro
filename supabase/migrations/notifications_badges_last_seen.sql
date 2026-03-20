-- Add last_seen timestamps for inbox badge dots

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS last_activity_seen_at TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS last_dm_seen_at TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS last_group_seen_at TIMESTAMPTZ DEFAULT NOW(),
  ADD COLUMN IF NOT EXISTS last_qa_seen_at TIMESTAMPTZ DEFAULT NOW();
