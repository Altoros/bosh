require 'bosh/stemcell/disk_image'

RSpec.configure do |config|
  if ENV['STEMCELL_IMAGE']
    config.around(stemcell_image: true) do |example|
      Bosh::Stemcell::DiskImage.new(image_file_path: ENV['STEMCELL_IMAGE']).while_mounted do |disk_image|
        SpecInfra::Backend::Exec.instance.chroot_dir = disk_image.image_mount_point
        example.run
        SpecInfra::Backend::Exec.instance.chroot_dir = nil
      end
    end
  else
    warning = 'All stemcell_image tests are being skipped. STEMCELL_IMAGE needs to be set'
    puts RSpec::Core::Formatters::ConsoleCodes.wrap(warning, :yellow)
    config.filter_run_excluding stemcell_image: true
  end
end
