-- SQL Migration: Admin Passcode Management
-- Version: 1.0
-- Created: March 14, 2026

-- Create admin_passcode table to store and manage admin terminal passcode
CREATE TABLE IF NOT EXISTS admin_passcode (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  passcode TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT now(),
  updated_at TIMESTAMP DEFAULT now(),
  updated_by uuid REFERENCES auth.users(id),
  changed_count INTEGER DEFAULT 0,
  last_changed_by TEXT,
  last_changed_at TIMESTAMP
);

-- Enable RLS (Row Level Security)
ALTER TABLE admin_passcode ENABLE ROW LEVEL SECURITY;

-- Policy: Only admins can view
CREATE POLICY "Only admins can view admin passcode"
ON admin_passcode FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM auth.users
    WHERE auth.users.id = auth.uid()
    AND auth.users.raw_user_meta_data->>'role' = 'admin'
  )
);

-- Policy: Only admins can update
CREATE POLICY "Only admins can update admin passcode"
ON admin_passcode FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM auth.users
    WHERE auth.users.id = auth.uid()
    AND auth.users.raw_user_meta_data->>'role' = 'admin'
  )
);

-- Insert initial passcode (190308)
INSERT INTO admin_passcode (passcode, changed_count, last_changed_by)
VALUES ('190308', 0, 'system_init')
ON CONFLICT DO NOTHING;

-- Create audit log for passcode changes
CREATE TABLE IF NOT EXISTS admin_passcode_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  changed_by TEXT NOT NULL,
  old_passcode TEXT NOT NULL,
  new_passcode TEXT NOT NULL,
  changed_at TIMESTAMP DEFAULT now(),
  reason TEXT
);

-- Enable RLS on audit
ALTER TABLE admin_passcode_audit ENABLE ROW LEVEL SECURITY;

-- Policy: Only admins can view audit log
CREATE POLICY "Only admins can view passcode audit"
ON admin_passcode_audit FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM auth.users
    WHERE auth.users.id = auth.uid()
    AND auth.users.raw_user_meta_data->>'role' = 'admin'
  )
);
