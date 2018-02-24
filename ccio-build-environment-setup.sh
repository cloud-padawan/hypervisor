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
hvi_VERSION=v00.21.a
echo "
 NOTICE: YOU ARE RUNNING A BETA PROJECT!
 ContainerCraft.io ~~ ccio-hypervisor-install 
 $hvi_VERSION
"

# Check if run as root!
if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root!"
	echo "Exiting ... " 
        exit 1
fi

#################################################################################
# Debug Flag [true|false]
print_DBG_FLAGS="true"
# Debug output 
print_dbg_flags () {
if [ $print_DBG_FLAGS = "true" ]; then
    echo ">> >> $dbg_FLAG"
fi
}

#################################################################################
# Configure and validate libvirt installation
configure_libvirt () {
dbg_FLAG="WARNING! All automated Libvirt configuration currently disabled!!!" && print_dbg_flags; 
mkdir -p /etc/ccio/virsh_xml
virt-host-validate
}

#################################################################################
# install Libvirt | KVM | QEMU packages
install_libvirt () {
echo "[f25.0s] Installing Libvirt packages"
LIBVIRT_PKGS="qemu qemu-kvm qemu-utils libvirt-bin libvirt0"
#EFI_PKGS="qemu-efi \
#          ovmf"
       apt install $LIBVIRT_PKGS
       #apt install -y $LIBVIRT_PKGS #EFI_PKGS
echo "$SEP_2 Installed LibvirtD + KVM + QEMU Requirements!"
}

#################################################################################
prompt_libvirt_install () {
while true; do
   	read -rp "$SEP_2 Do you want to continue installation?" yn
   	case $yn in
   		[Yy]* ) echo "$SEP_2 Continuing ..." ; 
            libvirt_install
   			break
            ;;
		[Nn]* ) echo "$SEP_2 Exiting due to user input!"
  			exit 1
            ;;
   		* ) echo "$SEP_2 Please answer yes or no." ;;
	esac
    break
done
echo "[f10.0e]"
}

#################################################################################
# Test host system for virtual extensions
#   (Usually enabled in BIOS on supported hardware)
#   EG: VT-d or AMD-V 
check_host_virt_support () {
echo "[f10.0b]"
check_HOST_VIRT_EXT=$(grep -E '(vmx|svm)' /proc/cpuinfo)
if [ "$check_HOST_VIRT_EXT" != "0" ]; then
    echo "[f10.1r]"
	echo "$SEP_2 System passed host virtual extension support check"
    install_libvirt
elif [ "$check_HOST_VIRT_EXT" != "0" ]; then
    echo "[f10.2r]"
	echo "$SEP_2 ERROR: Host did not pass virtual extension support check!"
	echo "       $SEP_2 This means that your hardware either does not support"
	echo "       $SEP_2 KVM acceleration (VT-d|AMD-v), or the feature has not"
	echo "       $SEP_2 yet been enabled in BIOS."
	echo "       $SEP_2 You may continue installation but libvirt guests will"
	echo "       $SEP_2 only run in PVM mode. PVM guests will experience"
	echo "       $SEP_2 significantly degrated performance as compared to"
	echo "       $SEP_2 running with full HVM support.
	     "
    echo "[f10.3r]"
    prompt_install_libvirt
echo "[f10.0e]"
fi
}

#################################################################################
# Confirm safety of data removal
check_safety_zpool_delete () {
echo "checking pre-existing zpools"
zpool_NAME="default"
zpool_TYPE="zfs"
echo "[f24.0s] Preping host for LXD configuration"
echo "[f24.1r] CCIO_Setup is about to purge any zfs pools and lxd storage"
echo "         matching the name \"$zpool_NAME\""
if [ "$(zpool list $zpool_NAME; echo $?)" = "0" ]; then 
   echo "No pre-existing storage pools found matching $zpool_NAME"
else
    echo "$SEP_2 Showing pool information
    "
    zpool list $zpool_NAME
    #lxc storage list | grep $zpool_NAME
    echo ""
    while true; do
    read -rp "Are you sure $zpool_NAME is safe to erase?" yn
        case $yn in
            [Yy]* ) 
                echo "Purging $zpool_NAME ...." ; 
                break
                ;;
            [Nn]* ) 
                echo "Exiting due to user input" ; 
                exit 1
                ;;
            * ) 
                echo "Please answer yes or no.";;
        esac
    break
done
fi
}

#################################################################################
# Configure LXD for first time use
configure_lxd_daemon () {
echo "[f24.2r] Purging conflicting configurations"
check_safety_zpool_delete 
    zpool destroy -f $zpool_NAME
    lxc storage delete $zpool_NAME
    lxc storage create $zpool_NAME $zpool_TYPE
stty -echo; read -rp "Please Create a Password for your LXD Daemon: " PASSWD; echo
stty echo
cat <<EOF | lxd init --preseed 
echo "[f24.3r] Configuring LXD init with preseed data"
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
unset PASSWD
echo "Configured LXD successfully with preseed values"
}

#################################################################################
# Prompt for lxd install source from either Legacy PPA or SNAP package
# Install LXD Packages from PPA
install_lxd_legacy_ppa () {
echo "[f23.0s] Installing LXD from PPA"
    apt purge lxd lxd-client

    apt-add-repository ppa:ubuntu-lxc/stable -y
	apt update
	apt install -y -t xenial-backports \
		lxd \
		lxd-client \
		lxd-tools \
		lxc-common \
		lxcfs \
		liblxc1 \
		uidmap \
		criu \
		zfsutils-linux \
		squashfuse \
		ebtables
echo "$SEP_2 Installed LXD requirements successfully!"  
}

