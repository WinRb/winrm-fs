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
require 'fileutils'

module WinRM
  module FS
    module Core
      # Temporary zip file on the local system
      class TempZipFile
        attr_reader :zip_file, :path, :paths, :basedir, :options
        def initialize(basedir = Dir.pwd, options = {})
          @basedir = Pathname(basedir)
          @options = options
          @zip_file = options.delete(:zip_file) || Tempfile.new(['winrm_upload', '.zip'])
          @path = Pathname(@zip_file)
          factory = case options.delete(:via)
          when nil, :rubyzip
            RubyZipFactory
          when :shell
            ShellZipFactory
          else
            fail "Unknown zip factory: #{factory}"
          end

          yield self if block_given?
          factory.new(self).build
          @zip_file
        end

        def paths
          @paths ||= []
        end

        # Adds a file or directory to the temporary zip file
        # @param [String] Directory or file path relative to basedir to add into zip
        def add(*new_paths)
          new_paths.each do | path |
            absolute_path = File.expand_path(path, basedir)
            fail "#{path} must exist relative to #{basedir}" unless File.exist? absolute_path
            paths << Pathname(absolute_path).relative_path_from(basedir)
          end
        end

        def delete
          @zip_file.delete
        end
      end

      class ShellZipFactory
        attr_reader :zip_definition, :basedir, :zip_file, :paths, :options

        def initialize(zip_definition)
          @zip_definition = zip_definition
          @zip_file = zip_definition.zip_file
          @basedir = zip_definition.basedir
          @paths = zip_definition.paths
          @options = zip_definition.options.map do | key, value |
            prefix = key.length > 1 ? '--' : '-'
            if value == true
              "#{prefix}#{key}"
            else
              "#{prefix}#{key} #{value}"
            end
          end.join(' ')
        end

        def build
          Dir.chdir(basedir) do
            file_list = Tempfile.new('file_list')
            file_list.puts paths.join("\n")
            file_list.close
            # We need to use the .tmp file because Tempfile creates a blank file, which zip doesn't like
            output = `zip #{zip_definition.path}.tmp --names-stdin #{options} < #{file_list.path}`
            fail "zip command failed: #{output}" unless $?.success?

            FileUtils.mv("#{zip_definition.path}.tmp", "#{zip_definition.path}")
          end
        end
      end

      class RubyZipFactory
        attr_reader :zip_definition, :basedir

        def initialize(zip_definition)
          @zip_definition = zip_definition
          @basedir = zip_definition.basedir
          @zip = Zip::File.open(zip_definition.path, Zip::File::CREATE)
        end

        def build
          @zip_definition.paths.each do | path |
            absolute_path = File.expand_path(path, basedir)
            fail "#{path} doesn't exist" unless File.exist? absolute_path

            if File.directory?(absolute_path) && zip_definition.options[:recurse_paths]
              add_directory(path)
            else
              add_file(path)
            end
          end
          close
        end

        def close
          @zip.close if @zip
        end

        private

        # Adds all files in the specified directory recursively into the zip file
        # @param [String] Directory to add into zip
        def add_directory(dir)
          glob = File.join(basedir, dir, '**/*')
          Dir.glob(glob).each do |file|
            add_file(file)
          end
        end

        def add_file(file)
          write_zip_entry(file, basedir)
        end

        def write_zip_entry(file, file_entry_path)
          absolute_file = File.expand_path(file, basedir)
          relative_file = Pathname(absolute_file).relative_path_from(basedir).to_s
          entry = new_zip_entry(relative_file)
          @zip.add(entry, absolute_file)
        end

        def new_zip_entry(file_entry_path)
          Zip::Entry.new(
            @zip,
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
