-- Table: public.lightious_channels

CREATE TABLE IF NOT EXISTS public.lightious_channels
(
  id text NOT NULL,
  profile_id text NOT NULL,
  ucid text NOT NULL,
  title text NOT NULL,
  thumbnail_url text,
  playback_policy text NOT NULL DEFAULT 'listen_only',
  added_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT lightious_channels_pkey PRIMARY KEY (id),
  CONSTRAINT lightious_channels_profile_ucid_key UNIQUE (profile_id, ucid),
  CONSTRAINT lightious_channels_ucid_check CHECK (ucid ~ '^UC[A-Za-z0-9_-]{22}$'),
  CONSTRAINT lightious_channels_playback_policy_check
    CHECK (playback_policy IN ('listen_only', 'watch_and_listen')),
  CONSTRAINT lightious_channels_profile_id_fkey
    FOREIGN KEY (profile_id)
    REFERENCES public.lightious_profiles (id)
    ON DELETE CASCADE
);

GRANT ALL ON TABLE public.lightious_channels TO current_user;

CREATE INDEX IF NOT EXISTS lightious_channels_profile_added_at_idx
  ON public.lightious_channels (profile_id, added_at DESC);
