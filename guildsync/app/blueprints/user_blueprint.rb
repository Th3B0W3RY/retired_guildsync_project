class UserBlueprint < Blueprinter::Base
  identifier :id

  # SECURITY: Do not expose email in public views
  # Email should only be visible to the user themselves
  fields :username, :created_at, :updated_at

  view :extended do
    fields :username, :created_at, :updated_at
    association :guilds, blueprint: GuildBlueprint
  end

  # Private view for user's own profile (includes email)
  view :private do
    fields :email, :username, :created_at, :updated_at
    association :guilds, blueprint: GuildBlueprint
    association :current_subscription, blueprint: SubscriptionBlueprint
  end
end
