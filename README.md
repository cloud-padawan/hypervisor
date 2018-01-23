CCIO Hypervisor installer & OVS BridgeBuilder
==============================================

Hypervisor configuration and management tools

## To Install:

  ``$ sudo curl -L https://raw.githubusercontent.com/containercraft/hypervisor/master/install.sh |bash ``

  ``$ sudo ccio-install``

## Purpose:

This tooling provides a common platform to quickly and seamlessly build virtual environments.

The original inspiration for this project came from endless hours of testing different virtual
network building tools and strategies in search of a paradigm that meets a number of criteria.

Easy integration of technologies including:
  + Docker
  + LXC / LXD
  + Libvirt / QEMU+KVM
  + Bare Metal Hosts
  + Physical Switching Gear

Easy end-user management and setup:
  + Logical to comprehend
  + Easy to setup
  + Easy to manage
  + Easy to use over Wifi connections
  + Easy to integrate physical network gear
  + Capable of multi-host overlays
  + Capable of nesting multiple layers of networks

The tooling also needs to be consistent across hardware platforms including:
  + client laptops
  + client desktops
  + low cost home labs
  + devops lab servers
  + 100% virtual tenants
  + multi host rack systems

##  Usage and Syntax:
       command [option] [value]

    This tool will create a new OVS bridge.
    By default, this bridge will be ready for use with each of the following:

       LXD:
        \_______       
                \_Launch a container with the "lxd profile" flag to attach
                |    Example:                                               
                |      lxc launch ubuntu: test-container -p $NETWORK_NAME

       Libvirt Guests:
        \_______
                \_Attach Libvirt / QEMU / KVM guests:
                |   Example:
                |     virt-manager nic configuration
                |     virsh xml configuration

       Physical Ports:
        \_______
                \_Attach Physical Ports via the following
                |   Example with physical device name eth0
                |      ovs-vsctl add-port obb eth0

    Options:
       --help            -h    --    Print this help menu
       --health-check    -H    --    Check OVS|LXD|Libvirtd Service Status
       --show-config     -c    --    Show current networks configured locally
       --purge           -p    --    Purges network when pased with a value
                                     matching an existing network name.
       --name            -n    --    Sets the name for building the following:
                                        OVS Bridge
                                        Libvirt Bridge
                                        LXD Network & Profile Name

       |------------------------------------------------------------------+
       | OVS_BridgeBuilder_VERSION = v00.81.a
       |------------------------------------------------------------------+
