# frozen_string_literal: true

require "rails_helper"

RSpec.describe ErrorBatchReport, type: :model do
  describe "validations" do
    it "is valid with all required attributes" do
      report = build(:error_batch_report)
      expect(report).to be_valid
    end

    it "requires period_start" do
      report = build(:error_batch_report, period_start: nil)
      expect(report).not_to be_valid
      expect(report.errors[:period_start]).to include("can't be blank")
    end

    it "requires period_end" do
      report = build(:error_batch_report, period_end: nil)
      expect(report).not_to be_valid
      expect(report.errors[:period_end]).to include("can't be blank")
    end
  end

  describe "#delivered?" do
    it "returns false when delivered_at is nil" do
      expect(build(:error_batch_report).delivered?).to be false
    end

    it "returns true when delivered_at is set" do
      expect(build(:error_batch_report, :delivered).delivered?).to be true
    end
  end

  describe "#duration_hours" do
    it "returns the period length in whole hours" do
      report = build(:error_batch_report, period_start: 24.hours.ago, period_end: Time.current)
      expect(report.duration_hours).to be_within(0.1).of(24.0)
    end

    it "handles fractional hours and rounds to one decimal" do
      report = build(:error_batch_report, period_start: 90.minutes.ago, period_end: Time.current)
      expect(report.duration_hours).to eq(1.5)
    end
  end

  describe "#clusters" do
    it "returns an empty array when report_data has no clusters key" do
      report = build(:error_batch_report, report_data: {})
      expect(report.clusters).to eq([])
    end

    it "returns the cluster array from report_data" do
      report = build(:error_batch_report, :with_errors)
      expect(report.clusters.size).to eq(2)
      expect(report.clusters.first["error_class"]).to eq("StandardError")
    end
  end

  describe "#summary" do
    it "returns an empty hash when report_data has no summary key" do
      report = build(:error_batch_report, report_data: {})
      expect(report.summary).to eq({})
    end

    it "returns the summary hash from report_data" do
      report = build(:error_batch_report, :with_errors)
      expect(report.summary["total"]).to eq(3)
      expect(report.summary["by_severity"]).to eq("medium" => 2, "low" => 1)
    end
  end

  describe ".recent scope" do
    it "orders reports newest-first by created_at" do
      old_report = create(:error_batch_report, created_at: 3.days.ago)
      new_report = create(:error_batch_report, created_at: 1.hour.ago)
      expect(ErrorBatchReport.recent.first).to eq(new_report)
      expect(ErrorBatchReport.recent.last).to eq(old_report)
    end
  end
end
