-- App settings table for the App Settings screen
CREATE TABLE IF NOT EXISTS app_settings (
  id INT PRIMARY KEY DEFAULT 1,
  maintenance_mode BOOLEAN DEFAULT FALSE,
  registration_enabled BOOLEAN DEFAULT TRUE,
  posting_enabled BOOLEAN DEFAULT TRUE,
  streak_required_posts INTEGER DEFAULT 12,
  streak_required_engaged_posts INTEGER DEFAULT 5,
  streak_required_total_engagement INTEGER DEFAULT 0,
  streak_required_avg_likes DOUBLE PRECISION DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert default row
INSERT INTO app_settings (id) VALUES (1) ON CONFLICT DO NOTHING;
