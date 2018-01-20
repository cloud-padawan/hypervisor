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
# Add support for LXD Snap "lxc/lxd.lxc commands"
# - this feature should be partially enabled in the 'check_service_names'
# - function which should switch the lxc/lxd.lxc command variable triggering
# - 'lxd_SET_PROFILE' and 'lxd_SET_CONFIG' command to operate off that value   
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
# obb_VERSION
# dbg_FLAG
# show_HELP_SHORT 
# show_HELP_LONG
# show_CONFIG
# show_HEALTH
# remove_PORT
# delete_NETWORK
# add_OVS_PORT
# add_LXD_PORT
# lxd_NAME_LIST
# lxd_CONT_NAME 
# lxd_CONT_IS_REAL
# lxd_SERVICE_NAME
# lxd_SERVICE_STATUS
# ovs_NAME_LIST
# ovs_SERVICE_NAME
# ovs_SERVICE_STATUS
# libvirt_NAME_LIST
# libvirt_SERVICE_NAME
# libvirt_SERVICE_STATUS
#
# - script_functions
# 
# cmd_parse_run      
# show_config 
# print_help_short
# print_help_long
# print_dbg_flags
# check_service_health
# add_lxd_port 
# add_ovs_port
# lxd_cont_check_if_exists
# delete_network_bridge
# show_host_configuration
# bridge_build  
# end_build 

# Check if run as root!
if [[ "$EUID" -ne "0" ]]; then
	echo "ERROR: Must be run with root/sudo priviledges!" 
	echo "Exiting!"
	exit 1
fi
      
# Set Output Formatting Variables:
SEP_1="------------------------------------------------------------------+"
SEP_2="       |"
SEP_3="       +"

# Set Bridge-Builder Variables 
# Used unless otherwise set by flags at run-time
echo "[o00.0b]$SEP_1"
echo "$SEP_2 Setting Default Variables"
OBB_VERSION=v00.87.a
# Check for pre-determined system values
# If present, will set value for the `CONF_FILE` variable.
# If CONF_FILE ualue = enabled
if [ -f /etc/ccio/ccio.conf ]; then
    echo "$SEP_2 Detected ccio.conf, loading configuration ..."
    source /etc/ccio/ccio.conf
    if [ $CONF_FILE = true ]; then
        echo "$SEP_2 ccio.conf Enabled"
    fi
#   # Need to add conf file creation routine
#   if [ ! -f /etc/ccio/ccio.conf]; then
#       echo ""
#   fi
fi

# Determine Distribution and Package Specific System Service Names
check_service_names () {
# List 
lxd_NAME_LIST="\
lxd.service|\
snap.lxd.daemon.service"
ovs_NAME_LIST="\
ovs-vswitchd.service|\
openvswitch-switch.service"
libvirt_NAME_LIST="\
libvirtd.service"

for svc_UNK in lxd_NAME_LIST ovs_NAME_LIST libvirt_NAME_LIST; do
    systemctl list-unit-files \
        | grep -E "$svc_UNK" \
        | $svc_UNK=$(awk '{print $1}')
done
echo "Detected $LXD_"
lxd_SERVICE_NAME="snap.lxd.daemon"
ovs_SERVICE_NAME="openvswitch-switch.service"
libvirt_SERVICE_NAME="libvirtd.service"
}

# Default Variables
# Used unless otherwise set in ccio.conf or at command line
# Debug & Verbosity Settings:
print_DBG_FLAGS="true"
dbg_BREAK="true"
# Operating Variables
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
work_DIR=$(pwd)
running_function="false"

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
print_vars () {
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
if [ $print_DBG_FLAGS = "true" ]; then
        echo "$dbg_FLAG"
fi
if [ $dbg_BREAK = "true" ]; then
    print_vars
    exit 0
fi
}

#################################################################################
end_BUILD () {
# Confirm end of setup script 
echo "[f0e.0s]$SEP_1"
echo "$SEP_2 $NETWORK_NAME Build complete for LXD and KVM"
echo "[f0e.0e]$SEP_1"
}

#################################################################################
config_IFACE_UP () {
cat <<EOF >>/root/iface.cfg

auto $NETWORK_NAME
iface $NETWORK_NAME inet manual
EOF
}

