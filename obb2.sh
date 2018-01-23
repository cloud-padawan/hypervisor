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
# option_INSTALL_CCIO_ENV
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
