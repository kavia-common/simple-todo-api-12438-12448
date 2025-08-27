#!/bin/bash
set -euo pipefail

# Minimal PostgreSQL startup script with robust recovery from stale locks
# Allow overrides via environment variables; defaults chosen to align with container expectations
DB_NAME="${DB_NAME:-myapp}"
DB_USER="${DB_USER:-appuser}"
DB_PASSWORD="${DB_PASSWORD:-dbuser123}"
DB_PORT="${DB_PORT:-5001}"
DATA_DIR="${PGDATA:-/var/lib/postgresql/data}"

echo "Starting PostgreSQL setup on port ${DB_PORT}..."
echo "Data directory: ${DATA_DIR}"

# Find PostgreSQL version and set paths
PG_VERSION=$(ls /usr/lib/postgresql/ | head -1)
PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"
PG_CTL="${PG_BIN}/pg_ctl"

echo "Found PostgreSQL version: ${PG_VERSION}"
echo "Using binaries from: ${PG_BIN}"

diagnostics() {
  echo "=== Diagnostics ==="
  echo "- Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "- Data dir exists? $( [ -d "${DATA_DIR}" ] && echo yes || echo no )"
  echo "- PG_VERSION file? $( [ -f "${DATA_DIR}/PG_VERSION" ] && echo yes || echo no )"
  echo "- postmaster.pid exists? $( [ -f "${DATA_DIR}/postmaster.pid" ] && echo yes || echo no )"
  if [ -f "${DATA_DIR}/postmaster.pid" ]; then
    echo "--- postmaster.pid contents ---"
    head -n 6 "${DATA_DIR}/postmaster.pid" || true
    echo "-------------------------------"
  fi
  echo "- Listeners on ${DB_PORT}:"
  ss -ltnp 2>/dev/null | grep ":${DB_PORT}" || echo "none"
  echo "===================="
}

# Check if PostgreSQL is already running on the specified port
if sudo -u postgres ${PG_BIN}/pg_isready -p "${DB_PORT}" > /dev/null 2>&1; then
  echo "PostgreSQL is already running on port ${DB_PORT}!"
  echo "Database: ${DB_NAME}"
  echo "User: ${DB_USER}"
  echo "Port: ${DB_PORT}"
  echo ""
  echo "To connect to the database, use:"
  echo "psql -h localhost -U ${DB_USER} -d ${DB_NAME} -p ${DB_PORT}"
  if [ -f "db_connection.txt" ]; then
    echo "Or use: $(cat db_connection.txt)"
  fi
  echo ""
  echo "Script stopped - server already running."
  exit 0
fi

# If pg_isready fails, try to detect a running postgres process for this data dir
if pgrep -f "postgres .* -D ${DATA_DIR}" >/dev/null 2>&1; then
  echo "Detected a postgres process using data dir ${DATA_DIR}."
  echo "Attempting a quick connectivity check on port ${DB_PORT}..."
  if sudo -u postgres ${PG_BIN}/psql -p "${DB_PORT}" -d "${DB_NAME}" -c '\q' 2>/dev/null; then
    echo "Database ${DB_NAME} is accessible. Exiting."
    exit 0
  fi
fi

# Initialize PostgreSQL data directory if it doesn't exist
if [ ! -f "${DATA_DIR}/PG_VERSION" ]; then
  echo "Initializing PostgreSQL data directory at ${DATA_DIR}..."
  sudo -u postgres ${PG_BIN}/initdb -D "${DATA_DIR}"
fi

# Handle stale postmaster.pid (unclean shutdown)
if [ -f "${DATA_DIR}/postmaster.pid" ]; then
  echo "Detected ${DATA_DIR}/postmaster.pid. Checking if it is stale..."
  PID_IN_FILE="$(head -n1 "${DATA_DIR}/postmaster.pid" || echo "")"
  if [ -n "${PID_IN_FILE}" ] && ps -p "${PID_IN_FILE}" > /dev/null 2>&1; then
    echo "A process with PID ${PID_IN_FILE} is running. It may be a live postgres."
    echo "Refusing to remove lock. Please ensure no other postgres is using ${DATA_DIR}."
    diagnostics
    # Try a graceful stop on the data directory if owned by postgres
    echo "Attempting 'pg_ctl stop -m fast' on ${DATA_DIR}..."
    if sudo -u postgres "${PG_CTL}" -D "${DATA_DIR}" status >/dev/null 2>&1; then
      sudo -u postgres "${PG_CTL}" -D "${DATA_DIR}" stop -m fast || true
      sleep 2
    fi
    if sudo -u postgres ${PG_BIN}/pg_isready -p "${DB_PORT}" > /dev/null 2>&1; then
      echo "Postgres still appears to be running. Exiting safely."
      exit 0
    fi
  else
    echo "postmaster.pid appears stale (no active PID). Cleaning up..."
    sudo -u postgres rm -f "${DATA_DIR}/postmaster.pid"
    # Clean up any leftover sockets for this data dir/port
    sudo -u postgres rm -f /var/run/postgresql/.s.PGSQL."${DB_PORT}" 2>/dev/null || true
    sudo -u postgres rm -f /tmp/.s.PGSQL."${DB_PORT}" 2>/dev/null || true
    # Clean orphaned shared memory segments if any (best-effort)
    # Note: modern Postgres uses POSIX shm, kernel clears on restart; no action usually required.
  fi
