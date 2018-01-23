#!/bin/bash
# Network Setup script to create and manage LXD & Libvirt OpenVswitch Networks
# This is currently only tested on Arch and Ubuntu-Xenial; YMMV on other
# distros
#
# Requires LXD, Libvirt, and OpenVSwitch services
# Also requires that zfsutils-linux package be installed for LXD or that you
# manually create a "default" storage pool for LXD instead
# 
# Initial prep and variable are set before the body of the script. 
# All actions are executed within functions
# All functions originate from the "RUN" function first
# The "RUN" function starts at the bottom of the script
# All other functions are arranged roughly in the order of the script's logic
# from bottom to top. 

#################################################################################
# TODO BUG FIX LIST
#
# FIX: command line issue where short flag is recognized but long flags do not
# work.
#
# TODO FEATURE REQUEST LIST
# 
# Add logging function
# Add support for LXD+MAAS Integration
# - https://github.com/lxc/lxd/blob/master/doc/containers.md (MAAS Integration)
# Add support for LXD Snap "lxc/lxd.lxc commands" = Should be complete
# Add GRE IFACE Configuration as optional function
# Add Better Error handling & Detection
# Add "--del-port" function
# Add package/dependency install function
# - This is partially complete in the form of a helper "install.sh" script
# Add function to create local LXD Firewall/Gateway Container
# - This will be built in the ccio-utils package
# Add support for other LXD storage configuration options during profile creation
# - negative; this will occur in the ccio-utils package
# Enable multi-distribution detection & setting of service unit name congruence
# - added in release v0.87.a
# Add support for Ubuntu Core OS
# Add Verbose/Quiet run option
# Add new testing script that automates all documented commands 
#
# Review & research:
# - https://github.com/yeasy/easyOVS

#################################################################################
# Script Index:
# 
# 
# - script_VARIABLES (In order of execution top to bottom)
# 
# add_LXD_PORT
# build_OVS_PORT
# dbg_FLAG
# dead_SERVICE_NAME
# delete_NETWORK
# show_HELP
# show_HELP_SHORT 
# show_HELP_LONG
# show_CONFIG
# show_HEALTH
# key_lxd_IFACE_NAME
# key_lxd_IFACE_HWADDR
# key_lxd_IFACE_HOST_NAME
# key_lxd_SET
# libvirt_NAME_LIST
# libvirt_SERVICE_NAME
# libvirt_SERVICE_STATUS
# lxd_CMD
# lxd_NAME_LIST
# lxd_CONT_NAME 
# lxd_NEW_KEY_VAL
# lxd_CONT_IS_REAL
# lxd_PROFILE_NAME 
# lxd_SERVICE_NAME
# lxd_SERVICE_STATUS
# obb_VERSION
# ovs_NAME_LIST
# ovs_BR_NAME
# ovs_BR_DRIVER
# ovs_ADD_PORT 
# ovs_BR_IS_REAL 
# ovs_SERVICE_NAME
# ovs_SERVICE_STATUS
# ovs_IFACE_IS_UNIQUE 
# port_IFACE_HWADDR
# remove_PORT
# 
# - script_functions
# 
# add_lxd_port 
# add_ovs_port
# build_bridge_lxd
# build_bridge_virsh
# bridge_build  
# check_defaults
# config_lxd
# cmd_parse_run      
# check_vars_obb
# config_auto_up
# config_libvirt
# config_libvirt
# check_services_is_enabled
# check_service_health
# delete_bridge_network
# delete_network_bridge
# end_build 
# lxd_set_config
# lxd_set_profile
# lxc_config_set
# lxc_profile_set 
# lxc_network_set 
# lxd_cont_check_if_exists
# ovs_br_check_if_exists 
# ovs_iface_check_if_exists
# print_config 
# port_hwaddr_gen
# print_help_short
# print_help_long
# print_dbg_flags
# rerun_at_function
# remove_network_port
# set_vars_lxd
# set_lxd_defaults
# start_system_service 
# show_host_configuration
# virt_services_is_enabled

# Check if run as root!
if [[ "$EUID" -ne "0" ]]; then
	echo "ERROR: Must be run as root priviledges!" 
	echo "Exiting!"
	exit 1
fi
      
