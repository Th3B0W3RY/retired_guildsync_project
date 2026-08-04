class GearSnapshot < ApplicationRecord
  # Uploaded screenshot + extracted stats are removed together after this many days
  # (see PurgeExpiredGearSnapshotsJob). Keeps storage bounded and matches product retention.
  RETENTION_PERIOD_DAYS = 60

  belongs_to :guild
  belongs_to :user
  belongs_to :game
  
  # Active Storage for screenshot image
  has_one_attached :screenshot
  
  enum :source, { web: 'web', discord: 'discord' }
  
  validates :source, presence: true
  # Data must be present (not nil), but can be an empty hash {}
  # presence: true would fail for empty hashes, so we validate not nil explicitly
  validate :data_not_nil
  validate :screenshot_present

  after_commit :touch_uploader_guild_membership, on: :create
  
  # Scopes - optimized for performance
  # Note: This returns a relation, call .first on the result
  scope :latest_for_user, ->(guild, user) {
    where(guild: guild, user: user)
      .order(created_at: :desc)
      .limit(1)
  }
  
  # Bulk query for multiple users (more efficient)
  scope :latest_for_users, ->(guild, users) {
    where(guild: guild, user: users)
      .select("DISTINCT ON (user_id) *")
      .order(:user_id, created_at: :desc)
  }
  
  scope :recent, -> { where('created_at > ?', 30.days.ago) }
  scope :outdated, ->(days = 7) { where('created_at < ?', days.days.ago) }
  scope :past_retention, -> { where("created_at < ?", RETENTION_PERIOD_DAYS.days.ago) }
  
  # Status helpers
  def status
    return 'missing' if new_record?
    return 'outdated' if outdated?
    'up_to_date'
  end
  
  def outdated?(threshold_days = 7)
    created_at < threshold_days.days.ago
  end
  
  # Embedding helpers
  def embedding_vector
    return nil unless embedding.present?
    JSON.parse(embedding) rescue nil
  end
  
  def embedding_vector=(vector)
    self.embedding = vector.to_json if vector
  end
  
  # Key stats preview (for table display) — first few extracted stats, any game/UI.
  def key_stats
    StatScanner::StatRows.from_data(data).first(3).each_with_object({}) do |row, h|
      h[row.label] = row.value
    end
  end

  def stat_rows
    StatScanner::StatRows.from_data(data)
  end

  def within_retention_period?
    created_at >= self.class::RETENTION_PERIOD_DAYS.days.ago
  end

  # Screenshot may be shown in the stat scanner UI (same visibility rules as viewing stats).
  def reference_screenshot_available?
    screenshot.attached? && within_retention_period?
  end

  # Shown as "last updated" in the stat scanner UI: scan time (created_at) or last data edit (updated_at).
  # Returns nil on an unsaved record (no timestamps yet); callers should guard UI accordingly.
  def last_activity_at
    times = [created_at, updated_at].compact
    return nil if times.empty?

    times.max
  end
  
  private

  def touch_uploader_guild_membership
    guild_member = GuildMember.find_by(guild_id: guild_id, user_id: user_id)
    guild_member&.update_columns(updated_at: Time.current)
  end
  
  def data_not_nil
    errors.add(:data, :blank) if data.nil?
  end
  
  def screenshot_present
    errors.add(:screenshot, :must_be_attached) unless screenshot.attached?
  end
end

