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

ICA_TESTRUNNING="TestRunning"
ICA_TESTCOMPLETED="TestCompleted"
ICA_TESTABORTED="TestAborted"

#######################################################################
# Adds a timestamp to the log file
#######################################################################
LogMsg()
{
    echo `date "+%a %b %d %T %Y"` : ${1}
}

#######################################################################
# Updates the summary.log file
#######################################################################
UpdateSummary()
{
    echo $1 >> ~/summary.log
}

#######################################################################
# Keeps track of the state of the test
#######################################################################
UpdateTestState()
{
    echo $1 > ~/state.txt
}

####################################################################### 
# 
# Main script body 
# 
#######################################################################

# Create the state.txt file so ICA knows we are running
UpdateTestState $ICA_TESTRUNNING

# Cleanup any old summary.log files
if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi

# Make sure the constants.sh file exists
if [ ! -e ./constants.sh ];
then
    LogMsg "Cannot find constants.sh file."
    UpdateTestState $ICA_TESTABORTED
    exit 1
fi

# Source the constants file
if [ -e $HOME/constants.sh ]; then
    . $HOME/constants.sh
else
    LogMsg "ERROR: Unable to source the constants file."
    exit 1
fi

if [ ! -e ./freezefs ];
then
	LogMsg "Cannot find freezefs file"
	UpdateTestState $ICA_TESTABORTED
    exit 1
fi

# Check if Variable in Const file is present or not
if [ ! ${FILESYS} ]; then
    LogMsg "No FILESYS variable in constants.sh"
    UpdateTestState "TestAborted"
    exit 1
fi

# make partition with gpart
for i in `camcontrol devlist | awk -F \( '{print $2}' | grep "da[0-9]*"|awk -F , '{print $1}'`
do
     if [ $i == "da0" ]
     then
        continue
     fi

     LogMsg "check partition on $i"
     gpart show -p $i > /dev/null
     if [ $? -eq 0 ]
     then
       LogMsg "partition is existed!"
       a=`gpart show -p $i|grep $i|wc -l`
       if [ $a -eq 2 ]
       then
          LogMsg "delete the existing partition"
          gpart delete -i 1 da1
          gpart destroy da1
       fi
     fi
    LogMsg "partition is not existed, and we create it"
    gpart create -s GPT /dev/$i
    gpart add -t ${FILESYS} /dev/$i
done

sleep 1

# mount the partition
  for i in `camcontrol devlist | awk -F \( '{print $2}' | grep "da[0-9]*"|awk -F , '{print $1}'`
  do
    if [ $i == "da0" ]
    then
       continue
    fi

    for j in `ls /dev/da* | grep "/dev/$i"`
    do
		if [ $j != "/dev/$i" ]
		then
			LogMsg "newfs $j"
			newfs $j
			LogMsg "Try to mount $j"
			mnt_name=`echo $j | cut -c 6-`
			if [ ! -e /mnt/$mnt_name ]
			then
				mkdir /mnt/$mnt_name
			fi
			mount | grep "/mnt/$mnt_name"
			if [ $? -eq 0 ]
			then
				nohup sleep 1; ./freezefs -F /mnt/$mnt_name -d ${FREEZEDUR} &
				LogMsg " Partition disk $j is already freezed: Success"
				UpdateSummary " Partition disk $j is already freezed: Success"
				continue
			fi
			mount $j /mnt/$mnt_name
			if [ $? -eq 0 ]
			then
				nohup sleep 1; ./freezefs -F /mnt/$mnt_name -d ${FREEZEDUR} &
				LogMsg " Partitioning disk $j is already freezed: Success"
				UpdateSummary " Partitioning disk $j is already freezed: Success"
			else
				UpdateTestState "TestAborted"
				LogMsg " Partitioning disk $j freezed: Failed"
				UpdateSummary " Partitioning disk $j freezed: Failed"
				exit 1
			fi
		fi
    done
  done

UpdateTestState $ICA_TESTCOMPLETED

exit 0
