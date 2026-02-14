# pglock

A lightweight lock service for distributed systems inside PostgreSQL.

## Synopsis

```sql
-- Acquire a lock
SELECT pglock.lock('worker-1', 'resource-a');
-- Returns true if lock acquired, false if already locked

-- Release the lock
SELECT pglock.unlock('worker-1', 'resource-a');
-- Returns true

-- Set database to serializable isolation (recommended)
SELECT pglock.set_serializable();
```

## Description

pglock provides distributed locking using PostgreSQL as the backing store. It is designed for multi-instance applications that need to coordinate access to shared resources. Locks are stored in a table with configurable TTL (time-to-live) for automatic expiration of stale locks.

## Installation

### From source

```bash
make
make install
```

### Create the extension

```sql
CREATE EXTENSION pglock;
```

Requires PostgreSQL 9.1 or later and the `plpgsql` language (included by default).

## Requirements

- **PostgreSQL** 9.1 or later
- **Optional:** [pg_cron](https://github.com/citusdata/pg_cron) extension for automatic TTL expiration (locks expire every minute via a cron job)

## Usage

### Acquiring a lock

```sql
SELECT pglock.lock(id, resource);
```

- **id** — Lock identifier (e.g., worker ID, process ID)
- **resource** — Resource name to lock
- **Returns:** `true` if lock acquired, `false` if already locked by another process

### Releasing a lock

```sql
SELECT pglock.unlock(id, resource);
```

- **id** — Lock identifier
- **resource** — Resource name
- **Returns:** `true` (idempotent; safe to call even if not locked)

### Serializable isolation

For correct behavior under concurrent access, use serializable transaction isolation:

```sql
-- Option 1: Per-session (for current session only)
SELECT pglock.set_serializable();

-- Option 2: Per-transaction
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT pglock.lock('my-id', 'my-resource');
-- ... do work ...
SELECT pglock.unlock('my-id', 'my-resource');
COMMIT;
```

### TTL expiration

Locks have a configurable TTL (default 5 minutes). The `pglock.ttl()` function unlocks records where `updated_at` exceeds the TTL. If [pg_cron](https://github.com/citusdata/pg_cron) is installed, a job runs `pglock.ttl()` every minute. Otherwise, call it manually or schedule it externally:

```sql
SELECT pglock.ttl();
```

## Schema

### Table: pglock.locks

| Column     | Type        | Description                          |
|------------|-------------|--------------------------------------|
| id         | varchar     | Lock identifier                      |
| resource   | varchar     | Resource name                        |
| locked     | boolean     | Whether the lock is held             |
| ttl        | int         | TTL in minutes (default: 5)          |
| created_at | timestamptz | Creation timestamp                   |
| updated_at | timestamptz | Last update timestamp                |

Primary key: `(id, resource)`

### Functions

| Function                    | Returns | Description                              |
|----------------------------|---------|------------------------------------------|
| pglock.lock(id, resource)  | boolean | Acquire lock; false if already locked    |
| pglock.unlock(id, resource)| boolean | Release lock                             |
| pglock.ttl()               | boolean | Expire locks past their TTL              |
| pglock.set_serializable()  | void    | Set DB default isolation to serializable |

## License

PostgreSQL License

## Author

Francisco Ruiz <franciscoruizlezcano@gmail.com>

## Resources

- [Repository](https://github.com/fraruiz/pglock)
