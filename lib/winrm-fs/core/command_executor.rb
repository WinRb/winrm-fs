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

require_relative 'powershell_script'

module WinRM
  module FS
    module Core
      # Executes commands used by the WinRM file management module
      class CommandExecutor
        def initialize(service)
          @service = service
        end

        def open
          @shell = @service.open_shell
          @shell_open = true
        end

        def close
          @service.close_shell(@shell) if @shell
          @shell_open = false
        end

        def run_powershell(script_text)
          assert_shell_is_open
          script = WinRM::FS::Core::PowershellScript.new(script_text)
          run_cmd('powershell', ['-encodedCommand', script.encoded])
        end

        def run_cmd(command, arguments = [])
          assert_shell_is_open
          result = nil
          @service.run_command(@shell, command, arguments) do |command_id|
            result = @service.get_command_output(@shell, command_id)
          end
          assert_command_success(result)
          result.stdout
        end

        private

        def assert_shell_is_open
          fail 'You must call open before calling any run methods' unless @shell_open
        end

        def assert_command_success(result)
          return if result[:exitcode] == 0 && result.stderr.length == 0
          fail WinRMUploadError, result.output
        end
      end
    end
  end
end
