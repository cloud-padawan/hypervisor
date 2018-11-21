#!/bin/bash
#
## Written By ContainerCraft.io (CCIO|ccio) 
# This tool will:
# -- Install LXD from PPA
# -- Install Libvirt+KVM+QEMU
# -- Install OpenVSwitch (dpdk)
#
## ToDo:
# Cleanup LXD Init function to handle pre-existing zfs volumes more gracefully
# Add ability to pass variables via yaml *(1) *(2) *(3) 
# Add ability to turn component install on and off with flags at command line:
# Add docker installation either as a guest vm or natively (research required)
# Create helper tui
# Finish libvirt logical EFI enablement on properly equipped systems if EFI vars are detected
# - /sys/firmware/efi/efivars
#   Eg: $ ccio --hypervisor-install --[lxd-snap|lxd-ppa] --kvm-qemu --[openvswitch|openvswitch-dpdk] 
#
## Add support for `lxd init` yaml config as follows for CCIO supported values: 
# Do you want to configure a new storage pool (yes/no) [default=yes]? yes
# Name of the new storage pool [default=default]: default
# Name of the storage backend to use (dir, lvm, zfs) [default=zfs]: zfs
# Create a new ZFS pool (yes/no) [default=yes]? yes
# Would you like to use an existing block device (yes/no) [default=no]? no
# Size in GB of the new loop device (1GB minimum) [default=100GB]: 64
# Would you like LXD to be available over the network (yes/no) [default=no]? yes
# Address to bind LXD to (not including port) [default=all]:  all
# Port to bind LXD to [default=8443]: 8443
# Trust password for new clients:    
# Again:                             
# Would you like stale cached images to be updated automatically (yes/no) [default=yes]? yes
# Would you like to create a new network bridge (yes/no) [default=yes]? no       

# Refrences: 
# https://software.intel.com/en-us/articles/set-up-open-vswitch-with-dpdk-on-ubuntu-server
# http://dpdk.org/doc/guides/linux_gsg/sys_reqs.html#running-dpdk-applications
# https://help.ubuntu.com/community/JeOSVMBuilder
# https://www.ibm.com/support/knowledgecenter/en/linuxonibm/liaat/liaatvirtinstalloptions.htm
# https://ubuntu-smoser.blogspot.co.uk/2013/02/using-ubuntu-cloud-images-without-cloud.html
# https://dshcherb.github.io/2017/12/04/qemu-kvm-virtual-machines-in-unprivileged-lxd.html
# https://github.com/dillonhafer/wiki/wiki/KVM
#  (1) https://medium.com/@frontman/how-to-parse-yaml-string-via-command-line-374567512303
#  (2) https://gist.github.com/pkuczynski/8665367
#  (3) https://github.com/0k/shyaml
#################################################################################
# Version
hvi_VERSION=v00.31.a

# Print Notice
clear && echo "
 NOTICE: YOU ARE RUNNING A BETA PROJECT!
 ContainerCraft.io ~~ ccio-hypervisor-install 
 Hypervisor Installer Utility Version: $hvi_VERSION
"

# Temporary Debug Toggle
print_DBG_FLAGS="true"

