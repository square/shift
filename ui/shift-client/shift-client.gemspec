# encoding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'shift_client/version'

Gem::Specification.new do |spec|
  spec.name          = 'shift-client'
  spec.version       = ShiftClient::VERSION
  spec.authors       = ['Michael Finch']
  spec.email         = ['mfinch@squareup.com']
  spec.summary       = 'Client gem for interacting with the shift API'
  spec.homepage      = 'https://github.com/square/shift/tree/master/ui/shift-client'
  spec.required_ruby_version = '>= 2.0.0'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(/^bin\//) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(/^(test|spec|features)\//)
  spec.require_paths = ['lib']

  spec.add_runtime_dependency 'json'
  spec.add_runtime_dependency 'rest-client', '>= 1.8.0'
  spec.add_runtime_dependency 'colored'
  spec.add_runtime_dependency 'commander', '~> 4.2'

  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'rspec', '~> 3.0'
end
