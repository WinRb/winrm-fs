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

require_relative 'base64_file_decoder'
require_relative 'base64_zip_file_decoder'
require_relative 'base64_file_uploader'
require_relative 'md5_temp_file_resolver'
require_relative 'command_executor'

module WinRM
  module FS
    module Core
      class RemoteFile

        def self.single_remote_file(service)
          create_remote_file(service) do |cmd_executor|
            WinRM::FS::Core::Base64FileDecoder.new(cmd_executor)
          end
        end

        def self.multi_remote_file(service)
          create_remote_file(service) do |cmd_executor|
            WinRM::FS::Core::Base64ZipFileDecoder.new(cmd_executor)
          end
        end

        def initialize(cmd_executor, temp_file_resolver, file_uploader, file_decoder)
          @logger = Logging.logger[self]
          @cmd_executor = cmd_executor
          @temp_file_resolver = temp_file_resolver
          @file_uploader = file_uploader
          @file_decoder = file_decoder
        end

        def upload(local_path, remote_path, &block)
          @cmd_executor.open()

          temp_path = @temp_file_resolver.temp_file_path(local_path, remote_path)
          if temp_path.empty?
            @logger.debug("Content up to date, skipping: #{local_path}")
            return 0
          end

          @logger.debug("Uploading: #{local_path} -> #{remote_path}")
          size = @file_uploader.upload_to_temp_file(local_path, temp_path, remote_path, &block)
          @file_decoder.decode(temp_path, remote_path)

          size
        rescue WinRMUploadError => e
          # add additional context, from and to
          raise WinRMUploadError,
            :from => local_path,
            :to => remote_path,
            :message => e.message
        ensure
          @cmd_executor.close()
        end

        private

        def self.create_remote_file(service, &block)
          cmd_executor = WinRM::FS::Core::CommandExecutor.new(service)
          temp_file_resolver = WinRM::FS::Core::Md5TempFileResolver.new(cmd_executor)
          file_uploader = WinRM::FS::Core::Base64FileUploader.new(cmd_executor)
          file_decoder = block.call(cmd_executor)
          WinRM::FS::Core::RemoteFile.new(cmd_executor, temp_file_resolver, file_uploader, file_decoder)
        end
      end
    end
  end
end