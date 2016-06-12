# encoding: UTF-8
require 'pathname'

describe WinRM::FS::FileManager do
  let(:dest_dir) { subject.temp_dir }
  let(:this_file) { "C:/Users/matt/Downloads/[MS-WSMV].pdf" }
  let(:service) { winrm_connection }

  subject { WinRM::FS::FileManager.new(service) }

  context 'upload file' do
    let(:dest_file) { File.join(dest_dir, "test.pdf") }

    before(:each) do
      expect(subject.delete(dest_dir)).to be true
    end

    it 'should upload the specified file' do
      blah = Benchmark.measure do
        subject.upload(this_file, dest_file)
      end
      puts blah
    end
  end
end
