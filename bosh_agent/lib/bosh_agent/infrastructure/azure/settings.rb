module Bosh::Agent
  class Infrastructure::Azure::Settings
    DEFAULT_OVF_ENV_LOCATION = '/var/lib/waagent/ovf-env.xml'.freeze
    DEFAULT_WAIT_AGENT_TIME = 10

    def initialize
      @logger = Bosh::Agent::Config.logger
    end

    def load_settings
      begin
        data = File.read(DEFAULT_OVF_ENV_LOCATION, :encoding => "UTF-8")
      rescue => e
        @logger.info("Waiting for #{DEFAULT_OVF_ENV_LOCATION} to appear: #{e.inspect}")
        sleep DEFAULT_WAIT_AGENT_TIME
        raise
      end

      data = data.match(/\<CustomData\>(.*)\<\/CustomData\>/)[1]
      decoded_data = Base64.decode64(data)
      @settings = Yajl::Parser.new.parse(decoded_data)
    end
  end
end