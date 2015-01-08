# encoding: UTF-8
#
# Copyright 2015 Shawn Neal <sneal@sneal.net>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require_relative 'scripts/scripts'
require_relative 'core/temp_zip_file'
require_relative 'core/file_decoder'
require_relative 'core/zip_file_decoder'
require_relative 'core/file_uploader'
require_relative 'core/command_executor'

module WinRM
  module FS
    # Perform file transfer operations between a local machine and winrm endpoint
    class FileManager
      # Creates a new FileManager instance
      # @param [WinRMWebService] WinRM web service client
      def initialize(service)
        @service = service
        @logger = Logging.logger[self]
      end

      # Gets the MD5 checksum of the specified file if it exists,
      # otherwise ''
      # @param [String] The remote file path
      def checksum(path)
        @logger.debug("checksum: #{path}")
        script = WinRM::FS::Scripts.render('checksum', path: path)
        @service.powershell(script).stdout.chomp
      end

      # Create the specifed directory recursively
      # @param [String] The remote dir to create
      # @return [Boolean] True if successful, otherwise false
      def create_dir(path)
        @logger.debug("create_dir: #{path}")
        script = WinRM::FS::Scripts.render('create_dir', path: path)
        @service.powershell(script)[:exitcode] == 0
      end

      # Deletes the file or directory at the specified path
      # @param [String] The path to remove
      # @return [Boolean] True if successful, otherwise False
      def delete(path)
        @logger.debug("deleting: #{path}")
        script = WinRM::FS::Scripts.render('delete', path: path)
        @service.powershell(script)[:exitcode] == 0
      end

      # Downloads the specified remote file to the specified local path
      # @param [String] The full path on the remote machine
      # @param [String] The full path to write the file to locally
      def download(remote_path, local_path)
        @logger.debug("downloading: #{remote_path} -> #{local_path}")
        script = WinRM::FS::Scripts.render('download', path: remote_path)
        output = @service.powershell(script)
        return false if output[:exitcode] != 0
        contents = output.stdout.gsub('\n\r', '')
        out = Base64.decode64(contents)
        IO.binwrite(local_path, out)
        true
      end

      # Checks to see if the given path exists on the target file system.
      # @param [String] The full path to the directory or file
      # @return [Boolean] True if the file/dir exists, otherwise false.
      def exists?(path)
        @logger.debug("exists?: #{path}")
        script = WinRM::FS::Scripts.render('exists', path: path)
        @service.powershell(script)[:exitcode] == 0
      end

      # Gets the current user's TEMP directory on the remote system, for example
      # 'C:/Windows/Temp'
      # @return [String] Full path to the temp directory
      def temp_dir
        @guest_temp ||= (@service.cmd('echo %TEMP%')).stdout.chomp.gsub('\\', '/')
      end

      # Upload one or more local files and directories to a remote directory
      # @example copy a single directory to a winrm endpoint
      #
      #   file_manager.upload('c:/dev/my_dir', '$env:AppData')
      #
      # @example copy several paths to the winrm endpoint
      #
      #   file_manager.upload(['c:/dev/file1.txt','c:/dev/dir1'], '$env:AppData')
      #
      # @param [Array<String>] One or more paths that will be copied to the remote path.
      #   These can be files or directories to be deeply copied
      # @param [String] The target directory or file
      #   This path may contain powershell style environment variables
      # @yieldparam [Fixnum] Number of bytes copied in current payload sent to the winrm endpoint
      # @yieldparam [Fixnum] The total number of bytes to be copied
      # @yieldparam [String] Path of file being copied
      # @yieldparam [String] Target path on the winrm endpoint
      # @return [Fixnum] The total number of bytes copied
      def upload(local_paths, remote_path, &block)
        @logger.debug("uploading: #{local_paths} -> #{remote_path}")
        local_paths = [local_paths] if local_paths.is_a? String

        if FileManager.src_is_single_file?(local_paths)
          upload_file(local_paths[0], remote_path, &block)
        else
          upload_multiple_files(local_paths, remote_path, &block)
        end
      end

      private

      def upload_file(src_file, remote_path, &block)
        # If the src has a file extension and the destination does not
        # we can assume the caller specified the dest as a directory
        if File.extname(src_file) != '' && File.extname(remote_path) == ''
          remote_path = File.join(remote_path, File.basename(src_file))
        end

        # See if we need to upload the file
        local_checksum = Digest::MD5.file(src_file).hexdigest
        remote_checksum = checksum(remote_path)

        if remote_checksum == local_checksum
          @logger.debug("#{remote_path} is up to date")
          return 0
        end

        @logger.debug("Uploading #{remote_path}")
        temp_path = "$env:TEMP/winrm-upload/#{local_checksum}.tmp"

        cmd_executor = WinRM::FS::Core::CommandExecutor.new(@service)
        cmd_executor.open

        file_uploader = WinRM::FS::Core::FileUploader.new(cmd_executor)
        bytes = file_uploader.upload(src_file, temp_path) do |bytes_copied, total_bytes|
          yield bytes_copied, total_bytes, src_file, remote_path if block_given?
        end

        file_decoder = WinRM::FS::Core::FileDecoder.new(cmd_executor)
        file_decoder.decode(temp_path, remote_path)

        bytes
      ensure
        cmd_executor.close if cmd_executor
      end

      def upload_multiple_files(local_paths, remote_path, &block)
        temp_zip = FileManager.create_temp_zip_file(local_paths)

        # See if we need to upload the file
        local_checksum = Digest::MD5.file(temp_zip.path).hexdigest
        temp_path = "$env:TEMP/winrm-upload/#{local_checksum}.zip"
        remote_checksum = checksum(temp_path)

        if remote_checksum == local_checksum
          @logger.debug("#{remote_path} is up to date")
          return 0
        end

        @logger.debug("Uploading #{remote_path}")

        cmd_executor = WinRM::FS::Core::CommandExecutor.new(@service)
        cmd_executor.open

        file_uploader = WinRM::FS::Core::FileUploader.new(cmd_executor)
        bytes = file_uploader.upload(temp_zip.path, temp_path) do |bytes_copied, total_bytes|
          yield bytes_copied, total_bytes, temp_zip.path, remote_path if block_given?
        end

        file_decoder = WinRM::FS::Core::ZipFileDecoder.new(cmd_executor)
        file_decoder.decode(temp_path, remote_path)

        bytes
      ensure
        temp_zip.delete if temp_zip
        cmd_executor.close if cmd_executor
      end

      def self.create_temp_zip_file(local_paths)
        temp_zip = WinRM::FS::Core::TempZipFile.new
        local_paths.each { |p| temp_zip.add(p) }
        temp_zip
      end

      def self.src_is_single_file?(local_paths)
        local_paths.count == 1 && File.file?(local_paths[0])
      end
    end
  end
end
