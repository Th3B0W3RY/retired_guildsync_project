class EventBlueprint < Blueprinter::Base
  identifier :id

  fields :title, :description, :event_type, :scheduled_at, :duration, :status, :created_at, :updated_at, :guild_id, :created_by_id

  association :guild, blueprint: GuildBlueprint
  association :created_by, blueprint: UserBlueprint

  view :extended do
    association :event_participations, blueprint: EventParticipationBlueprint
  end
end
