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
#show_HELP_LONG="false"
#show_HELP="false"
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

# Version
obb_VERSION=v00.87.a
echo "
 NOTICE: YOU ARE RUNNING AN ALPHA PROJECT!
 ContainerCraft.io ~~ OVS-BridgeBuilder 
 $obb_VERSION
"

#################################################################################
# Check if run as root!
if [[ "$EUID" -ne "0" ]]; then
	echo "ERROR: Must be run as root priviledges!" 
	echo "Exiting!"
	exit 1
fi

#################################################################################
# Debug Flag [true|false]
print_DBG_FLAGS="false"
# Debug output 
print_dbg_flags () {
if [ $print_DBG_FLAGS = "true" ]; then
        echo "$dbg_FLAG"
fi
}
      
#################################################################################
# Load Bridge-Builder Default Variables 
# Used unless otherwise set by flags at run-time
# Check for host ccio.conf configuration
dbg_FLAG="[d00.0b] " && print_dbg_flags; 
if [ -f /etc/ccio/ccio.conf ]; then
    dbg_FLAG="[d00.0r] > Detected ccio.conf, loading configuration ..." && print_dbg_flags; 
    source /etc/ccio/ccio.conf
fi
if [ ! -f /etc/ccio/ccio.conf ]; then
    echo "ERROR: ccio.conf not found!"
    echo "Aborting!"
    exit 1
fi

#################################################################################
# Notice: Print DBG Flag Notice
if [ $print_DBG_FLAGS = "true" ]; then
    echo "[d00.1r] > OBB Debug Flags Enabled
     
    To Disable Debug messages, change /etc/ccio/ccio.conf value:
        
        print_DBG_FLAGS='false'
        
        "
fi
# Read variables from command line
dbg_FLAG="[d00.2r] > Enabling Command Line Options" && print_dbg_flags; 
OPTS=`getopt -o sHhz: --long show-config,health,help,zee: -n 'parse-options' -- "$@"`

# Fail if options are not sane

dbg_FLAG="[d00.3r] > Checking Command Line Option Sanity" && print_dbg_flags; 
if [ $? != 0 ] ; 
    then echo " > Failed parsing options ... Exiting!" >&2 ; 
    exit 1
fi

eval set -- "$OPTS"

# Parse variables

dbg_FLAG="[d00.4r] > Parsing Command Line Options" && print_dbg_flags; 
while true; do
    case "$1" in
        -h                ) 
           show_HELP="true"; 
           show_HELP_LONG="false"; 
           shift 
           ;;
             --help       ) 
           show_HELP="true" 
           show_HELP_LONG="true"; 
           shift 
           ;;
       -H | --health     ) 
           show_HEALTH=true ; 
           shift 
           ;;
       -s | --show-config) 
           show_CONFIG=true ; 
           shift
           ;;
#       -b | --add-bridge ) NETWORK_NAME="$3"; shift; shift ;;
#       -d | --delbr      ) 
#            PURGE_NETWORK="$3"; 
#             shift; 
#            shift 
#            ;;
#       -p | --port-add   ) 
#           OVS_BRIDGE_NAME="$3"
#           OVS_ADD_PORT="$4" 
#           LXD_CONT_NAME="$5"; 
#           shift 
#           shift 
#           ;;
#            --del-port   ) PURGE_PORT="$3"; shift; shift ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
done
dbg_FLAG="[d00.0e] > Processed Variables and Flags" && print_dbg_flags; 

#################################################################################
#Print option values
print_switch_vars () {
if [ $print_DBG_FLAGS = "true" ]; then
dbg_FLAG="[d01.0b]\\" && print_dbg_flags; 
echo "       | | show_HELP        =  $show_HELP"
echo "       | | show_HELP_LONG   =  $show_HELP_LONG"
echo "       | | show_CONFIG      =  $show_CONFIG"
echo "       | | show_HEALTH      =  $show_HEALTH"
#echo "       | | NETWORK_NAME     =  $NETWORK_NAME"
#echo "       | | PURGE_NETWORK    =  $PURGE_NETWORK"
#echo "       | | OVS_ADD_PORT     =  $OVS_ADD_PORT"
#echo "       | | OVS_BRIDGE_NAME  =  $OVS_BRIDGE_NAME"
#echo "       | | LXD_CONT_NAME    =  $LXD_CONT_NAME"
#echo "       | | Confirmed command line options are useable .... Continuing"
dbg_FLAG="[d01.0e]/" && print_dbg_flags; 
fi
}

