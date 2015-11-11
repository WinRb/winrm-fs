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

require_relative 'temp_zip_file'
require_relative 'file_uploader'
require_relative 'command_executor'
require_relative '../scripts/scripts'

module WinRM
  module FS
    module Core
      # Orchestrates the upload of a file or directory
      class UploadOrchestrator
        def initialize(service)
          @service = service
          @logger = Logging.logger[self]
        end

        def upload_file(local_path, remote_path, &block)
          # If the src has a file extension and the destination does not
          # we can assume the caller specified the dest as a directory
          if File.extname(local_path) != '' && File.extname(remote_path) == ''
            remote_path = File.join(remote_path, File.basename(local_path))
          end
          temp_path = temp_file_path(local_path)
          with_command_executor do |cmd_executor|
            return 0 unless out_of_date?(cmd_executor, local_path, remote_path)
            do_file_upload(cmd_executor, local_path, temp_path, remote_path, &block)
          end
        end

        def upload_directory(local_path, remote_path, &block)
          with_local_zip(local_path) do |local_zip|
            temp_path = temp_file_path(local_zip.path)
            with_command_executor do |cmd_executor|
              return 0 unless out_of_date?(cmd_executor, local_zip.path, temp_path)
              do_file_upload(cmd_executor, local_zip.path, temp_path, remote_path, &block)
            end
          end
        end

        private

        def do_file_upload(cmd_executor, local_path, temp_path, remote_path)
          file_uploader = WinRM::FS::Core::FileUploader.new(cmd_executor)
          bytes = file_uploader.upload(local_path, temp_path) do |bytes_copied, total_bytes|
            yield bytes_copied, total_bytes, local_path, remote_path if block_given?
          end

          cmd_executor.run_powershell(
            WinRM::FS::Scripts.render('decode_file', src: temp_path, dest: remote_path))

          bytes
        end

        def with_command_executor
          cmd_executor = WinRM::FS::Core::CommandExecutor.new(@service)
          cmd_executor.open
          yield cmd_executor
        ensure
          cmd_executor.close
        end

        def with_local_zip(local_path)
          local_zip = create_temp_zip_file(local_path)
          yield local_zip
        ensure
          local_zip.delete if local_zip
        end

        def out_of_date?(cmd_executor, local_path, remote_path)
          local_checksum = local_checksum(local_path)
          remote_checksum = remote_checksum(cmd_executor, remote_path)

          if remote_checksum == local_checksum
            @logger.debug("#{remote_path} is up to date")
            return false
          end
          true
        end

        def remote_checksum(cmd_executor, remote_path)
          script = WinRM::FS::Scripts.render('checksum', path: remote_path)
          cmd_executor.run_powershell(script).chomp
        end

        def local_checksum(local_path)
          Digest::MD5.file(local_path).hexdigest
        end

        def temp_file_path(local_path)
          ext = '.tmp'
          ext = '.zip' if File.extname(local_path) == '.zip'
          "$env:TEMP/winrm-upload/#{local_checksum(local_path)}#{ext}"
        end

        def create_temp_zip_file(local_path)
          zip = WinRM::FS::Core::TempZipFile.new(local_path, recurse_paths: true)
          zip.add(local_path)
          zip.build
          zip
        end
      end
    end
  end
end
