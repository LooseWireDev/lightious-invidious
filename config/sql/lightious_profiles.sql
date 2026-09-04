-- Table: public.lightious_profiles

CREATE TABLE IF NOT EXISTS public.lightious_profiles
(
  id text NOT NULL,
  invidious_user_email text NOT NULL,
  mode text NOT NULL DEFAULT 'focused',
  revision bigint NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT lightious_profiles_pkey PRIMARY KEY (id),
  CONSTRAINT lightious_profiles_invidious_user_email_key UNIQUE (invidious_user_email),
  CONSTRAINT lightious_profiles_mode_check CHECK (mode IN ('explore', 'focused')),
  CONSTRAINT lightious_profiles_revision_check CHECK (revision >= 0),
  CONSTRAINT lightious_profiles_invidious_user_email_fkey
    FOREIGN KEY (invidious_user_email)
    REFERENCES public.users (email)
    ON DELETE CASCADE
);

GRANT ALL ON TABLE public.lightious_profiles TO current_user;
