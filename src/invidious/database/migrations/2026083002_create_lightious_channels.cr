module Invidious::Database::Migrations
  class CreateLightiousChannels < Migration
    version 2026083002

    def up(conn : DB::Connection)
      conn.exec <<-SQL
      ALTER TABLE public.lightious_items
        ADD COLUMN IF NOT EXISTS author_ucid text;
      SQL

      conn.exec <<-SQL
      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1
          FROM pg_constraint
          WHERE conname = 'lightious_items_author_ucid_check'
            AND conrelid = 'public.lightious_items'::regclass
        ) THEN
          ALTER TABLE public.lightious_items
            ADD CONSTRAINT lightious_items_author_ucid_check
            CHECK (author_ucid IS NULL OR author_ucid ~ '^UC[A-Za-z0-9_-]{22}$');
        END IF;
      END
      $$;
      SQL

      conn.exec <<-SQL
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
      SQL

      conn.exec <<-SQL
      GRANT ALL ON TABLE public.lightious_channels TO current_user;
      SQL

      conn.exec <<-SQL
      CREATE INDEX IF NOT EXISTS lightious_channels_profile_added_at_idx
        ON public.lightious_channels (profile_id, added_at DESC);
      SQL

      conn.exec <<-SQL
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
      SQL

      conn.exec <<-SQL
      GRANT ALL ON TABLE public.lightious_playlists TO current_user;
      SQL

      conn.exec <<-SQL
      CREATE INDEX IF NOT EXISTS lightious_playlists_profile_created_at_idx
        ON public.lightious_playlists (profile_id, created_at DESC);
      SQL

      conn.exec <<-SQL
      CREATE TABLE IF NOT EXISTS public.lightious_playlist_items
      (
        playlist_id text NOT NULL,
        item_id text NOT NULL,
        position integer NOT NULL,
        added_at timestamp with time zone NOT NULL DEFAULT now(),
        CONSTRAINT lightious_playlist_items_pkey PRIMARY KEY (playlist_id, item_id),
        CONSTRAINT lightious_playlist_items_playlist_position_key
          UNIQUE (playlist_id, position),
        CONSTRAINT lightious_playlist_items_position_check CHECK (position >= 0),
        CONSTRAINT lightious_playlist_items_playlist_id_fkey
          FOREIGN KEY (playlist_id)
          REFERENCES public.lightious_playlists (id)
          ON DELETE CASCADE,
        CONSTRAINT lightious_playlist_items_item_id_fkey
          FOREIGN KEY (item_id)
          REFERENCES public.lightious_items (id)
          ON DELETE CASCADE
      );
      SQL

      conn.exec <<-SQL
      GRANT ALL ON TABLE public.lightious_playlist_items TO current_user;
      SQL

      conn.exec <<-SQL
      CREATE INDEX IF NOT EXISTS lightious_playlist_items_item_id_idx
        ON public.lightious_playlist_items (item_id);
      SQL
    end
  end
end
