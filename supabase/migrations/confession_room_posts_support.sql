-- Migration: Add Confession Room Post Support
-- This migration adds support for confession room posts in the feed

-- Add post_type column to distinguish between regular posts and confession room posts
ALTER TABLE posts
ADD COLUMN IF NOT EXISTS post_type VARCHAR(50) DEFAULT 'regular';

-- Add related_confession_room_id column to link posts to confession rooms
ALTER TABLE posts
ADD COLUMN IF NOT EXISTS related_confession_room_id UUID REFERENCES confession_rooms(id) ON DELETE SET NULL;

-- Create index for faster queries of confession room posts
CREATE INDEX IF NOT EXISTS idx_posts_post_type ON posts(post_type);
CREATE INDEX IF NOT EXISTS idx_posts_related_confession_room ON posts(related_confession_room_id);

-- Update existing posts to have post_type = 'regular' (already set by default)
UPDATE posts SET post_type = 'regular' WHERE post_type IS NULL;