#################################################################################
config_AUTO_UP () {
if [ -f /root/iface.cfg ]; 
    then
        echo "$SEP_2 OBB can raise the $NETWORK_NAME bridge & and configure to auto up."
        while true; do
            read -p "$SEP_2 Would you like the $NETWORK_NAME bridge to start on boot?  " yn
            case $yn in
                [Yy]* ) 
                      echo "Enabling OVS $NETWORK_NAME bridge on boot"; 
                      enable_AUTO_UP="true"
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
config_LIBVIRT () {
# create virsh network xml & define new virsh network
echo "[f08.0s]$SEP_1"
echo "$SEP_2 Configuring Network Definitions for Libvirtd+KVM+QEMU"
# Set VIRSH Working Variables
VIRSH_XML_FILE=$NETWORK_NAME.xml 
VIRSH_XML_PATH="/var/lib/libvirt/network-config" 
VIRSH_XML_TARGET=$VIRSH_XML_PATH/$VIRSH_XML_FILE

# Create xml file path and file
echo "[f08.1r]$SEP_1"
echo "$SEP_2 Creating virsh network xml configuration file"
    mkdir -p $VIRSH_XML_PATH 
echo "$SEP_2 Creating virsh network xml directory"

# Write xml configuration
echo "[f08.2r]$SEP_1"
echo "$SEP_2 Writing configuration: 
$SEP_2       > $VIRSH_XML_PATH/$VIRSH_XML_FILE"
cat >$VIRSH_XML_TARGET <<EOF
<network>
  <name>$NETWORK_NAME</name>
  <forward mode='bridge'/>
  <bridge name='$NETWORK_NAME' />
  <virtualport type='openvswitch'/>
</network>
EOF
echo "$SEP_2 $VIRSH_XML_FILE VIRSH XML Config Written"

# Defining libvirt network $NETWORK_NAME
echo "[f08.3r]$SEP_1"
echo "$SEP_2 Creating virsh network from $VIRSH_XML_TARGET"
echo "$SEP_3
 "
    virsh net-define $VIRSH_XML_TARGET 
echo "$SEP_3"
echo "$SEP_2 > Defined virsh network from $VIRSH_XML_FILE"

#Starting Libvirt network
echo "$SEP_3"
echo "[f08.4r] Starting virsh $NETWORK_NAME"
echo "$SEP_3
 "
virsh net-start $NETWORK_NAME
# Setting network to auto-start at boot
echo "$SEP_3"
echo "$SEP_2 Switching virsh $NETWORK_NAME to autostart"
echo "$SEP_3
 "
virsh net-autostart $NETWORK_NAME

echo "$SEP_3"
echo "[f08.0e] Done Configuring Libvirt $NETWORK_NAME"
}

