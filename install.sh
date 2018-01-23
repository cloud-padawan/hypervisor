# Install ccio-utils

# Check if run as root!
if [[ $EUID -ne 0 ]]; then
        echo "$SEP_2 This script must be run as root!"
	echo "$SEP_2 Exiting ... " 
        exit 1
fi


#################################################################################
install_virt_requirements () {
ln -s /etc/ccio/tools/install_ccio_build_env.sh /usr/bin/ccio-install

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
ln -s /etc/ccio/tools/obb.sh /usr/bin/obb
}

#################################################################################
# Download virt setup installer
download_virt_requirements () {
virt_BUILD_ENV_URL="https://raw.githubusercontent.com/containercraft/hypervisor/master/install-ccio-hypervisor.sh"

wget -O /etc/ccio/tools/install_ccio_build_env.sh $virt_BUILD_ENV_URL
}

#################################################################################
# Create CCIO Configuration File
seed_ccio_filesystem () {

# Create ccio directorys
echo "Seeding CCIO file system ..."
mkdir -p /etc/ccio/tools

echo "Checking service names ..."
lxd_SVC_NAME_CHECK=$(systemctl list-unit-files \
                    | grep -E "lxd.service|snap.lxd.daemon.service")
ovs_SVC_NAME_CHECK=$(systemctl list-unit-files \
                    | grep -E "ovs-vswitchd.service|openvswitch-switch.service")
libvirt_SVC_NAME_CHECK=$(systemctl list-unit-files \
                        | grep -E "libvirt.service")

echo "Writing ccio.conf ..."
cat >/etc/ccio/ccio.conf <<EOF

# Default Variables
# Used unless otherwise set in ccio.conf or at command line
# Debug & Verbosity Settings:
print_DBG_FLAGS="true"
dbg_BREAK="true"

# Operating Variables
ovs_SERVICE_NAME="$ovs_SVC_NAME"
lxd_SERVICE_NAME="$lxd_SVC_NAME_CHECK"
libvirt_SERVICE_NAME="$libvirt_SVC_NAME_CHECK"
default_NETWORK_NAME="obb"
network_NAME="$default_NETWORK_NAME"
tmp_FILE_STORE="/tmp/bridge-builder/"
bridge_DRIVER="openvswitch"
delete_NETWORK="false"
ovs_ADD_PORT="false"
ovs_BRIDGE_NAME="false"
lxd_CONT_NAME="false"
show_CONFIG="false"
show_HEALTH="false"
show_HELP="false"
show_HELP_LONG="false"   
running_function="false"

EOF
}

seed_ccio_filesystem
download_virt_requirements
install_obb
install_virt_requirements
