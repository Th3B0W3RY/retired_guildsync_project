class GuildMemberBlueprint < Blueprinter::Base
  identifier :id

  fields :role, :status, :joined_at, :created_at, :updated_at

  association :user, blueprint: UserBlueprint
end
