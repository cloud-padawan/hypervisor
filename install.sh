#!/bin/bash
# Install ccio-utils

# Set URL's
url_OBB="https://raw.githubusercontent.com/containercraft/hypervisor/master/ovs-bridge-builder.sh"
virt_BUILD_ENV_URL="https://raw.githubusercontent.com/containercraft/hypervisor/master/ccio-build-environment-setup.sh"

# Check if run as root!
if [[ $EUID -ne 0 ]]; then
        echo "$SEP_2 This script must be run as root!"
	echo "$SEP_2 Exiting ... " 
        exit 1
fi

#################################################################################
# End Script & Echo Install command 
end_script_echo () {
echo "

   Thank you for downloading CCIO utils. 
   
   Run the following command to continue:
      
       $ sudo ccio-install
       
       "
exit 0
}

#################################################################################
# Write ccio.conf
seed_ccio_conf () {
echo "Checking service names ..."

# Determine host system's service names for LXD
lxd_SVC_NAME_CHECK=$(systemctl list-unit-files \
                    | grep -E "lxd.service|snap.lxd.daemon.service" \
                    | awk '{print $1}')
lxd_SVC_CHECK_SUCCESS="$?"
if [[ $lxd_SVC_CHECK_SUCCESS -ne "0" ]]; then
    lxd_SVC_NAME_CHECK="DISABLED"
    echo "OVS Service Not Found!"
    echo "LXD Service: $lxd_SVC_NAME_CHECK"
 else
    echo "LXD Service: $lxd_SVC_NAME_CHECK"
fi

# Determine host system's service names for OVS
ovs_SVC_NAME_CHECK=$(systemctl list-unit-files \
                    | grep -E "ovs-vswitchd.service|openvswitch-switch.service" \
                    | awk '{print $1}')
ovs_SVC_CHECK_SUCCESS="$?"
if [[ $ovs_SVC_CHECK_SUCCESS -ne "0" ]]; then
    ovs_SVC_NAME_CHECK="DISABLED"
    echo "OVS Service Not Found!"
    echo "OVS Service: $ovs_SVC_NAME_CHECK"
 else
    echo "OVS Service: $ovs_SVC_NAME_CHECK"
fi

# Determine host system's service names for LibVirt
libvirt_SVC_NAME_CHECK=$(systemctl list-unit-files \
                        | grep -E "libvirtd.service" \
                        | awk '{print $1}')
libvirt_SVC_CHECK_SUCCESS="$?"
if [[ $libvirt_SVC_CHECK_SUCCESS -ne "0" ]]; then
    libvirt_SVC_NAME_CHECK="DISABLED"
    echo "Libvirt Service Not Found!"
    echo "KVM Service: $libvirt_SVC_NAME_CHECK"
 else
    echo "KVM Service: $libvirt_SVC_NAME_CHECK"
fi

echo "
LXD Service: $lxd_SVC_NAME_CHECK
OVS Service: $ovs_SVC_NAME_CHECK
KVM Service: $libvirt_SVC_NAME_CHECK
"
         
# Write ccio.conf
default_BR_NAME="ovsbr01"
echo "Writing ccio.conf ..."
cat >/etc/ccio/ccio.conf <<EOF
# OVS-BridgeBuilder  --  Virtual Network Management utility
# 
# Use to manage LXD & Libvirt OpenVswitch Networks
# This is currently only tested on Arch and Ubuntu-Xenial; YMMV on other
# distros
#
# Requires LXD, Libvirt, and OpenVSwitch services
# 
# Initial prep and variable are sourced from the ccio.conf file
# All actions are executed within functions

# Debugging Switches [true|false]
dbg_BREAK="true"
print_DBG_FLAGS="true"

# Host System Service Names
# Will be disabled at install time if service is not installed on host
ovs_SERVICE_NAME="$ovs_SVC_NAME_CHECK"
lxd_SERVICE_NAME="$lxd_SVC_NAME_CHECK"
libvirt_SERVICE_NAME="$libvirt_SVC_NAME_CHECK"

# Default Run Values
xml_FILE_DIR="/etc/ccio/virsh_xml"
show_HELP="false"
show_HELP_LONG="false"
show_HEALTH="false"
show_CONFIG="false"
ovs_BR_DRIVER="openvswitch"
lxd_CMD="lxc"
purge_DEAD_OVS_PORTS="false"
delete_NETWORK="false"
add_OVS_PORT="false"
default_BR_NAME="ovsbr01"
name_OVS_BR="$default_BR_NAME"
lxd_CONT_NAME="false"
ovs_BR_NAME="false"
add_OVS_BR="false"
ovs_ADD_PORT="false"

dbg_FLAG="[d00.0b] > Imported ccio.conf" && print_dbg_flags;
EOF
}

#################################################################################
# Download and install obb tool
install_obb () {
rm /usr/bin/obb
echo "Installing OVS_Bridge_Builder"
wget -O /etc/ccio/tools/obb.sh $url_OBB
chmod +x /etc/ccio/tools/obb.sh
ln -s /etc/ccio/tools/obb.sh /usr/bin/obb
}

#################################################################################
# Download virt setup installer
download_virt_requirements () {
rm /usr/bin/ccio-install
echo "Preparing ccio-install utility"
wget -O /etc/ccio/tools/ccio-build-environment-setup.sh $virt_BUILD_ENV_URL
chmod +x /etc/ccio/tools/ccio-build-environment-setup.sh
ln -s /etc/ccio/tools/ccio-build-environment-setup.sh /usr/bin/ccio-install
}

#################################################################################
# Create CCIO File System
seed_ccio_filesystem () {
echo "Seeding CCIO file system ..."
mkdir -p /etc/ccio/tools
}

#################################################################################
# 
purge_legacy_lxd () {
echo "purging legacy LXD .deb installations"
apt-get purge lxd lxd-client -y
}

purge_legacy_lxd 
seed_ccio_filesystem
download_virt_requirements
install_obb
seed_ccio_conf 
end_script_echo
