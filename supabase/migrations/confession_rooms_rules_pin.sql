-- Add rules and pinned message to confession rooms

ALTER TABLE public.confession_rooms
  ADD COLUMN IF NOT EXISTS rules TEXT,
  ADD COLUMN IF NOT EXISTS pinned_message TEXT;
