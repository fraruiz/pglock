------------------------------------------------------------
-- Schema, tables, records, privileges, indexes, etc
------------------------------------------------------------
-- When installed as an extension, we don't need to create the `pglock` schema
-- because it is automatically created by postgres due to being declared in
-- the extension control fi

CREATE EXTENSION IF NOT EXISTS pg_cron;

CREATE SCHEMA IF NOT EXISTS pglock;

CREATE TABLE IF NOT EXISTS pglock.services (
    "id"             uuid NOT NULL default gen_random_uuid(),
    "name"           varchar NOT NULL,
    "description"    varchar NOT NULL,
    "ttl"            int NOT NULL DEFAULT 5,
    "created_at"     timestamptz NOT NULL DEFAULT now(),
    "updated_at"     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS pglock.locks (
    "id"             uuid NOT NULL,
    "resource"       varchar NOT NULL,
    "service_id"     uuid NOT NULL,
    "locked"         boolean NOT NULL,
    "created_at"     timestamptz NOT NULL DEFAULT now(),
    "updated_at"     timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id, resource, service_id),
    CONSTRAINT fk_locks_service FOREIGN KEY (service_id) REFERENCES pglock.services(id)
);

-- Index for TTL function: find expired locks (locked=true, updated_at past ttl)
CREATE INDEX IF NOT EXISTS idx_pglock_locks_expired ON pglock.locks (updated_at) WHERE locked = true;

CREATE FUNCTION pglock.register_service(id uuid, name varchar, description varchar, ttl int)
RETURNS boolean AS $$
DECLARE
    existing_service uuid;
BEGIN
    -- Validate input parameters
    IF $2 IS NULL OR trim($2) = '' THEN
        RAISE EXCEPTION 'Service name cannot be null or empty';
    END IF;
    
    IF $4 IS NULL OR $4 <= 0 THEN
        RAISE EXCEPTION 'TTL must be a positive integer';
    END IF;
    
    -- Check if service already exists
    SELECT s.id INTO existing_service
    FROM pglock.services s
    WHERE s.id = $1;
    
    IF FOUND THEN
        RAISE EXCEPTION 'Service with ID % already exists', $1;
    END IF;
    
    -- Insert new service
    INSERT INTO pglock.services (id, name, description, ttl)
    VALUES ($1, $2, $3, $4);
    
    RETURN true;
EXCEPTION
    WHEN others THEN
        RAISE;
        RETURN false;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION pglock.lock(id uuid, resource varchar, service_id uuid)
RETURNS boolean AS $$
DECLARE
    is_locked boolean;
BEGIN
    -- 1. Find lock by id and resource
    SELECT l.locked INTO is_locked
    FROM pglock.locks l
    WHERE l.id = $1 AND l.resource = $2 AND l.service_id = $3;

    -- 2. If record exists
    IF FOUND THEN
        -- 2.1 If locked field is true, return false
        IF is_locked THEN
            RETURN false;
        END IF;
        -- 2.1 else: update record with locked true and updated_at now, return true
        UPDATE pglock.locks l
        SET locked = true, updated_at = now()
        WHERE l.id = $1 AND l.resource = $2 AND l.service_id = $3;
        RETURN true;
    END IF;

    -- 2.2 If record does not exist, insert lock record with locked true, return true
    INSERT INTO pglock.locks (id, resource, service_id, locked)
    VALUES ($1, $2, $3, true);
    RETURN true;
END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION pglock.unlock(id uuid, resource varchar, service_id uuid)
RETURNS boolean AS $$
DECLARE
    is_locked boolean;
BEGIN
    -- 1. Find lock by id and resource
    SELECT l.locked INTO is_locked
    FROM pglock.locks l
    WHERE l.id = $1 AND l.resource = $2 AND l.service_id = $3;

    -- 2. If record exists
    IF FOUND THEN
        -- 2.1 If locked field is true, update record with locked false and return true
        IF is_locked THEN
            UPDATE pglock.locks l
            SET locked = false, updated_at = now()
            WHERE l.id = $1 AND l.resource = $2 AND l.service_id = $3;
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
    -- 1. Search all lock records where locked is true and updated_at exceeds service TTL (in minutes)
    FOR rec IN
        SELECT l.id, l.resource, l.service_id
        FROM pglock.locks l
        JOIN pglock.services s ON l.service_id = s.id
        WHERE l.locked = true
          AND l.updated_at < now() - (s.ttl * interval '1 minute')
    LOOP
        -- 2.1 Execute unlock function for each record
        PERFORM pglock.unlock(rec.id, rec.resource, rec.service_id);
    END LOOP;

    RETURN true;
END;
$$ LANGUAGE plpgsql;

------------------------------------------------------------
-- pg_cron job (requires pg_cron extension: CREATE EXTENSION pg_cron;)
------------------------------------------------------------
-- Execute TTL function every minute to expire stale locks
SELECT cron.schedule('pglock-ttl', '* * * * *', 'SELECT pglock.ttl()');