# Set Bridge-Builder Variables 
# Used unless otherwise set by flags at run-time
echo "[o00.0b] Setting Default Variables"
OBB_VERSION=v00.87.a
# Check for pre-determined system values
# If present, will set value for the `CONF_FILE` variable.
# If CONF_FILE ualue = enabled
if [ -f /etc/ccio/ccio.conf ]; then
    echo "$SEP_2 Detected ccio.conf, loading configuration ..."
    source /etc/ccio/ccio.conf
    if [ $conf_FILE_VARS = true ]; then
        echo "Found ccio.conf"
        echo "ccio.conf Enabled"
    fi
    if [ ! -f /etc/ccio/ccio.conf]; then
        echo "CCIO environment not found"
        option_INSTALL_CCIO_ENV="true"
    fi
fi

# Read variables from command line
echo "$SEP_2 Enabling Command Line Options"
OPTS=`getopt -o pdhbsHz: --long help,name,show,health,delbr: -n 'parse-options' -- "$@"`
#OPTS=`getopt -o phnsHz: --long help,name,show,health,purge: -n 'parse-options' -- "$@"`

# Fail if options are not sane
echo "$SEP_2 Checking Command Line Option Sanity"
if [ $? != 0 ] ; 
    then echo "$SEP_2 Failed parsing options ... Exiting!" >&2 ; 
        exit 1
fi

eval set -- "$OPTS"

# Parse variables
echo "$SEP_2 Parsing Command Line Options"
while true; do
    case "$1" in
        -h                ) 
               SHOW_HELP="true"; 
               shift 
               ;;
             --help       ) 
               SHOW_HELP="true" 
               SHOW_HELP_LONG="true"; 
               shift 
               ;;
        -b | --add-bridge ) NETWORK_NAME="$3"; shift; shift ;;
        -s | --show-config) SHOW_CONFIG=true; shift;;
        -H | --health     ) 
            SHOW_HEALTH=true ; 
            shift 
            ;;
        -d | --delbr      ) 
             PURGE_NETWORK="$3"; 
#             shift; 
             shift 
             ;;
        -p | --port-add   ) 
            OVS_BRIDGE_NAME="$3"
            OVS_ADD_PORT="$4" 
            LXD_CONT_NAME="$5"; 
            shift 
            shift 
            ;;
#            --del-port   ) PURGE_PORT="$3"; shift; shift ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
done
echo "[o00.0e]$SEP_1"

#################################################################################
#Print option values
print_switch_vars () {
if [ $print_DBG_FLAGS = "true" ]; then
echo "[d00.0b]$SEP_1"
echo "       | SHOW_HELP        =  $SHOW_HELP"
echo "       | SHOW_HELP_LONG   =  $SHOW_HELP"
echo "       | NETWORK_NAME     =  $NETWORK_NAME"
echo "       | SHOW_CONFIG      =  $SHOW_CONFIG"
echo "       | SHOW_HEALTH      =  $SHOW_HEALTH"
echo "       | PURGE_NETWORK    =  $PURGE_NETWORK"
echo "       | OVS_ADD_PORT     =  $OVS_ADD_PORT"
echo "       | OVS_BRIDGE_NAME  =  $OVS_BRIDGE_NAME"
echo "       | LXD_CONT_NAME    =  $LXD_CONT_NAME"
echo "       | Confirmed command line options are useable .... Continuing"
echo "[d00.0e]$SEP_1"
fi
}

#################################################################################
# Debug output & Testing break
print_dbg_flags () {
if [ $show_DBG_FLAGS = "true" ]; then
        echo "$dbg_FLAG"
fi
if [ $dbg_BREAK = "true" ]; then
    print_switch_vars
    exit 0
fi
}

#################################################################################
# Confirm end of setup script 
end_BUILD () {
echo "[f0e.0r] OpenVswitch $NETWORK_NAME Build complete for LXD and KVM"
}

#################################################################################
# Add ifup network config file to interfaces.d
set_iface_auto_up () {
cat <<EOF >/etc/network/interfaces.d/iface-$ovs_BR_NAME.cfg

auto $ovs_BR_NAME
iface $ovs_BR_NAME inet manual
EOF
}

#################################################################################
# Prompt for Network startup on boot
config_auto_up () {
if [ -f /root/iface.cfg ]; 
    then
        echo "$SEP_2 OBB can raise the $NETWORK_NAME bridge & and configure to auto up."
        while true; do
            read -p "$SEP_2 Would you like the $NETWORK_NAME bridge to start on boot?  " yn
            case $yn in
                [Yy]* ) 
                      echo "Enabling OVS $NETWORK_NAME bridge on boot"; 
                      set_AUTO_UP="true"
                      break
                      ;;
                [Nn]* ) 
                      echo "Not enabling bridge autostart on boot"
                      break
                      ;;
                * ) echo "Please answer yes or no.";;
            esac
    done
    else 
        echo "$SEP_2 'iface.cfg' file not found"
        echo "$SEP_2 Not running function to auto enable on boot"
