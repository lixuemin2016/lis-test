#!/bin/bash

########################################################################
#
# Linux on Hyper-V and Azure Test Code, ver. 1.0.0
# Copyright (c) Microsoft Corporation
#
# All rights reserved.
# Licensed under the Apache License, Version 2.0 (the ""License"");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
#
# THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS
# OF ANY KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
# ANY IMPLIED WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR
# PURPOSE, MERCHANTABLITY OR NON-INFRINGEMENT.
#
# See the Apache Version 2.0 License for specific language governing
# permissions and limitations under the License.
#
########################################################################

########################################################################
#
# FC_disks.sh
#
# Description:
# This script will identify the number of total disks detected inside the guest VM.
# It will then format the FC disks, perform read/write checks and check
# Call Trace.
#
########################################################################

dos2unix utils.sh
. utils.sh || {
    echo "Error: unable to source utils.sh!"
    exit 1
}

#
# Source constants file and initialize most common variables
#
UtilsInit

sdCount=0
#
# Compute the number of sd* drives on the system.
#
for drive in /dev/sd*[^0-9]
do
    sdCount=$((sdCount+1))
done

#
# Subtract the boot disk from the sdCount
#
sdCount=$((sdCount-1))
echo "/dev/sd* disk count = $sdCount"

if [ $sdCount -lt 1 ]; then
    echo " disk count from /dev/sd* ($sdCount) returns only the boot disk"
    SetTestStateAborted
    exit 1
fi

# exclude specific disks from being multipathed
if [ -e /etc/multipath.conf ]; then
    rm /etc/multipath.conf
fi
echo -e "blacklist {\n\tdevnode \"^sd[a-z]\"\n}" > /etc/multipath.conf
service multipathd restart
sleep 5

osdisk=$(get_OSdisk)
UpdateSummary "OS disk:$osdisk"

#
# For each drive, run fdisk -l and extract the drive size in bytes
#
for driveName in /dev/sd*[^0-9];
do
    #
    # Skip os disk
    #
    if [ ${driveName} = "/dev/${osdisk}" ]; then
        continue
    fi
    fdisk -l $driveName > fdisk.dat 2> /dev/null

    # Delete the existing partition
    for (( c=1 ; c<=count; count--))
        do
            (echo d; echo $c ; echo ; echo w) |  fdisk $driveName
        done

    (echo n;echo p;echo 1;echo;echo;echo w) | fdisk $driveName
    if [ "$?" = "0" ]; then
        sleep 5
        mkfs.ext4 -F ${driveName}1
        if [ "$?" = "0" ]; then
            LogMsg "mkfs.ext4 ${driveName}1 successful..."
            mount   ${driveName}1 /mnt
                    if [ "$?" = "0" ]; then
                    LogMsg "Drive mounted successfully..."
                    mkdir /mnt/Example
                    dd if=/dev/zero of=/mnt/Example/data bs=10M count=30
                    if [ "$?" = "0" ]; then
                        LogMsg "Successful created directory /mnt/Example"
                        LogMsg "Listing directory: ls /mnt/Example"
                        ls /mnt/Example
                        umount /mnt
                        if [ "$?" = "0" ]; then
                            LogMsg "Drive unmounted successfully..."
                     fi
                        LogMsg "Disk test completed for ${driveName}1"
                        UpdateSummary "Disk test is completed for ${driveName}1"
                    else
                        LogMsg "Error in creating directory /mnt/Example!"
                        UpdateSummary "Error in creating directory /mnt/Example!"
                        SetTestStateFailed
                        exit 60
                    fi
                else
                    LogMsg "Error in mounting drive!"
                    UpdateSummary "Drive mount : Failed!"
                    SetTestStateFailed
                    exit 70
                fi
        else
            LogMsg "Error in creating file-system!"
            UpdateSummary "Creating file-system has failed!"
            SetTestStateFailed
            exit 80
        fi
    else
        LogMsg "Error in executing fdisk  ${driveName}1"
        UpdateSummary "Error in executing fdisk  ${driveName}1"
        SetTestStateFailed
        exit 90
    fi
done

# Check for Call Trace
CheckCallTracesWithDelay 20
SetTestStateCompleted
exit 0
