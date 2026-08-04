# frozen_string_literal: true

class DiscordRoleSync < ApplicationRecord
  belongs_to :guild

  validates :role_id, presence: true, uniqueness: { scope: :guild_id }
  validates :role_name, presence: true
end

