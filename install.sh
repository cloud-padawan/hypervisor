#!/bin/bash
# Install ccio-utils

# Set URL's
url_OBB="https://raw.githubusercontent.com/containercraft/hypervisor/master/ovs-bridge-builder.sh"
virt_BUILD_ENV_URL="https://raw.githubusercontent.com/containercraft/hypervisor/master/ccio-build-environment-setup.sh"


#################################################################################
# Logging Function
run_log () {

    if [ $1 == 0 ]; then
        [[ -z $? ]] && echo "INFO: $2"
    elif [ $1 == 6 ]; then
        echo "$2"
    elif [ $1 == 22 ]; then
        echo "WARN: $2"
    elif [ $1 == 1 ]; then
        echo "CRIT: $2"
	    echo "CRIT: Exiting ... " 
        exit 1
    fi
}

# Check if run as root!
clear
[[ $EUID -ne 0 ]] && run_log 1 "Must be run as root!"

#################################################################################
# End Script & Echo Install command 
end_script_echo () {
run_log 6 "

   Thank you for downloading CCIO utils. 
   
   Run the following command to continue:
      
       $ sudo ccio-install
       
       "
exit 0
}

#################################################################################
# Write ccio.conf
seed_ccio_conf () {
run_log 0 "Checking service names ..."

# Determine host system's service names for LXD
lxd_SVC_NAME_CHECK=$(systemctl list-unit-files \
                    | grep -E "lxd.service|snap.lxd.daemon.service" \
                    | awk '{print $1}')

# Check if SVC Name Valid
lxd_SVC_CHECK_SUCCESS="$?"
if [[ $lxd_SVC_CHECK_SUCCESS -ne "0" ]]; then
    lxd_SVC_NAME_CHECK="DISABLED"
    run_log 22 "OVS Service Not Found!"
    run_log 22 "LXD Service: $lxd_SVC_NAME_CHECK"
 else
    run_log 0 "LXD Service: $lxd_SVC_NAME_CHECK"
fi

# Determine host system's service names for OVS
ovs_SVC_NAME_CHECK=$(systemctl list-unit-files \
                    | grep -E "ovs-vswitchd.service|openvswitch-switch.service" \
                    | awk '{print $1}')

# Check if SVC Name Valid
ovs_SVC_CHECK_SUCCESS="$?"
if [[ $ovs_SVC_CHECK_SUCCESS -ne "0" ]]; then
    ovs_SVC_NAME_CHECK="DISABLED"
    run_log 22 "OVS Service Not Found!"
    run_log 22 "OVS Service: $ovs_SVC_NAME_CHECK"
 else
    run_log 0 "OVS Service: $ovs_SVC_NAME_CHECK"
fi

# Determine host system's service names for LibVirt
libvirt_SVC_NAME_CHECK=$(systemctl list-unit-files | awk '/libvirtd/ {print $1}')
libvirt_SVC_CHECK_SUCCESS="$?"

# Check if SVC Name Valid
if [[ $libvirt_SVC_CHECK_SUCCESS -ne "0" ]]; then
    libvirt_SVC_NAME_CHECK="DISABLED"
    run_log 22 "Libvirt Service Not Found!"
    run_log 22 "KVM Service: $libvirt_SVC_NAME_CHECK"
 else
    run_log 0 "KVM Service: $libvirt_SVC_NAME_CHECK"
fi

run_log 0 "LXD Service: $lxd_SVC_NAME_CHECK"
run_log 0 "OVS Service: $ovs_SVC_NAME_CHECK"
run_log 0 "KVM Service: $libvirt_SVC_NAME_CHECK"
         
    # Write ccio.conf
    default_BR_NAME="ovsbr01"
    run_log 0 "Writing ccio.conf ..."

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

    # Purge Old Files
    rm -rf /usr/bin/obb*

    # Download & Install OBB
    run_log 0 "Installing OVS_Bridge_Builder"
    wget -q $url_OBB -O /etc/ccio/tools/obb.sh

    ln /etc/ccio/tools/obb.sh /usr/bin/obb
    chmod +x /usr/bin/obb

}

#################################################################################
# Download virt setup installer
download_virt_requirements () {

    # Remove init dependency
    rm -rf /usr/bin/ccio-install

    # Donwload & Install ccio-build-environment-setup Script
    run_log 0 "Preparing ccio-install utility"
    wget -q $virt_BUILD_ENV_URL -O /etc/ccio/tools/ccio-build-environment-setup.sh

    ln /etc/ccio/tools/ccio-build-environment-setup.sh /usr/bin/ccio-install
    chmod +x /usr/bin/ccio-install

}

#################################################################################
# Create CCIO File System
seed_ccio_filesystem () {

    # Seeding ccio directory
    run_log 0 "Seeding CCIO file system ..."
    mkdir -p /etc/ccio/tools

}

#################################################################################
# Purging Legacy Deb Based LXD Install
purge_legacy_lxd () {

    # Remove debs
    run_log 0 "purging legacy LXD .deb installations"
    apt-get purge -qq lxd lxd-client -y

}

#################################################################################
# Disclaimer Prompt & User Agreement
user_agreement () {

# Disclaimer 
run_log 6 "You are about to wipe all LXD / OpenVSwitch / KVM Configuration.
Are you sure you want to continue?"

# Read User Agreement Response
while true; do
    read -rp "(Enter 'Yes' or 'No'):  " yn
    case $yn in
        [Yy]* ) run_log 6 "Confirmed. Continuing ...
                "
                break
                ;;
        [Nn]* ) run_log 1 "Canceling due to user input ...";
                ;;
            * ) run_log 0 "Please enter 'Yes' or 'No' ...";
    esac
done
}

user_agreement
purge_legacy_lxd 
seed_ccio_filesystem
download_virt_requirements
install_obb
seed_ccio_conf 
end_script_echo
