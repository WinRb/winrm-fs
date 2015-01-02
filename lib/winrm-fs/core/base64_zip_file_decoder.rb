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
      class Base64ZipFileDecoder < Base64FileDecoder

        def initialize(command_executor)
          @command_executor = command_executor
        end

        # Decodes the given base64 encoded file, unzips it, and writes it to the dest
        # @param [String] Path to the base64 encoded zip file on the target machine.
        # @param [String] Path to the unzip location on the target machine.
        def decode(base64_encoded_zip_file, dest_file)
          # Windows shell unzip requires the file ends with .zip
          unencoded_zip_file = "#{base64_encoded_zip_file}.zip"
          script =  decode_script(base64_encoded_zip_file, unencoded_zip_file)
          script += "\n" + unzip_script(unencoded_zip_file, dest_file)

          @command_executor.run_powershell(script)
        end

        private

        def unzip_script(zip_file, dest_file)
          <<-EOH
            $zip = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("#{zip_file}")
            $zipFile = [System.IO.Path]::GetFullPath($zip)
            $dest = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath("#{dest_file}")
            $destDir = [System.IO.Path]::GetFullPath($dest)

            mkdir $destDir -ErrorAction SilentlyContinue | Out-Null
            
            $shellApplication = new-object -com shell.application 
            $zipPackage = $shellApplication.NameSpace($zipFile) 
            $destinationFolder = $shellApplication.NameSpace($destDir) 
            $destinationFolder.CopyHere($zipPackage.Items(),0x10) | Out-Null
          EOH
        end
      end
    end
  end
end