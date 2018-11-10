#!/bin/bash
# Network Setup script to create and manage LXD & Libvirt OpenVswitch Networks
# This is currently only tested on Arch and Ubuntu-Xenial; YMMV on other
# distros
#
# Requires LXD, Libvirt, and OpenVSwitch services
# Also requires that zfsutils-linux package be installed for LXD or that you
# manually create a "default" storage pool for LXD instead
# 
# Default install:
#  Located in /etc/ccio/tools/obb.sh
#  Linked at /usr/bin/obb
#
#################################################################################
# TODO - BUG FIX LIST
# OVS|LXD|LIBVIRTD Service Names not populated in ccio.conf (on Ubuntu Zesty)
# lxd_CMD="lxc" on snap install (17.10)
# - lxd.lxc --version | lxc --version == "command not found"
#
# TODO - FEATURE REQUEST LIST
# Add logging function
# Add Better Error handling & Detection
# Enable simple "--del-port" function
# - Function already present for --add-port, requires breakout run independently
# Add [VLAN|GRE|Static_IP] IFACE Configuration as options
# Add support for LXD+MAAS Integration
# - https://github.com/lxc/lxd/blob/master/doc/containers.md (MAAS Integration)
# Add Verbose/Quiet run option
# Improve multi-distribution support
# - Started in release v0.87.a
# - Roadmap:
# - - Arch Linux
# - - Fedora
# - - CentOS
# - - RHEL
# - - Alpine Linux
# Add support for Ubuntu Core OS
# Add new testing script that automates testing of all documented commands 
#
# Review & research:
# - https://github.com/yeasy/easyOVS
#
#################################################################################
# Logging Function
run_log () {

    if [ $1 == 0 ]; then
        echo "${dbg_FLAG}INFO: ${2}"
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

#################################################################################
# Version
obb_VERSION=v00.27.b
echo "
 NOTICE: YOU ARE RUNNING A BETA PROJECT!
 ContainerCraft.io ~~ OVS-BridgeBuilder 
 $obb_VERSION
"

#################################################################################
# Debug Flag [true|false]
print_DBG_FLAGS="false"
# Debug output 
print_dbg_flags () {
if [ $print_DBG_FLAGS = "true" ]; then
    run_log 0 "$dbg_FLAG"
fi
}
      
#################################################################################
# Load Bridge-Builder Default Variables 
# Used unless otherwise set by flags at run-time
# Check for host ccio.conf configuration
run_log 0 "[d00.0b] > Looking for ccio.conf" 
if [ -f /etc/ccio/ccio.conf ]; then
    run_log 0 "[d00.0r] > Detected ccio.conf, loading configuration ..." \
        
    source /etc/ccio/ccio.conf
fi
if [ ! -f /etc/ccio/ccio.conf ]; then
    run_log 1 "ccio.conf not found!"
fi

#################################################################################
# Notice: Print DBG Flag Notice
if [ $print_DBG_FLAGS = "true" ]; then
    run_log 0 "[d00.1r] > OBB Debug Flags Enabled
     
    To Disable Debug messages, change /etc/ccio/ccio.conf value:
        
        print_DBG_FLAGS='false'
        "
fi

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
echo "       | | name_OVS_BR      =  $name_OVS_BR"
echo "       | | add_OVS_PORT     =  $add_OVS_PORT"
echo "       | | del_OVS_PORT     =  $add_OVS_BR"
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
    run_log 1 "[d00.0x] > Debugging Break Enabled! Stopping!" 
fi
}

#################################################################################
# Set LXD Daemon Key Values
lxc_daemon_set () {
    run_log 0 "Set LXD Daemon key to '$lxd_NEW_KEY_VAL'"
    $lxd_CMD config set $key_lxd_SET
}

#################################################################################
# Set LXD Profile Key Values
lxc_profile_set () {
    run_log 0 "Set LXD Profile \"$lxd_PROFILE_NAME\" key to \"$key_lxd_SET\""
    $lxd_CMD profile set $lxd_PROFILE_NAME $key_lxd_SET
}

#################################################################################
# Set LXD Network Key Values
lxc_network_set () {
    run_log 0 "Set LXD Network \"$add_OVS_BR\" key to \"$key_lxd_SET\""
    $lxd_CMD network set $add_OVS_BR $key_lxd_SET
}

