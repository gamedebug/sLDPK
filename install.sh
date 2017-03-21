#!/bin/bash
#
###############################################################
#
#       Released under GPL v2.
#       Author : Josh Pellerin
#
# VERSION: 1.9
# February 2, 2017
# 
# THIS IS A SAMPLE. VENDORS MAY CUSTOMIZE THIS SCRIPT IF THEY
# WISH OR USE THIS SCRIPT TO CALL THEIR OWN SCRIPT. IT IS THEIR
# RESPONSIBILITY TO EXPLAIN EXTRA SCRIPT FILES TO THE
# CUSTOMERS VIA A README FILE
#
# 'install.sh' is used to install the appropriate driver rpm to
# the system that's running. It does this by discovering the OS
# and current running kernel and using those values to select
# the correct RPM from the install package. 
#
###############################################################


# The directory this script is being run from
cwd=$(pwd)

# Log file
INSTALL_LOG_DIR="/var/log/Lenovo_Support"
INSTALL_LOG="$INSTALL_LOG_DIR/fixInstall.log"
DEBUG_LOG="$INSTALL_LOG_DIR/debugFixInstall.log"

#exec > >(tee -a $INSTALL_LOG) 2>&1

#Available error codes: 173 - 191
SUCCESS=0
FAIL=1
INVALID_OS=173
NO_RPM_FOUND=174
ALREADY_INSTALLED=175
RPM_INSTALL_FAILED=176

#Array to store error codes/messages
ERRORS=()
#ERRORS+=("Error $INVALID_OS : Example error")
#
#

# Directory within fix package where rpms are stored
RPMS_DIR="$cwd/RPMS"

# List of folders containing rpms which are to be installed
RPMS_TO_INSTALL=()

# Keep this variable, it 
INSTALL_OPTIONS=("$@")      #$@ grabs all parameters used when script was executed
echo $@

# RPM_FLAG will contain the parameters for the 'rpm' command
RPM_FLAG="${INSTALL_OPTIONS[@]}"

#####################################
#	...setup work done
#
#	functions begin below...
#####################################

createLogFile()
{
cat << EOF
#
######################################
#
# fixInstall.log
#
#
######################################
Logged at : `date`
`uname -a`
`rpm -qf /etc/issue`
EOF
}

get_current_os()
{
	echo "-------------- get current os ------------------"
	#######################################################
	
	currOS=`rpm -qf /etc/issue | grep sles`
	if [ ! -z $currOS ] ; then
		#current OS is SLES. Find out which version
		osVersion=(`cat /etc/os-release | grep 'VERSION' | egrep -o '[0-9]{1,2}'`)
		if [ ! -z $osVersion ] ; then
			CURRENT_OS="SLES${osVersion[0]}"
			echo $CURRENT_OS
			return 0
		fi
	else
		currOS=`cat /etc/redhat-release | grep 'Red Hat' | egrep -o '[0-9]\.?[0-9]*' | cut -c1`
		if [ ! -z $currOS ] ; then
			CURRENT_OS="RHEL${currOS}"
			echo $CURRENT_OS
			return 0
		else
			echo "Error : Unsupported OS detected"
			ERRORS+=("Error $INVALID_OS - Unsupported OS detected")
			exit $INVALID_OS
		fi
	fi
}

