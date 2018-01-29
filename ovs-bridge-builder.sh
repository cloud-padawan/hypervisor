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
# ovs_BR_DRIVER
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
dbg_FLAG="[d00.0b] > Looking for ccio.conf " && print_dbg_flags; 
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
OPTS=`getopt \
    -o bpdsHhz: \
    --long add-bridge,add-port,del-br,purge-ports,show-config,show-health,help,zee: \
    -n 'parse-options' -- "$@"`

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
           shift 
           ;;
             --help       ) 
           show_HELP="true" 
           show_HELP_LONG="true"; 
           shift 
           ;;
       -H | --show-health ) 
           show_HEALTH=true ; 
           shift 
           ;;
       -s | --show-config ) 
           show_CONFIG=true ; 
           shift
           ;;
       --purge-ports      ) 
           purge_DEAD_OVS_PORTS="true"; 
           shift 
           ;;
       -d | --del-br      )
           delete_NETWORK="$3"; 
           shift; 
           shift 
           ;;
        -p | --add-port   ) 
            name_OVS_BR="$3"
            lxd_CONT_NAME="$4"; 
            add_OVS_PORT="$5" 
            shift; 
            shift;
            ;;
        -b | --add-bridge ) 
            build_NEW_BRIDGE="true"
            name_OVS_BR="$3"; 
            add_OVS_BR="$3"; 
            shift; 
            shift; 
            ;;
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
echo "[d01.0b]\\"
echo "       | | show_HELP        =  $show_HELP"
echo "       | | show_HELP_LONG   =  $show_HELP_LONG"
echo "       | | show_CONFIG      =  $show_CONFIG"
echo "       | | show_HEALTH      =  $show_HEALTH"
echo "       | | orphan_OVS_PORTS =  $purge_DEAD_OVS_PORTS"
echo "       | | delete_NETWORK   =  $delete_NETWORK"
echo "       | | name_OVS_BR      =  $name_OVS_BR"
echo "       | | add_OVS_PORT     =  $add_OVS_PORT"
echo "       | | lxd_CONT_NAME    =  $lxd_CONT_NAME"
echo "       | | add_OVS_BR       =  $add_OVS_BR"
echo "[d01.0e]/"
fi
}

#################################################################################
# Testing break
stop_dbg_break () {
if [ $dbg_BREAK = "true" ]; then
    print_switch_vars
    dbg_FLAG="[d00.0x] > Debugging Break Enabled! Stopping!" && print_dbg_flags; 
    exit 0
fi
}

#################################################################################
# Set LXD Daemon Key Values
lxc_daemon_set () {
    echo "Set LXD Daemon key to \"$lxd_NEW_KEY_VAL\""
    $lxd_CMD config set $key_lxd_SET
}

#################################################################################
# Set LXD Profile Key Values
lxc_profile_set () {
    echo "Set LXD Profile \"$lxd_PROFILE_NAME\" key to \"$key_lxd_SET\""
    $lxd_CMD profile set $lxd_PROFILE_NAME $key_lxd_SET
}

#################################################################################
# Set LXD Network Key Values
lxc_network_set () {
    echo "Set LXD Network \"$add_OVS_BR\" key to \"$key_lxd_SET\""
    $lxd_CMD network set $add_OVS_BR $key_lxd_SET
}

#################################################################################
# Set LXD Container Key Values
lxc_container_set () {
    echo "[xXX.Xx] > Set LXD Container \"$lxd_CONT_NAME\" key to \"$key_lxd_SET\""
    $lxd_CMD config set $lxd_CONT_NAME $key_lxd_SET
}

#################################################################################
# If container was running, restart container
lxd_cont_resume () {
echo "LXD Container $lxd_CONT_NAME is currently $lxd_CONT_IS_STATE"
if [ $lxd_CONT_IS_STATE = "RUNNING" ]; then

    # Start Container
    echo "Restoring LXD Container state to: $lxd_CONT_IS_STATE"
    $lxd_CMD start $lxd_CONT_NAME

    # Re-Check Container State
    $lxc_WAIT --name $lxd_CONT_NAME --state=RUNNING \
       && lxd_CONT_IS_STATE=$($lxd_CMD list --format=csv -c n,s \
                             | grep $lxd_CONT_NAME \
                             | awk -F',' '{print $2}') 

    # Echo Container State
    echo "LXD Container state is now: $lxd_CONT_IS_STATE"
fi
}