fi
if [ $enable_AUTO_UP = "true" ]; 
    then
        config_IFACE_UP
fi
}

#################################################################################
# Create VIRSH Network XML Configuration File
write_config_network_virsh () {

# Set VIRSH Working Variables
virsh_XML_FILE="$ovs_BR_NAME.xml"
virsh_XML_TARGET="$tmp_FILE_STORE/$virsh_XML_FILE"

# Create temp file storage director
mkdir -p $tmp_FILE_STORE

# Write xml configuration
echo "[f08.2r] Writing configuration > $virsh_XML_TARGET"
cat >$virsh_XML_TARGET <<EOF
<network>
  <name>$ovs_BR_NAME</name>
  <forward mode='bridge'/>
  <bridge name='$ovs_BR_NAME' />
  <virtualport type='openvswitch'/>
</network>
EOF

echo "Done Writing $virsh_XML_FILE"
}

#################################################################################
# Write virsh network xml & define new virsh network
build_bridge_virsh () {
echo "Configuring Network Definitions for Libvirtd+KVM+QEMU"

# Run xml creatioin function
write_config_network_virsh

# Defining libvirt network $ovs_BR_NAME
virsh net-define $virsh_XML_TARGET 
echo "> Defined virsh network from $virsh_XML_FILE"

#Starting Libvirt network
virsh net-start $ovs_BR_NAME

# Setting network to auto-start at boot
virsh net-autostart $ovs_BR_NAME

echo "[f08.0e] Done Configuring Libvirt $ovs_BR_NAME"
}

#################################################################################
# Create LXD Profile matching network bridge name
build_profile_lxd () {
echo "[f07.1r] Building LXD Profile \"$ovs_BR_NAME\""
$$lxd_CMD profile create $lxd_PROFILE_NAME
$lxd_CMD profile device add $lxd_PROFILE_NAME $ovs_BR_NAME nic nictype=bridged parent=$ovs_BR_NAME
$lxd_CMD profile device add $lxd_PROFILE_NAME root disk path=/ pool=default
}

#################################################################################
# Create initial bridge with OVS driver & configure LXD
build_network_lxd () {
echo "[f07.1r] Building LXD Network \"$ovs_BR_NAME\" using \"$bridge_DRIVER\" driver"

# Create network 
echo "[f07.1r]"
$lxd_CMD network create $ovs_BR_NAME

# Set LXD Network Keys
echo "[f07.1r]"
for key_lxd_SET in $key_lxd_NETWORK_SET; do
    lxc_network_set
done
}

#################################################################################
# Check for user confirmation if running with default ovs-bridge name
check_vars_obb () {
echo "[f06.1r] Validating OVS Bridge Name ... "
check_DEFAULT_CONFIRM_1=" > A Name has not been declared for the OVS Bridge, using default values ... " 
check_DEFAULT_CONFIRM_2=" > Are you sure you want to continue building the $ovs_BR_NAME bridge?  "
if [ $ovs_BR_NAME == $default_BR_NAME ]; then
        echo "$check_DEFAULT_CONFIRM_1"
        while true; do
            read -p " > $check_DEFAULT_CONFIRM_2" yn
            case $yn in
                [Yy]* ) echo "Continuing ...."; 
                      break
                      ;;
                [Nn]* ) 
                      echo " > ERROR: Canceling due to user input!"
                      exit
                      ;;
                * ) echo " > Please answer yes or no.";;
            esac
    done
    else 
        echo "[f06.3r]----------------------------------------------------------"
        echo "       | Preparing to configure $ovs_BR_NAME"
fi
echo "[f06.0e]$SEP_1"
}

