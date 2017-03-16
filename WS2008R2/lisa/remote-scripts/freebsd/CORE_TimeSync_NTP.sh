#!/bin/bash
########################################################################
#
# Synopsis
#     This tests Network Time Protocol sync.
#
# Description
#     This script was created to automate the testing of a FreeBSD
#     Integration services. It enables Network Time Protocol and 
#     checks if the time is in sync.
#    
#     
#     A typical xml entry looks like this:
# 
#         <test>
#             <testName>TimeSyncNTP</testName>
#             <testScript>CORE_TimeSync_NTP.sh</testScript>
#             <files>remote-scripts/freebsd/CORE_TimeSync_NTP.sh</files>
#             <timeout>300</timeout>
#             <onError>Continue</onError>
#         </test>
#
########################################################################


ICA_TESTRUNNING="TestRunning"      # The test is running
ICA_TESTCOMPLETED="TestCompleted"  # The test completed successfully
ICA_TESTABORTED="TestAborted"      # Error during setup of test
ICA_TESTFAILED="TestFailed"        # Error during execution of test

maxdelay=5000   # max offset in milliseconds.

CONSTANTS_FILE="constants.sh"

UpdateTestState()
{
    echo $1 > ~/state.txt
}

#######################################################################
# Adds a timestamp to the log file
#######################################################################
function LogMsg() {
    echo $(date "+%a %b %d %T %Y") : ${1}
}

####################################################################### 
# 
# Main script body 
# 
#######################################################################

cd ~

# Create the state.txt file so LISA knows we are running
UpdateTestState $ICA_TESTRUNNING

# Cleanup any old summary.log files
if [ -e ~/summary.log ]; then
    rm -rf ~/summary.log
fi

LogMsg "This script tests NTP time syncronization"
#
# Create the state.txt file so ICA knows we are running
#
echo "Updating test case state to running"
UpdateTestState $ICA_TESTRUNNING


echo "Covers CORE-04" > ~/summary.log

#
# Source the constants.sh file to pickup definitions from
# the ICA automation
#
if [ -e ./${CONSTANTS_FILE} ]; then
    source ${CONSTANTS_FILE}
else
    echo "Info: no ${CONSTANTS_FILE} found"
    UpdateTestState $ICA_TESTABORTED
    exit 5
fi

grep "^[ ]*ntpd_enable"  /etc/rc.conf
if [ $? -ne 0 ]; then
    cat <<EOF>> /etc/rc.conf 
ntpd_enable="YES"
EOF
sh /etc/rc
fi

sleep 2

# Try to restart NTP. If it fails we try to install it.
service ntpd restart
if [ $? -ne 0 ]; then
	service ntpd onerestart
	if [ $? -ne 0 ]; then
		echo "NTPD not installed. Trying to install ..."
		echo "y" | pkg install ntp
		if [[ $? -ne 0 ]] ; then
				LogMsg "ERROR: Unable to install ntpd. Aborting"
				UpdateTestState $ICA_TESTABORTED
				exit 10
		fi
		rehash
		ntpdate pool.ntp.org
		if [[ $? -ne 0 ]] ; then
			LogMsg "ERROR: Unable to set ntpdate. Aborting"
			UpdateTestState $ICA_TESTABORTED
			exit 10
		fi
		service ntpd start
		if [[ $? -ne 0 ]] ; then
			LogMsg "ERROR: Unable to start ntpd. Aborting"
			UpdateTestState $ICA_TESTABORTED
			exit 10
		fi
		echo "NTPD installed succesfully!"
	fi
fi

# We wait 30 seconds for the ntp server to sync
sleep 30

# Variables for while loop. stopTest is the time until the test will run
isOver=false
secondsToRun=600
stopTest=$(( $(date +%s) + secondsToRun )) 

while [ $isOver == false ]; do
    offsets=$(ntpq -nc peers | tail -n +3 | cut -c 62-66 | tr -d '-')
    for offset in ${offsets}; do
        if [ ${offset:-0} -ge ${maxdelay:-3000} ]; then
            isOver=false
            LogMsg "Offset is $offset and it's bigger than $maxdelay in milliseconds."
        fi  
        isOver=true
        LogMsg "NTP offset is $offset milliseconds."
    done

    # The loop will run for 10 mins if delay doesn't match the requirements
    if  [[ $(date +%s) -gt $stopTest ]]; then
        isOver=true
        LogMsg "ERROR: NTP Time out of sync. Test Failed"
        UpdateTestState $ICA_TESTFAILED
        exit 1
    fi

    sleep 5    
done

# If we reached this point, time is synced.
LogMsg "SUCCESS: NTP time synced!"
UpdateTestState $ICA_TESTCOMPLETED
exit 0