#################################################################################
# Install LXD Packages from SNAP
install_lxd_snap () {
# TODO: add migration support from ppa>snap
PS3="
      CAUTION, this is a DESTRUCTIVE ACTION!

      DO NOT PROCEED UNLESS YOU UNDERSTAND THE CONSEQUENCES!

      This installer was intended to be run on a clean install of Ubuntu.

      Continuing will remove any legacy "lxd" & "lxd-client" .deb packages.
      This does NOT affect the snap install of lxd. 
      Once the ppa ".deb" packages have been removed you will not have access
      to any previously created LXD containers.

Select: "
echo "
      Are you sure you want to continue? 

     "
options=("Continue" "Cancel")
select opt in "${options[@]}"; do
    case $REPLY in
        "Continue")
            echo "Continuing LXD Installation ..."
            ;;
        "Cancel")
            echo "Canceling due to user input"
            echo "Exiting immidiately ..."
            exit 1
            ;;
        *)
            echo "$1 is not a valid option"
            echo "Please type in: 'Continue' or 'Cancel'"
            ;;
    esac
    break
done

    # Purge legacy lxd packages
    apt purge lxd lxd-client -y

    # Install lxd
    echo "[f22.0s] Installing LXD from SNAP"
    apt install -y zfsutils-linux squashfuse
    snap install lxd 
    snap refresh lxd --edge
}

#################################################################################
# Prompt for lxd install source from either Legacy PPA or SNAP package
check_install_source_lxd () {
PS3="
      CAUTION, this will remove any existing versions of LXD!

      Please note that the SNAP package is HIGHLY recommended! 

      Only use the PPA Install option if you know what you are doing.
      PPA installation is required for the CRIU live migration feature.

Select: "
echo "
      Do you want to install LXD from the SNAP package or legacy PPA? 

     "
options=("Install Snap Package" "Install Legacy PPA" "Cancel")
select opt in "${options[@]}"; do
    case $REPLY in
        "1")
            echo "Installing via snap"
            install_lxd_snap
            ;;
        "2")
            echo "Installing via legacy ppa"
            install_lxd_legacy_ppa
            ;;
        "3")
            echo "Canceling due to user input"
            echo "Exiting immidiately ..."
            exit 1
            ;;
        *)
            echo "$1 is not a valid option"
            ;;
    esac
    break
done
}

#################################################################################
# configure system for OVS
# If supported & user approves, enable dpdk
configure_openvswitch () {
dbg_FLAG="[f22.0s]" && print_dbg_flags; 
#dbg_FLAG="[f22.1r] Configuring Host for OpenVSwitch with DPDK Enablement" && print_dbg_flags; 
#	update-alternatives --set \
#        ovs-vswitchd /usr/lib/openvswitch-switch-dpdk/ovs-vswitchd-dpdk
dbg_FLAG="[f22.2r]" && print_dbg_flags; 
	systemctl restart openvswitch-switch.service
	systemctl enable openvswitch-switch.service
dbg_FLAG="Done" && print_dbg_flags; 
}

#################################################################################
# Install OpenVSwitch Packages
install_openvswitch () {
dbg_FLAG="[f21.0s] Installing OpenVSwitch Components" && print_dbg_flags; 
OVS_PKGS="openvswitch-common openvswitch-switch"
OVS_DPDK_PKGS="dkms dpdk dpdk-dev openvswitch-switch-dpdk"

	apt install -y $OVS_PKGS $OVS_DPDK_PKGS
}

#################################################################################
# System upgrade routine called when required
apt_upgrade () {
apt upgrade -y 
apt dist-upgrade -y 
apt autoremove -y
}

#################################################################################
# System update routine called when required
apt_udpate () {
apt update 
}

#################################################################################
# 
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
}

#################################################################################
# Check if services are installed & launch installers if required
cmd_parse_run () {
check_OVS_IS_INSTALLED=$(command -v ovs-vsctl >/dev/null; echo $?) 
check_LIBVIRT_IS_INSTALLED=$(command -v libvirtd >/dev/null; echo $? ) 
check_LXD_IS_INSTALLED="1"
#check_LXD_IS_INSTALLED=$(command -v lxd >/dev/null; echo $? )

dbg_FLAG="running updates ..." && print_dbg_flags; 
apt_udpate
apt_upgrade

echo "is ovs installed, .... checking"
echo "$check_OVS_IS_INSTALLED"
if [ "$check_OVS_IS_INSTALLED" != "0" ]; then
    dbg_FLAG="installing openvswitch" && print_dbg_flags; 
    install_openvswitch
    dbg_FLAG="configuring openvswitch" && print_dbg_flags; 
    configure_openvswitch 
fi
echo "is lxd installed, .... checking"
if [ $check_LXD_IS_INSTALLED != "0" ]; then
    dbg_FLAG="installing lxd" && print_dbg_flags; 
    check_install_source_lxd 
    dbg_FLAG="configuring lxd" && print_dbg_flags; 
    configure_lxd_daemon 
fi
echo "is libvirt installed, .... checking"
if [ "$check_LIBVIRT_IS_INSTALLED" != "0" ]; then
    dbg_FLAG="installing libvirt+qemu+kvm" && print_dbg_flags; 
    check_host_virt_support
    configure_libvirt 
fi
if [ "$check_LIBVIRT_IS_INSTALLED" = "0" ] && \
   [ "$check_LXD_IS_INSTALLED" = "0" ]     && \
   [ "$check_OVS_IS_INSTALLED" = "0" ]; then
   echo "All services are already installed"
   exit 1
fi
rm /usr/bin/ccio-install
}


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