#################################################################################
# Halt lxd container
# Recheck Container State
# Echo Container State
lxd_cont_halt () {
    # Halt Container
    # Recheck State
    # Echo Container State:
    $lxd_CMD stop $lxd_CONT_NAME
    $lxc_WAIT --name $lxd_CONT_NAME --state=STOPPED \
        && echo "$lxd_CONT_NAME Halted"
}

#################################################################################
# Check LXD Container Run State
# Halt if running 
# And set flag 
lxd_cont_halt_check () {

# TODO @setuid
# How does one make following the awk pattern matching work off variable within
# the "'" quotes? Specifically needing awk to read value of '$lxd_CONT_NAME'
#lxc_CONT_IS_STATE=$($lxd_CMD list \
#    --format=csv -c n,s | awk -F',' '/$lxd_CONT_NAME/{print $2}' )

# Define lxc-wait command
# Check status of container and set flag value
lxc_WAIT="$lxd_CMD-wait"
lxd_CONT_IS_STATE=$($lxd_CMD list \
    --format=csv -c n,s | grep $lxd_CONT_NAME | awk -F',' '{print $2}' )

# If container is running, halt container with user permission or abort obb
if [ $lxd_CONT_IS_STATE = 'RUNNING' ]; then

    # Echo current status
    echo "LXD Container $lxd_CONT_NAME is currently running"

    # Confirm container shutdown 
    # If "Y" .. Stop Container
    # If "N" .. Abort Configuration
    echo "Container must be halted before continuing"
    while true; do
        read -p "Are you sure you want to power off $lxd_CONT_NAME ? " yn
        case $yn in
            [Yy]* ) echo "Confirmed ..... Powering off $lxd_CONT_NAME";
                lxd_cont_halt
                break
                ;;
            [Nn]* ) echo "Rejected ...... Aborting obb!"
                exit 1
                ;;
            * ) echo "Please answer yes or no" ;;
        esac
    done
fi
}