#################################################################################
# Set LXD Container Key Values
lxc_container_set () {
    run_log 0 "[xXX.Xx] > Set LXD Container \"$lxd_CONT_NAME\" key to \"$key_lxd_SET\""
    $lxd_CMD config set $lxd_CONT_NAME $key_lxd_SET
}

#################################################################################
# If container was running, restart container
lxd_cont_resume () {
echo "LXD Container $lxd_CONT_NAME is currently $lxd_CONT_IS_STATE"
if [ $lxd_CONT_IS_STATE = "RUNNING" ]; then

    # Start Container
    run_log 0 "Restoring LXD Container state to: $lxd_CONT_IS_STATE"
    $lxd_CMD start $lxd_CONT_NAME

    # Re-Check Container State
    $lxc_WAIT --name $lxd_CONT_NAME --state=RUNNING --timeout=5 \
       && lxd_CONT_IS_STATE=$($lxd_CMD list --format=csv -c n,s \
                             | grep $lxd_CONT_NAME \
                             | awk -F',' '{print $2}') 

    # run_log 0 Container State
    run_log 0 "LXD Container state is now: $lxd_CONT_IS_STATE"
fi
}

#################################################################################
# Halt lxd container
# Recheck Container State
# run_log 0 Container State
lxd_cont_halt () {
    # Halt Container
    # Recheck State
    # run_log 0 Container State:
    $lxd_CMD stop $lxd_CONT_NAME
    $lxc_WAIT --name $lxd_CONT_NAME --state=STOPPED \
        && run_log 0 "$lxd_CONT_NAME Halted"
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
    lxc_WAIT="lxc-wait"
    lxd_CONT_IS_STATE=$($lxd_CMD list \
        --format=csv -c n,s | grep $lxd_CONT_NAME | awk -F',' '{print $2}' )

    # run_log 0 current status
    run_log 0 "LXD Container $lxd_CONT_NAME is currently running"
}

#################################################################################
# Check LXD Container Run State & halt if running 
# If container is running, halt container with user permission or abort obb
lxd_cont_halt_confirm () {
if [ $lxd_CONT_IS_STATE = 'RUNNING' ]; then
    # run_log 0 current status
    run_log 0 "LXD Container $lxd_CONT_NAME is currently running"

    # Confirm container shutdown 
    # If "Y" .. Stop Container
    # If "N" .. Abort Configuration
    run_log 0 "Container must be halted before continuing"
    while true; do
        read -rp "Are you sure you want to power off $lxd_CONT_NAME ? " yn
        case $yn in
            [Yy]* ) run_log 0 "Confirmed ..... Powering off $lxd_CONT_NAME";
                lxd_cont_halt
                break
                ;;
            [Nn]* ) run_log 1 "User Rejected ...... Aborting obb!"
                ;;
            * ) run_log 0 "Please answer yes or no" ;;
        esac
    done
fi
}

