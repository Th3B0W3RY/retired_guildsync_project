# frozen_string_literal: true

# Handles the /help slash command (no subcommands).
# Displays the full command list from I18n, tailored to the user's role.
class DiscordHelpCommandService
  include DiscordCommandHelpers

  def self.handle(interaction)
    new.handle(interaction)
  end

  def handle(interaction)
    result = resolve_guild_and_user(interaction)
    return result if result.is_a?(Hash)

    @guild, @user, @guild_member = result

    embed = {
      title:       I18n.t("discord.commands.help.title"),
      description: I18n.t("discord.commands.help.description"),
      color:       0x5865F2,
      footer:      { text: "GuildSync • guild-sync.net" }
    }

    embed_response(embed, ephemeral: true)
  end
end