rpms_exist_for_curr_kernel()
{
	echo "-------------- rpms_exist_for_curr_kernel ------------------"
	#######################################################

	echo "Searching for $CURRENT_OS rpm"
	rpm_folders=($(ls $RPMS_DIR))
	if [ ! -z $rpm_folders ]; then
		#curr_kernel=$(uname -r | sed s/[a-zA-Z].*//g | sed s/[\.-]$//g)
		os_release_info=`rpm -qf /etc/issue`
		# Compare os_release_info to list of rpm_folders
		# to find a match
		for folder in "${rpm_folders[@]}"; do
			# if $os_release_info contains $rpm_folders string ; then install that
			if [[ "$os_release_info" == *"$folder"* ]]; then
				echo "Attempting to install RPM from directory '$RPMS_DIR/$folder'..."
				RPMS_TO_INSTALL+=("$RPMS_DIR/$folder")
				#return 0
			fi
		done
		if [ ! -z $RPMS_TO_INSTALL ]; then
			return 0
		fi
		echo "Error : Fix package does not contain RPMs for this version of the OS: '$os_release_info'"
		ERRORS+=("Error $NO_RPM_FOUND - Fix package does not contain RPMs for this version of the OS: '$os_release_info'")
		exit $NO_RPM_FOUND
	else
		echo "Error : No RPMs exist for OS $CURRENT_OS!"
		ERRORS+=("Error $NO_RPM_FOUND - No RPMs exist for OS $CURRENT_OS!")
		exit $NO_RPM_FOUND	
	fi
}

install_rpm()
{
	echo "-------------- install_rpm ------------------"
	#######################################################
	
	echo "Attempting to install rpm..."
	rpms=(`ls $1`)
	if [ ${#rpms[@]} -lt 1 ]; then
		echo "Error : No RPMs found in $1!"
		ERRORS+=("Error $NO_RPM_FOUND - No RPMs found in $1!")
		exit $NO_RPM_FOUND
	else
		#choose right one by comparing flavor
		sys_flavor=$(uname -r | egrep -o "[a-zA-Z]*$")
		sys_arch=(`echo $MACHTYPE | egrep -o '[^-]*'`)
		install_success="false"
		for rpm in ${rpms[@]}; do
			if [[ "$rpm" == *"$sys_flavor"* ]]; then
				if [[ "$rpm" == *"${sys_arch[0]}"* ]]; then
					echo "Installing $rpm..."
					rpm -Uvh $RPM_FLAG $1/$rpm
					# check return code; add special error code for rpm install fail
					if [ $? -ne 0 ]; then
						echo "rpm command failed to install the driver"
						ERRORS+=("Error $RPM_INSTALL_FAILED - rpm command failed to install the driver")
						echo "$(md5sum $1/$rpm)"
						echo "$(rpm -qlp $1/$rpm)"
						return $?            # $? is the return code value from rpm -ivh....don't overwrite this
					fi
					install_success="true"
				fi
			fi
		done
		if [ "$install_success" == "true" ]; then
			return 0
		fi
		echo "No RPMs found for system flavor $sys_flavor!"
		ERRORS+=("Error $NO_RPM_FOUND - No RPMs found for system flavor $sys_flavor!")
		exit $NO_RPM_FOUND
	fi
}

if [ $(id -u) -ne 0 ]; then
	echo "Must have 'root' privileges to invoke this script"
	exit 1
fi

if [ ! -f $INSTALL_LOG ]; then
	mkdir -p $INSTALL_LOG_DIR
	createLogFile > $INSTALL_LOG
	createLogFile > $DEBUG_LOG
else
	createLogFile >> $INSTALL_LOG
	createLogFile >> $DEBUG_LOG
fi

exec 2>$DEBUG_LOG; set -x;
exec > >(tee -a $INSTALL_LOG)

#
# The work begins here
#
get_current_os # >> $INSTALL_LOG 2>&1

if [ $? -eq 0 ]; then
	rpms_exist_for_curr_kernel # >> $INSTALL_LOG 2>&1
	if [ $? -eq 0 ]; then
		#Check if already installed
		# then RPM_DIR points to rpm directory
		for rpm_dir in ${RPMS_TO_INSTALL[@]}; do
			install_rpm $rpm_dir  # >> $INSTALL_LOG 2>&1
			
		done
	fi		
else
	echo "Unable to determine running OS. Ensure that Rhel or Sles is being used" # >> $INSTALL_LOG 2>&1
	ERRORS+=("Error $INVALID_OS - Unsupported OS detected")
fi

##################################################

# exit
if [ ${#ERRORS[@]} -gt 0 ]; then
	echo "${ERRORS[@]}"
	exit $FAIL
fi
exit $SUCCESS