#################################################################################
# Define default lxd provisioning variables
set_vars_lxd () {
echo "[f05.0r] Setting additional LXD Network and Profile Build Variables"

# Configure DHCP function
v4_DHCP="false"
v6_DHCP="false"

# Configure Routing/NAT'ing function - Valid Options "true|false" 
v4_ROUTE="false"
v6_ROUTE="false"

# Define Network Key Values
key_lxd_NETWORK_SET="key_lxd_BR_DRIVER='bridge.driver $ovs_BR_DRIVER' \
                     key_lxd_v4_ADDR='key_lxd_ipv4.address none'      \
                     key_lxd_v6_ADDR='key_lxd_ipv6.address none'      \
                     key_lxd_v4_FW='ipv4.firewall $v4_ROUTE'          \
                     key_lxd_v6_FW='ipv6.firewall $v6_ROUTE'          \
                     key_lxd_v4_NAT='ipv4.nat $v4_ROUTE'              \
                     key_lxd_v6_NAT='ipv6.nat $v6_ROUTE'              \
                     key_lxd_v4_ROUTING='ipv4.routing $v4_ROUTE'      \ 
                     key_lxd_v6_ROUTING='ipv6.routing $v6_ROUTE'      \ 
                     key_lxd_v4_DHCP='ipv4.dhcp $v4_DHCP'             \ 
                     key_lxd_v6_DHCP='ipv6.dhcp $v6_DHCP'             "
echo "[f05.0r]"

lxd_PROFILE_NAME="$ovs_BR_NAME"
}

#################################################################################
# Core Bridge Builder Feature
# This function calls the child functions which build the bridge and configure
# client services such as LXD and KVM+QEMU (virsh) for use with OVS
bridge_build () {
rerun_at_function="bridge_build"
echo "[f04.1r]> Checking System Readiness"
check_services_is_enabled
echo "[f04.2r]> Setting LXD Default Variables"
set_vars_lxd
echo "[f04.3r]> Checking Variables"
check_vars_obb
echo "[f04.4r]> Purging pre-existing $ovs_BR_NAME configuration"
delete_bridge_network
echo "[f04.5r]> Starting LXD Configuration"
build_bridge_lxd
echo "[f04.6r]> Starting LIBVIRT Configuration"
build_bridge_virsh
echo "[f04.0s]>"
print_config
}

#################################################################################
# Set LXD Network Key Values
lxc_network_set () {
    $lxd_CMD network set $ovs_BR_NAME $key_lxd_SET
    echo "Set LXD Network \"$ovs_BR_NAME\" key to \"$key_lxd_SET\""
}

#################################################################################
# Set LXD Profile Key Values
lxc_profile_set () {
    $lxd_CMD profile set $lxd_PROFILE_NAME $key_lxd_SET
    echo "Set LXD Profile \"$lxd_PROFILE_NAME\" key to \"$key_lxd_SET\""
}

#################################################################################
# Set LXD Container Key Values
lxc_container_set () {
    $lxd_CMD config set $lxd_CONT_NAME $key_lxd_SET
    echo "Set LXD Container \"$lxd_CONT_NAME\" key to \"$lxd_NEW_KEY_VAL\""
}

#################################################################################
# Set LXD Daemon Key Values
lxc_container_set () {
    $lxd_CMD config set $key_lxd_SET
    echo "Set LXD Daemon key to \"$lxd_NEW_KEY_VAL\""
}

#################################################################################
# Check if interface name is already configured
ovs_iface_check_if_exists () {
for br in $(ovs-vsctl list-br); do 
    ovs-vsctl list-ports $br | grep $ovs_ADD_PORT 
    ovs_IFACE_IS_UNIQUE="$?"
    if [ $ovs_IFACE_IS_UNIQUE = "0" ]; then 
        echo "WARN: Found $ovs_ADD_PORT port on the $br OVS Bridge."
    elif [ $ovs_IFACE_IS_UNIQUE != "0" ]; then 
        echo "Port Name $ovs_ADD_PORT does not appear to be in use."
    fi
done
}


#################################################################################
# Check if lxd container name exists on host
lxd_cont_check_if_exists () {
    $lxd_CMD list --format=csv -c n | grep $lxd_CONT_NAME ;
    lxd_CONT_IS_REAL="$?"
}

#################################################################################
# Check if bridge name exists on host 
ovs_br_check_if_exists () {
    ovs-vsctl list-br | grep $ovs_BRIDGE_NAME
    ovs_BR_IS_REAL="$?"
}