#################################################################################
# Generate unique hardware mac address for interface
# Uses container name, bridge name, and interface name as unique md5sum input
# Will be globally unique while also being repeatable if required
port_hwaddr_gen () {
[[ -z $lxd_CONT_NAME ]] \
    && host_NAME=${lxd_CONT_NAME} \
    || host_NAME=$(cat /etc/hostname)

    # run_log 0 Action
    run_log 0 "[s05.0b] > Generating Unique MAC Address for $add_OVS_PORT..." \
        

    # Collect input values
    combined_HASH_INPUT="${host_NAME}${name_OVS_BR}${add_OVS_PORT}"

    # Generate mac address
    # All OBB generated MAC addresses will start with "02"
    if [[ ! -z $lxd_CONT_NAME ]]; then
        port_IFACE_HWADDR=$( run_log 0 "$combined_HASH_INPUT" \
        | md5sum \
        | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/02:\1:\2:\3:\4:\5/')

    elif [[ -z $lxd_CONT_NAME ]]; then
        port_IFACE_HWADDR=$( run_log 0 "$combined_HASH_INPUT" \
        | md5sum \
        | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/02\\:\1\\:\2\\:\3\\:\4\\:\5/')

    fi

    # run_log 0 result
    run_log 0 "[s05.0s] > STAT: Using MAC Address: '$port_IFACE_HWADDR'" \
        
}

#################################################################################
# Check if interface name is already configured
ovs_iface_check_if_exists () {

    #echo Action
    run_log 0 "[s04.0b] > Searching for OVS Port Name: $add_OVS_PORT ..." \
        

    # Search for port by name on each bridge
    # Set variable with exit status of search command
    for br in $(ovs-vsctl list-br); do 
        ovs-vsctl list-ports $br | grep $add_OVS_PORT 
        ovs_IFACE_IS_UNIQUE="$?"
    done

    # run_log 0 Search Complete
    run_log 0 "[s04.0s] > STAT: Interface Search Exit Code: $ovs_IFACE_IS_UNIQUE"\
        

    # run_log 0 Search Result
        if [ $ovs_IFACE_IS_UNIQUE = "0" ]; then 
            run_log 0 "[s04.1s] > WARN: Found OVS Port: $add_OVS_PORT on the $br OVS Bridge."
        elif [ $ovs_IFACE_IS_UNIQUE != "0" ]; then 
            run_log 0 "[s04.1x] > WARN: No Port Name $add_OVS_PORT found on this host."
        fi
}

#################################################################################
# Check if lxd container name exists on host
lxd_cont_check_if_exists () {

    # run_log 0 Action
    run_log 0 "[s03.0b] > Searching for LXD Container: $lxd_CONT_NAME ..." \
        && print_dbg_flags 

    # Search for container by name
    # Set variable with exit status of search command
    $lxd_CMD list --format=csv -c n | grep $lxd_CONT_NAME ;
    lxd_CONT_IS_REAL="$?"

    # run_log 0 Search Complete
    run_log 0 "[s03.0e] > LXD Container Search Exit Code: $lxd_CONT_IS_REAL" \
        

    # run_log 0 Search Result
    if [ $lxd_CONT_IS_REAL = "0" ]; then 
        run_log 0 "[s03.0s] > STAT: Found LXD Container: $lxd_CONT_NAME"
    elif [ $lxd_CONT_IS_REAL != "0" ]; then 
        run_log 0 "[s03.0x] > WARN: No Container Name $lxd_CONT_NAME found on this host." \
            && print_dbg_flags
    fi
}

#################################################################################
# Check if bridge name exists on host 
ovs_br_check_if_exists () {

    # run_log 0 Action
    run_log 0 "[s02.0b] > Searching for Bridge: $name_OVS_BR ..." \
        

    # Search for Bridge by Name
    # Set variable with exit status of search command
    ovs-vsctl list-br | grep $name_OVS_BR 
    ovs_BR_IS_REAL="$?"

    # run_log 0 Search Complete
    run_log 0 "[s02.0s] > STAT: OVS Bridge Query Complete" \
        

    # run_log 0 Search Result
    if [ $ovs_BR_IS_REAL = "0" ]; then
        run_log 0 "[s02.1e] > WARN: Found Bridge: $name_OVS_BR ..." \
            
    elif [ $ovs_BR_IS_REAL != "0" ]; then
        run_log 0 "[s02.0x] > WARN: No Bridge Name: $name_OVS_BR found on this host" \
            
    fi
}

#################################################################################
# Start dead service if service found to not be running
# Will also attempt to enable the service at boot as well
start_system_service () {
run_log 0 "[s01.0b] > Attempting to re-start $dead_SERVICE_NAME ..." 

# try to start dead service
systemctl start $dead_SERVICE_NAME
sleep 5
systemctl is-active $dead_SERVICE_NAME

# If the dead service is not enabled:
# 1. attempt to enable the service
# 2. if the service cannot be enabled, print warning
# 3. if all stopped services start successfully, attempt re-run previous
#    function
if [ $(systemctl is-enabled "$dead_SERVICE_NAME") != "0" ]; then
    systemctl enable $dead_SERVICE_NAME
    if [ $? != "0" ]; then
    run_log 0 "[s01.1r] > WARN: $dead_SERVICE_NAME is not currently enabled to start at boot" \
        
    run_log 0 "[s01.1r] > WARN: OBB could not enable the service" \
        
    fi
fi

# If service starts successfully, attempt to re-run the previous function
# ... or die trying
if [ $? = 0 ]; then
    run_log 0 "[s01.2r] > Successfully restarted $dead_SERVICE_NAME" 
    run_log 0 "[s01.2r] > Retrying $rerun_start_function" 
# TODO: FIX!! This function bookmark does not return to parent function
#   rerun_at_function
elif [ $(systemctl is-active $dead_SERVICE_NAME) != 0 ]; then
    run_log 0 "[s01.3r] > ERROR: Unable to start dead service $dead_SERVICE_NAME!"
    run_log 1 "[s01.3r] > Unrecoverable error ... Aborting!"
fi
}

#################################################################################
# Check for user confirmation if running with default ovs-bridge name
check_vars_obb () {
echo "[s0X.0s] Validating OVS Bridge Name ... "
check_DEFAULT_CONFIRM_1=" > A Name has not been declared for the OVS Bridge, using default values ... " 
check_DEFAULT_CONFIRM_2=" > Are you sure you want to continue building the $add_OVS_BR bridge?  "
if [ $add_OVS_BR == $default_BR_NAME ]; then
    run_log 0 "$check_DEFAULT_CONFIRM_1"
    while true; do
        read -rp " > $check_DEFAULT_CONFIRM_2" yn
        case $yn in
            [Yy]* ) run_log 0 "Continuing ...."; 
                  break
                  ;;
            [Nn]* ) 
                  run_log 1 " > ERROR: Canceling due to user input!"
                  ;;
            * ) run_log 0 " > Please answer yes or no.";;
        esac
    done         
    else 
        run_log 0 "[s0X.0s] > Preparing to configure $add_OVS_BR"