#################################################################################
# Create initial bridge with OVS driver & configure LXD
config_LXD () {
# Create network via LXD API
echo "[f07.0s]$SEP_1"
echo "$SEP_2 Building LXD Network \"$NETWORK_NAME\" using \"$BRIDGE_DRIVER\" driver"
echo "$SEP_3
"
lxc network create $NETWORK_NAME 
echo "
$SEP_3"
    echo "$SEP_2 Created LXD Network $NETWORK_NAME"

# Setup network driver type
echo "[f07.1r]$SEP_1"
lxc network set $NETWORK_NAME \
    bridge.driver $BRIDGE_DRIVER 
    echo "$SEP_2 Configured $NETWORK_NAME with $BRIDGE_DRIVER driver"

## DNS configuration Options
# define default domain name:
#echo "[f07.2r]$SEP_1"
#lxc network set $NETWORK_NAME \
#    dns.domain $DNS_DOMAIN 
#    echo "$SEP_2 Configured $NETWORK_NAME with default domain name: $DNS_DOMAIN"  
# define dns mode = set via hostname
#lxc network set $NETWORK_NAME \
#    dns.mode dynamic         

echo "[f07.3r] Disabling LXD IP Configuration"
# Set ipv4 address on bridge
lxc network set $NETWORK_NAME \
    ipv4.address none        
# Set ipv6 address on bridge
lxc network set $NETWORK_NAME \
    ipv6.address none        

# Configure ipv4 & ipv6 address on bridge [true/false]
#echo "[f07.4r] Disabling Bridge Address"
# configure ipv4 nat setting
#lxc network set $NETWORK_NAME \
#    ipv4.nat $NATv4          
#    echo "$SEP_2 Switching ipv4 nat to $NATv4"
# configure ipv4 nat setting
#lxc network set $NETWORK_NAME \
#    ipv6.nat $NATv6          
#    echo "$SEP_2 Switching ipv6 nat to $NATv6"

# Configure routing on bridge [enable/disable]
echo "[f07.5r] Disabling Bridge Routing function"
# set ipv4 routing
#lxc network set $NETWORK_NAME \
#    ipv4.routing $ROUTEv4    
#    echo "$SEP_2 Switching ipv4 routing to $DHCPv4"
# Set ipv6 routing
#lxc network set $NETWORK_NAME \
#    ipv6.routing $ROUTEv6    
#    echo "$SEP_2 Switching ipv6 routing to $DHCPv6"

# configure dhcp on bridge 
# options: true false
echo "[f07.6r] Disabling LXD DHCP Function"
# set ipv4 dhcp
lxc network set $NETWORK_NAME \
    ipv4.dhcp $DHCPv4        
# set ipv6 dhcp
lxc network set $NETWORK_NAME \
    ipv6.dhcp $DHCPv6        

# Bridge nat+router+firewall settings
echo "[f07.7r] Disabling LXD NAT+Firewall Function"
# disable ipv4 firewall 
lxc network set $NETWORK_NAME \
    ipv4.firewall false      
# disable ipv6 firewall
lxc network set $NETWORK_NAME \
    ipv6.firewall false      

# Create associated lxd profile with default ethernet device name and storage
# path
echo "[f07.8r] Creating LXD Profile for $NETWORK_NAME"
echo "$SEP_3
"
lxc profile create $LXD_PROFILE
lxc profile device add $NETWORK_NAME $LXD_PROFILE \
    nic nictype=bridged parent=$NETWORK_NAME
lxc profile device add $LXD_PROFILE \
    root disk path=/ pool=default
echo "
$SEP_3"
echo "[f07.0e] LXD Network \"$NETWORK_NAME\" Configuration Complete"
}

#################################################################################
check_DEFAULTS () {
echo "[f06.0s]$SEP_1"
echo "[f06.1r] Validating All LXD Configuration Variables"
DEFAULT_CHECK_CONFIRM="$SEP_2 > Are you sure you want to continue building the $NETWORK_NAME bridge?  "
if [ $NETWORK_NAME == $DEFAULT_NETWORK_NAME ]
    then
        echo "[f06.2r] WARN: Bridge Builder run with default value for OVS network configuration!"
        while true; do
            read -p "$SEP_2 $DEFAULT_CHECK_CONFIRM" yn
            case $yn in
                [Yy]* ) echo "Continuing ...." ; break;;
                [Nn]* ) 
                      echo "$SEP_2 $SEP_2 > ERROR: Canceling due to user input!"
                      exit
                      ;;
                * ) echo "Please answer yes or no.";;
            esac
    done
    else 
        echo "[f06.3r]----------------------------------------------------------"
        echo "       | Preparing to configure $NETWORK_NAME"
fi
echo "[f06.0e]$SEP_1"
}

#################################################################################
set_LXD_DEFAULTS () {
# Define default DNS domain assignment
echo "[f05.0s]$SEP_1"
echo "$SEP_2 Setting additional LXD Network and Profile Build Variables"

#DNS_DOMAIN="braincraft.io" 
#echo "Setting Default Domain Name to $DNS_DOMAIN"

# Set Working Dir for temp files such as network .xml definitions for KVM+QEMU
IFACE_CFG_DIR="/root/network/"
# Set LXD Profile name to match network name
LXD_PROFILE=$NETWORK_NAME

# Configure default LXD container interface name
LXD_ETHERNET="eth0"

# Configure DHCP function
# Valid options "true|false"
DHCPv4="false"
DHCPv6="false"

# Configure Routing function
# Valid Options "true|false" 
ROUTEv4="false"
ROUTEv6="false"
echo "[f05.0e]$SEP_1"
}