#################################################################################
# Generate unique hardware mac address for interface
# Uses container name, bridge name, and interface name as unique md5sum input
# Will be globally unique while also being repeatable if required
port_hwaddr_gen () {
combined_HASH_INPUT="$ovs_BRIDGE_NAME$lxd_CONTAINER_NAME$port_IFACE_NAME"
port_IFACE_HWADDR=$( \
    echo "$combined_HASH_INPUT" \
    | md5sum \
    | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/02:\1:\2:\3:\4:\5/')
}

#################################################################################
# Add interface to LXD Container on OVS Bridge
# Format: command [option] [bridge-name] [interface-name] [container-name]
# Command Example: 
#   obb -p br0 eth2 container1
# Checks value sanity on:
# - Bridge Name
# - Container Name
# - Interface Name
# If all values are sensible, will:
# - Create a new network interface named as specified in command
# - Attach new port to container specified
# - Attach new port to OVS Bridge specified
# - Set LXD container property to make interface name persistent
add_ovs_port () {
echo "[f09.1r]"
if [ $lxd_CONT_NAME != "false" ]; then
    
    # Check if bridge name exists
    # fail if bridge does not exist
    echo "Checking for variable sanity"
    ovs_br_check_if_exists
    if [ $ovs_BR_IS_REAL = "0" ]; then
        echo "$SEP_2 Found $ovs_BR_NAME" 
    else
        echo "$SEP_2 Found the following bridge names:"
        ovs-vsctl list-br
        echo "$SEP_2 Aborting port configuration due to error!"
        echo "$SEP_2 ERROR: Bridge Name Not Found!"
    exit 1
    fi

    # Check if container name exists
    # Fail if container name does not exist
    lxd_cont_check_if_exists
    if [ $lxd_CONT_IS_REAL = "0" ]; then
        echo "$SEP_2 Found $lxd_CONT_NAME" 
    else
        echo "$SEP_2 Available Containers:
        "
        $lxd_CMD list --format=csv -c n
        echo ""
        echo "$SEP_2 Aborting port configuration due to error!"
        echo "$SEP_2 ERROR: Container Not Found!"
    exit 1
    fi

    # check if port name already exists
    # fail if a port matching this name already exists
    ovs_iface_check_if_exists
    if [ $ovs_IFACE_IS_UNIQUE != "0" ]; then
        echo "$SEP_2 Confirmed Port Name $ovs_ADD_PORT is useable "
    fi
    if [ $ovs_IFACE_IS_UNIQUE = "0" ]; then
        echo "$SEP_2 Aborting port configuration due to error!"
        echo "$SEP_2 ERROR: Interface Name $ovs_ADD_PORT already in use!"
        exit 1
    fi

# Generate unique hardware mac address for interface
port_hwaddr_gen

# Generate lxd container key values
# ~IFACE_NAME sets the name of the device in the lxd configuration file
# ~IFACE_HOST_NAME creates a persistent ovs bridge device name
# ~IFACE_HWADDR uses the port_HWADDR_GEN value to set a static and repeatable mac
key_lxd_IFACE_NAME="volatile.$ovs_ADD_PORT.name $ovs_ADD_PORT"
key_lxd_IFACE_HOST_NAME="volatile.$ovs_ADD_PORT.host_name $ovs_ADD_PORT"
key_lxd_IFACE_HWADDR="volatile.$ovs_ADD_PORT.hwaddr $port_IFACE_HWADDR"

    # Create interface and attach to LXD
    # Set key values for IFACE_NAME, IFACE_HOST_NAME, and IFACE_HWADDR
    echo "Attaching LXD Container $lxd_CONT_NAME to:" 
    echo "          OVS Bridge:   $ovs_BRIDGE_NAME"
    echo "          On Port:      $ovs_ADD_PORT"
    if [ $ovs_BR_IS_REAL = "0" ] && \
       [ $lxd_CONT_IS_REAL = "0" ] && \
       [ $ovs_IFACE_IS_UNIQUE != "0" ]; then
            $lxd_CMD network attach $ovs_BR_NAME $lxd_CONT_NAME $ovs_ADD_PORT
        for lxd_NEW_KEY_VAL in \
            $key_lxd_IFACE_NAME \
            $key_lxd_IFACE_HOST_NAME \
            $key_lxd_IFACE_HWADDR;
        do   
            lxd_set_config
        done
    fi
fi
echo "[f09.2r]"
}

#################################################################################
# Remove network bridge by name 
# TODO add feature to prompt for confirmation & disconnect any containers on
#      bridbridge to gracefully avoid error out/failure
delete_network_bridge () {

# Purge networks by name ) --purge | -p
if [ $delete_NETWORK != "false" ]; then
    ovs_BR_NAME="$delete_NETWORK"
    ovs_br_check_if_exists 
    echo "Found $ovs_BR_NAME"
    if [ $ovs_BR_IS_REAL = "0" ]; then

        # Remove lxd network and profile
        echo "[f03.1r] Purging $delete_NETWORK from LXD Network and Profile configuration"
        $lxd_CMD network delete $delete_NETWORK > /dev/null 2>&1 ;
        $lxd_CMD profile delete $delete_NETWORK > /dev/null 2>&1 

        # Remove virsh network configuration
        echo "[f03.2r] Purging $delete_NETWORK from Libvirt Network Configuration"
        virsh net-undefine $delete_NETWORK > /dev/null 2>&1 ;
        virsh net-destroy $delete_NETWORK > /dev/null 2>&1 ;

        # Remove OVS Bridge
        echo "[f03.3r] Purging OpenVswitch Configuration"
        ovs-vsctl del-br $delete_NETWORK > /dev/null 2>&1  ;

        # Remove ifup file
        rm /etc/network/interfaces.d/iface-$ovs_BR_NAME.cfg

        # Confirm when done
        echo "$SEP_2 Finished Purging $delete_NETWORK from system"

    elif [ $ovs_BR_IS_REAL != "0" ]; then
        echo "$delete_NETWORK is not configured on this system"
    fi
fi
}

#################################################################################
# Start dead service if service found to not be running
# Will also attempt to enable the service at boot as well
start_system_service () {
dbg_FLAG="[f3h.0o] $dead_SERVICE_NAME not running, attempting to re-start..." && print_dbg_flags; 

# try to start dead service
systemctl start $dead_SERVICE_NAME
wait 10
systemctl is-active $dead_SERVICE_NAME

# If the dead service is not enabled:
# 1. attempt to enable the service
# 2. if the service cannot be enabled, print warning
# 3. if all stopped services start successfully, attempt re-run previous
#    function
if [ $(systemctl is-enabled "$dead_SERVICE_NAME") != "0" ]; then
    systemctl enable $dead_SERVICE_NAME
    if [ $? != "0" ]; then
        echo "WARN: $dead_SERVICE_NAME is not currently enabled to start at boot"
        echo "WARN: and OBB was unable to enable the service"
    fi
fi

# If service starts successfully, attempt to re-run the previous function
# ... or die trying
if [ $? = 0 ]; then
    dbg_FLAG="[f3h.0o] Successfully restarted $dead_SERVICE_NAME" && print_dbg_flags; 
    dbg_FLAG="[f3h.0o] Retrying $rerun_start_function" && print_dbg_flags; 
    rerun_at_function
elif [ $(systemctl is-active $dead_SERVICE_NAME) != 0 ]; then
        echo "ERROR: Unable to start dead service $dead_SERVICE_NAME!"
        echo "Unrecoverable error ... Aborting!"
    exit 1
fi
}

#################################################################################
# Check that required services are running
virt_services_is_enabled () {

# Load System Service Status
ovs_SERVICE_STATUS=$(systemctl is-active $ovs_SERVICE_NAME)
lxd_SERVICE_STATUS=$(systemctl is-active $lxd_SERVICE_NAME)
libvirt_SERVICE_STATUS=$(systemctl is-active $libvirt_SERVICE_NAME)

# Display Service Status
dbg_FLAG="[f3h.0o] Showing Local service health:" && print_dbg_flags; 
echo "$ovs_SERVICE_NAME = $ovs_SERVICE_STATUS"
echo "$lxd_SERVICE_NAME = $lxd_SERVICE_STATUS"
echo "$libvirt_SERVICE_NAME = $libvirt_SERVICE_STATUS"

# If OVS Service is not active, error & attempt to start service
if [ "$ovs_SERVICE_STATUS" != active ]; then
    dead_SERVICE_NAME="ovs_SERVICE_NAME"
    echo "ERROR: The OpenVSwitch System Service is NOT RUNNING"
    echo "Attempting to start $dead_SERVICE_NAME"
    start_system_service 
fi

# If LXD Service is not active, error & attempt to start service
if [ "$lxd_SERVICE_STATUS" != "active" ]; then
    dead_SERVICE_NAME="lxd_SERVICE_NAME"
    echo "ERROR: The LXD System Service IS NOT RUNNING"
    echo "Attempting to start $dead_SERVICE_NAME"
    start_system_service 
fi

# If Libvirtd Service is not active, error & attempt to start service
if [ "$libvirt_SERVICE_STATUS" != "active" ]; then
    dead_SERVICE_NAME="libvirt_SERVICE_NAME"
    echo "$SEP_2 ERROR: The LibVirtD System Service IS NOT RUNNING"
    echo "Attempting to start $dead_SERVICE_NAME"
    start_system_service 
fi
}

#################################################################################
# Show current networks configured for OVS/LXD/KVM+QEMU ) --show | -s
print_config () {
rerun_at_function="show_config"

# Check that required services are running
virt_services_is_enabled

# List Openvswitch Networks
dbg_FLAG="[f3h.0o] Showing Local Bridge Configuration" && print_dbg_flags; 
if [ "$libvirt_SERVICE_STATUS" = "active" ] && \
       [ "$lxd_SERVICE_STATUS" = "active" ] && \
       [ "$ovs_SERVICE_STATUS" = "active" ]; then

    dbg_FLAG="[f3h.0o] Showing Local Bridge Configuration" && print_dbg_flags; 
    
    # List OpenVSwitch Networks
    echo "  > OpenVSwitch Network Configuration <"
    ovs-vsctl show

    # List LXD Networks
    echo "  > LXD Network Configuration <"
    $lxd_CMD network list

    # List LibVirtD Networks
    echo "  > LibVirtD Network Configuration < "
    virsh net-list --all
fi
}

#################################################################################
# Show Help menu short format ) --help | -h
print_help_short () {
    dbg_FLAG="[f1h.1r]" && print_dbg_flags; 
    echo "
    OpenVSwitch Bridge Builder 

    syntax: command [option] [value]

    Options:
                         -h    --    Print the basic help menu
       --help                  --    Print the extended help menu
       --                -H    --    Check OVS|LXD|Libvirtd Service Status
       --                -s    --    Show current networks configured locally
       --                -p    --    Add port to bridge and optionally connect
                                     port to container named. 
                                     Value Ordering:
                                        [bridge] [port] [container] 
       --                -d    --    Deletes network when pased with a value
                                     matching an existing network name.
       --                -b    --    Sets the name for building the following: 
                                        OVS Bridge
                                        Libvirt Bridge
                                        LXD Network & Profile Name
"
if [ $show_HELP_LONG = "false" ]; then
    dbg_FLAG="[f1h.1e]" && print_dbg_flags; 
fi
}

#################################################################################
# Show Help menu long format ) --help | -h
print_help_long () {
    dbg_FLAG="[f2h.1r]" && print_dbg_flags; 
    echo "
       Learn more or contribute at:
           https://github.com/containercraft/hypervisor

       This tool will create a new OVS bridge. The OVS bridge can be used for
       connecting physical ports, lxd containers, libvirt guests, and building
       logical openvswitch vxlan overlays spanning multiple physical hosts. 

       By default, this bridge will be ready for use with each of the following:
________________
    \\           \\
     \\_LXD:
        \\_______       
                \_Launch a container with the \"lxd profile\" flag to attach
                |    Example:                                               
                |      $ lxc launch ubuntu: test-container -p \$NETWORK_NAME 

       Libvirt Guests:
        \_______
                \_Attach Libvirt / QEMU / KVM guests:
                |   Example:
                |     virt-manager nic configuration
                |     virsh xml configuration

       Physical Ports:
        \_______
                \_Attach Physical Ports via the following
                |   Example with physical device name "eth0"
                |      ovs-vsctl add-port $NETWORK_NAME eth0

       Logical Ports:
        \_______
                \_Create and Attach Logical Ports via the following
                |   Examples with the following criteria:
                |
                |                OVS Bridge Name:  mybridge
                |              New OVS Port-Name:  eth0
                |                  LXD Container:  mycontainer < (optional)
                |
                |      $ obb --add-port mybridge eth0  
                |      $ obb --add-port mybridge eth0 mycontainer
________________/
"
    dbg_FLAG="[f2h.1e]" && print_dbg_flags; 
}

read_MORE () {
    echo "
       The CCIO build environmet provides the base build environment for local
       virtual infrastructure development. Your system will also be configured 
       with the DEVELOPMENT CCIO Utils Development packages into /etc/ccio/. 
       
       Installation will also include:
            
             OpenVSwitch
             Libvirtd 
             QEMU
             KVM
             LXD

       Learn more and contribute at:
           https://github.com/containercraft/hypervisor

       ~~ WARNING THIS IS A DEVELOPMENT BUILD - UNDERSTAND THE MEANING OF ALPHA ~~
    "
option_install_ccio_run 
}

#################################################################################
# Option Run CCIO Installer
option_install_ccio_run () {
inst_URL="https://raw.githubusercontent.com/containercraft/hypervisor/master/install-ccio-hypervisor.sh"
if [ $option_INSTALL_CCIO_ENV = 'true' ]; then
        echo "Would you like to install CCIO?" 
        read -p "$SEP_2 Would you like to install CCIO?  " ryn
        case $ryn in
            [Yy]* ) 
                  echo "Installing CCIO"; 
                  curl $inst_URL | bash
                  break
                  ;;
            [Nn]* ) 
                  echo "Not enabling bridge autostart on boot"
                  break
                  ;;
            [Rr]* ) 
                  read_MORE
                  break
                  ;;
                * ) echo "Please answer yes or no.";;
        esac
