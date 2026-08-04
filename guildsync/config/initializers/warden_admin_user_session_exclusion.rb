# frozen_string_literal: true

# Mutually exclusive admin-console auth (ENV credentials + session flags) and Devise `:user`
# scope. Prevents a browser session from acting as both a normal user and an admin, which
# caused confusing logout behavior and intermittent Warden/session desync.
Rails.application.config.to_prepare do
  Warden::Manager.after_set_user do |user, auth, opts|
    next unless opts[:scope].to_sym == :user
    next unless user.is_a?(User)

    # Only react to a fresh sign-in in this request — not session restore (`:fetch`) or other events.
    next unless opts[:event].respond_to?(:to_sym) && opts[:event].to_sym == :authentication

    rack_session = auth.env["rack.session"]
    next unless rack_session

    rack_session.delete("admin_authenticated")
    rack_session.delete(:admin_authenticated)
    rack_session.delete("admin_email")
    rack_session.delete(:admin_email)
  end
end
