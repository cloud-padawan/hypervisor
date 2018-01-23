# hypervisor
Hypervisor installer and management tools

## To Install:

   `$ sudo curl -L https://github.com/containercraft/hypervisor/blob/master/install.sh | bash`
   `$ sudo ccio-install`

    syntax:
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
