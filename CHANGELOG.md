# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-02-14

### Added

- `pglock.locks` table with `id`, `resource`, `locked`, `ttl`, `created_at`, and `updated_at` columns
- `pglock.lock(id, resource)` - Acquire a lock; returns `true` on success, `false` if already locked
- `pglock.unlock(id, resource)` - Release a lock; always returns `true`
- `pglock.ttl()` - Expire stale locks whose `updated_at` exceeds their TTL (in minutes)
- `pglock.set_serializable()` - Set database default transaction isolation to serializable
- Partial index `idx_pglock_locks_expired` for efficient TTL cleanup queries
- pg_cron job `pglock-ttl` to run TTL expiration every minute (requires pg_cron extension)
