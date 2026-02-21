-- Add media URL columns for coaches.
ALTER TABLE coaches
    ADD COLUMN IF NOT EXISTS image_url TEXT,
    ADD COLUMN IF NOT EXISTS video_url TEXT;