fi
}

#################################################################################
# Initial function that determines behavior from command line flags
cmd_parse_run () {
if [ $option_INSTALL_CCIO_ENV = 'true' ]; then
echo "CCIO Environment not detected. Cannot continue running OBB"
    option_install_ccio_run
fi
if [ $show_HELP = 'true' ]; then
    dbg_FLAG="[f0h.0o]" && print_dbg_flags; 
    if [ $show_HELP_LONG = 'false' ]; then
        dbg_FLAG="[f1h.0r]" && print_dbg_flags; 
        print_help_short
        dbg_FLAG="[f1h.0c] OVS_BridgeBuilder_VERSION = $obb_VERSION" && print_dbg_flags; 
    exit 0
    elif [ $show_HELP_LONG = 'true' ]; then
        dbg_FLAG="[f1h.0r]" && print_dbg_flags; 
        print_help_short
        print_help_long
        dbg_FLAG="[f1h.0c] OVS_BridgeBuilder_VERSION = $obb_VERSION" && print_dbg_flags; 
    exit 0
    fi
fi
if [ $show_CONFIG != 'false' ]; then
        dbg_FLAG="[f3h.0o]" && print_dbg_flags; 
        print_config
        dbg_FLAG="[f3h.0c]" && print_dbg_flags; 
    exit 0
fi
if [ $show_HEALTH != 'false' ]; then
        dbg_FLAG="[f4h.0o]" && print_dbg_flags; 
        virt_services_is_enabled
        dbg_FLAG="[f4h.0c]" && print_dbg_flags; 
    exit 0
fi
if [ $delete_NETWORK != 'false' ]; then
        dbg_FLAG="[f1d.0o] Purging $delete_NETWORK ..." && print_dbg_flags;
        delete_network_bridge
        show_host_configuration
        dbg_FLAG="[f1d.0c] Removed $ delete_NETWORK Bridge" && print_dbg_flags; 
    exit 0
fi
if [ $remove_PORT = 'true' ]; then
        dbg_FLAG="[f1r.0o] Purging $delete_NETWORK ..." && print_dbg_flags;
        remove_network_port
        show_host_configuration
        dbg_FLAG="[f1r.0c] Removed $ delete_NETWORK Bridge" && print_dbg_flags; 
    exit 0
fi
if [ $build_OVS_PORT != 'false' ]; then
    dbg_FLAG="[f1b.0o] Adding a new OVS Port" && print_dbg_flags; 
    if [ $lxd_CONT_NAME = "false" ]; then
        dbg_FLAG="[f1b.1b] Building Stand-alone OVS Port" && print_dbg_flags; 
        add_ovs_port
        dbg_FLAG="[f1b.0c] Done" && print_dbg_flags; 
    exit 0
    elif [ $lxd_CONT_NAME != "false" ]; then
        dbg_FLAG="[f1b.2b] Creating a new bridge port for LXD" && print_dbg_flags; 
        lxd_cont_check_if_exists
        if [ $lxd_CONT_IS_REAL = "0" ]; then
            dbg_FLAG="[f1b.3b] Adding OVS port $build_OVS_PORT to $lxd_CONT_NAME" && print_dbg_flags; 
            add_lxd_port
            dbg_FLAG="[f1b.3e] $build_OVS_PORT Port created $lxd_CONT_NAME" && print_dbg_flags; 
        fi
        dbg_FLAG="[f1b.0c] Done Building new OVS Port" && print_dbg_flags; 
    exit 0
    fi
fi
if    [ $build_OVS_PORT == 'false' ]  && \
      [ $delete_NETWORK == 'false' ]  && \
         [ $remove_PORT == 'false' ]  && \
         [ $show_CONFIG == 'false' ]  && \
         [ $show_HEALTH == 'false' ]  && \
           [ $show_HELP == 'false' ]; then
        dbg_FLAG="[f2b.0o]" && print_dbg_flags; 
        bridge_build
        dbg_FLAG="[f2b.1r]" && print_dbg_flags; 
        end_build
        dbg_FLAG="[f2b.0c]" && print_dbg_flags; 
    exit 0
else
dbg_FLAG="[f2b.0h] ERROR: Unable to parse comand line options .. EXITING!" && print_dbg_flags; 
exit 0
fi
}

# Start initial function that determines behavior from command line flags
cmd_parse_run
