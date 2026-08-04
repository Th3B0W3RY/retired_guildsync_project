class GuildBlueprint < Blueprinter::Base
  identifier :id

  fields :name, :description, :avatar_url, :settings, :created_at, :updated_at, :owner_id

  association :owner, blueprint: UserBlueprint
  association :guild_members, blueprint: GuildMemberBlueprint

  view :extended do
    association :events, blueprint: EventBlueprint
  end
end
