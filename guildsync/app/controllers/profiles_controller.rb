class ProfilesController < ApplicationController
  before_action :authenticate_user!

  def update_avatar
    if current_user.update(avatar_params)
      redirect_to profile_settings_path,
                  notice: I18n.t("settings.profile.avatar.updated_notice"),
                  status: :see_other
    else
      redirect_to profile_settings_path,
                  alert: current_user.errors.full_messages.to_sentence,
                  status: :see_other
    end
  end

  def remove_avatar
    current_user.avatar.purge if current_user.avatar.attached?
    redirect_to profile_settings_path,
                notice: I18n.t("settings.profile.avatar.removed_notice"),
                status: :see_other
  end

  private

  def avatar_params
    params.require(:user).permit(:avatar)
  end
end
