# frozen_string_literal: true

require 'date'

version = File.read(File.expand_path('VERSION', __dir__)).strip

Gem::Specification.new do |s|
  s.platform = Gem::Platform::RUBY
  s.name = 'winrm-fs'
  s.version = version
  s.date = Date.today.to_s

  s.author = ['Shawn Neal', 'Matt Wrock']
  s.email = ['sneal@sneal.net', 'matt@mattwrock.com']
  s.homepage = 'http://github.com/WinRb/winrm-fs'

  s.summary = 'WinRM File System'
  s.description = <<-EOF
    Ruby library for file system operations via Windows Remote Management
  EOF
  s.license = 'Apache-2.0'

  s.files = Dir.glob('{bin,lib}/**/*') + %w[LICENSE README.md]
  s.require_path = 'lib'
  s.rdoc_options = %w[-x test/ -x examples/]
  s.extra_rdoc_files = %w[README.md LICENSE]

  s.bindir = 'bin'
  s.executables = ['rwinrmcp']
  s.required_ruby_version = '>= 2.5.0'
  s.add_runtime_dependency 'benchmark'
  s.add_runtime_dependency 'csv', '~> 3.3'
  s.add_runtime_dependency 'erubi', '>= 1.7'
  s.add_runtime_dependency 'logging', ['>= 1.6.1', '< 3.0']
  # rubyzip >= 3.4.0 fixes CVE-2026-85396 (High, path traversal on extract;
  # no backport to 2.x) and moves optional Entry args to keywords.
  s.add_runtime_dependency 'rubyzip', '~> 3.4'
  s.add_runtime_dependency 'winrm', '~> 2.0'
  s.add_development_dependency 'pry'
  # rake 13.3+ no longer requires ostruct, which is not a bundled gem on Ruby 4.0
  s.add_development_dependency 'rake', '>= 10.3', '< 14'
  s.add_development_dependency 'rspec', '~> 3.0'
  s.add_development_dependency 'rubocop', '~> 1.26.0'
end
