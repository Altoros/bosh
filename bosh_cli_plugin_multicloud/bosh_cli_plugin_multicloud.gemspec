# coding: utf-8
require File.expand_path('../lib/bosh/multicloud/version', __FILE__)

version = Bosh::MultiCloud::VERSION

Gem::Specification.new do |s|
  s.name        = 'bosh_cli_plugin_multicloud'
  s.version     = version
  s.platform    = Gem::Platform::RUBY
  s.summary     = 'BOSH CLI plugin for multiple clouds'
  s.description = "BOSH CLI plugin for multiple clouds"
  s.author      = 'lomov.as@gmail.com'
  s.homepage    = 'https://github.com/cloudfoundry/bosh'
  s.license     = 'Apache 2.0'
  s.email       = 'lomov.as@gmail.com'
  s.required_ruby_version = Gem::Requirement.new('>= 1.9.3')

  s.files         = `git ls-files -- lib/* config/*`.split("\n") + %w(README.rdoc)
  s.require_paths = ['lib', 'config']

  s.add_dependency 'sqlite3',     '~>1.3.7'

  s.add_dependency 'bosh-core',      "~>#{version}"
  s.add_dependency 'bosh_cli',      "~>#{version}"
  s.add_dependency 'bosh-stemcell', "~>#{version}"
  s.add_dependency 'bosh-registry', "~>#{version}"
  s.add_dependency 'agent_client',  "~>#{version}"

  s.add_dependency 'bosh_cpi',           "~>#{version}"
  s.add_dependency 'bosh_aws_cpi',       "~>#{version}"
  s.add_dependency 'bosh_openstack_cpi', "~>#{version}"
  s.add_dependency 'bosh_vcloud_cpi',    '~>0.7.3'
  s.add_dependency 'bosh_vsphere_cpi',   "~>#{version}"
  s.add_dependency 'bosh-director-core', "~>#{version}"
  s.add_dependency 'blobstore_client',   "~>#{version}"

  s.add_development_dependency 'rake'
  s.add_development_dependency 'rspec'
  s.add_development_dependency 'rspec-its'
  s.add_development_dependency 'fakefs'
  s.add_development_dependency 'timecop'
end