#################################################################################
# Testing break
stop_dbg_break () {
print_switch_vars
if [ $dbg_BREAK = "true" ]; then
    exit 0
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
dbg_FLAG="[f3h.0o] > Showing Local service health:
" && print_dbg_flags; 
echo "OpenVSwitch Service Name = $ovs_SERVICE_NAME"
echo "                  Status = $ovs_SERVICE_STATUS
"
echo "LXD         Service Name = $lxd_SERVICE_NAME"
echo "                  Status = $lxd_SERVICE_STATUS
"
echo "Libvirtd    Service Name = $libvirt_SERVICE_NAME" 
echo "                  Status = $libvirt_SERVICE_STATUS
"

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
# Check that required services are running
# virt_services_is_enabled

# Load System Service Status
ovs_SERVICE_STATUS=$(systemctl is-active $ovs_SERVICE_NAME)
lxd_SERVICE_STATUS=$(systemctl is-active $lxd_SERVICE_NAME)
libvirt_SERVICE_STATUS=$(systemctl is-active $libvirt_SERVICE_NAME)

# List Openvswitch Networks
dbg_FLAG="[f3h.0o] > Showing Local Bridge Configuration" && print_dbg_flags; 
if [ "$libvirt_SERVICE_STATUS" = "active" ] && \
       [ "$lxd_SERVICE_STATUS" = "active" ] && \
       [ "$ovs_SERVICE_STATUS" = "active" ]; then

    # List OpenVSwitch Networks
    dbg_FLAG="[f3h.0o] > OpenVSwitch Network Configuration
             " && print_dbg_flags; 
    echo "  > OpenVSwitch Network Configuration <
    "
    ovs-vsctl show

    # List LXD Networks
    dbg_FLAG="[f3h.0o] > LXD Network Configuration
             " && print_dbg_flags; 
    echo "  > LXD Network Configuration <
    "
    $lxd_CMD network list

    # List LibVirtD Networks
    dbg_FLAG="[f3h.0o] > Libvirtd Network Configuration
             " && print_dbg_flags; 
    echo "  > LibVirtD Network Configuration < 
    "
    virsh net-list --all
fi
}

#################################################################################
# Show Help menu short format ) --help | -h
print_help_short () {
    dbg_FLAG="[h01.0r] > Print Short" && print_dbg_flags; 
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
    dbg_FLAG="[h01.0e] > Print Short End" && print_dbg_flags; 
fi
}

#################################################################################
# Show Help menu long format ) --help | -h
print_help_long () {
    dbg_FLAG="[h02.0r] > Print Long" && print_dbg_flags; 
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
    dbg_FLAG="[h02.0e] > Print Long End" && print_dbg_flags; 
}

#################################################################################
# Initial function that determines behavior from command line flags
cmd_parse_run () {
if [ $show_HELP = 'true' ]; then
    dbg_FLAG="[h01.0o] > Showing Help Menu" && print_dbg_flags; 
    if [ $show_HELP_LONG = 'false' ]; then
        dbg_FLAG="[h01.0b] > Showing Help Short" && print_dbg_flags; 
        print_help_short
        dbg_FLAG="[h01.0c] > OVS_BridgeBuilder_VERSION = $obb_VERSION" && print_dbg_flags; 
    exit 0
    elif [ $show_HELP_LONG = 'true' ]; then
        dbg_FLAG="[h02.0b] > Showing Help Long" && print_dbg_flags; 
        print_help_short
        print_help_long
        dbg_FLAG="[h02.0c] > OVS_BridgeBuilder_VERSION = $obb_VERSION" && print_dbg_flags; 
    exit 0
    fi
fi
stop_dbg_break 
if [ $show_HEALTH != 'false' ]; then
    dbg_FLAG="[h03.0o]" && print_dbg_flags; 
    virt_services_is_enabled
    dbg_FLAG="[h03.0c]" && print_dbg_flags; 
exit 0
fi
if [ $show_CONFIG != 'false' ]; then
    dbg_FLAG="[h04.0o]" && print_dbg_flags; 
    print_config
    dbg_FLAG="[h04.0c]" && print_dbg_flags; 
exit 0
fi
}

# Start initial function that determines behavior from command line flags
cmd_parse_run
