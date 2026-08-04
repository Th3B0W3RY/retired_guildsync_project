# frozen_string_literal: true

# Handles the /docs slash command and all its subcommands.
#
# Subcommands (any active guild member):
#   /docs list   [folder:<str>] — list documents, optionally filtered by folder
#   /docs view   doc_id:<int>   — preview first 1 800 chars of a document
#   /docs search query:<str>    — search documents by title
class DiscordDocsCommandService
  include DiscordCommandHelpers

  PREVIEW_CHARS = 1_800

  def self.handle(interaction)
    new.handle(interaction)
  end

  def handle(interaction)
    result = resolve_guild_and_user(interaction)
    return result if result.is_a?(Hash)

    @guild, @user, @guild_member = result
    @interaction = interaction

    case subcommand_name(interaction)
    when :list   then handle_list
    when :view   then handle_view
    when :search then handle_search
    else ephemeral_response(I18n.t("discord.commands.errors.unknown_subcommand"))
    end
  end

  private

  # Recursively extract plain text from a Tiptap/ProseMirror JSON doc node
  # or from a plain String (supports both storage types).
  def extract_plain_text(content)
    return ""       if content.nil?
    return content.gsub(/<[^>]+>/, " ").strip if content.is_a?(String)
    return extract_plain_text(content.to_h) if content.respond_to?(:to_h) && !content.is_a?(Hash)
    return "" unless content.is_a?(Hash)

    parts = []
    parts << content["text"] if content["text"].is_a?(String)
    (content["content"] || []).each { |node| parts << extract_plain_text(node) }
    parts.join(" ").strip
  end

  # Only expose non-private documents to Discord (public_doc + unlisted_doc)
  def visible_docs
    @guild.guild_documents.where(visibility: %i[public_doc unlisted_doc])
  end

  def handle_list
    opts        = subcommand_options(@interaction)
    folder_name = opts["folder"].to_s.strip.presence

    docs = visible_docs.includes(:folder)

    if folder_name
      docs = docs.joins(:folder).where(guild_document_folders: { name: folder_name })
    end

    docs = docs.order(updated_at: :desc).limit(15)

    if docs.empty?
      return ephemeral_response(I18n.t("discord.commands.docs.none"))
    end

    lines = docs.map do |d|
      folder_label = d.folder ? "[#{d.folder.name}] " : ""
      updated      = "<t:#{d.updated_at.to_i}:D>"
      "**#{d.id}.** #{folder_label}#{d.title} — updated #{updated}"
    end

    embed = {
      title:       I18n.t("discord.commands.docs.list_title", guild: @guild.name),
      description: lines.join("\n"),
      color:       0x5865F2,
      footer:      { text: "Use /docs view doc_id:<id> to preview a document" }
    }

    embed_response(embed, ephemeral: true)
  end

  def handle_view
    opts   = subcommand_options(@interaction)
    doc_id = opts["doc_id"].to_i

    doc = visible_docs.find_by(id: doc_id)
    return ephemeral_response(I18n.t("discord.commands.docs.not_found")) unless doc

    raw_content = doc.respond_to?(:content) ? doc.content : nil
    plain = extract_plain_text(raw_content).presence || "_No content_"
    truncated = plain.truncate(PREVIEW_CHARS)

    embed = {
      title:       doc.title,
      description: truncated,
      color:       0x5865F2,
      footer:      { text: I18n.t("discord.commands.docs.preview_footer") }
    }

    embed_response(embed, ephemeral: true)
  end

  def handle_search
    opts  = subcommand_options(@interaction)
    query = opts["query"].to_s.strip

    return ephemeral_response(I18n.t("discord.commands.errors.generic")) if query.blank?

    docs = visible_docs.where("title ILIKE ?", "%#{query}%").order(updated_at: :desc).limit(10)

    if docs.empty?
      return ephemeral_response(I18n.t("discord.commands.docs.search_none", query: query))
    end

    lines = docs.map { |d| "**#{d.id}.** #{d.title}" }

    embed = {
      title:       "Search results for \"#{query}\"",
      description: lines.join("\n"),
      color:       0x5865F2,
      footer:      { text: "Use /docs view doc_id:<id> to preview" }
    }

    embed_response(embed, ephemeral: true)
  end
end