#################################################################################
# Generate unique hardware mac address for interface
# Uses container name, bridge name, and interface name as unique md5sum input
# Will be globally unique while also being repeatable if required
port_hwaddr_gen () {
     
    # Echo Action
    dbg_FLAG="[s05.0b] > Generating Unique MAC Address for $add_OVS_PORT..." \
        && print_dbg_flags; 

    # Collect input values
    combined_HASH_INPUT="$name_OVS_BR$lxd_CONTAINER_NAME$add_OVS_PORT"

    # Generate mac address
    # All OBB generated MAC addresses will start with "02"
    port_IFACE_HWADDR=$( echo "$combined_HASH_INPUT" | md5sum \
        | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/02:\1:\2:\3:\4:\5/')

    # Echo result
    dbg_FLAG="[s05.0s] > STAT: Using MAC Address: '$port_IFACE_HWADDR'" \
        && print_dbg_flags; 
}

#################################################################################
# Check if interface name is already configured
ovs_iface_check_if_exists () {

    #echo Action
    dbg_FLAG="[s04.0b] > Searching for OVS Port Name: $add_OVS_PORT ..." \
        && print_dbg_flags; 

    # Search for port by name on each bridge
    # Set variable with exit status of search command
    for br in $(ovs-vsctl list-br); do 
        ovs-vsctl list-ports $br | grep $add_OVS_PORT 
        ovs_IFACE_IS_UNIQUE="$?"

    # Echo Search Complete
    dbg_FLAG="[s04.0s] > STAT: Interface Search Exit Code: $ovs_IFACE_IS_UNIQUE" \
        && print_dbg_flags; 

    # Echo Search Result
        if [ $ovs_IFACE_IS_UNIQUE = "0" ]; then 
            echo "[s04.1s] > WARN: Found OVS Port: $add_OVS_PORT on the $br OVS Bridge."
        elif [ $ovs_IFACE_IS_UNIQUE != "0" ]; then 
            echo "[s04.1x] > WARN: No Port Name $add_OVS_PORT found on this host."
        fi
    done
}

#################################################################################
# Check if lxd container name exists on host
lxd_cont_check_if_exists () {

    # Echo Action
    dbg_FLAG="[s03.0b] > Searching for LXD Container: $lxd_CONT_NAME ..." \
        && print_dbg_flags 

    # Search for container by name
    # Set variable with exit status of search command
    $lxd_CMD list --format=csv -c n | grep $lxd_CONT_NAME ;
    lxd_CONT_IS_REAL="$?"

    # Echo Search Complete
    dbg_FLAG="[s03.0e] > LXD Container Search Exit Code: $lxd_CONT_IS_REAL" \
        && print_dbg_flags; 

    # Echo Search Result
    if [ $lxd_CONT_IS_REAL = "0" ]; then 
        echo "[s03.0s] > STAT: Found LXD Container: $lxd_CONT_NAME"
    elif [ $lxd_CONT_IS_REAL != "0" ]; then 
        dbg_FLAG="[s03.0x] > WARN: No Container Name $lxd_CONT_NAME found on this host." \
            && print_dbg_flags
    fi
}

#################################################################################
# Check if bridge name exists on host 
ovs_br_check_if_exists () {

    # Echo Action
    dbg_FLAG="[s02.0b] > Searching for Bridge: $name_OVS_BR ..." \
        && print_dbg_flags; 

    # Search for Bridge by Name
    # Set variable with exit status of search command
    ovs-vsctl list-br | grep $name_OVS_BR 
    ovs_BR_IS_REAL="$?"

    # Echo Search Complete
    dbg_FLAG="[s02.0s] > STAT: OVS Bridge Query Complete" \
        && print_dbg_flags; 

    # Echo Search Result
    if [ $ovs_BR_IS_REAL = "0" ]; then
        dbg_FLAG="[s02.1e] > WARN: Found Bridge: $name_OVS_BR ..." \
            && print_dbg_flags; 
    elif [ $ovs_BR_IS_REAL != "0" ]; then
        dbg_FLAG="[s02.0x] > WARN: No Bridge Name: $name_OVS_BR found on this host" \
            && print_dbg_flags; 
    fi
}

#################################################################################
# Start dead service if service found to not be running
# Will also attempt to enable the service at boot as well
start_system_service () {
dbg_FLAG="[s01.0b] > Attempting to re-start $dead_SERVICE_NAME ..." && print_dbg_flags; 

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
    dbg_FLAG="[s01.1r] > WARN: $dead_SERVICE_NAME is not currently enabled to start at boot" \
        && print_dbg_flags; 
    dbg_FLAG="[s01.1r] > WARN: OBB could not enable the service" \
        && print_dbg_flags; 
    fi
fi

# If service starts successfully, attempt to re-run the previous function
# ... or die trying
if [ $? = 0 ]; then
    dbg_FLAG="[s01.2r] > Successfully restarted $dead_SERVICE_NAME" && print_dbg_flags; 
    dbg_FLAG="[s01.2r] > Retrying $rerun_start_function" && print_dbg_flags; 
# TODO: FIX!! This function bookmark does not return to parent function
#   rerun_at_function
elif [ $(systemctl is-active $dead_SERVICE_NAME) != 0 ]; then
    echo "[s01.3r] > ERROR: Unable to start dead service $dead_SERVICE_NAME!"
    echo "[s01.3r] > Unrecoverable error ... Aborting!"
    exit 1
fi
}

#################################################################################
# Check for user confirmation if running with default ovs-bridge name
check_vars_obb () {
echo "[s0X.0s] Validating OVS Bridge Name ... "
check_DEFAULT_CONFIRM_1=" > A Name has not been declared for the OVS Bridge, using default values ... " 
check_DEFAULT_CONFIRM_2=" > Are you sure you want to continue building the $add_OVS_BR bridge?  "
if [ $add_OVS_BR == $default_BR_NAME ]; then
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
        echo "[s0X.0s] > Preparing to configure $add_OVS_BR"
fi
}

#################################################################################
# Create VIRSH Network XML Configuration File
write_config_network_virsh () {

    # Set VIRSH Working Variables
    virsh_XML_FILE="$add_OVS_BR.xml"
    virsh_XML_TARGET="$xml_FILE_DIR/$virsh_XML_FILE"

# Write xml configuration
echo "[s0X.2r] Writing configuration > $virsh_XML_TARGET"
cat >$virsh_XML_TARGET <<EOF
<network>
  <name>$add_OVS_BR</name>
  <forward mode='bridge'/>
  <bridge name='$add_OVS_BR' />
  <virtualport type='openvswitch'/>
</network>
EOF
}

#################################################################################
# Write virsh network xml & define new virsh network
build_bridge_virsh () {

    # Echo Action
    echo " > Configuring Network Definitions for Libvirtd+KVM+QEMU"

    # Write virsh XML Network Definition
    write_config_network_virsh

    # Defining libvirt network $add_OVS_BR
    virsh net-define $virsh_XML_TARGET 
    echo " > Defined virsh network"

    #Starting Libvirt network
    virsh net-start $add_OVS_BR

    # Setting network to auto-start at boot
    virsh net-autostart $add_OVS_BR

    echo "[f08.0e] > Done Configuring Libvirt $add_OVS_BR"
}

#################################################################################
# Create LXD Profile matching network bridge name
build_profile_lxd () {
echo "[s0X.1r] Building LXD Profile \"$add_OVS_BR\""
$lxd_CMD profile create $lxd_PROFILE_NAME
$lxd_CMD profile device add $lxd_PROFILE_NAME $add_OVS_BR nic nictype=bridged parent=$add_OVS_BR
$lxd_CMD profile device add $lxd_PROFILE_NAME root disk path=/ pool=default
}

#################################################################################
# Create initial bridge with OVS driver & configure LXD
build_network_lxd () {

    # Echo Action
    echo "[x0X.0b] Building LXD Network \"$add_OVS_BR\" using \"$ovs_BR_DRIVER\" driver"

    # Create network 
    echo "[x0X.1s]"
    $lxd_CMD network create $add_OVS_BR

    # Set LXD Network Keys
    #lxc_network_set
    $lxd_CMD network set $add_OVS_BR bridge.driver $ovs_BR_DRIVER 
    $lxd_CMD network set $add_OVS_BR ipv4.address none      
    $lxd_CMD network set $add_OVS_BR ipv6.address none     
    $lxd_CMD network set $add_OVS_BR ipv4.firewall $v4_ROUTE          
    $lxd_CMD network set $add_OVS_BR ipv6.firewall $v6_ROUTE          
    $lxd_CMD network set $add_OVS_BR ipv4.nat $v4_ROUTE              
    $lxd_CMD network set $add_OVS_BR ipv6.nat $v6_ROUTE              
    $lxd_CMD network set $add_OVS_BR ipv4.routing $v4_ROUTE       
    $lxd_CMD network set $add_OVS_BR ipv6.routing $v6_ROUTE       
    $lxd_CMD network set $add_OVS_BR ipv4.dhcp $v4_DHCP              
    $lxd_CMD network set $add_OVS_BR ipv6.dhcp $v6_DHCP             

    echo "[x0X.1r]"
}

#################################################################################
# Define default lxd provisioning variables
set_vars_lxd () {
echo "[s0X.0s] Setting additional LXD Network and Profile Build Variables"

# Configure DHCP function
v4_DHCP="false"
v6_DHCP="false"

# Configure Routing/NAT'ing function - Valid Options "true|false" 
v4_ROUTE="false"
v6_ROUTE="false"

# Define Network Key Values
# key_lxd_NETWORK_LIST="

echo "[s0X.0s]"

lxd_PROFILE_NAME="$add_OVS_BR"
}

#################################################################################
# Core Bridge Builder Feature
# This function calls the child functions which build the bridge and configure
# client services such as LXD and KVM+QEMU (virsh) for use with OVS
# TODO @setuid; How can I set a function bookmark to retry this function after 
# completing a child function routine? 
# I tried to set the value: rerun_at_function="add_ovs_br"
# Then calling "rerun_at_function" within the child function but this failed 
# ... later thoughts, would this work?
# rerun_at_function=$(add_ovs_br) 
add_ovs_bridge () {
echo "[f03.0r]> Checking if OVS Bridge $add_OVS_BR already exists"
ovs_br_check_if_exists 
if [ ovs_BR_IS_REAL != "0" ]; then
    echo "No bridge configured by this name, continuing ..."
elif [ ovs_BR_IS_REAL = "0" ]; then
    echo "OVS Bridge $add_OVS_BR already configured on this host!"
    echo "To continue we will need to purge previous configuration!"
    while true; do
        read -p " > Are you sure you want to continue? " yn
        case $yn in
            [Yy]* ) echo "Confirmed! Continuing ...."; 
                  break
                  ;;
            [Nn]* ) 
                  echo " > ERROR: Canceling due to user input!"
                  exit 1
                  ;;
            * ) echo " > Please answer yes or no.";;
        esac
    done