fi
}

#################################################################################
# Create Ifup port .cfg Configuration File
write_config_port_lxd () {

    # Set Iface .cfg target file and directory
    lxd_IFACE_CFG_FILE="$add_OVS_PORT.cfg"
    lxd_IFACE_CFG_TARGET="$lxd_IFACE_DIR/$lxd_IFACE_CFG_FILE"
    lxd_IFACE_CFG_DEST="/etc/network/interfaces.d/"

    # Write ifup .cfg file
    echo "[s0X.2r] Writing configuration > $lxd_IFACE_CFG_TARGET"

cat >$lxd_IFACE_CFG_TARGET <<EOF
auto $add_OVS_PORT
iface $add_OVS_PORT inet dhcp
EOF
}

#################################################################################
# Create VIRSH Network XML Configuration File
write_config_network_virsh () {

    # Set VIRSH Working Variables
    virsh_XML_FILE="$add_OVS_BR.xml"
    virsh_XML_TARGET="$xml_FILE_DIR/$virsh_XML_FILE"

    # Write xml configuration
    run_log 0 "[s0X.2r] Writing configuration > $virsh_XML_TARGET"

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

    # run_log 0 Action
    run_log 0 "Configuring Network Definitions for Libvirtd+KVM+QEMU"

    # Write virsh XML Network Definition
    write_config_network_virsh

    # Defining libvirt network $add_OVS_BR
    virsh net-define $virsh_XML_TARGET 
    run_log 0 "Defined virsh network"

    #Starting Libvirt network
    virsh net-start $add_OVS_BR

    # Setting network to auto-start at boot
    virsh net-autostart $add_OVS_BR

    run_log 0 "[f08.0e] > Done Configuring Libvirt $add_OVS_BR"
}

#################################################################################
# Create LXD Profile matching network bridge name
build_profile_lxd () {
run_log 0 "[s0X.1r] Building LXD Profile \"$add_OVS_BR\""

    $lxd_CMD profile create $lxd_PROFILE_NAME

    $lxd_CMD profile device add $lxd_PROFILE_NAME $add_OVS_BR \
        nic nictype=bridged parent=$add_OVS_BR
    
    $lxd_CMD profile device add $lxd_PROFILE_NAME \
        root disk path=/ pool=default

}

#################################################################################
# Create initial bridge with OVS driver & configure LXD
build_network_lxd () {

    # run_log 0 Action
    run_log 0 "[x0X.0b] Building LXD Network \"$add_OVS_BR\" using \"$ovs_BR_DRIVER\" driver"

    # Create network 
    run_log 0 "[x0X.1s]"
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

    run_log 0 "[x0X.1r]"
}