#################################################################################
# Logging Function
run_log () {

    if [ $1 == 0 ]; then
        echo "INFO: $2"
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
# Configure and validate libvirt installation
configure_libvirt () {
virt_VALIDATE=$(virt-host-validate ; echo $?)
grub_SAFETY=$(grep iommu /etc/default/grub ; echo $?)
virt_INTEL=$(grep vmx /proc/cpuinfo; echo $?)
virt_AMD=$(grep svm /proc/cpuinfo; echo $?)

    mkdir -p /etc/ccio/virsh_xml
    if [[ ! $virt_VALIDATE == "0" ]] && \
       [[ ! $grub_SAFETY == "0" ]]; then
        if [[ $virt_INTEL == "0" ]]; then

            sed -i \
                's/^GRUB_CMDLINE_LINUX_DEFAULT.*/& intel_iommu=on iommu=pt/' \
                /etc/default/grub
            update-grub

        elif [[ $virt_AMD == "0" ]]; then

            sed -i \
                's/^GRUB_CMDLINE_LINUX_DEFAULT.*/& amd_iommu=on iommu=pt/' \
                /etc/default/grub
            update-grub

        fi
    else

        run_log 0 "No Hardware VTd/AMD-V Virtual Extensions Detected"
        run_log 0 "Running in paravirtualized mode"

    fi

}

#################################################################################
# install Libvirt | KVM | QEMU packages
install_libvirt () {
LIBVIRT_PKGS="qemu qemu-kvm qemu-utils libvirt0 libvirt-bin libvirt-clients libvirt-daemon"

    run_log 0 "Installing Libvirt packages"

    apt install -y $LIBVIRT_PKGS #>/dev/null 2&>1

    run_log 0 "Installed LibvirtD + KVM + QEMU Requirements"

libvirt_SVC_NAME_CHECK=$(systemctl list-unit-files | awk '/libvirtd/ {print $1}')
sed -i "s/libvirt_SERVICE_NAME=\"*\"/libvirt_SERVICE_NAME=\"$libvirt_SVC_NAME_CHECK\"/g" /etc/ccio/ccio.conf
}

#################################################################################
# Prompt User to Continue Libvirt Installation
prompt_libvirt_install () {
while true; do
   	read -rp "$SEP_2 Do you want to continue installation?" yn
        case $yn in
   		    [Yy]* ) run_log 0 "Continuing ..." 
                    libvirt_install
                    break
                    ;;
	        [Nn]* ) run_log 1 "Exiting due to user input!"
                    ;;
   	            * ) run_log 0 "Please answer yes or no."
        esac
    break
done
}

#################################################################################
# Test host system for virtual extensions
#   (Usually enabled in BIOS on supported hardware)
#   EG: VT-d or AMD-V 
check_host_virt_support () {
check_HOST_VIRT_EXT=$(grep -E '(vmx|svm)' /proc/cpuinfo)

run_log 0 "Checking Host System Virtual Extensions"

if [ "$check_HOST_VIRT_EXT" != "0" ]; then

	    run_log 0 "System passed host virtual extension support check"

elif [ "$check_HOST_VIRT_EXT" != "0" ]; then

    run_log 0 "
    Host did not pass virtual extension support check!
    This means that your hardware either does not support
    KVM acceleration (VT-d|AMD-v), or the feature has not
    yet been enabled in BIOS.

    You may continue installation however libvirt guests will
    only run in PVM mode. PVM guests will experience
    significantly degrated performance as compared to
    running with full HVM support.
    "

    # Begin Libvirtd Installation
    prompt_install_libvirt

fi
}

#################################################################################
# Confirm safety of data removal
check_safety_zpool_delete () {
zpool_NAME="default"
zpool_TYPE="zfs"

    run_log 0 "checking pre-existing zpools"
    run_log 0 "Preping host for LXD configuration"
    run_log 0 "CCIO_Setup is about to purge any zfs pools and lxd storage"
    run_log 0 "matching the name \"$zpool_NAME\""

if [ "$(zpool list $zpool_NAME; echo $?)" = "0" ]; then 
        run_log 0 "No pre-existing storage pools found matching $zpool_NAME"
        run_log 0 "Continuing ..."
    else
        run_log 0 "Found existing ZFS configuration showing pool information
    "

        zpool list $zpool_NAME

        #lxc storage list | grep $zpool_NAME
        echo ""
        while true; do
        read -rp "Are you sure $zpool_NAME is safe to erase? " yn
            case $yn in
                [Yy]* ) run_log 0 "Purging $zpool_NAME ...." 
                        break
                        ;;
                [Nn]* ) run_log 1 "Exiting due to user input" 
                        ;;
                    * ) echo "Please answer yes or no.";;
            esac
        break
    done
fi
}

