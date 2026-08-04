# frozen_string_literal: true

require "rails_helper"

RSpec.describe DatabaseBackupToS3Job, type: :job do
  it "delegates to DatabaseBackupToS3Service" do
    service = instance_double(DatabaseBackupToS3Service)
    allow(DatabaseBackupToS3Service).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_return({ ok: true, disabled: false, key: "database_backups/x.dump", error: nil })

    described_class.perform_now

    expect(service).to have_received(:call)
  end

  it "does not raise when service reports error" do
    service = instance_double(DatabaseBackupToS3Service)
    allow(DatabaseBackupToS3Service).to receive(:new).and_return(service)
    allow(service).to receive(:call).and_return({ ok: false, disabled: false, key: nil, error: "pg_dump failed" })

    expect { described_class.perform_now }.not_to raise_error
  end
end