#################################################################################
# Define default lxd provisioning variables
set_vars_lxd () {
run_log 0 "[s0X.0s] Setting additional LXD Network and Profile Build Variables"

    # Configure DHCP function
    v4_DHCP="false"
    v6_DHCP="false"

    # Configure Routing/NAT'ing function - Valid Options "true|false" 
    v4_ROUTE="false"
    v6_ROUTE="false"

lxd_PROFILE_NAME="$add_OVS_BR"
run_log 0 "[s0X.0s]"
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

    run_log 0 "[f03.0r]> Checking if OVS Bridge $add_OVS_BR already exists"

    ovs_br_check_if_exists 

    if [ $ovs_BR_IS_REAL != "0" ]; then
        run_log 0 "No bridge configured by this name, continuing ..."
    elif [ $ovs_BR_IS_REAL = "0" ]; then
        run_log 0 "OVS Bridge $add_OVS_BR already configured on this host!"
        run_log 0 "To continue we will need to purge previous configuration!"
        while true; do
            read -rp " > Are you sure you want to continue? " yn
            case $yn in
                [Yy]* ) run_log 0 "Confirmed! Continuing ...."; 
                        break
                        ;;
                [Nn]* ) 
                        run_log 1 " > ERROR: Canceling due to user input!"
                        ;;
                    * ) run_log 0 " > Please answer yes or no.";;
            esac
        done
    fi

    run_log 0 "[f03.1r]> Checking System Readiness"
    virt_services_is_enabled 

    run_log 0 "[f03.2r]> Setting LXD Default Variables"
    set_vars_lxd

    run_log 0 "[f03.3r]> Checking Variables"
    check_vars_obb

    run_log "[f03.4r]> Purging pre-existing $add_OVS_BR configuration"
    del_OVS_BR="$add_OVS_BR" 
    delete_network_bridge

    run_log 0 "[f03.5r]> Starting LXD Configuration"
    build_network_lxd
    build_profile_lxd

    run_log 0 "[f03.6r]> Starting LIBVIRT Configuration"
    build_bridge_virsh

    run_log 0 "[f03.0s]>"
    print_config

}

