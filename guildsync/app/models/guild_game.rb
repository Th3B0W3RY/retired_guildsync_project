class GuildGame < ApplicationRecord
  belongs_to :guild
  belongs_to :game
  
  validates :guild_id, uniqueness: { scope: :game_id }
  validate :only_one_primary_per_guild
  
  scope :primary, -> { where(primary: true) }
  
  private
  
  def only_one_primary_per_guild
    return unless primary?
    
    if guild.guild_games.primary.where.not(id: id).exists?
      errors.add(:primary, :only_one_allowed)
    end
  end
end