fi
echo "[f03.1r]> Checking System Readiness"
virt_services_is_enabled 
echo "[f03.2r]> Setting LXD Default Variables"
set_vars_lxd
echo "[f03.3r]> Checking Variables"
check_vars_obb
echo "[f03.4r]> Purging pre-existing $add_OVS_BR configuration"
delete_NETWORK="$add_OVS_BR" 
delete_network_bridge
echo "[f03.5r]> Starting LXD Configuration"
build_network_lxd
build_profile_lxd
echo "[f03.6r]> Starting LIBVIRT Configuration"
build_bridge_virsh
echo "[f03.0s]>"
print_config
}

#################################################################################
# Checks value sanity on:
# - Bridge Name
# - Container Name
# - Interface Name
add_ovs_port_flight_check () {
dbg_FLAG="[f02.0b] > OVS Port Build Starting " && print_dbg_flags; 
if  [ $lxd_CONT_NAME != "false" ] && \
    [ $add_OVS_PORT != "false" ]  && \
    [ $name_OVS_BR != "false" ]; then
    
    # Check if bridge name exists
    dbg_FLAG="[s04.0o] > Checking for Bridge Name on host" && print_dbg_flags; 
    ovs_br_check_if_exists

    # Check if container name exists
    dbg_FLAG="[s03.0o] > Checking if Container Exists ..." && print_dbg_flags; 
    lxd_cont_check_if_exists

    # check if port name already exists
    dbg_FLAG="[s05.0o] > Checking for port name on host" && print_dbg_flags; 
    ovs_iface_check_if_exists

    # WARN if bridge does not exist
    # WARN if container name does not exist
    # WARN if a port matching this name already exists
    if [ $ovs_BR_IS_REAL != "0" ]; then
        dbg_FLAG="[f02.0x] > Unable to find $name_OVS_BR" && print_dbg_flags; 
        dbg_FLAG="[f02.0x] > Found the following bridge names:" && print_dbg_flags; 
        ovs-vsctl list-br
        echo "[f02.0x] Aborting due to error!"
        echo "[f02.0x] ERROR: Bridge Name Not Found!"

    elif [ $lxd_CONT_IS_REAL != "0" ]; then
        dbg_FLAG="[f02.1x] > Unable to find $lxd_CONT_NAME"
        dbg_FLAG="[f02.1x] > Found the following LXD Containers:
          " && print_dbg_flags; 
        $lxd_CMD list --format=csv -c n
        echo ""
        echo "[f02.1x] Aborting port configuration due to error!"
        echo "[f02.1x] ERROR: Container Not Found!"

    elif [ $ovs_IFACE_IS_UNIQUE = "0" ]; then
        dbg_FLAG="[f02.2x] > WARN: Detected a port named $add_OVS_PORT" && print_dbg_flags; 
        #echo "[f02.2x] Aborting port configuration due to error!"
        #echo "[f02.2x] ERROR: Interface Name $add_OVS_PORT already in use!"
    fi

    # Continue if Bridge Name / Container Name / Iface Name vars all sane
    # Else exit with error code 1
    echo "DBG PreRun Code: $ovs_BR_IS_REAL"
    if [ $ovs_BR_IS_REAL = "0" ]   && \
       [ $lxd_CONT_IS_REAL = "0" ]; then 
      #[ $ovs_IFACE_IS_UNIQUE != "0" ]; then
        dbg_FLAG="[f02.0s] > Found $name_OVS_BR"  && print_dbg_flags; 
        dbg_FLAG="[f02.1s] > Found $lxd_CONT_NAME"  && print_dbg_flags; 
       #dbg_FLAG="[f02.2s] > Confirmed Port Name $add_OVS_PORT is useable " && print_dbg_flags; 
    else
        echo "[f02.2x] > Exiting!"
        exit 1
    fi

    # Check if iface name is already present on container
    $lxd_CMD config show $lxd_CONT_NAME | grep $add_OVS_PORT;
    check_IFACE_CFG_IS_CONTAINER=$(echo $?)
    if [ $check_IFACE_CFG_IS_CONTAINER = 0 ]; then
        echo "IFACE $add_OVS_PORT already configured in host, will have to power off & remove"
    elif [ $check_IFACE_CFG_IS_CONTAINER = 0 ]; then
        echo "No IFACE $add_OVS_PORT configured on $lxd_CONT_NAME, Continuing..."
    fi
    
    # Generate unique hardware mac address for interface
    dbg_FLAG="[f02.3r] > " && print_dbg_flags; 
    port_hwaddr_gen

fi
dbg_FLAG="[f02.0e] > Add Port Flight Check Complete" && print_dbg_flags; 
}

