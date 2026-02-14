------------------------------------------------------------
-- Schema, tables, records, privileges, indexes, etc
------------------------------------------------------------
-- When installed as an extension, we don't need to create the `pglock` schema
-- because it is automatically created by postgres due to being declared in
-- the extension control fi

CREATE SCHEMA IF NOT EXISTS pglock;

-- Serializable isolation prevents race conditions in lock/unlock operations
-- Function to set default_transaction_isolation for the current database
CREATE OR REPLACE FUNCTION pglock.set_serializable()
RETURNS void AS $$
BEGIN
    EXECUTE format('ALTER DATABASE %I SET default_transaction_isolation = %L', current_database(), 'serializable');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute privilege so roles can call set_serializable
GRANT EXECUTE ON FUNCTION pglock.set_serializable() TO PUBLIC;

CREATE TABLE IF NOT EXISTS pglock.locks (
    "id"             varchar NOT NULL,
    "resource"       varchar NOT NULL,
    "locked"         boolean NOT NULL,
    "ttl"            int NOT NULL DEFAULT 5,
    "created_at"     timestamptz NOT NULL DEFAULT now(),
    "updated_at"     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id, resource)
);

-- Index for TTL function: find expired locks (locked=true, updated_at past ttl)
CREATE INDEX IF NOT EXISTS idx_pglock_locks_expired ON pglock.locks (updated_at) WHERE locked = true;

CREATE FUNCTION pglock.lock(id varchar, resource varchar)
RETURNS boolean AS $$
DECLARE
    is_locked boolean;
BEGIN
    -- 1. Find lock by id and resource
    SELECT l.locked INTO is_locked
    FROM pglock.locks l
    WHERE l.id = $1 AND l.resource = $2;

    -- 2. If record exists
    IF FOUND THEN
        -- 2.1 If locked field is true, return false
        IF is_locked THEN
            RETURN false;
        END IF;
        -- 2.1 else: update record with locked true and updated_at now, return true
        UPDATE pglock.locks
        SET locked = true, updated_at = now()
        WHERE id = $1 AND resource = $2;
        RETURN true;
    END IF;

    -- 2.2 If record does not exist, insert lock record with locked true, return true
    INSERT INTO pglock.locks (id, resource, locked)
    VALUES ($1, $2, true);
    RETURN true;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION pglock.unlock(id varchar, resource varchar)
RETURNS boolean AS $$
DECLARE
    is_locked boolean;
BEGIN
    -- 1. Find lock by id and resource
    SELECT l.locked INTO is_locked
    FROM pglock.locks l
    WHERE l.id = $1 AND l.resource = $2;

    -- 2. If record exists
    IF FOUND THEN
        -- 2.1 If locked field is true, update record with locked false and return true
        IF is_locked THEN
            UPDATE pglock.locks
            SET locked = false, updated_at = now()
            WHERE id = $1 AND resource = $2;
        END IF;
        -- 2.1 else return true (already unlocked)
        RETURN true;
    END IF;

    -- 2.2 If record does not exist, return true
    RETURN true;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION pglock.ttl()
RETURNS boolean AS $$
DECLARE
    rec RECORD;
BEGIN
    -- 1. Search all lock records where locked is true and updated_at exceeds ttl (in minutes)
    FOR rec IN
        SELECT id, resource
        FROM pglock.locks
        WHERE locked = true
          AND updated_at < now() - (ttl * interval '1 minute')
    LOOP
        -- 2.1 Execute unlock function for each record
        PERFORM pglock.unlock(rec.id, rec.resource);
    END LOOP;

    RETURN true;
END;
$$ LANGUAGE plpgsql;

------------------------------------------------------------
-- pg_cron job (requires pg_cron extension: CREATE EXTENSION pg_cron;)
------------------------------------------------------------
-- Execute TTL function every minute to expire stale locks
SELECT cron.schedule('pglock-ttl', '* * * * *', 'SELECT pglock.ttl()');