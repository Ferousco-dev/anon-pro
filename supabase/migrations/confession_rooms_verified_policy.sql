-- Only verified users (or admins) can create confession rooms

ALTER TABLE public.confession_rooms ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Verified can create rooms" ON public.confession_rooms;
CREATE POLICY "Verified can create rooms" ON public.confession_rooms
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid()
        AND (u.is_verified = TRUE OR u.role = 'admin')
    )
  );
