#!/bin/bash
set -eou pipefail

psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < config/sql/channels.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < config/sql/videos.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < config/sql/channel_videos.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < config/sql/users.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < config/sql/lightious_profiles.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < config/sql/lightious_items.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < config/sql/lightious_pairings.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < config/sql/lightious_devices.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < config/sql/session_ids.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < config/sql/nonces.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < config/sql/annotations.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < config/sql/playlists.sql
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" < config/sql/playlist_videos.sql
