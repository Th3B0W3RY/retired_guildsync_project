class AddCharacterDetailsToGuildApplications < ActiveRecord::Migration[8.0]
  def change
    add_column :guild_applications, :character_details, :text, if_not_exists: true
  end
end
