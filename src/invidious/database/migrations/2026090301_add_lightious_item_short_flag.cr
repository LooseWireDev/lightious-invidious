module Invidious::Database::Migrations
  class AddLightiousItemShortFlag < Migration
    version 2026090301

    def up(conn : DB::Connection)
      conn.exec <<-SQL
      ALTER TABLE public.lightious_items
        ADD COLUMN IF NOT EXISTS is_short boolean NOT NULL DEFAULT false;
      SQL

      conn.exec("DROP INDEX IF EXISTS public.lightious_items_profile_library_added_at_idx")
      conn.exec <<-SQL
      CREATE INDEX lightious_items_profile_library_added_at_idx
        ON public.lightious_items (profile_id, added_at DESC)
        WHERE library_visible AND NOT is_short;
      SQL
    end
  end
end
