# frozen_string_literal: true

require "rails_helper"

RSpec.describe SoftDeletedRecordRegistry do
  it "lists every ApplicationRecord that includes SoftDeletable (admin recovery must cover all soft-deleted types)" do
    soft_models = ApplicationRecord.descendants.select do |model|
      next false if model.abstract_class?
      next false if model.name.blank?

      model.included_modules.include?(SoftDeletable)
    end

    expected = soft_models.map(&:name).uniq.sort
    registered = described_class::RECORD_TYPES.keys.sort

    expect(registered).to eq(expected)
  end
end
