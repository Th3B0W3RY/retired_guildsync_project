class GuildInviteBlueprint < Blueprinter::Base
  identifier :id

  fields :status, :dismissed, :guild_id, :user_id, :created_at, :updated_at

  association :user, blueprint: UserBlueprint
  association :invited_by, blueprint: UserBlueprint
end
