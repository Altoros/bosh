# Copyright (c) 2009-2013 VMware, Inc.
# Copyright (c) 2012 Piston Cloud Computing, Inc.

# TODO: replace this with gem
require 'azure-sdk/lib/azure' 

module Bosh::AzureCloud 
end

require "fog"
require "httpclient"
require "json"
require "pp"
require "set"
require "tmpdir"
require "securerandom"
require "yajl"

require "common/exec"
require "common/thread_pool"
require "common/thread_formatter"

require 'bosh/registry/client'
require "cloud"
require "cloud/azure/helpers"
require "cloud/azure/cloud"
require "cloud/azure/version"

require "cloud/azure/network_configurator"
require "cloud/azure/network"
require "cloud/azure/dynamic_network"
require "cloud/azure/manual_network"
require "cloud/azure/vip_network"

module Bosh
  module Clouds
    Azure = Bosh::AzureCloud::Cloud
  end
end
