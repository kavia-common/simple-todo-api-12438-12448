# Todo Database (PostgreSQL)

This container provides a minimal PostgreSQL-compatible setup for the Todo app with a single table `todos`.

Schema:
- id: INTEGER PRIMARY KEY, auto-increment
- title: TEXT NOT NULL
- description: TEXT DEFAULT '' NOT NULL
- status: TEXT NOT NULL CHECK (status IN ('pending', 'done')) DEFAULT 'pending'

Contents:
- startup.sh: Idempotent script to start PostgreSQL (default port 5001), create database/user, and apply schema. You can override via env vars (DB_PORT, DB_NAME, DB_USER, DB_PASSWORD).
- schema.sql: SQL to create the todos table (safe to re-run).
- seed.sql: Optional seed data (safe to re-run).
- db_visualizer/: Small Node-based DB viewer config.
- db_connection.txt: Connection helper (written by startup.sh).

Usage:
1) Run the startup script (non-interactive):
   # default is port 5001
   bash startup.sh
   # or override
   DB_PORT=5001 bash startup.sh

2) Connect:
   psql postgresql://appuser:dbuser123@localhost:5001/myapp

Environment for other services (generated into db_visualizer/postgres.env):
- POSTGRES_URL="postgresql://localhost:5001/myapp"
- POSTGRES_USER="appuser"
- POSTGRES_PASSWORD="dbuser123"
- POSTGRES_DB="myapp"
- POSTGRES_PORT="5001"

Notes:
- The script tries to use system PostgreSQL binaries under /usr/lib/postgresql/<version>/bin.
- The script is idempotent and can be rerun safely.
- If PostgreSQL is already running on the configured port, it will not attempt to start another instance and will still re-ensure schema exists.
- Recovery from unclean shutdowns is handled automatically: if a stale lock file postmaster.pid is found without an active postgres process, the script removes it and cleans up leftover socket files, then starts PostgreSQL.
- If a different live postgres is detected using the same data directory, the script attempts a fast stop via pg_ctl. If it remains running, the script exits with diagnostics rather than risking data corruption.

Manual remediation (if startup still fails):
- Check listeners: ss -ltnp | grep :5001
- Remove stale lock ONLY if no postgres is running for this data dir:
  sudo -u postgres rm -f /var/lib/postgresql/data/postmaster.pid
  sudo -u postgres rm -f /var/run/postgresql/.s.PGSQL.5001 /tmp/.s.PGSQL.5001
- Start again:
  bash startup.sh
- View last server logs:
  sudo tail -n 100 /var/lib/postgresql/data/startup.log