#################################################################################
# Configure LXD for first time use
configure_lxd_daemon () {

    run_log 0 "Preparing System for Initialization"
    check_safety_zpool_delete 
    zpool destroy -f $zpool_NAME
    lxc storage delete $zpool_NAME
    lxc storage create $zpool_NAME $zpool_TYPE

stty -echo; read -rp "Please Create a Password for your LXD Daemon: " PASSWD; echo
stty echo


    # Initialize LXD with basic feature set
    run_log 0 "Configuring LXD init with preseed data"
    cat <<EOF | lxd init --preseed 
config:
  core.https_address: 0.0.0.0:8443
  core.trust_password: $PASSWD
  images.auto_update_interval: 60
networks:
- name: ovs
  type: bridge
  config:
    dns.mode: none
    ipv4.nat: false
    ipv4.dhcp: false
    ipv4.address: none
    ipv4.routing: false
    ipv4.firewall: false
    ipv6.nat: false
    ipv6.dhcp: false
    ipv6.address: none
    ipv6.routing: false
    ipv4.firewall: false
profiles:
- name: default
  devices:
    root:
      path: /
      pool: default
      type: disk
EOF

    # Add BCIO Container Repository Mirror
    lxc remote add bcio https://images.braincraft.io --public --accept-certificate

    unset PASSWD
    run_log 0 "LXD Configuration Complete"
}

#################################################################################
# Prompt for lxd install source from either Legacy PPA or SNAP package
# Install LXD Packages from PPA
install_lxd_legacy_ppa () {

    run_log 0 "Installing LXD from PPA"
    snap remove lxd 2&>/dev/null
    apt purge -qqq -y lxd lxd-client >/dev/null 2>&1

    #apt-add-repository ppa:ubuntu-lxc/stable -y
	#apt install -qqq -y -t xenial-backports \
    #apt update -qqq >/dev/null 2>&1
	apt install -y --assume-yes \
                      lxd \
                      lxd-client \
                      lxd-tools \
                      lxc-common \
                      lxc-utils \
                      lxcfs \
                      liblxc1 \
                      uidmap \
                      criu \
                      zfsutils-linux \
                      btrfs-tools \
                      squashfuse \
                      ebtables 

    run_log 0 "Installed LXD requirements successfully!"  

}

#################################################################################
# Install LXD Packages from SNAP
install_lxd_snap () {

    PS3="
    CAUTION, this is a DESTRUCTIVE ACTION!

    DO NOT PROCEED UNLESS YOU UNDERSTAND THIS CAN ERASE DATA!

    This installer is intended to be run on a clean install of Ubuntu.
    Running in any other conditions may have unexpected results.

    Continuing will remove any legacy "lxd" & "lxd-client" .deb packages.
    This does NOT affect the snap install of lxd. 
    Once the ppa ".deb" packages have been removed you will not have access
    to any previously created LXD containers created with those packages.

    Select: "

    run_log 0 "
        Are you sure you want to continue? 
    "

options=("Continue" "Cancel")
select opt in "${options[@]}"; do
    case $REPLY in
      "Continue") run_log 0 "Continuing LXD Installation ..."
                  ;;
        "Cancel") run_log 1 "Canceling due to user input"
                  ;;
               *) run_log 6 "$1 is not a valid option"
                  ;;
        esac
    break
done

    # Purge legacy lxd packages
    apt purge lxd lxd-client -y 2&>1

    # Install lxd
    echo "Installing LXD via snappy package"
    apt install -y zfsutils-linux squashfuse 
    snap install lxd 2&>1

# Determine host system's service names for LXD
lxd_SVC_NAME_CHECK=$(systemctl list-unit-files \
                    | grep -E "lxd.service|snap.lxd.daemon.service" \
                    | awk '{print $1}')

sed -i "s/lxd_SERVICE_NAME=\"*\"/lxd_SERVICE_NAME=\"$lxd_SVC_NAME_CHECK\"/g" /etc/ccio/ccio.conf
}

#################################################################################
# Prompt for lxd install source from either Legacy PPA or SNAP package
check_install_source_lxd () {

      PS3="
      CAUTION, this will remove any existing LXD installs and configuration!

      Please note that the SNAP package is recommended. 

Select: "

echo "
      Do you want to install LXD from the SNAP package or legacy PPA? 

     "

options=("Install Snap Package" "Install Legacy PPA" "Cancel")
select opt in "${options[@]}"; do
    case $REPLY in
       "1") run_log 6 "Installing via snap"
            install_lxd_snap
            ;;
       "2") run_log 6 "Installing via legacy ppa"
            install_lxd_legacy_ppa
            ;;
       "3") run_log 1 "Canceling due to user input"
            ;;
        *)  run_log 6 "$1 is not a valid option"
            ;;
    esac
    break
done
}