#################################################################################
BUILD () {
# Core Bridge Builder Feature
# This function calls the child functions which build the bridge and configure
# client services such as LXD and KVM+QEMU (virsh) for use with OVS
echo "[f04.0s]$SEP_1"
echo "[f04.1r] > Checking System Readiness"
virt_services_is_enabled
echo "[f04.2r]$SEP_2 > Setting LXD Default Variables"
set_LXD_DEFAULTS
echo "[f04.3r]$SEP_2 > Checking LXD Variables"
check_DEFAULTS
echo "[f04.4r]$SEP_2 > purging any pre-existing $NETWORK_NAME configuration"
purge_NETWORK
echo "[f04.5r]$SEP_2 > Starting LXD Configuration"
config_LXD
echo "[f04.6r]$SEP_2 > Starting LIBVIRT Configuration"
config_LIBVIRT
echo "[f04.7r]$SEP_2 > Running Auto-Up Option"
config_AUTO_UP

show_CONFIG
echo "[f04.0s]$SEP_1"
}

#################################################################################
# Needs Work to integrate
lxd_set_profile () {
    echo "doing something"
}

#################################################################################
lxd_set_config () {
    lxc config set $lxd_CONTAINER_NAME $lxd_NEW_KEY_VAL
    echo "Set $lxd_CONTAINER_NAME $lxe_NEW_KEY_VAL"
}

#################################################################################
ovs_iface_check_if_exists () {
for br in $(ovs-vsctl list-br); do 
    ovs-vsctl list-ports $br | grep $ovs_ADD_PORT 
    ovs_IFACE_IS_UNIQUE="$?"
    if [ $ovs_IFACE_IS_UNIQUE = "0" ]; then 
        echo "WARN: Found $ovs_ADD_PORT port on the $br OVS Bridge."
    fi
done
if [ $ovs_IFACE_IS_UNIQUE != "0" ]; then 
    echo "Port Name $ovs_ADD_PORT does not appear to be in use."
fi
}


#################################################################################
lxd_cont_check_if_exists () {
    lxc list --format=csv -c n | grep $lxd_CONT_NAME ;
    lxd_CONT_IS_REAL="$?"
}

#################################################################################
ovs_br_check_if_exists () {
    ovs-vsctl list-br | grep $ovs_BRIDGE_NAME
    ovs_BR_IS_REAL="$?"
}

