# frozen_string_literal: true

require "rails_helper"
require "aws-sdk-s3"

RSpec.describe ConfigSnapshotToS3Service do
  describe ".enabled?" do
    it "is true only when CONFIG_SNAPSHOT_TO_S3_ENABLED is 1" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("CONFIG_SNAPSHOT_TO_S3_ENABLED").and_return("1")
      expect(described_class.enabled?).to be true
    end

    it "is false when unset" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("CONFIG_SNAPSHOT_TO_S3_ENABLED").and_return(nil)
      expect(described_class.enabled?).to be false
    end
  end

  describe "#call" do
    it "returns disabled when not enabled" do
      allow(described_class).to receive(:enabled?).and_return(false)
      r = described_class.new.call
      expect(r[:disabled]).to be true
      expect(r[:ok]).to be true
    end

    context "when enabled" do
      before { allow(described_class).to receive(:enabled?).and_return(true) }

      it "returns error when bucket is missing" do
        allow_any_instance_of(described_class).to receive(:snapshot_bucket_name).and_return("")
        r = described_class.new.call
        expect(r[:ok]).to be false
        expect(r[:error]).to include("No S3 bucket")
      end

      it "returns error when S3 credentials are missing" do
        allow_any_instance_of(described_class).to receive(:snapshot_bucket_name).and_return("my-bucket")
        allow_any_instance_of(described_class).to receive(:s3_credentials).and_return({ ok: false })
        r = described_class.new.call
        expect(r[:ok]).to be false
        expect(r[:error]).to include("credentials")
      end

      it "returns error when archive would be empty" do
        allow_any_instance_of(described_class).to receive(:snapshot_bucket_name).and_return("my-bucket")
        allow_any_instance_of(described_class).to receive(:s3_credentials).and_return(
          { ok: true, access_key_id: "a", secret_access_key: "b" }
        )
        allow_any_instance_of(described_class).to receive(:relative_paths_for_snapshot).and_return([])
        allow_any_instance_of(described_class).to receive(:build_archive_bytes).and_return("")
        r = described_class.new.call
        expect(r[:ok]).to be false
        expect(r[:error]).to include("No files collected")
      end

      it "returns ok and key when upload succeeds" do
        allow_any_instance_of(described_class).to receive(:snapshot_bucket_name).and_return("my-bucket")
        allow_any_instance_of(described_class).to receive(:s3_credentials).and_return(
          { ok: true, access_key_id: "a", secret_access_key: "b" }
        )
        allow_any_instance_of(described_class).to receive(:object_key).and_return("config_snapshots/guildsync-config-test.tar.gz")
        gzip_body = String.new("\x1f\x8b", encoding: Encoding::BINARY) + "fake"
        allow_any_instance_of(described_class).to receive(:build_archive_bytes).and_return(gzip_body)
        client = instance_double(Aws::S3::Client)
        allow(Aws::S3::Client).to receive(:new).and_return(client)
        allow(client).to receive(:put_object)

        expect(Rails.cache).to receive(:write).with(
          described_class::LAST_SUCCESS_CACHE_KEY,
          hash_including("s3_key" => "config_snapshots/guildsync-config-test.tar.gz", "finished_at" => kind_of(String)),
          hash_including(expires_in: 10.years)
        )

        r = described_class.new.call
        expect(r[:ok]).to be true
        expect(r[:disabled]).to be false
        expect(r[:key]).to eq("config_snapshots/guildsync-config-test.tar.gz")
        expect(client).to have_received(:put_object).with(
          hash_including(bucket: "my-bucket", key: "config_snapshots/guildsync-config-test.tar.gz", content_type: "application/gzip")
        )
      end
    end
  end

  describe "#relative_paths_for_snapshot" do
    it "includes schema, core config, initializer Ruby, and locale YAML files that exist" do
      svc = described_class.new
      paths = svc.send(:relative_paths_for_snapshot)
      expect(paths).to include("db/schema.rb")
      expect(paths).to include("config/routes.rb")
      expect(paths).to include("config/database.yml")
      expect(paths).to include("config/initializers/assets.rb")
      expect(paths).to include("config/locales/en/en.yml")
    end
  end

  describe "#build_archive_bytes" do
    it "produces a gzip stream with tar entries for collected files" do
      svc = described_class.new
      allow(svc).to receive(:relative_paths_for_snapshot).and_return([ "config/routes.rb", "db/schema.rb" ])
      bytes = svc.send(:build_archive_bytes)
      expect(bytes).to start_with("\x1f\x8b".b)
      expect(bytes.bytesize).to be > 100
    end
  end

  describe ".list_recent_snapshots" do
    it "returns empty when disabled" do
      allow(described_class).to receive(:enabled?).and_return(false)
      r = described_class.list_recent_snapshots
      expect(r.entries).to eq([])
      expect(r.failed).to be false
    end

    context "when enabled" do
      before { allow(described_class).to receive(:enabled?).and_return(true) }

      it "passes continuation_token to list_objects_v2" do
        allow_any_instance_of(described_class).to receive(:snapshot_bucket_name).and_return("my-bucket")
        allow_any_instance_of(described_class).to receive(:s3_credentials).and_return(
          { ok: true, access_key_id: "a", secret_access_key: "b" }
        )
        allow_any_instance_of(described_class).to receive(:snapshot_prefix).and_return("config_snapshots/")
        o = instance_double(Aws::S3::Types::Object, key: "config_snapshots/x.tar.gz", size: 1, last_modified: Time.utc(2026, 2, 1))
        client = instance_double(Aws::S3::Client)
        allow(Aws::S3::Client).to receive(:new).and_return(client)
        resp = instance_double(Aws::S3::Types::ListObjectsV2Output, contents: [ o ], is_truncated: false, next_continuation_token: nil)
        expect(client).to receive(:list_objects_v2).with(
          bucket: "my-bucket",
          prefix: "config_snapshots/",
          max_keys: 10,
          continuation_token: "prev"
        ).and_return(resp)

        r = described_class.list_recent_snapshots(max_keys: 10, continuation_token: "prev")
        expect(r.failed).to be false
        expect(r.entries.size).to eq(1)
      end

      it "returns failed on S3 service error" do
        allow_any_instance_of(described_class).to receive(:snapshot_bucket_name).and_return("my-bucket")
        allow_any_instance_of(described_class).to receive(:s3_credentials).and_return(
          { ok: true, access_key_id: "a", secret_access_key: "b" }
        )
        allow_any_instance_of(described_class).to receive(:snapshot_prefix).and_return("config_snapshots/")
        client = instance_double(Aws::S3::Client)
        allow(Aws::S3::Client).to receive(:new).and_return(client)
        ctx = Seahorse::Client::RequestContext.new
        allow(client).to receive(:list_objects_v2).and_raise(Aws::S3::Errors::AccessDenied.new(ctx, "denied"))

        r = described_class.list_recent_snapshots
        expect(r.failed).to be true
        expect(r.entries).to eq([])
      end
    end
  end
end