#################################################################################
# Add interface to LXD Container on OVS Bridge
# Format: command [option] [bridge-name] [interface-name] [container-name]
# Command Example: 
#   obb -p br0 eth2 container1
# Runs add ovs port check
# If all values are sensible, will:
# - Purge conflicting configurations
# - Create a new network interface named as specified in command
# - Attach new port to container specified
# - Attach new port to OVS Bridge specified
# - Set LXD container property to make interface name persistent
add_ovs_port () {

# Port Configuration pre-flight check
add_ovs_port_flight_check 

# Continue if OVS Bridge is real & Container name is real
if [ $ovs_BR_IS_REAL = "0" ] && [ $lxd_CONT_IS_REAL = "0" ]; then

    # Echo configuration values
    dbg_FLAG="[f02.5r] > Attaching LXD Container $lxd_CONT_NAME to:" && print_dbg_flags;  
    dbg_FLAG="[f02.5r] >           OVS Bridge:   $name_OVS_BR" && print_dbg_flags; 
    dbg_FLAG="[f02.5r] >           On Port:      $add_OVS_PORT" && print_dbg_flags; 
    dbg_FLAG="[f02.5r] >           HW Address:   $port_IFACE_HWADDR
     " && print_dbg_flags; 

    # Halt container if there is a conflicting port already configured 
    # Remove conflicting port once container is stopped
    if [[ $check_IFACE_CFG_IS_CONTAINER = "0" ]] ; then
        lxd_cont_halt_check
        $lxd_CMD config device remove $lxd_CONT_NAME $add_OVS_PORT
    fi
        
    # ~IFACE_NAME sets the name of the device in the lxd configuration file
    # ~IFACE_HOST_NAME creates a persistent ovs bridge device name
    # ~IFACE_HWADDR uses the port_HWADDR_GEN value to set a static and repeatable mac
    $lxd_CMD network attach $name_OVS_BR $lxd_CONT_NAME $add_OVS_PORT
    $lxd_CMD config set $lxd_CONT_NAME volatile.$add_OVS_PORT.name $add_OVS_PORT
    $lxd_CMD config set $lxd_CONT_NAME volatile.$add_OVS_PORT.host_name $add_OVS_PORT
    $lxd_CMD config set $lxd_CONT_NAME volatile.$add_OVS_PORT.hwaddr $port_IFACE_HWADDR

    # Check if container was running at start of configuration 
    # Restart if container was running
    lxd_cont_resume

fi
}

