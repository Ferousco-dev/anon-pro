-- Verified profile customization fields

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS profile_theme TEXT DEFAULT 'blue',
  ADD COLUMN IF NOT EXISTS custom_emoji TEXT DEFAULT '';

-- Cover image already uses cover_image_url; ensure column exists
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS cover_image_url TEXT;