fi

# Start PostgreSQL server in background (using pg_ctl for better control)
echo "Starting PostgreSQL server..."
sudo -u postgres "${PG_CTL}" -D "${DATA_DIR}" -o "-p ${DB_PORT}" -l "${DATA_DIR}/startup.log" start

# Wait for PostgreSQL to start with timeout
echo "Waiting for PostgreSQL to start..."
READY=0
for i in {1..30}; do
  if sudo -u postgres ${PG_BIN}/pg_isready -p "${DB_PORT}" > /dev/null 2>&1; then
    echo "PostgreSQL is ready!"
    READY=1
    break
  fi
  if [ $i -eq 1 ]; then sleep 2; else sleep 1; fi
  echo "Waiting... ($i/30)"
done

if [ "${READY}" -ne 1 ]; then
  echo "ERROR: PostgreSQL failed to become ready on port ${DB_PORT}."
  diagnostics
  echo "Last 50 lines of server log (${DATA_DIR}/startup.log):"
  tail -n 50 "${DATA_DIR}/startup.log" 2>/dev/null || echo "(log not available)"
  echo "Troubleshooting tips:"
  echo "- Ensure the port ${DB_PORT} is free: ss -ltnp | grep :${DB_PORT}"
  echo "- Check ownership/permissions of ${DATA_DIR}"
  echo "- Remove stale ${DATA_DIR}/postmaster.pid if no postgres is running"
  exit 1
fi

# Apply schema and seed files idempotently (safe to re-run)
if [ -f "schema.sql" ]; then
  echo "Applying schema.sql..."
  sudo -u postgres ${PG_BIN}/psql -p "${DB_PORT}" -d "${DB_NAME}" -f "schema.sql" || {
    echo "Warning: Failed to apply schema.sql (continuing)"; 
  }
fi

if [ -f "seed.sql" ]; then
  echo "Applying seed.sql..."
  sudo -u postgres ${PG_BIN}/psql -p "${DB_PORT}" -d "${DB_NAME}" -f "seed.sql" || {
    echo "Warning: Failed to apply seed.sql (continuing)"; 
  }
fi

# Create database and user (after server ready)
echo "Setting up database and user..."
sudo -u postgres ${PG_BIN}/createdb -p "${DB_PORT}" "${DB_NAME}" 2>/dev/null || echo "Database might already exist"

# Set up user and permissions with proper schema ownership
sudo -u postgres ${PG_BIN}/psql -p "${DB_PORT}" -d postgres << EOF
-- Create user if doesn't exist
DO \$$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
        CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';
    END IF;
    ALTER ROLE ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
END
\$$;

-- Grant database-level permissions
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};

-- Connect to the specific database for schema-level permissions
\c ${DB_NAME}

-- For PostgreSQL 15+, handle public schema permissions
GRANT USAGE ON SCHEMA public TO ${DB_USER};
GRANT CREATE ON SCHEMA public TO ${DB_USER};

-- Default privileges for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TYPES TO ${DB_USER};

-- Also grant all on schema public to the user
GRANT ALL ON SCHEMA public TO ${DB_USER};

-- Ensure the user can work with any existing objects
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO ${DB_USER};
EOF

# Additionally, connect to the specific database to ensure permissions
sudo -u postgres ${PG_BIN}/psql -p "${DB_PORT}" -d "${DB_NAME}" << EOF
-- Double-check permissions are set correctly in the target database
GRANT ALL ON SCHEMA public TO ${DB_USER};
GRANT CREATE ON SCHEMA public TO ${DB_USER};

-- Show current permissions for debugging
\dn+ public
EOF

# Save connection command to a file
echo "psql postgresql://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}" > db_connection.txt
echo "Connection string saved to db_connection.txt"

# Save environment variables to a file
cat > db_visualizer/postgres.env << EOF
export POSTGRES_URL="postgresql://localhost:${DB_PORT}/${DB_NAME}"
export POSTGRES_USER="${DB_USER}"
export POSTGRES_PASSWORD="${DB_PASSWORD}"
export POSTGRES_DB="${DB_NAME}"
export POSTGRES_PORT="${DB_PORT}"
EOF

echo "PostgreSQL setup complete!"
echo "Database: ${DB_NAME}"
echo "User: ${DB_USER}"
echo "Port: ${DB_PORT}"
echo ""

echo "Environment variables saved to db_visualizer/postgres.env"
echo "To use with Node.js viewer, run: source db_visualizer/postgres.env"

echo "To connect to the database, use one of the following commands:"
echo "psql -h localhost -U ${DB_USER} -d ${DB_NAME} -p ${DB_PORT}"
echo "$(cat db_connection.txt)"
