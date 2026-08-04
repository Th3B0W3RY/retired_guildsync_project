# frozen_string_literal: true

require "rails_helper"
require "aws-sdk-s3"

RSpec.describe DatabaseBackupToS3Service do
  describe ".enabled?" do
    it "is true only when DATABASE_BACKUP_TO_S3_ENABLED is 1" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("DATABASE_BACKUP_TO_S3_ENABLED").and_return("1")
      expect(described_class.enabled?).to be true
    end

    it "is false when unset" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("DATABASE_BACKUP_TO_S3_ENABLED").and_return(nil)
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
        allow_any_instance_of(described_class).to receive(:backup_bucket_name).and_return("")
        r = described_class.new.call
        expect(r[:ok]).to be false
        expect(r[:error]).to include("No S3 bucket")
      end

      it "returns error when S3 credentials are missing" do
        allow_any_instance_of(described_class).to receive(:backup_bucket_name).and_return("my-bucket")
        allow_any_instance_of(described_class).to receive(:s3_credentials).and_return({ ok: false })
        r = described_class.new.call
        expect(r[:ok]).to be false
        expect(r[:error]).to include("credentials")
      end

      it "returns error when pg_dump fails" do
        allow_any_instance_of(described_class).to receive(:backup_bucket_name).and_return("my-bucket")
        allow_any_instance_of(described_class).to receive(:s3_credentials).and_return(
          { ok: true, access_key_id: "a", secret_access_key: "b" }
        )
        allow_any_instance_of(described_class).to receive(:object_key).and_return("database_backups/x.dump")
        allow_any_instance_of(described_class).to receive(:run_pg_dump).and_return(false)
        r = described_class.new.call
        expect(r[:ok]).to be false
        expect(r[:error]).to include("pg_dump")
      end

      it "returns ok and key when dump and S3 upload succeed" do
        allow_any_instance_of(described_class).to receive(:backup_bucket_name).and_return("my-bucket")
        allow_any_instance_of(described_class).to receive(:s3_credentials).and_return(
          { ok: true, access_key_id: "a", secret_access_key: "b" }
        )
        allow_any_instance_of(described_class).to receive(:object_key).and_return("database_backups/guildsync-test.dump")
        allow_any_instance_of(described_class).to receive(:run_pg_dump).and_return(true)
        client = instance_double(Aws::S3::Client)
        allow(Aws::S3::Client).to receive(:new).and_return(client)
        allow(client).to receive(:put_object)
        allow(File).to receive(:binread).and_return("fake-dump-bytes")

        expect(Rails.cache).to receive(:write).with(
          described_class::LAST_SUCCESS_CACHE_KEY,
          hash_including("s3_key" => "database_backups/guildsync-test.dump", "finished_at" => kind_of(String)),
          hash_including(expires_in: 10.years)
        )

        r = described_class.new.call
        expect(r[:ok]).to be true
        expect(r[:disabled]).to be false
        expect(r[:key]).to eq("database_backups/guildsync-test.dump")
        expect(client).to have_received(:put_object).with(
          hash_including(bucket: "my-bucket", key: "database_backups/guildsync-test.dump")
        )
      end
    end
  end

  describe ".list_recent_backups" do
    it "returns empty non-failed when disabled" do
      allow(described_class).to receive(:enabled?).and_return(false)
      r = described_class.list_recent_backups
      expect(r.entries).to eq([])
      expect(r.failed).to be false
      expect(r.truncated).to be false
      expect(r.next_continuation_token).to be_nil
    end

    context "when enabled" do
      before { allow(described_class).to receive(:enabled?).and_return(true) }

      it "returns empty when bucket is missing" do
        allow_any_instance_of(described_class).to receive(:backup_bucket_name).and_return("")
        r = described_class.list_recent_backups
        expect(r.entries).to eq([])
        expect(r.failed).to be false
      end

      it "returns empty when credentials are missing" do
        allow_any_instance_of(described_class).to receive(:backup_bucket_name).and_return("my-bucket")
        allow_any_instance_of(described_class).to receive(:s3_credentials).and_return({ ok: false })
        r = described_class.list_recent_backups
        expect(r.entries).to eq([])
        expect(r.failed).to be false
      end

      it "sorts by last_modified descending" do
        allow_any_instance_of(described_class).to receive(:backup_bucket_name).and_return("my-bucket")
        allow_any_instance_of(described_class).to receive(:s3_credentials).and_return(
          { ok: true, access_key_id: "a", secret_access_key: "b" }
        )
        allow_any_instance_of(described_class).to receive(:backup_prefix).and_return("database_backups/")
        t_old = Time.utc(2025, 1, 1)
        t_new = Time.utc(2026, 1, 1)
        o_old = instance_double(Aws::S3::Types::Object, key: "database_backups/a.dump", size: 10, last_modified: t_old)
        o_new = instance_double(Aws::S3::Types::Object, key: "database_backups/b.dump", size: 20, last_modified: t_new)
        client = instance_double(Aws::S3::Client)
        allow(Aws::S3::Client).to receive(:new).and_return(client)
        resp = instance_double(Aws::S3::Types::ListObjectsV2Output, contents: [ o_old, o_new ], is_truncated: false)
        allow(client).to receive(:list_objects_v2).with(
          hash_including(bucket: "my-bucket", prefix: "database_backups/", max_keys: 50)
        ).and_return(resp)

        r = described_class.list_recent_backups(max_keys: 50)
        expect(r.failed).to be false
        expect(r.truncated).to be false
        expect(r.entries.map { |h| h[:key] }).to eq([ "database_backups/b.dump", "database_backups/a.dump" ])
        expect(r.entries.first[:size]).to eq(20)
        expect(r.next_continuation_token).to be_nil
      end

      it "passes continuation_token to list_objects_v2" do
        allow_any_instance_of(described_class).to receive(:backup_bucket_name).and_return("my-bucket")
        allow_any_instance_of(described_class).to receive(:s3_credentials).and_return(
          { ok: true, access_key_id: "a", secret_access_key: "b" }
        )
        allow_any_instance_of(described_class).to receive(:backup_prefix).and_return("database_backups/")
        o = instance_double(Aws::S3::Types::Object, key: "database_backups/z.dump", size: 1, last_modified: Time.utc(2026, 2, 1))
        client = instance_double(Aws::S3::Client)
        allow(Aws::S3::Client).to receive(:new).and_return(client)
        resp = instance_double(Aws::S3::Types::ListObjectsV2Output, contents: [ o ], is_truncated: false, next_continuation_token: nil)
        expect(client).to receive(:list_objects_v2).with(
          bucket: "my-bucket",
          prefix: "database_backups/",
          max_keys: 10,
          continuation_token: "from-prev-page"
        ).and_return(resp)

        r = described_class.list_recent_backups(max_keys: 10, continuation_token: "from-prev-page")
        expect(r.failed).to be false
        expect(r.entries.size).to eq(1)
      end

      it "sets failed on S3 service error" do
        allow_any_instance_of(described_class).to receive(:backup_bucket_name).and_return("my-bucket")
        allow_any_instance_of(described_class).to receive(:s3_credentials).and_return(
          { ok: true, access_key_id: "a", secret_access_key: "b" }
        )
        allow_any_instance_of(described_class).to receive(:backup_prefix).and_return("database_backups/")
        client = instance_double(Aws::S3::Client)
        allow(Aws::S3::Client).to receive(:new).and_return(client)
        ctx = Seahorse::Client::RequestContext.new
        allow(client).to receive(:list_objects_v2).and_raise(Aws::S3::Errors::AccessDenied.new(ctx, "denied"))

        r = described_class.list_recent_backups
        expect(r.failed).to be true
        expect(r.entries).to eq([])
      end

      it "passes truncated from S3 response" do
        allow_any_instance_of(described_class).to receive(:backup_bucket_name).and_return("my-bucket")
        allow_any_instance_of(described_class).to receive(:s3_credentials).and_return(
          { ok: true, access_key_id: "a", secret_access_key: "b" }
        )
        allow_any_instance_of(described_class).to receive(:backup_prefix).and_return("database_backups/")
        o = instance_double(Aws::S3::Types::Object, key: "database_backups/x.dump", size: 1, last_modified: Time.utc(2026, 1, 1))
        client = instance_double(Aws::S3::Client)
        allow(Aws::S3::Client).to receive(:new).and_return(client)
        resp = instance_double(
          Aws::S3::Types::ListObjectsV2Output,
          contents: [ o ],
          is_truncated: true,
          next_continuation_token: "s3-next-token"
        )
        allow(client).to receive(:list_objects_v2).and_return(resp)

        r = described_class.list_recent_backups(max_keys: 10)
        expect(r.truncated).to be true
        expect(r.entries.size).to eq(1)
        expect(r.next_continuation_token).to eq("s3-next-token")
      end
    end
  end

  describe ".sanitize_list_continuation_token_param" do
    it "returns nil for blank" do
      expect(described_class.sanitize_list_continuation_token_param(nil)).to be_nil
      expect(described_class.sanitize_list_continuation_token_param("  ")).to be_nil
    end

    it "returns nil when over byte limit" do
      expect(described_class.sanitize_list_continuation_token_param("x" * 8193)).to be_nil
    end

    it "returns stripped token when valid" do
      expect(described_class.sanitize_list_continuation_token_param("  abc  ")).to eq("abc")
    end
  end
end
