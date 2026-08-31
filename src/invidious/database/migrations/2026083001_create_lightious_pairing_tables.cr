module Invidious::Database::Migrations
  class CreateLightiousPairingTables < Migration
    version 2026083001

    def up(conn : DB::Connection)
      conn.exec <<-SQL
      CREATE TABLE IF NOT EXISTS public.lightious_profiles
      (
        id text NOT NULL,
        invidious_user_email text NOT NULL,
        mode text NOT NULL DEFAULT 'explore',
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
      SQL

      conn.exec <<-SQL
      GRANT ALL ON TABLE public.lightious_profiles TO current_user;
      SQL

      conn.exec <<-SQL
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
      SQL

      conn.exec <<-SQL
      GRANT ALL ON TABLE public.lightious_items TO current_user;
      SQL

      conn.exec <<-SQL
      CREATE INDEX IF NOT EXISTS lightious_items_profile_added_at_idx
        ON public.lightious_items (profile_id, added_at DESC);
      SQL

      conn.exec <<-SQL
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
      SQL

      conn.exec <<-SQL
      GRANT ALL ON TABLE public.lightious_pairings TO current_user;
      SQL

      conn.exec <<-SQL
      CREATE INDEX IF NOT EXISTS lightious_pairings_claimed_profile_id_idx
        ON public.lightious_pairings (claimed_profile_id);
      SQL

      conn.exec <<-SQL
      CREATE INDEX IF NOT EXISTS lightious_pairings_expires_at_idx
        ON public.lightious_pairings (expires_at);
      SQL

      conn.exec <<-SQL
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
      SQL

      conn.exec <<-SQL
      GRANT ALL ON TABLE public.lightious_devices TO current_user;
      SQL

      conn.exec <<-SQL
      CREATE INDEX IF NOT EXISTS lightious_devices_profile_id_idx
        ON public.lightious_devices (profile_id);
      SQL
    end
  end
end
