#!/usr/bin/env bash
#
# Copyright (c) 2009-2012 VMware, Inc.

set -e

base_dir=$(readlink -nf $(dirname $0)/../..)
source $base_dir/lib/prelude_apply.bash

qemu-img convert -O vpc -o subformat=fixed $work/${stemcell_image_name} $work/root.vhd
ln $work/root.vhd $work/root.img
