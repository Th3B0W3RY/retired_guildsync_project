# frozen_string_literal: true

require "rails_helper"

RSpec.describe FileCompressionJob, type: :job do
  describe "#compress_pdf" do
    it "uses tempfile paths when invoking ghostscript" do
      job = described_class.new
      file_entry = instance_double(FileEntry, id: 42, name: "report.pdf")

      attachment = double("attachment")
      input_tmp = Tempfile.new(["input", ".pdf"])
      input_tmp.write("%PDF-1.4 test")
      input_tmp.rewind

      allow(file_entry).to receive(:file).and_return(attachment)
      allow(attachment).to receive(:attached?).and_return(true)
      allow(attachment).to receive(:open).and_yield(input_tmp)
      allow(attachment).to receive(:attach) do |io:, **_kwargs|
        io.close unless io.closed?
      end
      allow(file_entry).to receive(:update)

      calls = []
      allow(job).to receive(:system) do |*args, **kwargs|
        calls << [args, kwargs]
        if args == ["which", "gs"]
          true
        elsif args.first == "gs"
          output_path = args.find { |arg| arg.start_with?("-sOutputFile=") }.delete_prefix("-sOutputFile=")
          File.binwrite(output_path, "%PDF")
          true
        else
          false
        end
      end

      job.send(:compress_pdf, file_entry)

      gs_call = calls.find { |(args, _kwargs)| args.first == "gs" }
      expect(gs_call).to be_present
      expect(gs_call.first).to include(input_tmp.path)
      expect(gs_call.first).not_to include("%PDF-1.4 test")
      expect(attachment).to have_received(:attach)
      expect(file_entry).to have_received(:update).with(size: kind_of(Integer))
    ensure
      input_tmp.close!
    end
  end
end
