# encoding: UTF-8
require_relative '../lib/winrm-fs/core/temp_zip_file'

describe WinRM::FS::Core::TempZipFile, integration: true do
  let(:winrm_fs_dir) { File.expand_path('../lib/winrm-fs', File.dirname(__FILE__)) }
  let(:temp_zip_file_spec) { __FILE__ }
  let(:spec_helper) { File.expand_path('spec_helper.rb', File.dirname(__FILE__)) }

  subject { WinRM::FS::Core::TempZipFile.new }

  context 'temp file creation' do
    it 'should create a temp file on disk' do
      expect(File.exist?(subject.path)).to be true
      subject.delete
      expect(File.exist?(subject.path)).to be false
    end
  end

  context 'create zip' do
    it 'should raise error when file doesn not exist' do
      expect { subject.add('/etc/foo/does/not/exist') }.to raise_error
    end

    it 'should add a file to the zip' do
      subject.add(temp_zip_file_spec)
      subject.build
      expect(subject).to contain_zip_entries('spec/temp_zip_file_spec.rb')
    end

    it 'should add multiple files to the zip' do
      subject.add(temp_zip_file_spec)
      subject.add(spec_helper)
      subject.build
      expect(subject).to contain_zip_entries([
        'spec/temp_zip_file_spec.rb',
        'spec/spec_helper.rb'])
    end

    it 'should add all files in directory' do
      subject.add(winrm_fs_dir)
      subject.build
      expect(subject).to contain_zip_entries('lib/winrm-fs/exceptions.rb')
    end

    it 'should add all files in directory to the zip recursively' do
      subject = WinRM::FS::Core::TempZipFile.new(Dir.pwd, recurse_paths: true)
      subject.add(winrm_fs_dir)
      subject.build
      expect(subject).to contain_zip_entries([
        'lib/winrm-fs/exceptions.rb',
        'lib/winrm-fs/core/temp_zip_file.rb',
        'lib/winrm-fs/scripts/checksum.ps1.erb'])
    end
  end
end
