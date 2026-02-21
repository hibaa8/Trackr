-- Add numeric agent_id to users.
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS agent_id BIGINT;

-- Default to Marcus (id=1) when missing.
UPDATE users
SET agent_id = 1
WHERE agent_id IS NULL;
