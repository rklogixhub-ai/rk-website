-- ============================================================
-- RK Logix — Admins Table
-- Run this in Supabase SQL Editor (rklogix project)
-- ============================================================

-- 1. Create admins table
CREATE TABLE IF NOT EXISTS public.admins (
  id           BIGSERIAL PRIMARY KEY,
  email        TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,       -- SHA-256 hash of password
  full_name    TEXT,
  is_active    BOOLEAN DEFAULT TRUE,
  created_at   TIMESTAMPTZ DEFAULT now(),
  last_login   TIMESTAMPTZ
);

ALTER TABLE public.admins ENABLE ROW LEVEL SECURITY;

-- Only allow SELECT (login check) via anon key — no insert/update from frontend
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename='admins' AND policyname='Allow admin login check'
  ) THEN
    CREATE POLICY "Allow admin login check"
      ON public.admins FOR SELECT USING (true);
  END IF;
END $$;

-- ============================================================
-- 2. How to add an admin manually (run this separately):
--
-- First generate the SHA-256 hash of your password.
-- You can use this site: https://emn178.github.io/online-tools/sha256.html
-- Or run in browser console:
--   const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode('yourpassword'));
--   console.log(Array.from(new Uint8Array(buf)).map(b=>b.toString(16).padStart(2,'0')).join(''));
--
-- Then insert:
-- INSERT INTO public.admins (email, password_hash, full_name)
-- VALUES ('your@email.com', 'sha256hashhere', 'Your Name');
-- ============================================================