#################################################################################
# configure system for OVS
# If supported & user approves, enable dpdk
configure_openvswitch () {

    run_log 0 "Enable OVS systemd service"
	systemctl restart openvswitch-switch.service
	systemctl enable openvswitch-switch.service

}

#################################################################################
# Install OpenVSwitch Packages
install_openvswitch () {
OVS_PKGS="openvswitch-common openvswitch-switch"
OVS_DPDK_PKGS="dkms dpdk dpdk-dev openvswitch-switch-dpdk"

    run_log 0 "Installing OpenVSwitch Components"
	apt install -y $OVS_PKGS $OVS_DPDK_PKGS 

# Determine host system's service names for OVS
ovs_SVC_NAME_CHECK=$(systemctl list-unit-files \
                    | grep -E "openvswitch-switch.service"\
                    | awk '{print $1}')

sed -i "s/ovs_SERVICE_NAME=\"*\"/ovs_SERVICE_NAME=\"$ovs_SVC_NAME_CHECK\"/g" /etc/ccio/ccio.conf
}

#################################################################################
# System upgrade routine called when required
apt_upgrade () {

    apt upgrade -y -qqq 2>&1
    apt dist-upgrade -y -qqq 2>&1
    apt autoremove -y -qqq 2>&1

}

#################################################################################
# System update routine called when required
apt_udpate () {

    apt update -y -qqq #>/dev/null 2>&1

}

#################################################################################
# 
read_MORE () {
    echo "
       The CCIO build environmet provides the base build environment for local
       virtual infrastructure development. Your system will also be configured 
       with the DEVELOPMENT CCIO Utils Development packages into /etc/ccio/. 
       
       Installation will also include:
            
             OpenVSwitch              # For intra host networking
             Libvirtd / QEMU / KVM    # For Virtual Machines
             LXD                      # For Light Weight Containers

       Learn more and contribute at:
           https://github.com/containercraft/hypervisor

       ~~ WARNING THIS IS A DEVELOPMENT BUILD - UNDERSTAND THE MEANING OF ALPHA ~~
    "
}

#################################################################################
# Check if services are installed & launch installers if required
cmd_parse_run () {
check_OVS_IS_INSTALLED="$(command -v ovs-vsctl >/dev/null; echo $?)"
check_LIBVIRT_IS_INSTALLED="$(command -v libvirtd >/dev/null; echo $? )"
check_LXD_IS_INSTALLED="$(command -v lxd >/dev/null; echo $? )"

run_log 0 "Running system updates ..."
    apt_udpate 
    apt_upgrade 

run_log 0 "Checking if OpenVSwitch is Installed..."
if [[ "$check_OVS_IS_INSTALLED" == "0" ]]; then

    # Confirm OpenVSwitch Already Installed
    run_log 0 "OpenVSwitch Already Installed, Continuing.. "

elif [[ "$check_OVS_IS_INSTALLED" != "0" ]]; then

    # Install OpenVSwitch
    run_log 0 "installing openvswitch"
    install_openvswitch
    
    # Determine host system's service names for OVS
    ovs_SVC_NAME_CHECK=$(systemctl list-unit-files \
                        | grep -E "ovs-vswitchd.service|openvswitch-switch.service"\
                        | awk '{print $1}')

    # Update ccio.conf ovs service name
    sed -i "s/ovs_SERVICE_NAME=\"*\"/ovs_SERVICE_NAME=\"${ovs_SVC_NAME_CHECK}\"/g" /etc/ccio/ccio.conf

    run_log 0 "configuring openvswitch"
    configure_openvswitch 

fi

run_log 0 "Is LXD installed, .... checking"
if [[ $check_LXD_IS_INSTALLED == "0" ]]; then

    run_log 0 "LXD Already installed on system"

elif [[ $check_LXD_IS_INSTALLED != "0" ]]; then

    dbg_FLAG="Installing lxd" run_log 0
    check_install_source_lxd 

    # Determine host system's service names for LXD
    lxd_SVC_NAME_CHECK=$(systemctl list-unit-files \
                        | grep -E "lxd.service|snap.lxd.daemon.service" \
                        | awk '{print $1}')

    # Update ccio.conf lxd service name
    sed -i "s/lxd_SERVICE_NAME=\"*\"/lxd_SERVICE_NAME=\"${lxd_SVC_NAME_CHECK}\"/g" /etc/ccio/ccio.conf

    dbg_FLAG="configuring lxd" run_log 0
    configure_lxd_daemon 

fi

run_log 0 "Is libvirt installed, .... checking"
if [[ "$check_LIBVIRT_IS_INSTALLED" != "0" ]]; then

    run_log 0 "Checking Host Virtual Extensions"
    check_host_virt_support

    # Install Libvirtd
    install_libvirt

    # Detect libvirt service name
    libvirt_SVC_NAME_CHECK=$(systemctl list-unit-files \
                            | awk '/libvirtd/ {print $1}')

    # Update ccio.conf lxd service name
    sed -i "s/libvirt_SERVICE_NAME=\"*\"/libvirt_SERVICE_NAME=\"${libvirt_SVC_NAME_CHECK}\"/g" /etc/ccio/ccio.conf

    run_log 0 "Configuring libvirt"
    configure_libvirt 

fi

run_log 0 "Final System Check... "
if [[ "$check_LIBVIRT_IS_INSTALLED" = "0" ]] && \
       [[ "$check_LXD_IS_INSTALLED" = "0" ]]  && \
       [[ "$check_OVS_IS_INSTALLED" = "0" ]]; then

       dbg_FLAG="Removing ccio-install binary" run_log 0
       rm /usr/bin/ccio-install

       run_log 0 "All services are already installed"
       exit 0
fi
}


