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

require 'English'
require 'zip'
require 'fileutils'
require 'pathname'

module WinRM
  module FS
    module Core
      # Temporary zip file on the local system
      class TempZipFile
        attr_reader :zip_file, :path, :paths, :basedir, :options

        # Creates a new local temporary zip file
        # @param [String] Base directory to use when expanding out files passed to add
        # @param [Hash] Options: zip_file, via, recurse_paths
        def initialize(basedir = Dir.pwd, options = {})
          @basedir = Pathname.new(basedir)
          @options = options
          @zip_file = options[:zip_file] || Tempfile.new(['winrm_upload', '.zip'])
          @zip_file.close unless @zip_file.respond_to?('closed?') && @zip_file.closed?
          @path = Pathname.new(@zip_file)
        end

        # Adds a file or directory to the temporary zip file
        # @param [String] Directory or file path relative to basedir to add into zip
        def add(*new_paths)
          new_paths.each do | path |
            absolute_path = File.expand_path(path, basedir)
            fail "#{path} must exist relative to #{basedir}" unless File.exist? absolute_path
            paths << Pathname.new(absolute_path).relative_path_from(basedir)
          end
        end

        def paths
          @paths ||= []
        end

        def delete
          @zip_file.delete
        end

        def build
          factory.new(self).build
        end

        private

        def factory
          @factory ||= case options[:via]
                       when nil, :rubyzip
                         RubyZipFactory
                       when :shell
                         ShellZipFactory
                       else
                         fail "Unknown zip factory: #{factory}"
                       end
        end
      end

      # Creates a zip file by shelling out to the zip command
      class ShellZipFactory
        attr_reader :zip_definition, :basedir, :zip_file, :paths, :options

        def initialize(zip_definition)
          @zip_definition = zip_definition
          @zip_file = zip_definition.zip_file
          @basedir = zip_definition.basedir
          @paths = zip_definition.paths
          @options = build_options.push('--names-stdin').join(' ')
        end

        def build
          Dir.chdir(basedir) do
            # zip doesn't like the file that already exists
            output = `zip #{zip_definition.path}.tmp #{options} < #{write_file_list.path}`
            fail "zip command failed: #{output}" unless $CHILD_STATUS.success?

            FileUtils.mv("#{zip_definition.path}.tmp", "#{zip_definition.path}")
          end
        end

        private

        def write_file_list
          file_list = Tempfile.new('file_list')
          file_list.puts paths.join("\n")
          file_list.close
          file_list
        end

        def build_options
          zip_definition.options.map do | key, value |
            prefix = key.length > 1 ? '--' : '-'
            if value == true
              "#{prefix}#{key}"
            else
              "#{prefix}#{key} #{value}"
            end
          end
        end
      end

      # Creates a zip file using RubyZip
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

            if File.directory?(absolute_path)
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
          glob_pattern = '*'
          glob_pattern = '**/*' if zip_definition.options[:recurse_paths]

          glob = File.join(basedir, dir, glob_pattern)
          Dir.glob(glob).each do |file|
            add_file(file)
          end
        end

        def add_file(file)
          write_zip_entry(file, basedir)
        end

        def write_zip_entry(file, _file_entry_path)
          absolute_file = File.expand_path(file, basedir)
          relative_file = Pathname.new(absolute_file).relative_path_from(basedir).to_s
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
