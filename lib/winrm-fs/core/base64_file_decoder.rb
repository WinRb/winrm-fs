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
      # Decodes a base64 file on a target machine and writes it out
      class Base64FileDecoder
        def initialize(command_executor)
          @command_executor = command_executor
        end

        # Decodes the given base64 encoded file and writes it to another file.
        # @param [String] Path to the base64 encoded file on the target machine.
        # @param [String] Path to the unencoded file on the target machine.
        def decode(base64_encoded_file, dest_file)
          script = decode_script(base64_encoded_file, dest_file)
          @command_executor.run_powershell(script)
        end

        protected

        # rubocop:disable Metrics/MethodLength
        def decode_script(base64_encoded_file, dest_file)
          <<-EOH
            $p = $ExecutionContext.SessionState.Path
            $tempFile = $p.GetUnresolvedProviderPathFromPSPath("#{base64_encoded_file}")
            $destFile = $p.GetUnresolvedProviderPathFromPSPath("#{dest_file}")

            # ensure the file's containing directory exists
            $destDir = ([System.IO.Path]::GetDirectoryName($destFile))
            if (!(Test-Path $destDir)) {
              New-Item -ItemType directory -Force -Path $destDir | Out-Null
            }

            # get the encoded temp file contents, decode, and write to final dest file
            if (Test-Path $tempFile -PathType Leaf) {
              $base64Content = Get-Content $tempFile
            }
            
            if ($base64Content -eq $null) {
              New-Item -ItemType file -Force $destFile
            } else {
              $bytes = [System.Convert]::FromBase64String($base64Content)
              [System.IO.File]::WriteAllBytes($destFile, $bytes) | Out-Null
            }
          EOH
        end
        # rubocop:enable Metrics/MethodLength
      end
    end
  end
end
