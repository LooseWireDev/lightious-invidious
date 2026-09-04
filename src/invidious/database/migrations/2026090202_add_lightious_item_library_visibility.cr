module Invidious::Database::Migrations
  class AddLightiousItemLibraryVisibility < Migration
    version 2026090202

    def up(conn : DB::Connection)
      conn.exec <<-SQL
      ALTER TABLE public.lightious_items
        ADD COLUMN IF NOT EXISTS library_visible boolean;
      SQL

      conn.exec <<-SQL
      UPDATE public.lightious_items
      SET library_visible = true
      WHERE library_visible IS NULL;
      SQL

      conn.exec <<-SQL
      ALTER TABLE public.lightious_items
        ALTER COLUMN library_visible SET DEFAULT true,
        ALTER COLUMN library_visible SET NOT NULL;
      SQL

      conn.exec <<-SQL
      CREATE INDEX IF NOT EXISTS lightious_items_profile_library_added_at_idx
        ON public.lightious_items (profile_id, added_at DESC)
        WHERE library_visible;
      SQL
    end
  end
end
