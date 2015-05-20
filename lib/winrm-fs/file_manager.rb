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
require_relative 'core/upload_orchestrator'

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
      # @example copy a single file to a winrm endpoint
      #
      #   file_manager.upload('/Users/sneal/myfile.txt', 'c:/foo/myfile.txt')
      #
      # @example copy a single directory to a winrm endpoint
      #
      #   file_manager.upload('c:/dev/my_dir', '$env:AppData')
      #
      # @param [String] A path to a local directory or file that will be copied
      #   to the remote Windows box.
      # @param [String] The target directory or file
      #   This path may contain powershell style environment variables
      # @yieldparam [Fixnum] Number of bytes copied in current payload sent to the winrm endpoint
      # @yieldparam [Fixnum] The total number of bytes to be copied
      # @yieldparam [String] Path of file being copied
      # @yieldparam [String] Target path on the winrm endpoint
      # @return [Fixnum] The total number of bytes copied
      def upload(local_path, remote_path, &block)
        @logger.debug("uploading: #{local_path} -> #{remote_path}")

        upload_orchestrator = WinRM::FS::Core::UploadOrchestrator.new(@service)
        if File.file?(local_path)
          upload_orchestrator.upload_file(local_path, remote_path, &block)
        else
          upload_orchestrator.upload_directory(local_path, remote_path, &block)
        end
      end
    end
  end
end
