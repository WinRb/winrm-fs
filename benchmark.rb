require 'winrm-fs'
require 'benchmark'

def files
  # This is a fairly short list of small files, may also want a benchmark with larger files
  files = `git ls-files`.lines
  files = files.map do | file |
    next if File.directory? file
    # File.expand_path(file.strip, Dir.pwd)
    file.strip
  end.compact
end

def create_zip(factory, file)
  WinRM::FS::Core::TempZipFile.new(Dir.pwd, {zip_file: file, via: factory, X: true}) do | temp_zip |
    temp_zip.add(*files)
  end
end

Benchmark.bm do | benchmark |
  benchmark.report('zip cmd') { `git ls-files | zip zip_command.zip -X --names-stdin` }
  benchmark.report('shell') { create_zip(:shell, 'shell.zip') }
  benchmark.report('ruby') { create_zip(:rubyzip, 'ruby.zip') }
end

