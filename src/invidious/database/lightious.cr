require "./base.cr"

module Invidious::Database::Lightious
  extend self

  record Profile,
    id : String,
    account : String,
    mode : String,
    revision : Int64,
    created_at : Time,
    updated_at : Time

  record PairingStatus,
    id : String,
    state : String,
    device_label : String,
    expires_at : Time,
    claimed_account : String?

  record Device,
    id : String,
    profile_id : String,
    label : String,
    account : String,
    created_at : Time,
    last_seen_at : Time?,
    revoked_at : Time?

  record Item,
    id : String,
    profile_id : String,
    video_id : String,
    title : String,
    author : String,
    length_seconds : Int64,
    thumbnail_url : String?,
    playback_policy : String,
    added_at : Time,
    updated_at : Time

  def ensure_profile(account : String, proposed_id : String, now : Time) : Profile
    request = <<-SQL
      INSERT INTO lightious_profiles (
        id,
        invidious_user_email,
        created_at,
        updated_at
      ) VALUES ($1, $2, $3, $3)
      ON CONFLICT (invidious_user_email) DO UPDATE
        SET invidious_user_email = EXCLUDED.invidious_user_email
      RETURNING id, invidious_user_email, mode, revision, created_at, updated_at
    SQL

    row = PG_DB.query_one(
      request,
      proposed_id,
      account,
      now,
      as: {String, String, String, Int64, Time, Time},
    )
    profile_from_row(row)
  end

  def profile_for_account(account : String) : Profile?
    request = <<-SQL
      SELECT id, invidious_user_email, mode, revision, created_at, updated_at
      FROM lightious_profiles
      WHERE invidious_user_email = $1
    SQL

    row = PG_DB.query_one?(
      request,
      account,
      as: {String, String, String, Int64, Time, Time},
    )
    row.try { |value| profile_from_row(value) }
  end

  def profile_for_id(id : String) : Profile?
    request = <<-SQL
      SELECT id, invidious_user_email, mode, revision, created_at, updated_at
      FROM lightious_profiles
      WHERE id = $1
    SQL

    row = PG_DB.query_one?(
      request,
      id,
      as: {String, String, String, Int64, Time, Time},
    )
    row.try { |value| profile_from_row(value) }
  end

  def update_mode(account : String, mode : String, now : Time) : Profile?
    request = <<-SQL
      UPDATE lightious_profiles
      SET
        mode = $1,
        revision = revision + CASE WHEN mode = $1 THEN 0 ELSE 1 END,
        updated_at = CASE WHEN mode = $1 THEN updated_at ELSE $2 END
      WHERE invidious_user_email = $3
      RETURNING id, invidious_user_email, mode, revision, created_at, updated_at
    SQL

    row = PG_DB.query_one?(
      request,
      mode,
      now,
      account,
      as: {String, String, String, Int64, Time, Time},
    )
    row.try { |value| profile_from_row(value) }
  end

  def items_for_profile(profile_id : String) : Array(Item)
    request = <<-SQL
      SELECT
        id,
        profile_id,
        video_id,
        title,
        author,
        length_seconds,
        thumbnail_url,
        playback_policy,
        added_at,
        updated_at
      FROM lightious_items
      WHERE profile_id = $1
      ORDER BY added_at DESC, id ASC
    SQL

    PG_DB.query_all(
      request,
      profile_id,
      as: {String, String, String, String, String, Int64, String?, String, Time, Time},
    ).map { |row| item_from_row(row) }
  end

  def upsert_item(
    account : String,
    item_id : String,
    video_id : String,
    title : String,
    author : String,
    length_seconds : Int64,
    thumbnail_url : String?,
    playback_policy : String,
    now : Time,
  ) : Bool
    request = <<-SQL
      WITH target AS (
        SELECT id
        FROM lightious_profiles
        WHERE invidious_user_email = $1
      ), upserted AS (
        INSERT INTO lightious_items (
          id,
          profile_id,
          video_id,
          title,
          author,
          length_seconds,
          thumbnail_url,
          playback_policy,
          added_at,
          updated_at
        )
        SELECT $2, target.id, $3, $4, $5, $6, $7, $8, $9, $9
        FROM target
        WHERE true
        ON CONFLICT (profile_id, video_id) DO UPDATE SET
          title = EXCLUDED.title,
          author = EXCLUDED.author,
          length_seconds = EXCLUDED.length_seconds,
          thumbnail_url = EXCLUDED.thumbnail_url,
          playback_policy = EXCLUDED.playback_policy,
          updated_at = EXCLUDED.updated_at
        RETURNING profile_id
      ), bumped AS (
        UPDATE lightious_profiles
        SET revision = revision + 1, updated_at = $9
        WHERE id = (SELECT profile_id FROM upserted LIMIT 1)
        RETURNING id
      )
      SELECT COUNT(*) FROM bumped
    SQL

    PG_DB.query_one(
      request,
      account,
      item_id,
      video_id,
      title,
      author,
      length_seconds,
      thumbnail_url,
      playback_policy,
      now,
      as: Int64,
    ) == 1
  end

  def update_item_policy(account : String, item_id : String, policy : String, now : Time) : Bool
    request = <<-SQL
      WITH target AS (
        SELECT id
        FROM lightious_profiles
        WHERE invidious_user_email = $1
      ), changed AS (
        UPDATE lightious_items
        SET playback_policy = $2, updated_at = $3
        WHERE id = $4
          AND profile_id = (SELECT id FROM target)
          AND playback_policy <> $2
        RETURNING profile_id
      ), bumped AS (
        UPDATE lightious_profiles
        SET revision = revision + 1, updated_at = $3
        WHERE id = (SELECT profile_id FROM changed LIMIT 1)
        RETURNING id
      )
      SELECT COUNT(*) FROM bumped
    SQL

    PG_DB.query_one(request, account, policy, now, item_id, as: Int64) == 1
  end

  def delete_item(account : String, item_id : String, now : Time) : Bool
    request = <<-SQL
      WITH target AS (
        SELECT id
        FROM lightious_profiles
        WHERE invidious_user_email = $1
      ), removed AS (
        DELETE FROM lightious_items
        WHERE id = $2
          AND profile_id = (SELECT id FROM target)
        RETURNING profile_id
      ), bumped AS (
        UPDATE lightious_profiles
        SET revision = revision + 1, updated_at = $3
        WHERE id = (SELECT profile_id FROM removed LIMIT 1)
        RETURNING id
      )
      SELECT COUNT(*) FROM bumped
    SQL

    PG_DB.query_one(request, account, item_id, now, as: Int64) == 1
  end

  def delete_expired_pairings(now : Time)
    request = <<-SQL
      DELETE FROM lightious_pairings
      WHERE expires_at <= $1
        AND state IN ('created', 'claimed', 'rejected')
    SQL
    PG_DB.exec(request, now)
  end

  def insert_pairing(
    id : String,
    user_code_digest : String,
    poll_secret_digest : String,
    device_bearer_digest : String,
    device_label : String,
    created_at : Time,
    expires_at : Time,
  )
    request = <<-SQL
      INSERT INTO lightious_pairings (
        id,
        user_code_digest,
        poll_secret_digest,
        device_bearer_digest,
        device_label,
        state,
        expires_at,
        created_at
      ) VALUES ($1, $2, $3, $4, $5, 'created', $6, $7)
    SQL

    PG_DB.exec(
      request,
      id,
      user_code_digest,
      poll_secret_digest,
      device_bearer_digest,
      device_label,
      expires_at,
      created_at,
    )
  end

  def pairing_for_user_code(user_code_digest : String, now : Time) : PairingStatus?
    request = <<-SQL
      SELECT id, state, device_label, expires_at, NULL::text
      FROM lightious_pairings
      WHERE user_code_digest = $1
        AND state = 'created'
        AND expires_at > $2
    SQL

    row = PG_DB.query_one?(
      request,
      user_code_digest,
      now,
      as: {String, String, String, Time, String?},
    )
    row.try { |value| pairing_from_row(value) }
  end

  def claim_pairing(
    user_code_digest : String,
    account : String,
    proposed_profile_id : String,
    claimed_at : Time,
  ) : PairingStatus?
    request = <<-SQL
      WITH profile AS (
        INSERT INTO lightious_profiles (
          id,
          invidious_user_email,
          created_at,
          updated_at
        ) VALUES ($1, $2, $3, $3)
        ON CONFLICT (invidious_user_email) DO UPDATE
          SET invidious_user_email = EXCLUDED.invidious_user_email
        RETURNING id, invidious_user_email
      )
      UPDATE lightious_pairings AS pairing
      SET
        state = 'claimed',
        claimed_profile_id = (SELECT id FROM profile),
        claimed_at = $3
      WHERE pairing.user_code_digest = $4
        AND pairing.state = 'created'
        AND pairing.expires_at > $3
      RETURNING
        pairing.id,
        pairing.state,
        pairing.device_label,
        pairing.expires_at,
        (SELECT invidious_user_email FROM profile)
    SQL

    row = PG_DB.query_one?(
      request,
      proposed_profile_id,
      account,
      claimed_at,
      user_code_digest,
      as: {String, String, String, Time, String},
    )
    row.try { |value| pairing_from_row(value) }
  end

  def pairing_status(id : String, poll_secret_digest : String) : PairingStatus?
    request = <<-SQL
      SELECT
        pairing.id,
        pairing.state,
        pairing.device_label,
        pairing.expires_at,
        profile.invidious_user_email
      FROM lightious_pairings AS pairing
      LEFT JOIN lightious_profiles AS profile
        ON profile.id = pairing.claimed_profile_id
      WHERE pairing.id = $1
        AND pairing.poll_secret_digest = $2
    SQL

    row = PG_DB.query_one?(
      request,
      id,
      poll_secret_digest,
      as: {String, String, String, Time, String?},
    )
    row.try { |value| pairing_from_row(value) }
  end

  # A retry after a lost activation response returns the same device. The
  # plaintext phone credential is never stored by or returned from the server.
  def activate_pairing(
    pairing_id : String,
    poll_secret_digest : String,
    device_id : String,
    activated_at : Time,
  ) : Device?
    request = <<-SQL
      WITH consumed AS (
        UPDATE lightious_pairings
        SET state = 'consumed'
        WHERE id = $1
          AND poll_secret_digest = $2
          AND state = 'claimed'
          AND expires_at > $3
        RETURNING claimed_profile_id, device_bearer_digest, device_label
      ), inserted AS (
        INSERT INTO lightious_devices (
          id,
          profile_id,
          bearer_digest,
          label,
          created_at
        )
        SELECT $4, claimed_profile_id, device_bearer_digest, device_label, $3
        FROM consumed
        ON CONFLICT (bearer_digest) DO NOTHING
        RETURNING id, profile_id, label, created_at, last_seen_at, revoked_at
      ), selected AS (
        SELECT id, profile_id, label, created_at, last_seen_at, revoked_at
        FROM inserted
        UNION ALL
        SELECT device.id, device.profile_id, device.label, device.created_at,
          device.last_seen_at, device.revoked_at
        FROM lightious_pairings AS pairing
        JOIN lightious_devices AS device
          ON device.bearer_digest = pairing.device_bearer_digest
        WHERE pairing.id = $1
          AND pairing.poll_secret_digest = $2
          AND pairing.state = 'consumed'
          AND NOT EXISTS (SELECT 1 FROM inserted)
      )
      SELECT
        device.id,
        device.profile_id,
        device.label,
        profile.invidious_user_email,
        device.created_at,
        device.last_seen_at,
        device.revoked_at
      FROM selected AS device
      JOIN lightious_profiles AS profile ON profile.id = device.profile_id
      LIMIT 1
    SQL

    row = PG_DB.query_one?(
      request,
      pairing_id,
      poll_secret_digest,
      activated_at,
      device_id,
      as: {String, String, String, String, Time, Time?, Time?},
    )
    row.try { |value| device_from_row(value) }
  end

  def active_device(bearer_digest : String) : Device?
    request = <<-SQL
      SELECT
        device.id,
        device.profile_id,
        device.label,
        profile.invidious_user_email,
        device.created_at,
        device.last_seen_at,
        device.revoked_at
      FROM lightious_devices AS device
      JOIN lightious_profiles AS profile ON profile.id = device.profile_id
      WHERE device.bearer_digest = $1
        AND device.revoked_at IS NULL
    SQL

    row = PG_DB.query_one?(
      request,
      bearer_digest,
      as: {String, String, String, String, Time, Time?, Time?},
    )
    row.try { |value| device_from_row(value) }
  end

  def touch_device(id : String, seen_at : Time)
    request = <<-SQL
      UPDATE lightious_devices
      SET last_seen_at = $1
      WHERE id = $2 AND revoked_at IS NULL
    SQL
    PG_DB.exec(request, seen_at, id)
  end

  def devices_for_account(account : String) : Array(Device)
    request = <<-SQL
      SELECT
        device.id,
        device.profile_id,
        device.label,
        profile.invidious_user_email,
        device.created_at,
        device.last_seen_at,
        device.revoked_at
      FROM lightious_devices AS device
      JOIN lightious_profiles AS profile ON profile.id = device.profile_id
      WHERE profile.invidious_user_email = $1
      ORDER BY device.created_at DESC
    SQL

    PG_DB.query_all(
      request,
      account,
      as: {String, String, String, String, Time, Time?, Time?},
    ).map { |row| device_from_row(row) }
  end

  def revoke_device(id : String, account : String, revoked_at : Time) : Bool
    request = <<-SQL
      UPDATE lightious_devices AS device
      SET revoked_at = $1
      FROM lightious_profiles AS profile
      WHERE device.id = $2
        AND device.profile_id = profile.id
        AND profile.invidious_user_email = $3
        AND device.revoked_at IS NULL
    SQL

    PG_DB.exec(request, revoked_at, id, account).rows_affected == 1
  end

  private def profile_from_row(row : {String, String, String, Int64, Time, Time}) : Profile
    Profile.new(
      id: row[0],
      account: row[1],
      mode: row[2],
      revision: row[3],
      created_at: row[4],
      updated_at: row[5],
    )
  end

  private def pairing_from_row(row : {String, String, String, Time, String?}) : PairingStatus
    PairingStatus.new(
      id: row[0],
      state: row[1],
      device_label: row[2],
      expires_at: row[3],
      claimed_account: row[4],
    )
  end

  private def device_from_row(
    row : {String, String, String, String, Time, Time?, Time?},
  ) : Device
    Device.new(
      id: row[0],
      profile_id: row[1],
      label: row[2],
      account: row[3],
      created_at: row[4],
      last_seen_at: row[5],
      revoked_at: row[6],
    )
  end

  private def item_from_row(
    row : {String, String, String, String, String, Int64, String?, String, Time, Time},
  ) : Item
    Item.new(
      id: row[0],
      profile_id: row[1],
      video_id: row[2],
      title: row[3],
      author: row[4],
      length_seconds: row[5],
      thumbnail_url: row[6],
      playback_policy: row[7],
      added_at: row[8],
      updated_at: row[9],
    )
  end
end
