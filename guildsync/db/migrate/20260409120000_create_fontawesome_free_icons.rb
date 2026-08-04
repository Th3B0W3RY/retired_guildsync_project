# frozen_string_literal: true

class CreateFontawesomeFreeIcons < ActiveRecord::Migration[8.0]
  def change
    create_table :fontawesome_free_icons do |t|
      t.string :style, null: false
      t.string :icon_name, null: false
      t.string :label, null: false

      t.timestamps
    end

    add_index :fontawesome_free_icons, [ :style, :icon_name ], unique: true, name: "index_fontawesome_free_icons_on_style_and_icon_name"
    add_index :fontawesome_free_icons, :label, name: "index_fontawesome_free_icons_on_label"
  end
end
