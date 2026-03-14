-- Scheduling support for confession rooms

ALTER TABLE public.confession_rooms
  ADD COLUMN IF NOT EXISTS scheduled_start_at TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_confession_rooms_scheduled_start
  ON public.confession_rooms(scheduled_start_at);
