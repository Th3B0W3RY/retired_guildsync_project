# frozen_string_literal: true

module Admin
  class HomepageFeatureCardsController < BaseController
    include Admin::TurboDashboardFrame

    before_action :set_homepage_feature_card, only: [ :edit, :update, :destroy ]

    def index
      @recovery_status = params[:recovery_status].presence_in(%w[active deleted all]) || "active"
      @homepage_feature_cards =
        case @recovery_status
        when "deleted" then HomepageFeatureCard.with_deleted.deleted.ordered
        when "all" then HomepageFeatureCard.with_deleted.ordered
        else HomepageFeatureCard.ordered
        end
      return if respond_with_dashboard_frame(:index_frame)
    end

    def new
      @homepage_feature_card = HomepageFeatureCard.new(visible: true, position: next_position, icon_key: HomepageFeatureCard::ICON_KEYS.first)
      return if respond_with_dashboard_frame(:new_frame)
    end

    def create
      @homepage_feature_card = HomepageFeatureCard.new(admin_params.merge(position: next_position))
      if @homepage_feature_card.save
        log_admin_action(action: "create_homepage_feature_card", changes_data: { id: @homepage_feature_card.id, slug: @homepage_feature_card.slug })
        redirect_to admin_homepage_feature_cards_path, notice: t("admin.homepage_feature_cards.created")
      else
        flash.now[:alert] = @homepage_feature_card.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      return if respond_with_dashboard_frame(:edit_frame)
    end

    def update
      if @homepage_feature_card.update(admin_params)
        log_admin_action(action: "update_homepage_feature_card", changes_data: { id: @homepage_feature_card.id, slug: @homepage_feature_card.slug })
        redirect_to admin_homepage_feature_cards_path, notice: t("admin.homepage_feature_cards.updated")
      else
        flash.now[:alert] = @homepage_feature_card.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      slug = @homepage_feature_card.slug
      id = @homepage_feature_card.id
      @homepage_feature_card.soft_delete!
      log_admin_action(action: "destroy_homepage_feature_card", changes_data: { id: id, slug: slug, soft_delete: true })
      redirect_to admin_homepage_feature_cards_path, notice: t("admin.homepage_feature_cards.destroyed")
    end

    # POST /admin/homepage-feature-cards/upload_image
    # Admin-only image upload for feature detail pages; stored via Active Storage (S3 in production).
    def upload_image
      file = params[:image] || params["image"] || params[:file] || params["file"]
      file = decode_base64_image(params[:image_data]) if file.blank? && params[:image_data].to_s.strip.start_with?("data:")

      if file.blank?
        render json: { error: "Please choose an image to upload." }, status: :unprocessable_entity
        return
      end

      # Validate MIME type and file size before attaching to avoid orphaned blobs.
      content_type, byte_size = if file.is_a?(Hash)
        [file[:content_type] || file["content_type"], nil]
      else
        [file.respond_to?(:content_type) ? file.content_type : nil,
         file.respond_to?(:size) ? file.size : nil]
      end
      allowed_types = %w[image/jpeg image/jpg image/png image/gif image/webp]
      if content_type.present? && !allowed_types.include?(content_type.to_s.downcase.strip)
        render json: { error: "Image must be JPEG, PNG, GIF, or WebP" }, status: :unprocessable_entity
        return
      end
      max_bytes = 10 * 1024 * 1024
      if byte_size.present? && byte_size > max_bytes
        render json: { error: "Image must be under 10MB" }, status: :unprocessable_entity
        return
      end

      record = HomepageFeatureCardImage.new
      if file.is_a?(Hash)
        record.image.attach(**file.symbolize_keys)
      else
        record.image.attach(file)
      end

      if record.save
        url = record.public_url.presence ||
              (record.image.attached? ? Rails.application.routes.url_helpers.rails_blob_path(record.image, only_path: true) : nil)
        render json: { url: url }
      else
        record.image.purge if record.image.attached?
        render json: { error: record.errors.full_messages.to_sentence.presence || "Image upload failed." }, status: :unprocessable_entity
      end
    rescue ArgumentError, ActiveSupport::MessageVerifier::InvalidSignature => e
      Rails.logger.warn("Admin::HomepageFeatureCardsController#upload_image invalid_data: #{e.message}")
      render json: { error: "Invalid image data." }, status: :unprocessable_entity
    rescue StandardError => e
      Rails.logger.error("Admin::HomepageFeatureCardsController#upload_image: #{e.class} - #{e.message}")
      payload = { error: "Image upload failed." }
      msg = e.message.to_s.strip
      payload[:error_detail] = "#{e.class.name}: #{msg.truncate(180)}" if msg.present?
      render json: payload, status: :unprocessable_entity
    end

    def reorder
      ids = Array(params[:order]).map(&:to_i).reject(&:zero?)
      unless complete_reorder_payload?(ids)
        head :unprocessable_entity
        return
      end

      HomepageFeatureCard.transaction do
        ids.each_with_index do |id, idx|
          HomepageFeatureCard.with_deleted.where(id: id).update_all(position: idx)
        end
      end
      head :ok
    end

    private

    def set_homepage_feature_card
      raw = params[:id].to_s.strip
      scope = HomepageFeatureCard.with_deleted
      @homepage_feature_card =
        if raw.match?(/\A\d+\z/)
          scope.find_by(id: raw.to_i) || scope.find_by(slug: raw.downcase)
        else
          scope.find_by(slug: raw.downcase)
        end
      raise ActiveRecord::RecordNotFound if @homepage_feature_card.blank?
    end

    def admin_params
      params.require(:homepage_feature_card).permit(:slug, :title, :description, :icon_key, :visible, :body)
    end

    def next_position
      (HomepageFeatureCard.with_deleted.maximum(:position) || -1) + 1
    end

    def complete_reorder_payload?(ids)
      expected_ids = HomepageFeatureCard.active.order(:id).pluck(:id)
      ids.uniq.length == expected_ids.length && ids.sort == expected_ids
    end

    def decode_base64_image(data_url)
      return nil if data_url.blank?
      prefix, b64 = data_url.to_s.split(",", 2)
      return nil unless prefix&.include?("base64") && b64.present?

      mime = prefix.to_s[/data:(.*?);base64/, 1].to_s.downcase
      ext = case mime
      when "image/jpeg", "image/jpg" then "jpg"
      when "image/png" then "png"
      when "image/gif" then "gif"
      when "image/webp" then "webp"
      else
        raise ArgumentError, "Unsupported image MIME type: #{mime}"
      end

      decoded = Base64.decode64(b64)
      io = StringIO.new(decoded)
      { io: io, filename: "homepage-feature-#{SecureRandom.hex(8)}.#{ext}", content_type: mime }
    end

  end
end
