# frozen_string_literal: true

begin
  require 'rspec/core/rake_task'

  namespace :test do
    desc "Run all specs except OCR tests (faster)"
    RSpec::Core::RakeTask.new(:fast) do |t|
      t.rspec_opts = "--tag ~ocr"
    end

    desc "Run only OCR tests"
    RSpec::Core::RakeTask.new(:ocr) do |t|
      t.rspec_opts = "--tag ocr"
    end
  end
rescue LoadError
  # RSpec not available, skip defining tasks
end

