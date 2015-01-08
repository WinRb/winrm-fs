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

require 'erubis'

module WinRM
  module FS
    # PS1 scripts
    module Scripts
      def self.render(template, context)
        template_path = File.expand_path(
          "#{File.dirname(__FILE__)}/#{template}.ps1.erb")
        template = File.read(template_path)
        Erubis::Eruby.new(template).result(context)
      end
    end
  end
end
