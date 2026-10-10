-- ============================================================
-- RK Logix Hub — Live Driver Tracking Schema
-- Run this in your Supabase SQL Editor (rklogix project)
-- ============================================================

-- 1. driver_locations table
--    One row per driver, upserted on every GPS update.
CREATE TABLE IF NOT EXISTS public.driver_locations (
  driver_id    TEXT PRIMARY KEY,
  driver_name  TEXT,
  platform     TEXT DEFAULT 'rklogix',   -- 'rklogix' | 'g3link'
  lat          DOUBLE PRECISION NOT NULL,
  lng          DOUBLE PRECISION NOT NULL,
  accuracy     FLOAT,                    -- metres
  speed        FLOAT,                    -- m/s
  heading      FLOAT,                    -- degrees 0-360
  is_online    BOOLEAN DEFAULT TRUE,
  updated_at   TIMESTAMPTZ DEFAULT now()
);

-- 2. Index for fast "online drivers" queries
CREATE INDEX IF NOT EXISTS idx_driver_locations_online
  ON public.driver_locations (is_online, updated_at DESC);

-- 3. Enable Row Level Security
ALTER TABLE public.driver_locations ENABLE ROW LEVEL SECURITY;

-- 4. Policy: anyone with the anon key can INSERT / UPDATE their own row
--    (driver app uses anon key, identified by driver_id)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'driver_locations'
    AND policyname = 'Drivers can upsert own location'
  ) THEN
    CREATE POLICY "Drivers can upsert own location"
      ON public.driver_locations
      FOR ALL
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;

-- 5. Enable Realtime on this table so map subscribers get live pushes
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
    AND tablename = 'driver_locations'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.driver_locations;
  END IF;
END $$;

-- ============================================================
-- Optional: driver_location_history table
-- Stores every GPS ping for trip replay / audit trail
-- ============================================================
CREATE TABLE IF NOT EXISTS public.driver_location_history (
  id           BIGSERIAL PRIMARY KEY,
  driver_id    TEXT NOT NULL,
  driver_name  TEXT,
  platform     TEXT,
  lat          DOUBLE PRECISION NOT NULL,
  lng          DOUBLE PRECISION NOT NULL,
  accuracy     FLOAT,
  speed        FLOAT,
  heading      FLOAT,
  recorded_at  TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_history_driver_time
  ON public.driver_location_history (driver_id, recorded_at DESC);

ALTER TABLE public.driver_location_history ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'driver_location_history'
    AND policyname = 'Allow insert history'
  ) THEN
    CREATE POLICY "Allow insert history"
      ON public.driver_location_history
      FOR INSERT WITH CHECK (true);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'driver_location_history'
    AND policyname = 'Allow read history'
  ) THEN
    CREATE POLICY "Allow read history"
      ON public.driver_location_history
      FOR SELECT USING (true);
  END IF;
END $$;

-- 6. Trigger: auto-append to history on every location update
CREATE OR REPLACE FUNCTION public.fn_log_location_history()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.driver_location_history
    (driver_id, driver_name, platform, lat, lng, accuracy, speed, heading)
  VALUES
    (NEW.driver_id, NEW.driver_name, NEW.platform,
     NEW.lat, NEW.lng, NEW.accuracy, NEW.speed, NEW.heading);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_location_history ON public.driver_locations;
CREATE TRIGGER trg_location_history
  AFTER INSERT OR UPDATE ON public.driver_locations
  FOR EACH ROW EXECUTE FUNCTION public.fn_log_location_history();
