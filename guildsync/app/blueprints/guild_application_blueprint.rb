class GuildApplicationBlueprint < Blueprinter::Base
  identifier :id

  fields :status, :discord_username, :message, :character_details, :guild_id, :user_id, :created_at, :updated_at

  association :user, blueprint: UserBlueprint
end
