# frozen_string_literal: true

class GuildDocumentsController < ApplicationController
  include RequiresActiveGuildAccess

  before_action :authenticate_user!, except: [ :share ]
  before_action :ensure_mfa_session_flags, except: [ :share ]
  before_action :set_guild
  before_action :require_active_guild_access, except: [ :share ]
  before_action :set_document, only: [ :show, :edit, :update, :destroy, :share ]
  # Image uploads come from JS (FormData) and can legitimately miss the standard CSRF flow.
  # We still require an authenticated, MFA-verified user via other before_actions.
  skip_forgery_protection only: [ :upload_image ]
  # Skip ApplicationController before_actions for share (public/unlisted can be accessed without auth)
  skip_before_action :validate_session, only: [ :share ]
  skip_before_action :check_credentials_setup_required, only: [ :share ]
  skip_before_action :require_mfa_if_enabled, only: [ :share ]
  skip_before_action :ensure_fully_authenticated, only: [ :share ]
  before_action :require_guild_documents_plan!, except: [ :share ]
  before_action :check_permissions, except: [ :index, :show, :share ]
  before_action :check_view_permissions, only: [ :show ]
  before_action :check_share_permissions, only: [ :share ]

  # Index is accessible to anyone, but only shows documents they can view
  # No permission check needed - filtering happens in the action
  # Share page doesn't require authentication (handled in check_share_permissions)

  def index
    @folders = @guild.guild_document_folders.ordered.includes(:user)

    if can_manage_documents?(@guild)
      # Show all documents if user can manage
      @documents = @guild.guild_documents.includes(:user, :folder).order(updated_at: :desc)
    else
      # Show only documents user can view
      all_docs = @guild.guild_documents.includes(:user, :folder).order(updated_at: :desc).to_a
      @documents = all_docs.select { |doc| doc.can_view?(current_user) }
    end

    # Group documents by folder
    @documents_by_folder = @documents.group_by(&:folder_id)
    @documents_without_folder = @documents_by_folder[nil] || []
  end

  def new
    @document = @guild.guild_documents.build
    @folders = @guild.guild_document_folders.ordered
  end

  def create
    @document = @guild.guild_documents.build(document_params)
    @document.user = current_user

    # Normalize content to ensure proper Tiptap format
    normalize_content!(@document)

    if @document.save
      GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "document_created", description: "Created document \"#{@document.title}\"", subject: @document, title: @document.title)
      redirect_to guild_documents_path(@guild), notice: t('controllers.guild_documents.created')
    else
      Rails.logger.warn("Guild document create failed guild_id=#{@guild.id} user_id=#{current_user&.id} errors=#{@document.errors.full_messages.join(', ')}")
      @folders = @guild.guild_document_folders.ordered
      render :new, status: :unprocessable_entity
    end
  end

  def show
    # Already checked permissions in before_action
  end

  def edit
    # Already checked permissions in before_action
    @folders = @guild.guild_document_folders.ordered
  end

  def update
    permitted = document_params
    @document.assign_attributes(permitted)

    # Normalize content to ensure proper Tiptap format
    normalize_content!(@document)

    if @document.save
      GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "document_updated", description: "Updated document \"#{@document.title}\"", subject: @document, title: @document.title)
      redirect_to guild_document_path(@guild, @document), notice: t('controllers.guild_documents.updated')
    else
      Rails.logger.warn("Guild document update failed guild_id=#{@guild.id} user_id=#{current_user&.id} document_id=#{@document.id} errors=#{@document.errors.full_messages.join(', ')}")
      @folders = @guild.guild_document_folders.ordered
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    title = @document.title
    @document.soft_delete!
    GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "document_deleted", description: "Deleted document \"#{title}\"", title: title)
    redirect_to guild_documents_path(@guild), notice: t('controllers.guild_documents.deleted')
  end

  def share
    # Public share page - permissions checked in before_action
    # If we get here, permissions are valid
  end

  def autosave
    if params[:id].present?
      @document = @guild.guild_documents.find(params[:id])
      unless @document.can_edit?(current_user)
        render json: { error: t("api.v1.not_authorized") }, status: :forbidden
        return
      end
      content = params[:content]
      if content.is_a?(String)
        content = JSON.parse(content) rescue {}
      end
      @document.update(content: content || {})
    else
      # Create new document for autosave
      content = params[:content]
      if content.is_a?(String)
        content = JSON.parse(content) rescue {}
      end
      @document = @guild.guild_documents.build(
        title: sanitize_text_input(params[:title]).presence || "Untitled",
        content: content || {},
        visibility: :private_doc,
        user: current_user
      )
      # Generate slug before saving (even with validate: false)
      @document.generate_slug if @document.slug.blank?
      @document.save(validate: false) # Skip validations for autosave
    end

    render json: {
      success: true,
      id: @document.id,
      slug: @document.slug
    }
  rescue => e
    Rails.logger.error("Autosave error: #{e.message}")
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST upload_image: accept image file or base64 from paste; store in S3 via Active Storage; return public URL
  def upload_image
    file = params[:image] || params["image"] || params[:file] || params["file"]
    if file.blank? && params[:image_data].to_s.strip.start_with?("data:")
      # Paste: client may send base64 data URL
      file = decode_base64_image(params[:image_data])
    end

    if file.blank?
      render json: { error: t("controllers.guild_documents.upload_image.missing") }, status: :unprocessable_entity
      return
    end

    record = @guild.guild_document_images.build(user: current_user)
    if file.is_a?(Hash)
      record.image.attach(**file.symbolize_keys)
    else
      record.image.attach(file)
    end

    if record.valid? && record.save
      GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "document_image_uploaded", description: "Uploaded an image to a guild document")
      url = record.public_url
      url ||= rails_blob_url(record.image) if record.image.attached?
      render json: { url: url }
    else
      errors = record.errors.full_messages.join(", ")
      render json: { error: errors }, status: :unprocessable_entity
    end
  rescue ArgumentError, ActiveSupport::MessageVerifier::InvalidSignature => e
    Rails.logger.warn("GuildDocumentsController#upload_image invalid_data: #{e.message}")
    render json: { error: t("controllers.guild_documents.upload_image.invalid_data") }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("GuildDocumentsController#upload_image: #{e.class} - #{e.message}\n#{e.backtrace.first(10).join("\n")}")
    payload = { error: t("controllers.guild_documents.upload_image.failed") }
    # Surface storage/network error so user or support can fix (e.g. S3 bucket, credentials). Safe to expose class + short message.
    msg = e.message.to_s.strip
    payload[:error_detail] = msg if Rails.env.development? || Rails.env.test?
    payload[:error_detail] = "#{e.class.name}: #{msg.truncate(180)}" if Rails.env.production? && msg.present?
    render json: payload, status: :unprocessable_entity
  end

  def create_folder
    @folder = @guild.guild_document_folders.build(folder_params)
    @folder.user = current_user
    @folder.position = @guild.guild_document_folders.maximum(:position).to_i + 1

    if @folder.save
      GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "folder_created", description: "Created folder \"#{@folder.name}\"", subject: @folder, name: @folder.name)
      redirect_to guild_documents_path(@guild), notice: t('controllers.guild_documents.folder.created')
    else
      Rails.logger.warn("Guild document folder create failed guild_id=#{@guild.id} user_id=#{current_user&.id} errors=#{@folder.errors.full_messages.join(', ')}")
      redirect_to guild_documents_path(@guild), alert: t('controllers.guild_documents.folder.create_failed', errors: @folder.errors.full_messages.join(', '))
    end
  end

  def update_folder
    @folder = @guild.guild_document_folders.find(params[:folder_id])
    unless @folder.can_manage?(current_user)
      redirect_to guild_documents_path(@guild), alert: t('controllers.guild_documents.folder.edit_denied')
      return
    end

    if @folder.update(folder_params)
      GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "folder_updated", description: "Updated folder \"#{@folder.name}\"", subject: @folder, name: @folder.name)
      redirect_to guild_documents_path(@guild), notice: t('controllers.guild_documents.folder.updated')
    else
      redirect_to guild_documents_path(@guild), alert: t('controllers.guild_documents.folder.update_failed', errors: @folder.errors.full_messages.join(', '))
    end
  end

  def destroy_folder
    @folder = @guild.guild_document_folders.find(params[:folder_id])
    unless @folder.can_manage?(current_user)
      redirect_to guild_documents_path(@guild), alert: t('controllers.guild_documents.folder.delete_denied')
      return
    end

    name = @folder.name
    @folder.destroy
    GuildActivityLogger.log(guild: @guild, user: current_user, action_type: "folder_deleted", description: "Deleted folder \"#{name}\"", name: name)
    redirect_to guild_documents_path(@guild), notice: t('controllers.guild_documents.folder.deleted')
  end

  private

  def require_guild_documents_plan!
    return if current_user.plan_allows?(:guild_documents)

    redirect_to upgrade_pricing_path, alert: t("plan_entitlements.upgrade_required")
  end

  def ensure_mfa_session_flags
    # Ensure MFA session flags are set for authenticated users
    # This ensures the layout shows the authenticated UI
    return unless user_signed_in? && current_user.present?

    # Discord auth users - set flags if not already set
    if current_user.oauth_primary_auth?
      unless session[:mfa_verified]
        session[:mfa_verified] = true
        session[:mfa_verified_at] = Time.current.to_i
      end
      # Refresh timestamp to keep session alive
      if session[:mfa_verified] && session[:mfa_verified_at]
        verified_at = Time.at(session[:mfa_verified_at])
        if verified_at > 30.minutes.ago
          session[:mfa_verified_at] = Time.current.to_i
        end
      end
    elsif current_user.mfa_enabled? && current_user.mfa_verified?
      # MFA users - refresh timestamp if verified
      if session[:mfa_verified] && session[:mfa_verified_at]
        verified_at = Time.at(session[:mfa_verified_at])
        if verified_at > 30.minutes.ago
          session[:mfa_verified_at] = Time.current.to_i
        end
      end
    end

    # Ensure session is saved
    session.save if session.respond_to?(:save)
  end

  def set_guild
    @guild = Guild.find(params[:guild_id])
  end

  def set_document
    @document = @guild.guild_documents.find(params[:id])
  end

  def check_permissions
    unless can_manage_documents?(@guild)
      redirect_to guild_path(@guild), alert: t('controllers.guild_documents.manage_denied')
    end
  end

  def check_view_permissions
    # Public documents can be viewed by anyone
    return if @document.visibility_public_doc?

    # For private/unlisted, check permissions
    unless @document.can_view?(current_user)
      redirect_to guild_path(@guild), alert: t('controllers.guild_documents.view_denied')
    end
  end

  def check_share_permissions
    # Verify slug matches (security check)
    if params[:slug] != @document.slug
      redirect_to root_path, alert: t('controllers.guild_documents.invalid_link')
      return false
    end

    # For share page, check visibility rules
    if @document.visibility_private_doc?
      # Private docs require authentication + guild membership
      # Try current_user first (works if authenticate_user! was called)
      # Fall back to warden if needed (for cases where authenticate_user! is skipped)
      authenticated_user = current_user
      if authenticated_user.nil?
        begin
          if respond_to?(:warden) && warden.present?
            authenticated_user = warden.user(:user, run_callbacks: false)
          end
        rescue => e
          Rails.logger.debug("Error checking authentication in share: #{e.message}")
          authenticated_user = nil
        end
      end

      # If no authenticated user, redirect
      unless authenticated_user.present?
        redirect_to root_path, alert: t('controllers.guild_documents.private_document')
        return false
      end
      # Check guild membership
      unless @guild.members.include?(authenticated_user)
        redirect_to root_path, alert: t('controllers.guild_documents.private_document')
        return false
      end
    elsif @document.visibility_public_doc? || @document.visibility_unlisted_doc?
      # Public and unlisted are accessible without authentication
      # No additional checks needed
    end
    true
  end

  def document_params
    # Get raw params first to check content type
    raw_params = params.require(:guild_document)
    content_value = raw_params[:content]

    # Parse content if it's a JSON string
    parsed_content = nil
    if content_value.is_a?(String) && content_value.present?
      begin
        parsed_content = JSON.parse(content_value)
      rescue JSON::ParserError => e
        Rails.logger.warn("Failed to parse content JSON: #{e.message}")
        parsed_content = { "type" => "doc", "content" => [] }
      end
    elsif content_value.is_a?(Hash) || content_value.is_a?(ActionController::Parameters)
      # Convert ActionController::Parameters to hash if needed
      if content_value.is_a?(ActionController::Parameters)
        parsed_content = content_value.to_unsafe_h
      else
        parsed_content = content_value
      end
    elsif content_value.blank?
      parsed_content = { "type" => "doc", "content" => [] }
    else
      parsed_content = { "type" => "doc", "content" => [] }
      Rails.logger.warn("Content is unexpected type: #{content_value.class}, using default")
    end
    
    # Build new params hash with parsed content
    safe_params = {
      title: sanitize_text_input(raw_params[:title]),
      visibility: raw_params[:visibility],
      folder_id: raw_params[:folder_id],
      content: parsed_content
    }
    
    # Permit the new hash
    permitted = ActionController::Parameters.new(safe_params).permit(:title, :visibility, :folder_id, content: {})
    
    permitted
  end

  def folder_params
    permitted = params.require(:guild_document_folder).permit(:name, :color)
    sanitize_permitted_text_fields!(permitted, [:name])
  end

  def normalize_content!(document)
    # Ensure content is in proper Tiptap format
    content = document.content

    Rails.logger.info("Normalizing content. Input: #{content.inspect}, class: #{content.class}")

    # If content is nil or not a hash, set to default structure
    if content.blank? || !content.is_a?(Hash)
      Rails.logger.warn("Content is blank or not a hash, setting to default")
      document.content = { "type" => "doc", "content" => [] }
      return
    end

    # Handle both symbol and string keys - normalize to string keys (Rails JSONB standard)
    content_type = content[:type] || content["type"]
    content_data = content[:content] || content["content"]

    Rails.logger.info("Content type: #{content_type}, content_data: #{content_data.inspect}, is_array: #{content_data.is_a?(Array)}")

    # If it's an empty hash, set to default
    if content.empty? || (content.keys.length == 1 && content.keys.first.to_s == "type" && content_data.nil?)
      Rails.logger.warn("Content is empty hash, setting to default")
      document.content = { "type" => "doc", "content" => [] }
      return
    end

    # Validate structure - must have type "doc" and content array
    if content_type != "doc"
      Rails.logger.warn("Invalid content type: #{content_type}, normalizing to default")
      document.content = { "type" => "doc", "content" => [] }
      return
    end

    if !content_data.is_a?(Array)
      Rails.logger.warn("Content data is not an array: #{content_data.class}, normalizing to default")
      document.content = { "type" => "doc", "content" => [] }
      return
    end

    # Preserve the content structure but normalize keys to strings (Rails JSONB standard)
    # Deep copy the content array to preserve nested structure
    begin
      normalized_content = content_data.deep_dup
    rescue => e
      Rails.logger.warn("Error deep copying content, using original: #{e.message}")
      normalized_content = content_data
    end

    document.content = {
      "type" => "doc",
      "content" => normalized_content
    }

    Rails.logger.info("Normalized content: #{document.content.inspect}")
  end

  def decode_base64_image(data_url)
    return nil if data_url.blank?

    match = data_url.match(/\Adata:([^;]+);base64,(.+)\z/m)
    raise ArgumentError, "Invalid data URL" unless match

    content_type = match[1].strip
    base64_data = match[2]
    decoded = Base64.decode64(base64_data)
    ext = content_type.split("/").last
    ext = "png" if ext.blank?
    filename = "pasted.#{ext}"

    {
      io: StringIO.new(decoded),
      filename: filename,
      content_type: content_type
    }
  end
end
