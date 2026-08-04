# frozen_string_literal: true

# Devise::Models::Authenticatable defaults to deliver_now for all Devise emails.
# This module prepends onto User so we consistently use deliver_later (MailDeliveryJob /
# Sidekiq in production), matching SignupMailer and other ApplicationMailer subclasses.
module UserDeviseMailDelivery
  protected

  def send_devise_notification(notification, *args)
    devise_mailer.send(notification, self, *args).deliver_later
  end
end
