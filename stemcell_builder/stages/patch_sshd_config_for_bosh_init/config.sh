#!/usr/bin/env bash

set -e

base_dir=$(readlink -nf $(dirname $0)/../..)
source $base_dir/lib/prelude_config.bash

stemcell_disk_device="/dev/xvde"
stemcell_boot_partition="/dev/xvde1"

persist_value stemcell_image_name
persist_value stemcell_disk_device
persist_value stemcell_boot_partition
