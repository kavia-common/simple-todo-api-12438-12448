# Todo Database (PostgreSQL)

This container provides a minimal PostgreSQL-compatible setup for the Todo app with a single table `todos`.

Schema:
- id: INTEGER PRIMARY KEY, auto-increment
- title: TEXT NOT NULL
- description: TEXT DEFAULT '' NOT NULL
- status: TEXT NOT NULL CHECK (status IN ('pending', 'done')) DEFAULT 'pending'

Contents:
- startup.sh: Idempotent script to start PostgreSQL (on port 5000), create database/user, and apply schema.
- schema.sql: SQL to create the todos table (safe to re-run).
- seed.sql: Optional seed data (safe to re-run).
- db_visualizer/: Small Node-based DB viewer config.
- db_connection.txt: Connection helper (written by startup.sh).

Usage:
1) Run the startup script (non-interactive):
   bash startup.sh

2) Connect:
   psql postgresql://appuser:dbuser123@localhost:5000/myapp

Environment for other services:
- POSTGRES_URL="postgresql://localhost:5000/myapp"
- POSTGRES_USER="appuser"
- POSTGRES_PASSWORD="dbuser123"
- POSTGRES_DB="myapp"
- POSTGRES_PORT="5000"

Notes:
- The script tries to use system PostgreSQL binaries under /usr/lib/postgresql/<version>/bin.
- The script is idempotent and can be rerun safely.
- If PostgreSQL is already running on port 5000, it will not attempt to start another instance and will still re-ensure schema exists.

