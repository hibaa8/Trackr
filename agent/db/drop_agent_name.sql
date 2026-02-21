-- Remove legacy agent_name column now that agent_id is used.
ALTER TABLE users
    DROP COLUMN IF EXISTS agent_name;
