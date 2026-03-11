-- Create broadcasts table for admin messages
CREATE TABLE IF NOT EXISTS public.broadcasts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  broadcast_type TEXT NOT NULL DEFAULT 'announcement', -- 'announcement', 'update', 'warning', 'event'
  emoji TEXT NOT NULL DEFAULT '📢',
  type_color TEXT NOT NULL DEFAULT '#007AFF', -- hex color code
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ, -- optional: when the broadcast expires
  
  CONSTRAINT valid_broadcast_type CHECK (broadcast_type IN ('announcement', 'update', 'warning', 'event'))
);

-- Create table to track which users have seen broadcasts
CREATE TABLE IF NOT EXISTS public.broadcast_views (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  broadcast_id UUID NOT NULL REFERENCES public.broadcasts(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  viewed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(broadcast_id, user_id)
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS broadcasts_admin_id_idx ON public.broadcasts(admin_id);
CREATE INDEX IF NOT EXISTS broadcasts_created_at_idx ON public.broadcasts(created_at DESC);
CREATE INDEX IF NOT EXISTS broadcasts_is_active_idx ON public.broadcasts(is_active);
CREATE INDEX IF NOT EXISTS broadcast_views_broadcast_id_idx ON public.broadcast_views(broadcast_id);
CREATE INDEX IF NOT EXISTS broadcast_views_user_id_idx ON public.broadcast_views(user_id);

-- Enable row-level security
ALTER TABLE public.broadcasts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.broadcast_views ENABLE ROW LEVEL SECURITY;

-- Broadcasts: only authenticated users can view active broadcasts
DROP POLICY IF EXISTS "broadcasts_select" ON public.broadcasts;
CREATE POLICY "broadcasts_select" ON public.broadcasts
  FOR SELECT USING (
    auth.role() = 'authenticated' AND is_active = TRUE
  );

-- Broadcasts: only admins can insert
DROP POLICY IF EXISTS "broadcasts_insert" ON public.broadcasts;
CREATE POLICY "broadcasts_insert" ON public.broadcasts
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Broadcasts: only admins who created it can update/delete
DROP POLICY IF EXISTS "broadcasts_update" ON public.broadcasts;
CREATE POLICY "broadcasts_update" ON public.broadcasts
  FOR UPDATE USING (
    admin_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

DROP POLICY IF EXISTS "broadcasts_delete" ON public.broadcasts;
CREATE POLICY "broadcasts_delete" ON public.broadcasts
  FOR DELETE USING (
    admin_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM public.users 
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Broadcast views: users can view their own views
DROP POLICY IF EXISTS "broadcast_views_select" ON public.broadcast_views;
CREATE POLICY "broadcast_views_select" ON public.broadcast_views
  FOR SELECT USING (user_id = auth.uid());

-- Broadcast views: users can insert their own views
DROP POLICY IF EXISTS "broadcast_views_insert" ON public.broadcast_views;
CREATE POLICY "broadcast_views_insert" ON public.broadcast_views
  FOR INSERT WITH CHECK (user_id = auth.uid());
