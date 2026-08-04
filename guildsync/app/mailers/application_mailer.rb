class ApplicationMailer < ActionMailer::Base
  # Proc may be called with the Mail instance ( arity 1 ) by Action Mailer in some code paths.
  default from: ->(*_) { ENV.fetch("MAILER_FROM", "no-reply@guild-sync.net") }
  layout "mailer"
end
