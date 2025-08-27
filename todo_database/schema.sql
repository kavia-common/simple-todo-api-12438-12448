-- Public schema initialization for the Todo app
-- Safe to re-run: uses IF NOT EXISTS and checks

-- Ensure public schema exists (usually present by default)
CREATE SCHEMA IF NOT EXISTS public;

-- Create todos table
CREATE TABLE IF NOT EXISTS public.todos (
    id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'pending',
    CONSTRAINT todos_status_check CHECK (status IN ('pending', 'done'))
);

-- Helpful index on status for filtering
CREATE INDEX IF NOT EXISTS idx_todos_status ON public.todos (status);

