-- Table: public.lightious_pairings

CREATE TABLE IF NOT EXISTS public.lightious_pairings
(
  id text NOT NULL,
  user_code_digest text NOT NULL,
  poll_secret_digest text NOT NULL,
  device_bearer_digest text NOT NULL,
  device_label text NOT NULL,
  state text NOT NULL DEFAULT 'created',
  claimed_profile_id text,
  expires_at timestamp with time zone NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  claimed_at timestamp with time zone,
  failed_attempts integer NOT NULL DEFAULT 0,
  CONSTRAINT lightious_pairings_pkey PRIMARY KEY (id),
  CONSTRAINT lightious_pairings_user_code_digest_key UNIQUE (user_code_digest),
  CONSTRAINT lightious_pairings_poll_secret_digest_key UNIQUE (poll_secret_digest),
  CONSTRAINT lightious_pairings_device_bearer_digest_key UNIQUE (device_bearer_digest),
  CONSTRAINT lightious_pairings_state_check
    CHECK (state IN ('created', 'claimed', 'consumed', 'rejected')),
  CONSTRAINT lightious_pairings_failed_attempts_check CHECK (failed_attempts >= 0),
  CONSTRAINT lightious_pairings_claimed_profile_id_fkey
    FOREIGN KEY (claimed_profile_id)
    REFERENCES public.lightious_profiles (id)
    ON DELETE CASCADE
);

GRANT ALL ON TABLE public.lightious_pairings TO current_user;

CREATE INDEX IF NOT EXISTS lightious_pairings_claimed_profile_id_idx
  ON public.lightious_pairings (claimed_profile_id);

CREATE INDEX IF NOT EXISTS lightious_pairings_expires_at_idx
  ON public.lightious_pairings (expires_at);
