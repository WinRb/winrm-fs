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
      class FileDecoder
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
$path = $ExecutionContext.SessionState.Path
$tempFile = $path.GetUnresolvedProviderPathFromPSPath("#{base64_encoded_file}")
$dest = $path.GetUnresolvedProviderPathFromPSPath("#{dest_file}")

function Decode-File($encodedFile, $decodedFile) {
    if (Test-Path $encodedFile) {
      $base64Content = Get-Content $encodedFile
    }
    if ($base64Content -eq $null) {
        New-Item -ItemType file -Force $decodedFile | Out-Null
    }
    else {
        $bytes = [System.Convert]::FromBase64String($base64Content)
        [System.IO.File]::WriteAllBytes($decodedFile, $bytes) | Out-Null
    }
}

function Ensure-Dir-Exists($path) {
    # ensure the destination directory exists
    if (!(Test-Path $path)) {
        New-Item -ItemType Directory -Force -Path $path | Out-Null
    }
}

if ([System.IO.Path]::GetExtension($tempFile) -eq '.zip') {
    Ensure-Dir-Exists $dest
    Decode-File $tempFile $tempFile
    $shellApplication = New-Object -com shell.application
    $zipPackage = $shellApplication.NameSpace($tempFile)
    $destinationFolder = $shellApplication.NameSpace($dest)
    $destinationFolder.CopyHere($zipPackage.Items(), 0x10) | Out-Null
}
else {
    Ensure-Dir-Exists ([System.IO.Path]::GetDirectoryName($dest))
    Decode-File $tempFile $dest
}
          EOH
        end
        # rubocop:enable Metrics/MethodLength
      end
    end
  end
end
