# -*- encoding: utf-8 -*-
#
# Author:: Fletcher (<fnichol@nichol.ca>)
#
# Copyright (C) 2015, Fletcher Nichol
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'base64'
require 'csv'
require 'stringio'
require 'logger'
require 'winrm'

require 'winrm-fs/core/file_transporter'

describe WinRM::FS::Core::FileTransporter do
  CheckEntry = Struct.new(
    :chk_exists, :src_md5, :dst_md5, :chk_dirty, :verifies)
  DecodeEntry = Struct.new(
    :dst, :verifies, :src_md5, :dst_md5, :tmpfile, :tmpzip)

  let(:logged_output) { StringIO.new }
  let(:logger)        { Logger.new(logged_output) }

  let(:randomness)    { %w(alpha beta charlie delta).each }
  let(:id_generator)  { -> { randomness.next } }
  let(:winrm_service) { double('winrm_service', logger: logger) }
  let(:service) { double('command_executor', service: winrm_service) }
  let(:transporter) do
    WinRM::FS::Core::FileTransporter.new(
      service,
      id_generator: id_generator
    )
  end

  before { @tempfiles = [] }

  after { @tempfiles.each(&:unlink) }

  describe 'when uploading a single file' do
    let(:content)     { '.' * 12_003 }
    let(:local)       { create_tempfile('input.txt', content) }
    let(:remote)      { 'C:\\dest' }
    let(:dst)         { "#{remote}/#{File.basename(local)}" }
    let(:src_md5)     { md5sum(local) }
    let(:size)        { File.size(local) }
    let(:cmd_tmpfile) { "%TEMP%\\b64-#{src_md5}.txt" }
    let(:ps_tmpfile)  { "$env:TEMP\\b64-#{src_md5}.txt" }

    let(:upload) { transporter.upload(local, remote) }

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    def self.common_specs_for_all_single_file_types
      it 'truncates a zero-byte hash_file for check_files' do
        expect(service).to receive(:run_cmd).with(
          regexify(%(echo|set /p=>"%TEMP%\\hash-alpha.txt")))
          .and_return(cmd_output)

        upload
      end

      it 'uploads the hash_file in chunks for check_files' do
        hash = outdent!(<<-HASH.chomp)
          @{
            "#{dst}" = "#{src_md5}"
          }
        HASH

        expect(service).to receive(:run_cmd)
          .with(%(echo #{base64(hash)} >> "%TEMP%\\hash-alpha.txt"))
          .and_return(cmd_output).once

        upload
      end

      it 'sets hash_file and runs the check_files powershell script' do
        expect(service).to receive(:run_powershell_script).with(
          regexify(%($hash_file = "$env:TEMP\\hash-alpha.txt")) &&
            regexify(
              'Check-Files (Invoke-Input $hash_file) | ' \
              'ConvertTo-Csv -NoTypeInformation')
        ).and_return(check_output)

        upload
      end
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

    # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    def self.common_specs_for_all_single_dirty_file_types
      it 'truncates a zero-byte tempfile' do
        expect(service).to receive(:run_cmd).with(
          regexify(%(echo|set /p=>"#{cmd_tmpfile}"))
        ).and_return(cmd_output)

        upload
      end

      it 'ploads the file in 8k chunks' do
        expect(service).to receive(:run_cmd)
          .with(%(echo #{base64('.' * 6000)} >> "#{cmd_tmpfile}"))
          .and_return(cmd_output).twice
        expect(service).to receive(:run_cmd)
          .with(%(echo #{base64('.' * 3)} >> "#{cmd_tmpfile}"))
          .and_return(cmd_output).once

        upload
      end

      describe 'with a small file' do
        let(:content) { 'hello, world' }

        it 'uploads the file in base64 encoding' do
          expect(service).to receive(:run_cmd)
            .with(%(echo #{base64(content)} >> "#{cmd_tmpfile}"))
            .and_return(cmd_output)

          upload
        end
      end

      it 'truncates a zero-byte hash_file for decode_files' do
        expect(service).to receive(:run_cmd).with(
          regexify(%(echo|set /p=>"%TEMP%\\hash-beta.txt"))
        ).and_return(cmd_output)

        upload
      end

      it 'uploads the hash_file in chunks for decode_files' do
        hash = outdent!(<<-HASH.chomp)
          @{
            "#{ps_tmpfile}" = @{
              "dst" = "#{dst}"
            }
          }
        HASH

        expect(service).to receive(:run_cmd)
          .with(%(echo #{base64(hash)} >> "%TEMP%\\hash-beta.txt"))
          .and_return(cmd_output).once

        upload
      end

      it 'sets hash_file and runs the decode_files powershell script' do
        expect(service).to receive(:run_powershell_script).with(
          regexify(%($hash_file = "$env:TEMP\\hash-beta.txt")) &&
            regexify(
              'Decode-Files (Invoke-Input $hash_file) | ' \
              'ConvertTo-Csv -NoTypeInformation')
        ).and_return(check_output)

        upload
      end
    end
    # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

    describe 'for a new file' do
      # let(:check_output) do
      def check_output
        create_check_output([
          CheckEntry.new('False', src_md5, nil, 'True', 'False')
        ])
      end

      let(:cmd_output) do
        o = ::WinRM::Output.new
        o[:exitcode] = 0
        o
      end

      # let(:decode_output) do
      def decode_output
        create_decode_output([
          DecodeEntry.new(dst, 'True', src_md5, src_md5, ps_tmpfile, nil)
        ])
      end

      before do
        allow(service).to receive(:run_cmd)
          .and_return(cmd_output)

        allow(service).to receive(:run_powershell_script)
          .with(/^Check-Files .+ \| ConvertTo-Csv/)
          .and_return(check_output)

        allow(service).to receive(:run_powershell_script)
          .with(/^Decode-Files .+ \| ConvertTo-Csv/)
          .and_return(decode_output)
      end

      common_specs_for_all_single_file_types

      common_specs_for_all_single_dirty_file_types

      it 'returns a report hash' do
        expect(upload[1]).to eq(
          src_md5 => {
            'src'         => local,
            'dst'         => dst,
            'tmpfile'     => ps_tmpfile,
            'tmpzip'      => nil,
            'src_md5'     => src_md5,
            'dst_md5'     => src_md5,
            'chk_exists'  => 'False',
            'chk_dirty'   => 'True',
            'verifies'    => 'True',
            'size'        => size,
            'xfered'      => size / 3 * 4,
            'chunks'      => (size / 6000.to_f).ceil
          }
        )
      end

      describe 'when a failed check command is returned' do
        def check_output
          o = ::WinRM::Output.new
          o[:exitcode] = 10
          o[:data].concat([{ stderr: 'Oh noes\n' }])
          o
        end

        it 'raises a FileTransporterFailed error' do
          expect { upload }.to raise_error(
            WinRM::FS::Core::FileTransporterFailed, /Upload failed \(exitcode: 10\)/)
        end
      end

      describe 'when a failed decode command is returned' do
        def decode_output
          o = ::WinRM::Output.new
          o[:exitcode] = 10
          o[:data].concat([{ stderr: 'Oh noes\n' }])
          o
        end

        it 'raises a FileTransporterFailed error' do
          expect { upload }.to raise_error(
            WinRM::FS::Core::FileTransporterFailed, /Upload failed \(exitcode: 10\)/)
        end
      end
    end

    describe 'for an out of date (dirty) file' do
      let(:check_output) do
        create_check_output([
          CheckEntry.new('True', src_md5, 'aabbcc', 'True', 'False')
        ])
      end

      let(:cmd_output) do
        o = ::WinRM::Output.new
        o[:exitcode] = 0
        o
      end

      let(:decode_output) do
        create_decode_output([
          DecodeEntry.new(dst, 'True', src_md5, src_md5, ps_tmpfile, nil)
        ])
      end

      before do
        allow(service).to receive(:run_cmd)
          .and_return(cmd_output)

        allow(service).to receive(:run_powershell_script)
          .with(/^Check-Files .+ \| ConvertTo-Csv/)
          .and_return(check_output)

        allow(service).to receive(:run_powershell_script)
          .with(/^Decode-Files .+ \| ConvertTo-Csv/)
          .and_return(decode_output)
      end

      common_specs_for_all_single_file_types

      common_specs_for_all_single_dirty_file_types

      it 'returns a report hash' do
        expect(upload[1]).to eq(
          src_md5 => {
            'src'         => local,
            'dst'         => dst,
            'tmpfile'     => ps_tmpfile,
            'tmpzip'      => nil,
            'src_md5'     => src_md5,
            'dst_md5'     => src_md5,
            'chk_exists'  => 'True',
            'chk_dirty'   => 'True',
            'verifies'    => 'True',
            'size'        => size,
            'xfered'      => size / 3 * 4,
            'chunks'      => (size / 6000.to_f).ceil
          }
        )
      end
    end

    describe 'for an up to date (clean) file' do
      let(:check_output) do
        create_check_output([
          CheckEntry.new('True', src_md5, src_md5, 'False', 'True')
        ])
      end

      let(:cmd_output) do
        o = ::WinRM::Output.new
        o[:exitcode] = 0
        o
      end

      before do
        allow(service).to receive(:run_cmd)
          .and_return(cmd_output)

        allow(service).to receive(:run_powershell_script)
          .with(/^Check-Files .+ \| ConvertTo-Csv/)
          .and_return(check_output)
      end

      common_specs_for_all_single_file_types

      it 'uploads nothing' do
        expect(service).not_to receive(:run_cmd).with(/#{remote}/)

        upload
      end

      it 'skips the decode_files powershell script' do
        expect(service).not_to receive(:run_powershell_script).with(regexify(
            'Decode-Files $files | ConvertTo-Csv -NoTypeInformation')
        )

        upload
      end

      it 'returns a report hash' do
        expect(upload[1]).to eq(
          src_md5 => {
            'src'         => local,
            'dst'         => dst,
            'size'        => size,
            'src_md5'     => src_md5,
            'dst_md5'     => src_md5,
            'chk_exists'  => 'True',
            'chk_dirty'   => 'False',
            'verifies'    => 'True'
          }
        )
      end
    end
  end

  describe 'when uploading a single directory' do
    let(:content)     { "I'm a fake zip file" }
    let(:local)       { Dir.mktmpdir('input') }
    let(:remote)      { 'C:\\dest' }
    let(:src_zip)     { create_tempfile('fake.zip', content) }
    let(:dst)         { remote }
    let(:src_md5)     { md5sum(src_zip) }
    let(:size)        { File.size(src_zip) }
    let(:cmd_tmpfile) { "%TEMP%\\b64-#{src_md5}.txt" }
    let(:ps_tmpfile)  { "$env:TEMP\\b64-#{src_md5}.txt" }
    let(:ps_tmpzip)   { "$env:TEMP\\winrm-upload\\tmpzip-#{src_md5}.zip" }

    let(:tmp_zip) { double('tmp_zip') }

    let(:cmd_output) do
      o = ::WinRM::Output.new
      o[:exitcode] = 0
      o
    end

    let(:check_output) do
      create_check_output([
        CheckEntry.new('False', src_md5, nil, 'True', 'False')
      ])
    end

    let(:decode_output) do
      create_decode_output([
        DecodeEntry.new(dst, 'True', src_md5, src_md5, ps_tmpfile, ps_tmpzip)
      ])
    end

    before do
      allow(tmp_zip).to receive(:path).and_return(Pathname(src_zip))
      allow(tmp_zip).to receive(:unlink)
      allow(WinRM::FS::Core::TmpZip).to receive(:new).with("#{local}/", logger)
        .and_return(tmp_zip)

      allow(service).to receive(:run_cmd)
        .and_return(cmd_output)

      allow(service).to receive(:run_powershell_script)
        .with(/^Check-Files .+ \| ConvertTo-Csv/)
        .and_return(check_output)

      allow(service).to receive(:run_powershell_script)
        .with(/^Decode-Files .+ \| ConvertTo-Csv/)
        .and_return(decode_output)
    end

    after do
      FileUtils.rm_rf(local)
    end

    let(:upload) { transporter.upload("#{local}/", remote) }

    it 'truncates a zero-byte hash_file for check_files' do
      expect(service).to receive(:run_cmd).with(regexify(%(echo|set /p=>"%TEMP%\\hash-alpha.txt"))
      ).and_return(cmd_output)

      upload
    end

    it 'uploads the hash_file in chunks for check_files' do
      hash = outdent!(<<-HASH.chomp)
        @{
          "#{ps_tmpzip}" = "#{src_md5}"
        }
      HASH

      expect(service).to receive(:run_cmd)
        .with(%(echo #{base64(hash)} >> "%TEMP%\\hash-alpha.txt"))
        .and_return(cmd_output).once

      upload
    end

    it 'sets hash_file and runs the check_files powershell script' do
      expect(service).to receive(:run_powershell_script).with(
        regexify(%($hash_file = "$env:TEMP\\hash-alpha.txt")) &&
          regexify(
            'Check-Files (Invoke-Input $hash_file) | ' \
            'ConvertTo-Csv -NoTypeInformation')
      ).and_return(check_output)

      upload
    end

    it 'truncates a zero-byte tempfile' do
      expect(service).to receive(:run_cmd).with(regexify(%(echo|set /p=>"#{cmd_tmpfile}"))
      ).and_return(cmd_output)

      upload
    end

    it 'uploads the zip file in base64 encoding' do
      expect(service).to receive(:run_cmd)
        .with(%(echo #{base64(content)} >> "#{cmd_tmpfile}"))
        .and_return(cmd_output)

      upload
    end

    it 'truncates a zero-byte hash_file for decode_files' do
      expect(service).to receive(:run_cmd).with(regexify(%(echo|set /p=>"%TEMP%\\hash-beta.txt"))
      ).and_return(cmd_output)

      upload
    end

    it 'uploads the hash_file in chunks for decode_files' do
      hash = outdent!(<<-HASH.chomp)
        @{
          "#{ps_tmpfile}" = @{
            "dst" = "#{dst}\\#{File.basename(local)}";
            "tmpzip" = "#{ps_tmpzip}"
          }
        }
      HASH

      expect(service).to receive(:run_cmd)
        .with(%(echo #{base64(hash)} >> "%TEMP%\\hash-beta.txt"))
        .and_return(cmd_output).once

      upload
    end

    it 'sets hash_file and runs the decode_files powershell script' do
      expect(service).to receive(:run_powershell_script).with(
        regexify(%($hash_file = "$env:TEMP\\hash-beta.txt")) &&
          regexify(
            'Decode-Files (Invoke-Input $hash_file) | ' \
            'ConvertTo-Csv -NoTypeInformation')
      ).and_return(check_output)

      upload
    end

    it 'returns a report hash' do
      expect(upload[1]).to eq(
        src_md5 => {
          'src'         => "#{local}/",
          'src_zip'     => src_zip,
          'dst'         => dst,
          'tmpfile'     => ps_tmpfile,
          'tmpzip'      => ps_tmpzip,
          'src_md5'     => src_md5,
          'dst_md5'     => src_md5,
          'chk_exists'  => 'False',
          'chk_dirty'   => 'True',
          'verifies'    => 'True',
          'size'        => size,
          'xfered'      => size / 3 * 4,
          'chunks'      => (size / 6000.to_f).ceil
        }
      )
    end

    it 'cleans up the zip file' do
      expect(tmp_zip).to receive(:unlink)

      upload
    end

    describe 'when a failed check command is returned' do
      def check_output
        o = ::WinRM::Output.new
        o[:exitcode] = 10
        o[:data].concat([{ stderr: 'Oh noes\n' }])
        o
      end

      it 'raises a FileTransporterFailed error' do
        expect { upload }.to raise_error(
          WinRM::FS::Core::FileTransporterFailed, /Upload failed \(exitcode: 10\)/)
      end
    end

    describe 'when a failed decode command is returned' do
      def decode_output
        o = ::WinRM::Output.new
        o[:exitcode] = 10
        o[:data].concat([{ stderr: 'Oh noes\n' }])
        o
      end

      it 'raises a FileTransporterFailed error' do
        expect { upload }.to raise_error(
          WinRM::FS::Core::FileTransporterFailed, /Upload failed \(exitcode: 10\)/)
      end
    end
  end

  describe 'when uploading multiple files' do
    let(:remote) { 'C:\\Program Files' }

    1.upto(3).each do |i|
      let(:"local#{i}") { create_tempfile("input#{i}.txt", "input#{i}") }
      let(:"src#{i}_md5") { md5sum(send("local#{i}")) }
      let(:"dst#{i}") { "#{remote}/#{File.basename(send("local#{i}"))}" }
      let(:"size#{i}") { File.size(send("local#{i}")) }
      let(:"cmd#{i}_tmpfile") { "%TEMP%\\b64-#{send("src#{i}_md5")}.txt" }
      let(:"ps#{i}_tmpfile") { "$env:TEMP\\b64-#{send("src#{i}_md5")}.txt" }
    end

    let(:check_output) do
      create_check_output([
        # new
        CheckEntry.new('False', src1_md5, nil, 'True', 'False'),
        # out-of-date
        CheckEntry.new('True', src2_md5, 'aabbcc', 'True', 'False'),
        # current
        CheckEntry.new('True', src3_md5, src3_md5, 'False', 'True')
      ])
    end

    let(:cmd_output) do
      o = ::WinRM::Output.new
      o[:exitcode] = 0
      o
    end

    let(:decode_output) do
      create_decode_output([
        DecodeEntry.new(dst1, 'True', src1_md5, src1_md5, ps1_tmpfile, nil),
        DecodeEntry.new(dst2, 'True', src2_md5, src2_md5, ps2_tmpfile, nil)
      ])
    end

    let(:upload) { transporter.upload([local1, local2, local3], remote) }

    before do
      allow(service).to receive(:run_cmd)
        .and_return(cmd_output)

      allow(service).to receive(:run_powershell_script)
        .with(/^Check-Files .+ \| ConvertTo-Csv/)
        .and_return(check_output)

      allow(service).to receive(:run_powershell_script)
        .with(/^Decode-Files .+ \| ConvertTo-Csv/)
        .and_return(decode_output)
    end

    it 'truncates a zero-byte hash_file for check_files' do
      expect(service).to receive(:run_cmd).with(regexify(%(echo|set /p=>"%TEMP%\\hash-alpha.txt"))
      ).and_return(cmd_output)

      upload
    end

    it 'uploads the hash_file in chunks for check_files' do
      hash = outdent!(<<-HASH.chomp)
        @{
          "#{dst1}" = "#{src1_md5}";
          "#{dst2}" = "#{src2_md5}";
          "#{dst3}" = "#{src3_md5}"
        }
      HASH

      expect(service).to receive(:run_cmd)
        .with(%(echo #{base64(hash)} >> "%TEMP%\\hash-alpha.txt"))
        .and_return(cmd_output).once

      upload
    end

    it 'sets hash_file and runs the check_files powershell script' do
      expect(service).to receive(:run_powershell_script).with(
        regexify(%($hash_file = "$env:TEMP\\hash-alpha.txt")) &&
          regexify(
            'Check-Files (Invoke-Input $hash_file) | ' \
            'ConvertTo-Csv -NoTypeInformation')
      ).and_return(check_output)

      upload
    end

    it 'only uploads dirty files' do
      expect(service).to receive(:run_cmd)
        .with(%(echo #{base64(IO.read(local1))} >> "#{cmd1_tmpfile}"))
      expect(service).to receive(:run_cmd)
        .with(%(echo #{base64(IO.read(local2))} >> "#{cmd2_tmpfile}"))
      expect(service).not_to receive(:run_cmd)
        .with(%(echo #{base64(IO.read(local3))} >> "#{cmd3_tmpfile}"))

      upload
    end

    it 'truncates a zero-byte hash_file for decode_files' do
      expect(service).to receive(:run_cmd).with(regexify(%(echo|set /p=>"%TEMP%\\hash-beta.txt"))
      ).and_return(cmd_output)

      upload
    end

    it 'uploads the hash_file in chunks for decode_files' do
      hash = outdent!(<<-HASH.chomp)
        @{
          "#{ps1_tmpfile}" = @{
            "dst" = "#{dst1}"
          };
          "#{ps2_tmpfile}" = @{
            "dst" = "#{dst2}"
          }
        }
      HASH

      expect(service).to receive(:run_cmd)
        .with(%(echo #{base64(hash)} >> "%TEMP%\\hash-beta.txt"))
        .and_return(cmd_output).once

      upload
    end

    it 'sets hash_file and runs the decode_files powershell script' do
      expect(service).to receive(:run_powershell_script).with(
        regexify(%($hash_file = '$env:TEMP\\hash-beta.txt')) &&
          regexify(
            'Decode-Files (Invoke-Input $hash_file) | ' \
            'ConvertTo-Csv -NoTypeInformation')
      ).and_return(check_output)

      upload
    end

    it 'returns a report hash' do
      report = upload[1]

      expect(report.fetch(src1_md5)).to eq(
        'src'         => local1,
        'dst'         => dst1,
        'tmpfile'     => ps1_tmpfile,
        'tmpzip'      => nil,
        'src_md5'     => src1_md5,
        'dst_md5'     => src1_md5,
        'chk_exists'  => 'False',
        'chk_dirty'   => 'True',
        'verifies'    => 'True',
        'size'        => size1,
        'xfered'      => size1 / 3 * 4,
        'chunks'      => (size1 / 6000.to_f).ceil
      )
      expect(report.fetch(src2_md5)).to eq(
        'src'         => local2,
        'dst'         => dst2,
        'tmpfile'     => ps2_tmpfile,
        'tmpzip'      => nil,
        'src_md5'     => src2_md5,
        'dst_md5'     => src2_md5,
        'chk_exists'  => 'True',
        'chk_dirty'   => 'True',
        'verifies'    => 'True',
        'size'        => size2,
        'xfered'      => size2 / 3 * 4,
        'chunks'      => (size2 / 6000.to_f).ceil
      )
      expect(report.fetch(src3_md5)).to eq(
        'src'         => local3,
        'dst'         => dst3,
        'src_md5'     => src3_md5,
        'dst_md5'     => src3_md5,
        'chk_exists'  => 'True',
        'chk_dirty'   => 'False',
        'verifies'    => 'True',
        'size'        => size3
      )
    end

    describe 'when a failed check command is returned' do
      def check_output
        o = ::WinRM::Output.new
        o[:exitcode] = 10
        o[:data].concat([{ stderr: "Oh noes\n" }])
        o
      end

      it 'raises a FileTransporterFailed error' do
        expect { upload }.to raise_error(
          WinRM::FS::Core::FileTransporterFailed, /Upload failed \(exitcode: 10\)/)
      end
    end

    describe 'when a failed decode command is returned' do
      def decode_output
        o = ::WinRM::Output.new
        o[:exitcode] = 10
        o[:data].concat([{ stderr: "Oh noes\n" }])
        o
      end

      it 'raises a FileTransporterFailed error' do
        expect { upload }.to raise_error(
          WinRM::FS::Core::FileTransporterFailed, /Upload failed \(exitcode: 10\)/)
      end
    end
  end

  it 'raises an exception when local file or directory is not found' do
    expect { transporter.upload('/a/b/c/nope', 'C:\\nopeland') }.to raise_error Errno::ENOENT
  end

  def base64(string)
    Base64.strict_encode64(string)
  end

  def create_check_output(entries)
    csv = CSV.generate(force_quotes: true) do |rows|
      rows << CheckEntry.new.members.map(&:to_s)
      entries.each { |entry| rows << entry.to_a }
    end

    o = ::WinRM::Output.new
    o[:exitcode] = 0
    o[:data].concat(csv.lines.map { |line| { stdout: line } })
    o
  end

  def create_decode_output(entries)
    csv = CSV.generate(force_quotes: true) do |rows|
      rows << DecodeEntry.new.members.map(&:to_s)
      entries.each { |entry| rows << entry.to_a }
    end

    o = ::WinRM::Output.new
    o[:exitcode] = 0
    o[:data].concat(csv.lines.map { |line| { stdout: line } })
    o
  end

  def create_tempfile(name, content)
    pre, _, ext = name.rpartition('.')
    file = Tempfile.open(["#{pre}-", ".#{ext}"])
    @tempfiles << file
    file.write(content)
    file.close
    file.path
  end

  def md5sum(local)
    Digest::MD5.file(local).hexdigest
  end

  def outdent!(string)
    string.gsub!(/^ {#{string.index(/[^ ]/)}}/, '')
  end

  def regexify(str, line = :whole_line)
    r = Regexp.escape(str)
    r = "^#{r}$" if line == :whole_line
    Regexp.new(r)
  end
end