#################################################################################
# Checks value sanity on:
# - Bridge Name
# - Container Name
# - Interface Name
add_ovs_port_flight_check () {
run_log 0 "[f02.0b] > OVS Port Build Starting " 
if  [ $lxd_CONT_NAME != "false" ] && \
    [ $add_OVS_PORT != "false" ]  && \
    [ $name_OVS_BR != "false" ]; then
    
    # Check if bridge name exists
    run_log 0 "[s04.0o] > Checking for Bridge Name on host" 
    ovs_br_check_if_exists

    # Check if container name exists
    run_log 0 "[s03.0o] > Checking if Container Exists ..." 
    lxd_cont_check_if_exists

    # check if port name already exists
    run_log 0 "[s05.0o] > Checking for port name on host" 
    ovs_iface_check_if_exists

    # WARN if bridge does not exist
    # WARN if container name does not exist
    # WARN if a port matching this name already exists
    if [ $ovs_BR_IS_REAL != "0" ]; then
        run_log 0 "[f02.0x] > Unable to find $name_OVS_BR" 
        run_log 0 "[f02.0x] > Found the following bridge names:" 
        ovs-vsctl list-br
        run_log 0 "[f02.0x] Aborting due to error!"
        run_log 0 "[f02.0x] ERROR: Bridge Name Not Found!"

    elif [ $lxd_CONT_IS_REAL != "0" ]; then
        run_log 0 "[f02.1x] > Unable to find $lxd_CONT_NAME"
        run_log 0 "[f02.1x] > Found the following LXD Containers:
        " 
        $lxd_CMD list --format=csv -c n
        run_log 0 ""
        run_log 0 "[f02.1x] Aborting port configuration due to error!"
        run_log 0 "[f02.1x] ERROR: Container Not Found!"

    elif [ $ovs_IFACE_IS_UNIQUE = "0" ]; then
        run_log 0 "[f02.2x] > WARN: Detected a port named $add_OVS_PORT" 
        #echo "[f02.2x] Aborting port configuration due to error!"
        #echo "[f02.2x] ERROR: Interface Name $add_OVS_PORT already in use!"
    fi

    # Continue if Bridge Name / Container Name / Iface Name vars all sane
    # Else exit with error code 1
    run_log 0 "DBG PreRun Code: $ovs_BR_IS_REAL"
    if [ $ovs_BR_IS_REAL = "0" ]   && \
       [ $lxd_CONT_IS_REAL = "0" ]; then 
      #[ $ovs_IFACE_IS_UNIQUE != "0" ]; then
        run_log 0 "[f02.0s] > Found $name_OVS_BR"  
        run_log 0 "[f02.1s] > Found $lxd_CONT_NAME"  
       #run_log 0 "[f02.2s] > Confirmed Port Name $add_OVS_PORT is useable " 
    else
        run_log 1 "[f02.2x] > Exiting!"
    fi

    # Check if iface name is already present on container
    $lxd_CMD config show $lxd_CONT_NAME | grep $add_OVS_PORT;
    check_IFACE_CFG_IS_CONTAINER=$(echo $?)
    if [ $check_IFACE_CFG_IS_CONTAINER = 0 ]; then
        run_log 0 "Found IFACE $add_OVS_PORT configured in host, power off & remove"
    elif [ $check_IFACE_CFG_IS_CONTAINER = 0 ]; then
        run_log 0 "No IFACE $add_OVS_PORT configured on $lxd_CONT_NAME, Continuing..."
    fi
    
    # Generate unique hardware mac address for interface
    run_log 0 "[f02.3r] > " 
    port_hwaddr_gen

fi
run_log 0 "[f02.0e] > Add Port Flight Check Complete" 
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

    # run_log 0 configuration values
    run_log 0 "[f02.5r] > Attaching LXD Container $lxd_CONT_NAME to:"  
    run_log 0 "[f02.5r] >           OVS Bridge:   $name_OVS_BR" 
    run_log 0 "[f02.5r] >           On Port:      $add_OVS_PORT" 
    run_log 0 "[f02.5r] >           HW Address:   $port_IFACE_HWADDR
     " 

    # Halt container if there is a conflicting port already configured 
    # Remove conflicting port once container is stopped
    if [[ $check_IFACE_CFG_IS_CONTAINER = "0" ]] ; then
        lxd_cont_halt_check
        lxd_cont_halt_confirm 
        $lxd_CMD config device remove $lxd_CONT_NAME $add_OVS_PORT
    fi
        
    # Write LXD Container Iface .cfg file
    # Defaults to "auto up" && "inet dhcp"
    write_config_port_lxd 

    # ~IFACE_NAME sets the name of the device in the lxd configuration file
    # ~IFACE_HOST_NAME creates a persistent ovs bridge device name
    # ~IFACE_HWADDR uses the port_HWADDR_GEN value to set a static and repeatable mac
    $lxd_CMD network attach $name_OVS_BR $lxd_CONT_NAME $add_OVS_PORT
    $lxd_CMD config set $lxd_CONT_NAME volatile.$add_OVS_PORT.name $add_OVS_PORT
    $lxd_CMD config set $lxd_CONT_NAME volatile.$add_OVS_PORT.host_name $add_OVS_PORT
    $lxd_CMD config set $lxd_CONT_NAME volatile.$add_OVS_PORT.hwaddr $port_IFACE_HWADDR
    $lxd_CMD file push $lxd_IFACE_CFG_TARGET $lxd_CONT_NAME$lxd_IFACE_CFG_DEST

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

if [ $del_OVS_BR != "false" ]; then

    # run_log 0 Action
    run_log 0 "[f01.0b] > Preparint to remove OVS Bridge: $del_OVS_BR ..." \
       
    
    # Check if network name exists
    # Continue with network removal if bridge is found
    ovs_br_check_if_exists 
    if [ $ovs_BR_IS_REAL = "0" ]; then
        run_log 0 "[f01.0r] > Found $name_OVS_BR"
    elif [ $ovs_BR_IS_REAL != "0" ]; then
        run_log 0 "[f01.0x] > Unable to find Bridge Name: $del_OVS_BR "
    fi

    # Remove lxd network and profile
    run_log 0 "[f01.1r] > Purging $del_OVS_BR from LXD Network and Profile configuration"
    $lxd_CMD network delete $del_OVS_BR > /dev/null 2>&1 ;
    $lxd_CMD profile delete $del_OVS_BR > /dev/null 2>&1 

    # Remove virsh network configuration
    run_log 0 "[f01.2r] > Purging $del_OVS_BR from Libvirt Network Configuration"
    virsh net-destroy $del_OVS_BR > /dev/null 2>&1 ;
    virsh net-undefine $del_OVS_BR > /dev/null 2>&1 ;

    # Remove OVS Bridge
    run_log 0 "[f01.3r] > Purging OpenVswitch Configuration"
    ovs-vsctl del-br $del_OVS_BR > /dev/null 2>&1  ;

    # Remove ifup file
    run_log 0 "[f01.4r] > Removing ifup $del_OVS_BR.cfg"
    rm /etc/network/interfaces.d/*$del_OVS_BR.cfg > /dev/null 2>&1 ;

    # Confirm when done
    run_log 0 "[f01.5r] > Finished Purging $del_OVS_BR from system"

fi

run_log 0 "[f01.0e] > Network Removal Complete for $del_OVS_BR ..."
}

#################################################################################
# Purge dead OVS Interfaces
purge_dead_iface_all () {
dead_OVS_IFACE=$(ovs-vsctl show | awk '$1 - /error:/{print $7;}')

    run_log 0 "[h05.0b] > Purging On All OVS Bridges" 
    for iface in $dead_OVS_IFACE; do 
        ovs-vsctl del-port $iface; 
        run_log 0 "[h05.0r] > Successfully removed $dead_OVS_IFACE" 
    done

run_log 0 "[h05.0e] > Purge Complete" 
}
     
#################################################################################
# Check that required services are running
virt_services_is_enabled () {
run_log 0 "[h03.0b] > Querying Starting ..." 

# Load System Service Status
ovs_SERVICE_STATUS=$(systemctl is-active $ovs_SERVICE_NAME)
lxd_SERVICE_STATUS=$(systemctl is-active $lxd_SERVICE_NAME)
libvirt_SERVICE_STATUS=$(systemctl is-active $libvirt_SERVICE_NAME)

# Display Service Status
run_log 0 "[h03.0r] > Showing Local service health:
" 
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
if [ "$ovs_SERVICE_STATUS" != "active" ]; then
    dead_SERVICE_NAME="ovs_SERVICE_NAME"
    run_log 0 "[h03.1r] > WARN: Dead Service Found  =  $dead_SERVICE_NAME"
    run_log 0 "The OpenVSwitch System Service is NOT RUNNING"
    run_log 0 "Attempting to start $dead_SERVICE_NAME"
    start_system_service 
fi

# If LXD Service is not active, error & attempt to start service
if [ "$lxd_SERVICE_STATUS" != "active" ]; then
    dead_SERVICE_NAME="$lxd_SERVICE_NAME"
    run_log 0 "[h03.2r] > WARN: Dead Service Found  =  $dead_SERVICE_NAME"
    run_log 0 "The LXD System Service IS NOT RUNNING"
    run_log 0 "Attempting to start $dead_SERVICE_NAME"
    start_system_service 
fi

# If Libvirtd Service is not active, error & attempt to start service
if [ "$libvirt_SERVICE_STATUS" != "active" ]; then
    dead_SERVICE_NAME="$libvirt_SERVICE_NAME"
    run_log 0 "[h03.3r] > WARN: Dead Service Found  =  $dead_SERVICE_NAME"
    run_log 0 "The LibVirtD System Service IS NOT RUNNING"
    run_log 0 "Attempting to start $dead_SERVICE_NAME"
    start_system_service 
fi
run_log 0 "[h03.0e] > Query Complete" 
}

#################################################################################
# Show current networks configured for OVS/LXD/KVM+QEMU ) --show | -s
print_config () {
# Check that required services are running
# virt_services_is_enabled
run_log 0 "[h04.0b] > Querying Host OVS Configuration" 

# Load System Service Status
ovs_SERVICE_STATUS=$(systemctl is-active $ovs_SERVICE_NAME)
lxd_SERVICE_STATUS=$(systemctl is-active $lxd_SERVICE_NAME)
libvirt_SERVICE_STATUS=$(systemctl is-active $libvirt_SERVICE_NAME)

# List Openvswitch Networks
run_log 0 "[h04.1r] > Showing Local Bridge Configuration" 
if [ "$libvirt_SERVICE_STATUS" = "active" ] && \
       [ "$lxd_SERVICE_STATUS" = "active" ] && \
       [ "$ovs_SERVICE_STATUS" = "active" ]; then

    # List OpenVSwitch Networks
    run_log 0 "[h04.2r] > OpenVSwitch Network Configuration" 
    run_log 0 "OpenVSwitch Network Configuration
    "
    ovs-vsctl show

    # List LXD Networks
    run_log 0 "[h04.3r] > LXD Network Configuration" 
    run_log 0 "LXD Network Configuration
    "
    $lxd_CMD network list

    # List LibVirtD Networks
    run_log 0 "[h04.4r] > Libvirtd Network Configuration" 
    run_log 0 "LibVirtD Network Configuration 
    "
    virsh net-list --all
fi
run_log 0 "[h04.0e] > Host Config Query Complete" 
}

#################################################################################
# Show Help menu short format ) --help | -h
print_help_short () {
    run_log 0 "[h01.0r] > Print Short" 
    run_log 0 "
    OpenVSwitch Bridge Builder 

    syntax: command [option] [value]

    Options:
                         -h    Print the basic help menu
       --help                  Print the extended help menu
       --show-health     -H    Check OVS|LXD|Libvirtd Service Status
       --show-config     -s    Show current networks configured locally
       --ovs-rm-orphans        Purge orphaned OVS ports 
                               Seen as 'no such device' error from following commands:
                                  'ovs-vsctl show'
                                  'obb -s | obb --show-config'
       --add-port        -p    Add port to bridge and optionally connect port to 
                               container if named. 
                               Value Ordering:
                                  [bridge] [port] [container] 
       --del-br          -d    Deletes network when pased with a value
                               matching an existing network name.
       --add-bridge      -b    Sets the name for building the following: 
                                  OVS Bridge
                                  Libvirt Bridge
                                  LXD Network & Profile Name
"
[[ $show_HELP_LONG = "false" ]] && run_log 0 "[h01.0e] > Print Short End" 
}

#################################################################################
# Show Help menu long format ) --help | -h
print_help_long () {
    run_log 0 "[h02.0r] > Print Long" 
    run_log 0 "
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
run_log 0 "[h02.0e] > Print Long End" 
}

#################################################################################
# Check if run as root!
[[ $EUID -ne 0 ]] && run_log 1 "Must be run as root!"

#################################################################################
# Start initial function that determines behavior from command line flags
# Read variables from command line
run_log 0 "[d00.2r] > Enabling Command Line Options" 
OPTS=`getopt \
    -o bpdsHhz: \
    --long \
    add-bridge,add-port,del-br,ovs-rm-orphans,show-config,show-health,help,zee: \
    -n 'parse-options' -- "$@"`

# Fail if options are not sane
run_log 0 "[d00.3r] > Checking Command Line Option Sanity" 
[[ $? != 0 ]] && run_log 1 " > Failed parsing options ... Exiting!" >&2

# Parse variables
run_log 0 "[d00.4r] > Parsing Command Line Options" 
eval set -- "$OPTS"
while true; do
    case "$1" in
        -h                ) 
           show_HELP="true"; 
           run_log 0 "[h01.0b] > Showing Help Short" 
           print_help_short
           shift 
           ;;
       --help             ) 
           show_HELP="true" 
           show_HELP_LONG="true"; 
           run_log 0 "[h02.0b] > Showing Help Long" 
           print_help_short
           print_help_long
           run_log 1 "[h02.0c] > OVS_BridgeBuilder_VERSION = $obb_VERSION" 
           shift 
           ;;
       -H | --show-health ) 
           show_HEALTH=true ; 
           run_log 0 "[h03.0o] > Querying Virt Services Status" 
           virt_services_is_enabled
           run_log 1 "[h03.0c] > Health Check Complete" 
           shift 
           ;;
       -s | --show-config ) 
           show_CONFIG=true ; 
           run_log 0 "[h04.0o] > Showing Host Network Configuration " 
           print_config
           run_log 1 "[h04.0c] > $obb_VERSION" 
           shift
           ;;
       --ovs-rm-orphans   ) 
           purge_DEAD_OVS_PORTS="true"; 
           run_log 0 "[h05.0o] > Purge Dead OVS Ports" 
           purge_dead_iface_all
           run_log 1 "[h05.0c] > $obb_VERSION" 
           shift 
           ;;
       -d | --del-br      )
           del_OVS_BR="$3"; 
           run_log 0 "[f01.0o] > Requesting to remove $del_OVS_BR ..."
           delete_network_bridge
           print_config
           run_log 1 "[f01.0c] > Purged $del_OVS_BR Bridge" 
           shift; 
           shift 
           ;;
        -p | --add-port   ) 
            name_OVS_BR="$3"
            add_OVS_PORT="$4" 
            lxd_CONT_NAME="$5" 
            run_log 0 "[f02.0o] > Addinng New OVS Port $add_OVS_PORT" 
            add_ovs_port 
            run_log 1 "[f02.0c] > Done adding OVS Port $add_OVS_PORT" 
            shift; 
            shift;
            ;;
        -b | --add-bridge ) 
            build_NEW_BRIDGE="true"
            name_OVS_BR="$3"; 
            add_OVS_BR="$3"; 
            run_log 0 "[f03.0o] > Addinng New OVS Bridge $add_OVS_BR" 
            add_ovs_bridge
            run_log 1 "[f03.0c] > Done adding OVS Bridge $add_OVS_BR" 
            shift; 
            shift; 
            ;;
#            --del-port   ) PURGE_PORT="$3"; shift; shift ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
done
run_log 0 "[d00.0e] > Processed Variables and Flags" 

