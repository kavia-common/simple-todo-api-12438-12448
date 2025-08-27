-- Optional seed data; safe to re-run avoiding duplicates by title+description+status
INSERT INTO public.todos (title, description, status)
SELECT 'Sample Task 1', 'This is a pending task', 'pending'
WHERE NOT EXISTS (
  SELECT 1 FROM public.todos
  WHERE title='Sample Task 1' AND description='This is a pending task' AND status='pending'
);

INSERT INTO public.todos (title, description, status)
SELECT 'Sample Task 2', 'This one is done', 'done'
WHERE NOT EXISTS (
  SELECT 1 FROM public.todos
  WHERE title='Sample Task 2' AND description='This one is done' AND status='done'
);
