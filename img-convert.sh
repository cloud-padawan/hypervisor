#!/bin/bash

# libvirt guest disk image file squashifier
# 1. Convert [raw|qcow2] disk image files to compressed qcow2 images
# 2. Backup or discard original disk images
# 3. Replace disk images with new compressed qcow2 image
#
# Usage:
#        img-convert
# TODO:
#   Add Features:
#        img-convert [filename]
#        img-convert [directory] --all
#        Blacklist-Array
#        img-convert --blacklist [img-name]
#        img-convert --blacklist-dom [libvirt guest name]
#
# WARNING! -- 1. For safety, Guests are powered off during image conversion 
#             2. Converts all disks found to qcow2 type unless included in
#             the blacklist below.
#             This will result in windows guests being unable to boot until
#             the image is restored back to raw format unless the virtio
#             baloon driver has been installed.

# Disk image type switches 
# Options: [true|false]
convert_RAW="true"
convert_QCOW2="false"

# Compress switch: Enables qemu-img convert "-c" flag
# Options: [true|false]
compress_SWITCH="true" 

## IMPORTANT!
## This flag sets the discard/backup flag for handling original disk images
## If set to "true" original disk image files will be immidiately discarded
## after conversion
## If set to "false", disk image files will be moved to the backup location
## specified by "discard_DIR" below. Please monitor disk usage in this scenario.
## Options: [true|false]
discard_OLD="true"

# This flag sets the destination for discarded image file originals
# Image file originals are moved to this location 
# if $discard_OLD is set to "false"
discard_DIR=/tmp/libvirt/images/

# Enable or disable compression during qcow2 conversion to save additional space
# Notice: takes longer and has slight impact on performance
[[ $compress_SWITCH ]] && compress_IMG="-c" || compress_IMG=""
#if [[ $compress_SWITCH = "true" ]]; then
#    compress_IMG="-c"
#elif [[ $compress_SWITCH = "false" ]]; then
#    compress_IMG=""
#fi

#################################################################################
# Replace original disk image with new qcow2 format
image_replace () {
    echo "Replacing disk image with compressed image"
    if [[ $discard_OLD = true ]]; then
        echo "Discarding original $disk"
        rm $disk
        mv $disk.tmp $disk
    elif [[ $discard_OLD = true ]]; then
        echo "Backing up original in $discard_DIR"
        mkdir -p $discard_DIR 
        mv $disk $discard_DIR
        mv $disk.tmp $disk
    fi
}

#################################################################################
# Perform disk image file conversion
image_convert () {
    echo " Converting $disk"
		qemu-img convert \
            -p $img_INPUT_TYPE \
            -O qcow2 $compress_IMG $disk $disk.$temp_STAMP
        echo "qcow2 conversion complete for $disk"
}

# Generate unique hash for temp file naming
gen_hash () {
    temp_STAMP=$(date -u +"%Y-%m-%dT%H:%M:%S.%N+00:00" | md5sum)
}
#################################################################################
# Find disk images
image_find () {
virsh_LIST_DOM=$(virsh list --name --all)

    # Search for domains & proceed on each disk found
    for dom in $virsh_LIST_DOM; do

        # Check if guest is powered off
        # Skip if not in "shut off" state
        dom_STATE=$(virsh domstate $dom | grep "shut off")
        if [[ $dom_STATE = "shut off" ]]; then
            echo "Power Check: $dom"
            echo "      State: shut off"
            echo "Continuing ... "
            dom_POWER_CHECK="SAFE"
        elif [[ $dom_STATE != "shut off" ]]; then
            echo "Power Check: $dom"
            echo "ERROR! >> Guest is not in state "shut off""
            dom_POWER_CHECK="WARN"
        fi

        # Find domain disk images
        if [[ $dom_POWER_CHECK = "SAFE" ]]; then
        echo ">> Inspecting disk images on $dom"
            virsh_DOM_DISK_LIST=$(virsh domblklist --details $dom \
                                 | awk '/file/ {print $4}')

            # Check disk image type & perform convert/replace
            for disk in $virsh_DOM_DISK_LIST; do
                image_TYPE_CHECK=$(qemu-img info $disk \
                                  | awk '/format:/ {print $3}' )
                if [[ $image_TYPE_CHECK = "raw" ]] && \
                    [[ $convert_RAW = "true" ]]; then
                    echo ">>   Found RAW disk image file $disk"
                    echo ">>   Converting to qcow2 format..."
                    img_INPUT_TYPE="-f raw"
                    gen_hash
                    image_convert
                    image_replace
                elif [[ $image_TYPE_CHECK = "qcow2" ]] && \
                    [[ $convert_QCOW2 = "true" ]]; then
                    echo ">>   Found QCOW2 disk image file $disk"
                    echo ">>   Compressing with qcow2 format..."
                    img_INPUT_TYPE=""
                    gen_hash
                    image_convert
                    image_replace
                fi
            done
        elif [[ $dom_POWER_CHECK = "WARN" ]]; then
            echo "Skipping $dom"
            echo "Please power off domain before running on this guest again"
        fi

    done
}

image_find