#################################################################################
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
add_OVS_PORT () {
echo "[f09.1r]"
if [ $lxd_CONT_NAME != "false" ]; then
    
    # Check if bridge name exists
    # fail if bridge does not exist
    echo "Checking for variable sanity"
    ovs_br_check_if_exists
    if [ $ovs_BR_IS_REAL = 0 ]; then
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
    if [ $lxd_CONT_IS_REAL = 0 ]; then
        echo "$SEP_2 Found $lxd_CONT_NAME" 
    else
        echo "$SEP_2 Available Containers:
        "
        lxc list --format=csv -c n
        echo ""
        echo "$SEP_2 Aborting port configuration due to error!"
        echo "$SEP_2 ERROR: Container Not Found!"
    exit 1
    fi

    # check if port name already exists
    # fail if a port matching this name already exists
    ovs_iface_check_if_exists
    if [ $ovs_IFACE_IS_UNIQUE != 0 ]; then
        echo "$SEP_2 Confirmed Port Name $ovs_ADD_PORT is useable "
    fi
    if [ $ovs_IFACE_IS_UNIQUE = 0 ]; then
        echo "$SEP_2 Aborting port configuration due to error!"
        echo "$SEP_2 ERROR: Interface Name $ovs_ADD_PORT already in use!"
        exit 1
    fi

# Generate unique hardware mac address for interface
# Uses container name, bridge name, and interface name as unique md5sum
# input
# Will be unique to this networkm cintaunerm and unterface name while being
# repeatable if required
port_hwaddr_gen

# Generate lxd container key values
# IFACE_NAME sets the name of the device in the lxd configuration file
# IFACE_HOST_NAME creates a persistent ovs bridge device name
# IFACE_HWADDR uses the port_HWADDR_GEN value to set a static and repeatable mac
key_lxd_IFACE_NAME="volatile.$ovs_ADD_PORT.name $ovs_ADD_PORT"
key_lxd_IFACE_HOST_NAME="volatile.$ovs_ADD_PORT.host_name $ovs_ADD_PORT"
key_lxd_IFACE_HWADDR="volatile.$ovs_ADD_PORT.hwaddr $port_IFACE_HWADDR"

    # Create interface and attach to LXD
    # Set key values for IFACE_NAME, IFACE_HOST_NAME, and IFACE_HWADDR
    echo "Attaching LXD Container $LXD_CONT_NAME to:" 
    echo "          OVS Bridge:   $OVS_BRIDGE_NAME"
    echo "          On Port:      $OVS_ADD_PORT"
    if [ $ovs_BR_IS_REAL = 0 ] && \
       [ $lxd_CONT_IS_REAL = 0 ] && \
       [ $ovs_IFACE_IS_UNIQUE != 0 ]; then
            lxc network attach $ovs_BRIDGE_NAME $lxd_CONTAINER_NAME $ovs_ADD_PORT
        for lxd_NEW_KEY_VAL in \
            $key_lxd_IFACE_NAME \
            $key_lxd_IFACE_HOST_NAME \
            $key_lxd_IFACE_HWADDR;
        do   
            lxd_CONFIG_SET $lxd_NEW_KEY_VAL
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
    if [ $ovs_BR_IS_REAL = 0 ]; then

        # Remove lxd network and profile
        echo "[f03.1r] Purging $delete_NETWORK from LXD Network and Profile configuration"
        lxc network delete $delete_NETWORK > /dev/null 2>&1 ;
        lxc profile delete $delete_NETWORK > /dev/null 2>&1 

        # Remove virsh network configuration
        echo "[f03.2r] Purging $PURGE_NETWORK from Libvirt Network Configuration"
        virsh net-undefine $delete_NETWORK > /dev/null 2>&1 ;
        virsh net-destroy $delete_NETWORK > /dev/null 2>&1 ;

        # Remove OVS Bridge
        echo "[f03.3r] Purging OpenVswitch Configuration"
        ovs-vsctl del-br $delete_NETWORK > /dev/null 2>&1  ;

        # Confirm when done
        echo "$SEP_2 Finished Purging $delete_NETWORK from system"

    elif [ $lxd_CONT_IS_REAL != 0 ]; then
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
if [ $(systemctl is-enabled $dead_SERVICE_NAME) != "0" ]; then
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
    elif [ $? != 0 ]; then
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
show_config () {
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
    lxc network list

    # List LibVirtD Networks
    echo "  > LibVirtD Network Configuration < "
    virsh net-list --all
fi
}

#################################################################################
# Show Help menu short format ) --help | -h
print_HELP () {
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
if [ $SHOW_HELP_LONG = "false" ]; then
    dbg_FLAG="[f1h.1e]" && print_dbg_flags; 
fi
}

#################################################################################
# Show Help menu long format ) --help | -h
print_HELP_LONG () {
    dbg_FLAG="[f2h.1r]" && print_dbg_flags; 
    echo "
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

#################################################################################
# Initial function that determines behavior from command line flags
cmd_parse_run () {
if [ $show_HELP = 'true' ]; then
    dbg_FLAG="[f0h.0o]" && print_dbg_flags; 
    if [ $show_HELP_LONG = 'false' ]; then
        dbg_FLAG="[f1h.0r]" && print_dbg_flags; 
        print_help_short
        dbg_FLAG="[f1h.0c] OVS_BridgeBuilder_VERSION = $obb_VERSION" && print_dbg_flags; 
    exit 0
    elif [ $show_HELP_LONG = 'true' ]; then
        dbg_FLAG="[f2h.0r]" && print_dbg_flags; 
        print_help_short
        print_help_long
        dbg_FLAG="[f2h.0c] OVS_BridgeBuilder_VERSION = $obb_VERSION" && print_dbg_flags; 
    exit 0
    fi
fi
if [ $show_CONFIG != 'false' ]; then
        dbg_FLAG="[f3h.0o]" && print_dbg_flags; 
        show_CONFIG
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
        delete_network_bridge
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
        if [ lxd_CONT_IS_REAL = 0 ]; then
            dbg_FLAG="[f1b.3b] Adding OVS port to $lxd_CONT_NAME" && print_dbg_flags; 
            add_lxd_port
            dbg_FLAG="[f1b.3e] OVS Port created on $lxd_CONT_NAME" && print_dbg_flags; 
        fi
        dbg_FLAG="[f1b.0c] Done Building new OVS Port" && print_dbg_flags; 
    exit 0
    fi
fi
if    [ $build_OVS_PORT == 'false' ]  && \
      [ $delete_NETWORK == 'false' ]  && \
#        [ $remove_PORT == 'false' ]  && \
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
