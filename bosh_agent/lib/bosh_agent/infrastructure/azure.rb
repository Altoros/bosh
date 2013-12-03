module Bosh::Agent
  class Infrastructure::Azure
    require 'bosh_agent/infrastructure/azure/settings'

    def load_settings
      Settings.new.load_settings
    end

    def get_network_settings(network_name, properties)
      # Nothing to do
    end

  end
end
