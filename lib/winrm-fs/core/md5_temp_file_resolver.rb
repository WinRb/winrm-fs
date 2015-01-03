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

require_relative 'command_executor'

module WinRM
  module FS
    module Core
      # Gets a unique path to a new temp file on the target machine
      class Md5TempFileResolver
        def initialize(command_executor)
          @command_executor = command_executor
        end

        # Gets the full path of a new empty temp file on the target machine, but
        # only if the source and target file contents differ. If the contents
        # match (i.e. upload isn't required) this will return ''
        #
        # @param [String] Full local path to the source file on this machine
        # @param [String] Full path to the file on the target machine
        # @return [String] Full path to a new tempfile, otherwise empty
        def temp_file_path(local_file, dest_file)
          script = temp_file_script(local_file, dest_file)
          @command_executor.run_powershell(script).to_s.chomp
        end

        private

        # rubocop:disable Metrics/MethodLength
        def temp_file_script(local_file, dest_file)
          local_md5 = Digest::MD5.file(local_file).hexdigest
          <<-EOH
          # get the resolved target path
          $p = $ExecutionContext.SessionState.Path
          $destFile = $p.GetUnresolvedProviderPathFromPSPath("#{dest_file}")

          # check if file is up to date
          if (Test-Path $destFile) {
            $cryptoProv = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider

            $file = [System.IO.File]::Open($destFile,
              [System.IO.Filemode]::Open, [System.IO.FileAccess]::Read)
            $guestMd5 = ([System.BitConverter]::ToString($cryptoProv.ComputeHash($file)))
            $guestMd5 = $guestMd5.Replace("-","").ToLower()
            $file.Close()

            # file content is up to date, send back an empty file path to signal this
            if ($guestMd5 -eq '#{local_md5}') {
              return ''
            }
          }

          # file doesn't exist or out of date, return a unique temp file path to upload to
          return [System.IO.Path]::GetTempFileName()
          EOH
        end
        # rubocop:enable Metrics/MethodLength
      end
    end
  end
end
