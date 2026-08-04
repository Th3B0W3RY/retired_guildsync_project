# frozen_string_literal: true

require "rails_helper"

RSpec.describe PurgeExpiredSoftDeletedRecordsJob, type: :job do
  it "hard-deletes soft-deleted rows past the retention period" do
    poll = create(:poll)
    poll.soft_delete!
    poll.update_column(:deleted_at, SoftDeletable::RETENTION_PERIOD.ago - 1.day)

    described_class.new.perform

    expect(Poll.with_deleted.find_by(id: poll.id)).to be_nil
  end

  it "does not destroy soft-deleted rows still inside the retention period" do
    poll = create(:poll)
    poll.soft_delete!

    described_class.new.perform

    expect(Poll.with_deleted.find(poll.id)).to be_deleted
  end

  it "orders dependent types before parents (comments before requests, files before folders)" do
    job = described_class.new
    names = job.send(:ordered_registry_classes).map(&:name)
    expect(names.index("FeatureRequestComment")).to be < names.index("FeatureRequest")
    expect(names.index("FileEntry")).to be < names.index("Folder")
    expect(names.sort).to eq(SoftDeletedRecordRegistry::RECORD_TYPES.keys.sort)
  end

  it "continues after a single record destroy failure and logs" do
    poll = create(:poll)
    poll.soft_delete!
    poll.update_column(:deleted_at, SoftDeletable::RETENTION_PERIOD.ago - 1.day)

    allow_any_instance_of(Poll).to receive(:destroy!).and_raise(StandardError, "boom")

    expect(Rails.logger).to receive(:error).at_least(:once)
    expect { described_class.new.perform }.not_to raise_error
  end
end
