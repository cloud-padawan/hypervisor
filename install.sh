# Install ccio-utils

# Check if run as root!
if [[ $EUID -ne 0 ]]; then
        echo "$SEP_2 This script must be run as root!"
	echo "$SEP_2 Exiting ... " 
        exit 1
fi


#################################################################################
install_virt_requirements () {
rm /usr/bin/ccio-install
ln -s /etc/ccio/tools/ccio-build-environment-setup.sh /usr/bin/ccio-install

echo "

   Thank you for downloading CCIO utils. 
   
   Run the following command to continue:
      
       $ sudo ccio-install
       
       "
exit 0
}

#################################################################################
# Download and install obb tool
install_obb () {
url_OBB="https://raw.githubusercontent.com/containercraft/hypervisor/master/ovs-bridge-builder.sh"

echo "Installing OVS_Bridge_Builder"
wget -O /etc/ccio/tools/obb.sh $url_OBB
chmod +x /etc/ccio/tools/obb.sh
rm /usr/bin/obb
ln -s /etc/ccio/tools/obb.sh /usr/bin/obb
}

#################################################################################
# Download virt setup installer
download_virt_requirements () {
virt_BUILD_ENV_URL="https://raw.githubusercontent.com/containercraft/hypervisor/master/install-ccio-hypervisor.sh"

wget -O /etc/ccio/tools/ccio-build-environment-setup.sh $virt_BUILD_ENV_URL
chmod +x /etc/ccio/tools/ccio-build-environment-setup.sh
}

#################################################################################
# Create CCIO Configuration File
seed_ccio_filesystem () {

# Create ccio directorys
echo "Seeding CCIO file system ..."
mkdir -p /etc/ccio/tools

# Determine host system's service names for ovs/libvirt/lxd
echo "Checking service names ..."
lxd_SVC_NAME_CHECK=$(systemctl list-unit-files \
                    | grep -E "lxd.service|snap.lxd.daemon.service")
ovs_SVC_NAME_CHECK=$(systemctl list-unit-files \
                    | grep -E "ovs-vswitchd.service|openvswitch-switch.service")
libvirt_SVC_NAME_CHECK=$(systemctl list-unit-files \
                    | grep -E "libvirt.service")

# Write ccio.conf
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

# Default Run Values
xml_FILE_DIR="/etc/ccio/virsh_xml"
show_HELP="false"
show_HELP_LONG="false"
show_HEALTH="false"
show_CONFIG="false"
ovs_SERVICE_NAME="$ovs_SVC_NAME"
lxd_SERVICE_NAME="$lxd_SVC_NAME_CHECK"
libvirt_SERVICE_NAME="$libvirt_SVC_NAME_CHECK"
ovs_BR_DRIVER="openvswitch"
lxd_CMD="lxc"
purge_DEAD_OVS_PORTS="false"
delete_NETWORK="false"
add_OVS_PORT="false"
default_BR_NAME="ovsbr01"
name_OVS_BR="$default_BR_NAME"
lxd_CONT_NAME="false"
ovs_BR_NAME="false"
ovs_ADD_PORT="false"

dbg_FLAG="[d00.0b] > Imported ccio.conf" && print_dbg_flags;
EOF
}

seed_ccio_filesystem
download_virt_requirements
install_obb
install_virt_requirements
