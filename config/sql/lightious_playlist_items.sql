-- Table: public.lightious_playlist_items

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

GRANT ALL ON TABLE public.lightious_playlist_items TO current_user;

CREATE INDEX IF NOT EXISTS lightious_playlist_items_item_id_idx
  ON public.lightious_playlist_items (item_id);
