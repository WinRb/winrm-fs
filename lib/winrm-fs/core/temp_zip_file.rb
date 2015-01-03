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

require 'zip'

module WinRM
  module FS
    module Core
      # Temporary zip file on the local system
      class TempZipFile
        attr_reader :path

        def initialize
          @logger = Logging.logger[self]
          @zip_file = Tempfile.new(['winrm_upload', '.zip'])
          @zip_file.close
          @path = @zip_file.path
        end

        # Adds a file or directory to the temporary zip file
        # @param [String] Directory or file path to add into zip
        def add(path)
          if File.directory?(path)
            add_directory(path)
          elsif File.file?(path)
            add_file(path)
          else
            fail "#{path} doesn't exist"
          end
        end

        # Adds all files in the specified directory recursively into the zip file
        # @param [String] Directory to add into zip
        def add_directory(dir)
          fail "#{dir} isn't a directory" unless File.directory?(dir)
          glob = File.join(dir, '**/*')
          Dir.glob(glob).each do |file|
            add_file_entry(file, dir)
          end
        end

        def add_file(file)
          fail "#{file} isn't a file" unless File.file?(file)
          add_file_entry(file, File.dirname(file))
        end

        def delete
          @zip_file.delete
        end

        private

        def add_file_entry(file, base_dir)
          base_dir = "#{base_dir}/" unless base_dir.end_with?('/')
          file_entry_path = file[base_dir.length..-1]
          write_zip_entry(file, file_entry_path)
        end

        def write_zip_entry(file, file_entry_path)
          @logger.debug("adding zip entry: #{file_entry_path}")
          Zip::File.open(@path, 'w') do |zipfile|
            entry = new_zip_entry(file_entry_path)
            zipfile.add(entry, file)
          end
        end

        def new_zip_entry(file_entry_path)
          Zip::Entry.new(
            @path,
            file_entry_path,
            nil,
            nil,
            nil,
            nil,
            nil,
            nil,
            ::Zip::DOSTime.new(2000))
        end
      end
    end
  end
end
