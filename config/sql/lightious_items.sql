-- Table: public.lightious_items

CREATE TABLE IF NOT EXISTS public.lightious_items
(
  id text NOT NULL,
  profile_id text NOT NULL,
  video_id text NOT NULL,
  title text NOT NULL,
  author text NOT NULL,
  length_seconds bigint NOT NULL DEFAULT 0,
  thumbnail_url text,
  playback_policy text NOT NULL DEFAULT 'listen_only',
  added_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT lightious_items_pkey PRIMARY KEY (id),
  CONSTRAINT lightious_items_profile_video_key UNIQUE (profile_id, video_id),
  CONSTRAINT lightious_items_video_id_check CHECK (video_id ~ '^[A-Za-z0-9_-]{11}$'),
  CONSTRAINT lightious_items_length_seconds_check CHECK (length_seconds >= 0),
  CONSTRAINT lightious_items_playback_policy_check
    CHECK (playback_policy IN ('listen_only', 'watch_and_listen')),
  CONSTRAINT lightious_items_profile_id_fkey
    FOREIGN KEY (profile_id)
    REFERENCES public.lightious_profiles (id)
    ON DELETE CASCADE
);

GRANT ALL ON TABLE public.lightious_items TO current_user;

CREATE INDEX IF NOT EXISTS lightious_items_profile_added_at_idx
  ON public.lightious_items (profile_id, added_at DESC);
