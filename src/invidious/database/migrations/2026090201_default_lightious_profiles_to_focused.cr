module Invidious::Database::Migrations
  class DefaultLightiousProfilesToFocused < Migration
    version 2026090201

    def up(conn : DB::Connection)
      conn.exec <<-SQL
      ALTER TABLE public.lightious_profiles
        ALTER COLUMN mode SET DEFAULT 'focused';
      SQL
    end
  end
end
