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

require 'winrm'
require_relative 'scripts/scripts'
require_relative 'core/file_transporter'

module WinRM
  module FS
    # Perform file transfer operations between a local machine and winrm endpoint
    class FileManager
      # Creates a new FileManager instance
      # @param [WinRM::Connection] WinRM web connection client
      def initialize(connection)
        @connection = connection
        @logger = connection.logger
      end

      # Gets the SHA1 checksum of the specified file if it exists,
      # otherwise ''
      # @param [String] The remote file path
      # @parms [String] The digest method
      def checksum(path, digest = 'SHA1')
        @logger.debug("checksum with #{digest}: #{path}")
        script = WinRM::FS::Scripts.render('checksum', path: path, digest: digest)
        @connection.shell(:powershell) { |e| e.run(script).stdout.chomp }
      end

      # Create the specifed directory recursively
      # @param [String] The remote dir to create
      # @return [Boolean] True if successful, otherwise false
      def create_dir(path)
        @logger.debug("create_dir: #{path}")
        script = WinRM::FS::Scripts.render('create_dir', path: path)
        @connection.shell(:powershell) { |e| e.run(script).exitcode == 0 }
      end

      # Deletes the file or directory at the specified path
      # @param [String] The path to remove
      # @return [Boolean] True if successful, otherwise False
      def delete(path)
        @logger.debug("deleting: #{path}")
        script = WinRM::FS::Scripts.render('delete', path: path)
        @connection.shell(:powershell) { |e| e.run(script).exitcode == 0 }
      end

      # Downloads the specified remote file to the specified local path
      # @param [String] The full path on the remote machine
      # @param [String] The full path to write the file to locally
      def download(remote_path, local_path, recurse = true)
        @logger.debug("downloading: #{remote_path} -> #{local_path}")
        script = WinRM::FS::Scripts.render('download', path: remote_path)
        output = @connection.shell(:powershell) { |e| e.run(script) }
        return false if output.exitcode != 0
        contents = output.stdout.gsub('\n\r', '')
        download_dir(remote_path, local_path) if contents.empty? && recurse
        IO.binwrite(local_path, Base64.decode64(contents)) unless contents.empty?
        true
      end

      # Checks to see if the given path exists on the target file system.
      # @param [String] The full path to the directory or file
      # @return [Boolean] True if the file/dir exists, otherwise false.
      def exists?(path)
        @logger.debug("exists?: #{path}")
        script = WinRM::FS::Scripts.render('exists', path: path)
        @connection.shell(:powershell) { |e| e.run(script).exitcode == 0 }
      end

      # Gets the current user's TEMP directory on the remote system, for example
      # 'C:/Windows/Temp'
      # @return [String] Full path to the temp directory
      def temp_dir
        @guest_temp ||= begin
          (@connection.shell(:powershell) { |e| e.run('$env:TEMP') }).stdout.chomp.tr('\\', '/')
        end
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
        @connection.shell(:powershell) do |shell|
          file_transporter ||= WinRM::FS::Core::FileTransporter.new(shell)
          file_transporter.upload(local_path, remote_path, &block)[0]
        end
      end

      private

      def download_dir(remote_path, local_path)
        local_path = File.join(local_path.to_s, File.basename(remote_path.to_s))
        FileUtils.mkdir_p(local_path)
        command = "Get-ChildItem #{remote_path} | Select-Object Name"
        @connection.shell(:powershell) { |e| e.run(command) }.stdout.strip.split(/\n/).drop(2).each do |file|
          download(File.join(remote_path.to_s, file.strip), File.join(local_path, file.strip))
        end
      end
    end
  end
end