#################################################################################
# Purge networks by name ) --purge | -p
# TODO add feature to prompt for confirmation & disconnect any containers on
#      bridbridge to gracefully avoid error out/failure
delete_network_bridge () {

if [ $delete_NETWORK != "false" ]; then

    # Echo Action
    dbg_FLAG="[f01.0b] > Preparint to remove OVS Bridge: $delete_NETWORK ..." \
        && print_dbg_flags;
    
    # Check if network name exists
    # Continue with network removal if bridge is found
    ovs_br_check_if_exists 
    if [ $ovs_BR_IS_REAL = "0" ]; then
        echo "[f01.0r] > Found $name_OVS_BR"
    elif [ $ovs_BR_IS_REAL != "0" ]; then
        echo "[f01.0x] > Unable to find Bridge Name: $delete_NETWORK "
    fi

    # Remove lxd network and profile
    echo "[f01.1r] > Purging $delete_NETWORK from LXD Network and Profile configuration"
    $lxd_CMD network delete $delete_NETWORK > /dev/null 2>&1 ;
    $lxd_CMD profile delete $delete_NETWORK > /dev/null 2>&1 

    # Remove virsh network configuration
    echo "[f01.2r] > Purging $delete_NETWORK from Libvirt Network Configuration"
    virsh net-undefine $delete_NETWORK > /dev/null 2>&1 ;
    virsh net-destroy $delete_NETWORK > /dev/null 2>&1 ;

    # Remove OVS Bridge
    echo "[f01.3r] > Purging OpenVswitch Configuration"
    ovs-vsctl del-br $delete_NETWORK > /dev/null 2>&1  ;

    # Remove ifup file
    echo "[f01.4r] > Removing ifup $delete_NETWORK.cfg"
    rm /etc/network/interfaces.d/*$delete_NETWORK.cfg > /dev/null 2>&1 ;

    # Confirm when done
    echo "[f01.5r] > Finished Purging $delete_NETWORK from system"

fi
dbg_FLAG="[f01.0e] > Network Removal Complete for $delete_NETWORK ..." && print_dbg_flags;
}

#################################################################################
# Purge dead OVS Interfaces
purge_dead_iface_all () {
dbg_FLAG="[h05.0b] > Purging On All OVS Bridges" && print_dbg_flags; 
dead_OVS_IFACE=$(ovs-vsctl show | awk '$1 - /error:/{print $7;}')
for iface in $dead_OVS_IFACE; do 
    ovs-vsctl del-port $iface; 
    dbg_FLAG="[h05.0r] > Successfully removed $dead_OVS_IFACE" && print_dbg_flags; 
done
dbg_FLAG="[h05.0e] > Purge Complete" && print_dbg_flags; 
}
     
#################################################################################
# Check that required services are running
virt_services_is_enabled () {
dbg_FLAG="[h03.0b] > Querying Starting ..." && print_dbg_flags; 

# Load System Service Status
ovs_SERVICE_STATUS=$(systemctl is-active $ovs_SERVICE_NAME)
lxd_SERVICE_STATUS=$(systemctl is-active $lxd_SERVICE_NAME)
libvirt_SERVICE_STATUS=$(systemctl is-active $libvirt_SERVICE_NAME)

# Display Service Status
dbg_FLAG="[h03.0r] > Showing Local service health:
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
    dbg_FLAG="[h03.1r] > WARN: Dead Service Found  =  $dead_SERVICE_NAME"
    echo " > ERROR: The OpenVSwitch System Service is NOT RUNNING"
    echo " > Attempting to start $dead_SERVICE_NAME"
    start_system_service 
fi

# If LXD Service is not active, error & attempt to start service
if [ "$lxd_SERVICE_STATUS" != "active" ]; then
    dead_SERVICE_NAME="lxd_SERVICE_NAME"
    dbg_FLAG="[h03.2r] > WARN: Dead Service Found  =  $dead_SERVICE_NAME"
    echo " > ERROR: The LXD System Service IS NOT RUNNING"
    echo " > Attempting to start $dead_SERVICE_NAME"
    start_system_service 
fi

# If Libvirtd Service is not active, error & attempt to start service
if [ "$libvirt_SERVICE_STATUS" != "active" ]; then
    dead_SERVICE_NAME="libvirt_SERVICE_NAME"
    dbg_FLAG="[h03.3r] > WARN: Dead Service Found  =  $dead_SERVICE_NAME"
    echo " > ERROR: The LibVirtD System Service IS NOT RUNNING"
    echo " > Attempting to start $dead_SERVICE_NAME"
    start_system_service 
fi
dbg_FLAG="[h03.0e] > Query Complete" && print_dbg_flags; 
}

#################################################################################
# Show current networks configured for OVS/LXD/KVM+QEMU ) --show | -s
print_config () {
# Check that required services are running
# virt_services_is_enabled
dbg_FLAG="[h04.0b] > Querying Host OVS Configuration" && print_dbg_flags; 

# Load System Service Status
ovs_SERVICE_STATUS=$(systemctl is-active $ovs_SERVICE_NAME)
lxd_SERVICE_STATUS=$(systemctl is-active $lxd_SERVICE_NAME)
libvirt_SERVICE_STATUS=$(systemctl is-active $libvirt_SERVICE_NAME)

# List Openvswitch Networks
dbg_FLAG="[h04.1r] > Showing Local Bridge Configuration" && print_dbg_flags; 
if [ "$libvirt_SERVICE_STATUS" = "active" ] && \
       [ "$lxd_SERVICE_STATUS" = "active" ] && \
       [ "$ovs_SERVICE_STATUS" = "active" ]; then

    # List OpenVSwitch Networks
    dbg_FLAG="[h04.2r] > OpenVSwitch Network Configuration
             " && print_dbg_flags; 
    echo "  > OpenVSwitch Network Configuration <
    "
    ovs-vsctl show

    # List LXD Networks
    dbg_FLAG="[h04.3r] > LXD Network Configuration
             " && print_dbg_flags; 
    echo "  > LXD Network Configuration <
    "
    $lxd_CMD network list

    # List LibVirtD Networks
    dbg_FLAG="[h04.4r] > Libvirtd Network Configuration
             " && print_dbg_flags; 
    echo "  > LibVirtD Network Configuration < 
    "
    virsh net-list --all
fi
dbg_FLAG="[h04.0e] > Host Config Query Complete" && print_dbg_flags; 
}

#################################################################################
# Show Help menu short format ) --help | -h
print_help_short () {
    dbg_FLAG="[h01.0r] > Print Short" && print_dbg_flags; 
    echo "
    OpenVSwitch Bridge Builder 

    syntax: command [option] [value]

    Options:
                         -h    Print the basic help menu
       --help                  Print the extended help menu
       --show-health     -H    Check OVS|LXD|Libvirtd Service Status
       --show-config     -s    Show current networks configured locally
       --purge-ports           Purge orphaned OVS ports 
                                  Usually seen in the following command output as
                                  'no such device' errors
                                      'ovs-vsctl show'
                                      'obb -s | obb --show-config'
       --add-port        -p    Add port to bridge and optionally connect port to 
                               container if named. 
                               Value Ordering:
                                  [bridge] [port] [container] 
       --del-br          -d    Deletes network when pased with a value
                               matching an existing network name.
       --new-bridge      -b    Sets the name for building the following: 
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
print_switch_vars 
#stop_dbg_break 
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
if [ $show_HEALTH != 'false' ]; then
    dbg_FLAG="[h03.0o] > Querying Virt Services Status" && print_dbg_flags; 
    virt_services_is_enabled
    dbg_FLAG="[h03.0c] > Health Check Complete" && print_dbg_flags; 
exit 0
fi
if [ $show_CONFIG != 'false' ]; then
    dbg_FLAG="[h04.0o] > Showing Host Network Configuration " && print_dbg_flags; 
    print_config
    dbg_FLAG="[h04.0c] > $obb_VERSION" && print_dbg_flags; 
exit 0
fi
if [ $purge_DEAD_OVS_PORTS = 'true' ]; then
    dbg_FLAG="[h05.0o] > Purge Dead OVS Ports" && print_dbg_flags; 
    purge_dead_iface_all
    dbg_FLAG="[h05.0c] > $obb_VERSION" && print_dbg_flags; 
exit 0
fi
if [ $delete_NETWORK != 'false' ]; then
    dbg_FLAG="[f01.0o] > Requesting to remove $delete_NETWORK ..." && print_dbg_flags;
    delete_network_bridge
    print_config
    dbg_FLAG="[f01.0c] > Purged $delete_NETWORK Bridge" && print_dbg_flags; 
    exit 0
fi
if [ $add_OVS_PORT != 'false' ]; then
    dbg_FLAG="[f02.0o] > Addinng New OVS Port $add_OVS_PORT" && print_dbg_flags; 
    add_ovs_port 
    dbg_FLAG="[f02.0c] > Done adding OVS Port $add_OVS_PORT" && print_dbg_flags; 
    exit 0
fi
if [ $build_NEW_BRIDGE = 'true' ]; then
    dbg_FLAG="[f03.0o] > Addinng New OVS Bridge $add_OVS_BR" && print_dbg_flags; 
    add_ovs_bridge
    dbg_FLAG="[f03.0c] > Done adding OVS Bridge $add_OVS_BR" && print_dbg_flags; 
    exit 0
fi
}

# Start initial function that determines behavior from command line flags
cmd_parse_run
