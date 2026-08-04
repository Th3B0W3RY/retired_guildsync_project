# frozen_string_literal: true

module LandingCompare
  class Form
    include ActiveModel::Model

    def initialize(controller_params)
      @params = controller_params
      raw = @params[:landing_compare] || @params["landing_compare"]
      @raw = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw&.to_h
    end

    def save
      return false if @raw.blank?

      (0..2).each do |pos|
        if table_bucket(pos).blank?
          errors.add(:base, I18n.t("admin.landing_compare.table_payload_missing"))
          return false
        end
      end

      ActiveRecord::Base.transaction do
        persist_section_title!
        (0..2).each { |pos| persist_table!(pos) }
      end

      true
    rescue ActiveRecord::RecordInvalid => e
      errors.add(:base, e.record.errors.full_messages.to_sentence)
      false
    rescue ActiveRecord::RecordNotFound
      errors.add(:base, I18n.t("admin.landing_compare.missing_tables"))
      false
    end

    private

    def persist_section_title!
      title = sanitize_label(@raw[:section_title] || @raw["section_title"])
      if title.blank?
        SiteSetting.find_by(key: "landing_compare_section_title")&.destroy
      else
        SiteSetting.set("landing_compare_section_title", title)
      end
    end

    def persist_table!(position)
      bucket = table_bucket(position)
      table = LandingComparisonTable.find_by(position: position)
      raise ActiveRecord::RecordNotFound, "LandingComparisonTable #{position}" unless table
      table.update!(
        feature_column_label: sanitize_label(bucket[:feature_column_label] || bucket["feature_column_label"]),
        guildsync_column_label: sanitize_label(bucket[:guildsync_column_label] || bucket["guildsync_column_label"]),
        competitor_column_label: sanitize_label(bucket[:competitor_column_label] || bucket["competitor_column_label"]),
        show_guildsync_badge: truthy?(bucket, "show_guildsync_badge")
      )

      rows_param = bucket[:rows] || bucket["rows"]
      rows_hash = normalize_rows_hash(rows_param)
      if rows_hash.size > LandingComparisonTable::MAX_ROWS
        table.errors.add(:base, I18n.t("admin.landing_compare.too_many_rows", max: LandingComparisonTable::MAX_ROWS))
        raise ActiveRecord::RecordInvalid, table
      end
      if rows_hash.empty?
        table.errors.add(:base, I18n.t("admin.landing_compare.rows_required"))
        raise ActiveRecord::RecordInvalid, table
      end

      table.landing_comparison_rows.destroy_all
      sorted_row_keys(rows_hash).each_with_index do |key, idx|
        r = rows_hash[key]
        label = sanitize_label(row_field(r, :feature_label))
        next if label.blank?

        table.landing_comparison_rows.create!(
          position: idx,
          feature_label: label,
          guildsync_included: truthy?(r, "guildsync_included"),
          competitor_included: truthy?(r, "competitor_included")
        )
      end
    end

    def table_bucket(position)
      t = @raw[:tables] || @raw["tables"]
      return nil unless t.is_a?(Hash)

      t[position.to_s] || t[position]
    end

    def normalize_rows_hash(rows_param)
      return {} if rows_param.blank?

      h = rows_param.respond_to?(:to_unsafe_h) ? rows_param.to_unsafe_h : rows_param.to_h
      h.stringify_keys
    end

    def sorted_row_keys(rows_hash)
      rows_hash.keys.sort_by { |k| k.to_s.to_i }
    end

    def row_field(row, name)
      row[name] || row[name.to_s]
    end

    def truthy?(hash, key)
      v = hash[key] || hash[key.to_sym]
      ActiveModel::Type::Boolean.new.cast(v)
    end

    def sanitize_label(str)
      stripped = ActionController::Base.helpers.strip_tags(str.to_s)
      CGI.unescapeHTML(stripped).squish.truncate(255, omission: "")
    end
  end
end
