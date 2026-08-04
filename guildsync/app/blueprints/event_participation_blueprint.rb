class EventParticipationBlueprint < Blueprinter::Base
  identifier :id

  fields :status, :notes, :created_at, :updated_at, :user_id

  association :user, blueprint: UserBlueprint
end
