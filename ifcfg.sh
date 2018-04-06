#!/bin/bash
# Write network interface .cfg file & push to target lxd interfaces.d
# Usage:
#    [command] [container_name] [interface_name] [subnet_mask]

# Read Arguments from CMD Line
container_NAME="$1"
ip_IFACE="$2"
ip_ADDR="$3"
ip_MASK="$4"

# Set Temp, Destination, & Template Files
tmp_FILE="/tmp/ccio/$ip_IFACE.cfg"
ifcfg_TEMPLATE="/etc/ccio/lib/ifcfg.static"
target_DIR="/etc/network/interfaces.d/"

# Make Temp Directory if Not Found
[[ -d /tmp/ccio/ ]] || mkdir -p /tmp/ccio/

# Test if template found & abort if fail
[[ ! -d /etc/ccio/lib/ifcfg.template ]] || \
    echo "ERROR: Template File Not Found!" && \
    echo "Aborting!" && exit 1

pipe_template () {
    eval "echo \"$(cat $1)\""
}

gen_config () {
    ifcfg_CONFIG=$(pipe_template $ifcfg_TEMPLATE)
}

make_ifcfg () {
gen_config
echo "Writing Config to $tmp_FILE"
echo -e "$ifcfg_CONFIG" | tee $tmp_FILE
}

push_ifcfg () {
lxc file push $tmp_FILE $container_NAME$target_DIR
}

make_ifcfg
#push_ifcfg
