-- ============================================================
-- RK Logix — Driver Authentication & Approval Schema
-- Run this in Supabase SQL Editor (rklogix project)
-- ============================================================

-- 1. drivers table
CREATE TABLE IF NOT EXISTS public.drivers (
  id           BIGSERIAL PRIMARY KEY,
  driver_id    TEXT UNIQUE NOT NULL,        -- e.g. DRV-001 (auto-generated)
  full_name    TEXT NOT NULL,
  phone        TEXT NOT NULL,
  email        TEXT,
  password_hash TEXT NOT NULL,              -- bcrypt hash stored by Supabase function
  platform     TEXT DEFAULT 'rklogix',
  status       TEXT DEFAULT 'pending',      -- 'pending' | 'approved' | 'suspended'
  created_at   TIMESTAMPTZ DEFAULT now(),
  approved_at  TIMESTAMPTZ,
  approved_by  TEXT
);

CREATE INDEX IF NOT EXISTS idx_drivers_driver_id ON public.drivers (driver_id);
CREATE INDEX IF NOT EXISTS idx_drivers_status    ON public.drivers (status);

ALTER TABLE public.drivers ENABLE ROW LEVEL SECURITY;

-- Anyone can register (insert)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename='drivers' AND policyname='Allow driver registration'
  ) THEN
    CREATE POLICY "Allow driver registration"
      ON public.drivers FOR INSERT WITH CHECK (true);
  END IF;
END $$;

-- Drivers can read their own row (by driver_id match)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename='drivers' AND policyname='Drivers read own row'
  ) THEN
    CREATE POLICY "Drivers read own row"
      ON public.drivers FOR SELECT USING (true);
  END IF;
END $$;

-- ============================================================
-- 2. Auto-generate driver_id on insert (DRV-001, DRV-002 ...)
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_generate_driver_id()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  next_id TEXT;
  next_num INT;
BEGIN
  SELECT COUNT(*) + 1 INTO next_num FROM public.drivers;
  next_id := 'DRV-' || LPAD(next_num::TEXT, 3, '0');
  -- ensure uniqueness
  WHILE EXISTS (SELECT 1 FROM public.drivers WHERE driver_id = next_id) LOOP
    next_num := next_num + 1;
    next_id := 'DRV-' || LPAD(next_num::TEXT, 3, '0');
  END LOOP;
  NEW.driver_id := next_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_generate_driver_id ON public.drivers;
CREATE TRIGGER trg_generate_driver_id
  BEFORE INSERT ON public.drivers
  FOR EACH ROW
  WHEN (NEW.driver_id IS NULL OR NEW.driver_id = '')
  EXECUTE FUNCTION public.fn_generate_driver_id();