#################################################################################
# Check if run as root!
clear
[[ $EUID -ne 0 ]] && run_log 1 "Must be run as root!"

#################################################################################
# Begin Main Function
cmd_parse_run

#===============================================================================#
# Research required on scripting the following:
# - Hugepages
# - OVS-DPDK configuration
#
# DO NOT USE UNTIL FULLY TESTED!!!!!
#(/etc/default/grub) <> 
# GRUB_CMDLINE_LINUX_DEFAULT= \
#    "default_hugepagesz=1G \
#    hugepagesz=1G \
#    hugepages=16 \
#    hugepagesz=2M \
#    hugepages=2048 \
#    iommu=pt \
#    intel_iommu=on \
#    isolcpus=2-8,10-16,18-24,26-32"
#(/etc/dpdk/dpdk.conf) <> NR_1G_PAGES=8
#sudo mkdir -p /mnt/huge
#sudo mkdir -p /mnt/huge_2mb
#sudo mount -t hugetlbfs none /mnt/huge
#sudo mount -t hugetlbfs none /mnt/huge_2mb -o pagesize=2MB
#sudo mount -t hugetlbfs none /dev/hugepages
#sudo update-grub
#sudo reboot
#(confirm HP config) $ grep HugePages_ /proc/meminfo cat /proc/cmdline
#‘sudo ovs-vsctl ovs-vsctl set Open_vSwitch . <argument>’.
#sudo ovs-vsctl --no-wait set Open_vSwitch . other_config:dpdk-init=true
# Allow running libvirt commands as user without passwd
# gpasswd libvirtd -a <username>
#
# Enable pci-passthrough on bare metal
# /etc/modules
# pci_stub  
# vfio  
# vfio_iommu_type1  
# vfio_pci  
# vfio_virqfd  
# kvm  
# kvm_intel  
# 
# Enable IOMMU at grub cmdline
# /etc/default/grub
# sed find replace
# line: GRUB_CMDLINE_LINUX_DEFAULT
# s/quiet splash/intel_iommu=on/g
# 
# intelligent kvm nested enablement
# Only enable if bare metal
# Only enable if following command output != Y
# cat /sys/module/kvm_intel/parameters/nested
# then: echo 'options kvm_intel nested=1' >> \
#	/etc/modprobe.d/qemu-system-x86.conf
# if intel then
# /etc/default/grub
# s/quiet splash/kvm-intel.nested=1/g
#
# grub-update
# double check against:
# https://computingforgeeks.com/complete-installation-of-kvmqemu-and-virt-manager-on-arch-linux-and-manjaro/
# https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF
# https://wiki.archlinux.org/index.php/KVM
# sudo -i
# groupadd --system-extrausers lxd
# lxd --group lxd --debug
# newgrp lxd
# lxc remote add images images.linuxcontainers.org
# usermod -G lxd -a <username>
# snap install lxd (--edge) 
