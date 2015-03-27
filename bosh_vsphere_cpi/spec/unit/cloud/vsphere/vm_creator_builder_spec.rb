require 'spec_helper'
# require 'cloud/vsphere/vm_creator_builder'

module VSphereCloud
  describe VmCreatorBuilder do
    describe '#build' do
      it 'injects the placer, memory size, disk size, number of cpu, vsphere client, logger and the cpi into the VmCreator instance' do
        resources = double('resources')
        client = double('client')
        cloud_searcher = instance_double('VSphereCloud::CloudSearcher')
        logger = double('logger')
        cpi = double('cpi')
        vm_creator = double('vm creator')
        memory = double('memory in mb')
        disk = double('disk in mb')
        cpu = double('number of cpus')
        agent_env = double('agent_env')
        file_provider = double('file_provider')
        disk_provider = double('disk_provider')

        cloud_properties = {
          'ram' => memory,
          'disk' => disk,
          'cpu' => cpu,
        }
        expect(
          class_double('VSphereCloud::VmCreator').as_stubbed_const
        ).to receive(:new).with(
          memory,
          disk,
          cpu,
          resources,
          client,
          cloud_searcher,
          logger,
          cpi,
          agent_env,
          file_provider,
          disk_provider
        ).and_return(vm_creator)

        expect(
          subject.build(resources, cloud_properties, client, cloud_searcher, logger, cpi, agent_env, file_provider, disk_provider)
        ).to eq(vm_creator)
      end
    end
  end
end
