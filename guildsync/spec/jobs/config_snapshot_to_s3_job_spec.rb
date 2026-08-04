# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConfigSnapshotToS3Job, type: :job do
  it "delegates to ConfigSnapshotToS3Service" do
    service = instance_double(ConfigSnapshotToS3Service)
    allow(ConfigSnapshotToS3Service).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_return({ ok: true, disabled: false, key: "config_snapshots/x.tar.gz", error: nil })

    described_class.perform_now

    expect(service).to have_received(:call)
  end

  it "does not raise when service reports error" do
    service = instance_double(ConfigSnapshotToS3Service)
    allow(ConfigSnapshotToS3Service).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_return({ ok: false, disabled: false, key: nil, error: "tar failed" })

    expect { described_class.perform_now }.not_to raise_error
  end
end
