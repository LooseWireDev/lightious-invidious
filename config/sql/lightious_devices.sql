-- Table: public.lightious_devices

CREATE TABLE IF NOT EXISTS public.lightious_devices
(
  id text NOT NULL,
  profile_id text NOT NULL,
  bearer_digest text NOT NULL,
  label text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  last_seen_at timestamp with time zone,
  revoked_at timestamp with time zone,
  CONSTRAINT lightious_devices_pkey PRIMARY KEY (id),
  CONSTRAINT lightious_devices_bearer_digest_key UNIQUE (bearer_digest),
  CONSTRAINT lightious_devices_profile_id_fkey
    FOREIGN KEY (profile_id)
    REFERENCES public.lightious_profiles (id)
    ON DELETE CASCADE
);

GRANT ALL ON TABLE public.lightious_devices TO current_user;

CREATE INDEX IF NOT EXISTS lightious_devices_profile_id_idx
  ON public.lightious_devices (profile_id);
