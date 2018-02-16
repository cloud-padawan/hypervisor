CCIO Hypervisor installer & OVS BridgeBuilder
==============================================

Hypervisor configuration and management tools

#### To Install:
  Install full hypervisor setup and CCIO-Utils

    sudo curl -L https://goo.gl/YPSs6k | bash

    sudo ccio-install                                                                                

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

#  Usage and Syntax:
  OpenVSwitch Bridge Builder

  syntax: command [option] [value]

Options:

    --                -h    Print the basic help menu
    --help                  Print the extended help menu
    --show-health     -H    Check OVS|LXD|Libvirtd Service Status
    --show-config     -s    Show current networks configured locally
    --ovs-del-orphans       Purge orphaned OVS ports
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


       LXD:
        \_______       
                \_Launch a container with the lxd profile flag to attach
                |    Example:                                               
                |      $ lxc launch ubuntu: test-container -p $network

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
                |          OVS Bridge Name:  mybridge
                |        New OVS Port-Name:  eth0
                |            LXD Container:  mycontainer < (optional)
                |
                |      $ obb --add-port mybridge eth0  
                |      $ obb --add-port mybridge eth0 mycontainer
                |
