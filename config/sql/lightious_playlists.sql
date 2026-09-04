-- Table: public.lightious_playlists

CREATE TABLE IF NOT EXISTS public.lightious_playlists
(
  id text NOT NULL,
  profile_id text NOT NULL,
  name text NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT lightious_playlists_pkey PRIMARY KEY (id),
  CONSTRAINT lightious_playlists_name_check
    CHECK (octet_length(name) BETWEEN 1 AND 100),
  CONSTRAINT lightious_playlists_profile_id_fkey
    FOREIGN KEY (profile_id)
    REFERENCES public.lightious_profiles (id)
    ON DELETE CASCADE
);

GRANT ALL ON TABLE public.lightious_playlists TO current_user;

CREATE INDEX IF NOT EXISTS lightious_playlists_profile_created_at_idx
  ON public.lightious_playlists (profile_id, created_at DESC);
