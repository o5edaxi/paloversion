#!/bin/bash

#####################################################################

# Sets the password used during password change prompts from PAN-OS #

BACKUP_PASSWORD="Admin123"

#####################################################################

# The script will stop if more than these reboots happen in a run   #

PATH_MAX=20

#####################################################################

# Sets the maximum number of firewalls in a run                     #

BATCH_MAX=10

#####################################################################

# Palo Alto OUI list for batch mode

OUI_LIST=(00:1B:17 00:86:9C 08:03:42 08:30:6B 08:66:1F 24:0B:0A 34:E5:EC 58:49:3B 78:6D:94 7C:89:C1 84:D4:12 94:56:41 B4:0C:25 C4:24:56 D4:1D:71 D4:9C:F4 D4:F4:BE E4:A7:49 E8:98:6D EC:68:81 00:90:0B 8C:36:7A 5C:58:E6 64:7C:E8 FC:10:1A 60:15:2B 3C:FA:30 F4:D5:8A 7C:C0:25 58:76:9C 04:47:2A A4:27:A5 CC:38:D0 7C:C7:90 C8:29:C8 DC:0E:96)

#####################################################################

# Sets the maximum run time in seconds for batch mode               #

TIME_BATCH_MAX=18000

#####################################################################

# Separator for csv files                                           #

SEP=","

#####################################################################

# Regex to capture version number in PanOS file names               #

EASY_REGEX='^PanOS[^-]*-(.+)$'

#####################################################################

CURL_CA_IGNORE="-k"

FACTORY_USERNAME="admin"

FACTORY_PASSWORD="admin"

shopt -s expand_aliases

alias beep="{ echo -ne '\007'; }"
alias beepbeep="{ echo -ne '\007'; sleep 1; echo -ne '\007'; sleep 1; echo -ne '\007'; }"
alias endbeep="{ echo -ne '\007'; sleep 1; echo -ne '\007'; sleep 1; echo -ne '\007'; echo \"---FAILED---\"; exit 1; }"

# Kills child batches on CTRL+C

trap "kill 0" SIGINT

usage="The following options are supported:

	-h				Displays instructions
	-d				Dry run
	-s				Shutdown after completion
	-l				Lazy mode
	-e				Easy mode
	-x				Enable debug
	-f				Batch mode
	-k				Install licenses
	-t \"STRING\"			Install Threats
	-a \"STRING\"			Install Antivirus
	-c				Upload & commit custom config
	-p \"STRING\"			Set Panorama Authkey
	-z \"STRING\"			Non-interactive mode
	-m				Disable MAC Filter for batch mode
	-q				Validate firewall certificates
	-i				Ignore autocommit and process errors

Usage: paloversion.sh [ -hdsxkcpmiq ] [ -e | -lzf ] [ -t threat_file ] [ -a antivirus_file ] [ -p panorama_authkey ] [ -z fw_address user password files_folder target_version [ network_interface ] ]

"

help="

This script automatically upgrades a Palo Alto firewall. Please add the firmware files in the preferred folder and edit the .csv for the platform accordingly.
To avoid the need for the .csv files, manual upgrade paths are also supported (see -e below).

Usage: paloversion.sh [ -hdsxkcpmiq ] [ -e | -lzf ] [ -t threat_file ] [ -a antivirus_file ] [ -p panorama_authkey ] [ -z fw_address user password files_folder target_version [ network_interface ] ]

Options:

	-h	help

	Displays these instructions

	-d	dry-run

	Outputs the operations without performing any action on the firewall

	-s	shutdown

	Shuts down the firewall after performing the upgrades
	
	-l	lazy
	
	Skips installing patches during upgrades (ie. skip 9.0.10 when going 9.0.0 -> 9.1.0)
	
	-e	easy
	
	Allows the user to list the upgrade steps and files manually, and doesn't check file hashes
	
	-x	debug
	
	Bash debug mode
	
	-f	factory-batch mode
	
	This mode will search for one or more firewalls on the same L2 broadcast domain as the host, and automatically upgrade them by using their IPv6 link-local address
	
	-k	licenses
	
	Install license files before starting upgrade
	
	-t	threats
	
	Install App&Threats packages after upgrade (requires -a flag)
	
	-a	antivirus
	
	Install Antivirus packages after upgrade (requires -t flag)
	
	-c	configuration
	
	Upload and commit a configuration after upgrade
	
	-p	panorama authkey
	
	Set a Panorama authkey after upgrade (10.1 and above)
	
	-z	non-interactive mode
	
	Requires all input as arguments to the script, e.g.:
	paloversion.sh -p \"2:12345AUTHKEY\" -t \"panupv2-all-contents-1234-5678\" -a \"panup-all-antivirus-1234-5678\"  -lzc \"192.0.2.1\" \"admin\" \"password\" \"/home/PA/Firmware/\" \"8.1.15-h3\"
	Arguments are mandatory according to the features selected.
	
	-m disable batch mode MAC filter
	
	Disable checks for valid Palo Alto MAC addresses, upgrades all firewalls on broadcast domain (requires -f)
	
	-q validate firewall certificates
	
	Enforces trusted CAs for every HTTPS connection
	
	-i ignore autocommit and process errors
	
	Autocommit/Process errors during upgrades and downgrades will not stop the activity

Easy mode:

	You will be prompted to enter the file names that will be installed in order, separated by a space. Enter a capital \"R\" to indicate a reboot step, e.g:
	PanOS_800-9.1.9 R PanOS_800-10.0.0 R PanOS_800-10.1.0 PanOS_800-10.1.4 R
	All filenames must be original as downloaded from the support website. You will also be prompted for an App package to bypass the need for the content.csv file.
	The files will be recursively searched for in the selected folder path.

For licenses:

	License files are searched for recursively in the general firmware folder, and must be in the format $SERIAL_NUMBER-$LICENSE.key as downloaded from the CSP, e.g. \"01234567890-support.key\"
	Run the script with a target version identical to the current version to quickly install licenses without upgrading.
	Supports multiple firewalls in batch mode by placing one or more license files for each serial number.

For Threat and Antivirus:

	App&Threat and Anti-Virus packages are searched for recursively in the general firmware folder with the name specified at run time.
	A content file must be set even if the content.csv file already specifies App&Threat packages.
	Run the script with a target version identical to the current version to quickly install packages without upgrading.
	Supports multiple firewalls in batch mode.

For configuration files:

	Configuration files are searched for recursively in the general firmware folder, and must be in the format $SERIAL_NUMBER-config.xml, e.g. \"01234567890-config.xml\"
	Run the script with a target version identical to the current version to quickly install a config file without upgrading.
	Supports multiple firewalls in batch mode by placing a different config file for each serial number (similarly to firewall bootstrapping).
	The script will log a diff between the config file and the final running config to double check the results.
	
For Panorama authkeys:

	The authkey is inserted at run time, and when using batch mode must work for all firewalls in the batch.
	Please note that 88 character authkeys are bugged for firewalls <10.1.3, so it is recommended to target a more recent version if onboarding to Panorama.
	Run the script with a target version identical to the current version to quickly set authkeys without upgrading.
	The script will exit if the firewall refuses the authkey.

CSV files must be named after the platform family (e.g. \"800.csv\", this is visible in the output of \"show system info\" on the firewall) and have the following format:

csv separator: \",\" or \";\", according to the SEP variable

Column 1: An ascending integer indicating the order of software releases (higher is most recent)

Column 2: Name of software release (e.g. 8.1.5)

Column 3: Name of major train (e.g. 8.1)

Column 4: Release type (Feature or Maintenance)

Column 5: Image file name on disk

Column 6: SHA256 Checksum

Example:

1,8.1.5,8.1,Maintenance,PanOS_800-8.1.5,shashashashashashashashashashashashashashasha
2,8.1.6,8.1,Maintenance,PanOS_800-8.1.6,shashashashashashashashashashashashashashasha
3,8.1.7,8.1,Maintenance,PanOS_800-8.1.7,shashashashashashashashashashashashashashasha

The csv file named \"content.csv\" must contain the minimum content version for each major release, and have the following format:

csv separator: \",\" or \";\", according to the SEP variable

Column 1: Major version (e.g. 8.1)

Column 2: Minimum content version without the dash (e.g. 769, this is the first number in the content package name) for the corresponding major

Column 3: Name of the file that will be installed if the firewall does not meet the minimum content version requirement

Column 4: SHA256 Checksum of the content package to be installed

Example:

8.1,769,panupv2_all_apps_769,shashashashashashashashashashashashashashasha

	"

while getopts 'hdslexfzmkt:a:cp:qi' option; do
  case "$option" in
    h) echo "$help"
       exit
       ;;
	d) DRY_RUN=1
       ;;
	s) SHUTDOWN=1
       ;;
	l) LAZY=1
	   ;;
	e) EASY=1
	   ;;
	x) DEBUG=1
	   ;;
	f) BATCH_MODE=1
	   ;;
	k) UPLOAD_LICENSES=1
	   ;;
	t) INSTALL_THREATS=1; THREAT_FILENAME="$OPTARG"
	   ;;
	a) INSTALL_THREATS=1; ANTIVIRUS_FILENAME="$OPTARG"
	   ;;
	c) INSTALL_CONFIG=1
	   ;;
	p) SET_PRA_AUTHKEY=1; PANORAMA_AUTHKEY="$OPTARG"
	   ;;
	z) NON_INTERACTIVE=1
	   ;;
	m) DISABLE_OUI=1
	   ;;
	q) unset CURL_CA_IGNORE
	   ;;
	i) IGNORE_ERRORS=1
	   ;;
   \?) printf "illegal option: -%s\n" "$OPTARG" >&2
       echo "$usage" >&2
       exit 1
       ;;
  esac
done
shift $((OPTIND - 1))

if (( INSTALL_THREATS == 1 )); then
	if [[ "$ANTIVIRUS_FILENAME" == "" ]]; then
		echo "The -t option requires a filename and the -a option to be set. Exiting..."
		endbeep
	fi
	if [[ "$THREAT_FILENAME" == "" ]]; then
		echo "The -a option requires a filename and the -t option to be set. Exiting..."
		endbeep
	fi
fi

##########################################################################################################################################################################################
# Checks if the requested version is found in the csv files
##########################################################################################################################################################################################

versionPresent(){

PRESENT=0

while IFS="$SEP" read -r Order Name Major Type File Checksum
do
	if [[ "$Name" == "$2" ]]; then
		PRESENT=1
		break
	else
		continue
	fi
done < "$1"

if (( PRESENT == 0 )); then
	date +"%T In function versionPresent(), incorrect input or unsupported software release. Input: $1 $2" >&2
	return 1
fi
}

##########################################################################################################################################################################################
# Returns the on-disk file name for the requested version name
##########################################################################################################################################################################################

fileName(){

PRESENT=0

while IFS="$SEP" read -r Order Name Major Type File Checksum
do
	if [[ "$Name" == "$2" ]]; then
		echo "$File"
		PRESENT=1
		break
	else
		continue
	fi
done < "$1"

if (( PRESENT == 0 )); then
	date +"%T In function fileName(), incorrect input or unsupported software release. Input: $1 $2" >&2
	return 1
fi

}

##########################################################################################################################################################################################
# Returns the official checksum for the requested file name
##########################################################################################################################################################################################

fileChecksum(){

local PRESENT_SOFTWARE
PRESENT_SOFTWARE=0

while IFS="$SEP" read -r Order Name Major Type File Checksum
do
	if [[ "$File" == "$2" ]]; then
		echo "$Checksum"
		PRESENT_SOFTWARE=1
		break
	else
		continue
	fi
done < "$1"

if (( PRESENT_SOFTWARE == 0 )); then
	date +"%T In function fileChecksum(), incorrect input or unsupported software release. Input: $1 $2" >&2
	return 1
fi

}

##########################################################################################################################################################################################
# Returns the official checksum for the requested content package
##########################################################################################################################################################################################

fileChecksumContent(){

local PRESENT_CONTENT
PRESENT_CONTENT=0

while IFS="$SEP" read -r Major MinContent File Checksum
do
	if [[ "$File" == "$2" ]]; then
		echo "$Checksum"
		PRESENT_CONTENT=1
		break
	else
		continue
	fi
done < "$1"

if (( PRESENT_CONTENT == 0 )); then
	date +"%T In function fileChecksumContent(), incorrect input or unsupported content release. Input: $1 $2" >&2
	return 1
fi

}

##########################################################################################################################################################################################
# Checks if an upgrade or a downgrade is needed
##########################################################################################################################################################################################

majorCompare(){

while IFS="$SEP" read -r Order Name Major Type File Checksum
do
	if [[ "$Name" == "$3" ]]; then
		MAJOR_REQ="$Major"
		ORDER_REQ="$Order"
		continue
	elif [[ "$Name" == "$2" ]]; then
		MAJOR_CUR="$Major"
		ORDER_CUR="$Order"
		continue
	else
		continue
	fi
done < "$1"

if [[ "$MAJOR_CUR" == "$MAJOR_REQ" ]]; then
	echo "Patch"
elif [[ "$MAJOR_CUR" != "$MAJOR_REQ" ]]; then
	if (( ORDER_REQ > ORDER_CUR )); then
		echo "Upgrade"
	elif (( ORDER_REQ < ORDER_CUR )); then
		echo "Downgrade"
	else
		echo "Error"
		return 1
	fi
else
	echo "Error"
	return 1
fi

}

##########################################################################################################################################################################################
# Returns what the next feature release is
##########################################################################################################################################################################################

nextFeature(){

local ORDER_CUR
local MAJOR_CUR
local INPUT_NEXT_FOUND
local ORDER_MAX
local FOUND
local RECURSION

if [[ "$3" == "" ]]; then
        RECURSION=0
else
	RECURSION=$(( $3 + 1 ))
fi

while IFS="$SEP" read -r Order Name Major Type File Checksum
do
	if [[ "$Name" == "$2" ]]; then
		ORDER_CUR="$Order"
		MAJOR_CUR="$Major"
		INPUT_NEXT_FOUND=1
	fi
done < "$1"

if (( INPUT_NEXT_FOUND != 1 )); then
	echo "Error"
	return 1
fi

ORDER_MAX=0

while IFS="$SEP" read -r Order Name Major Type File Checksum
do
	if (( Order > ORDER_MAX )); then
		ORDER_MAX=$Order
	fi
done < "$1"

if (( ORDER_CUR < ORDER_MAX )); then
	i=$((ORDER_CUR + 1))
else
	i=$ORDER_MAX
fi

while true
do
	while IFS="$SEP" read -r Order2 Name2 Major2 Type2 File2 Checksum2
	do
		# Prefer a newer feature release
		if (( FOUND == 1 )); then
			if [[ "$Type2" != "Feature" ]]; then
				break
			else
				# Avoid hotfix and beta
				if ! [[ "$Name2" =~ [-_] ]]; then
					FEATURE_NEXT="$Name2"
				fi
				continue
			fi
		fi
		if (( Order2 == i )); then
			if [[ "$MAJOR_CUR" != "$Major2" ]]; then
				if [[ "$Type2" == "Feature" ]]; then
					FEATURE_NEXT="$Name2"
					FOUND=1
					continue
				fi
			fi
		fi
	done < "$1"
	if (( FOUND == 1 )); then
		# No version skip if starting major is <= 10.0 or there is only 1 hop to the target major
		if [[ "$2" =~ ^[0-9]\.[0-2]\. ]] || [[ "$2" =~ ^10\.0\. ]] || [[ "$Major2" == "$MAJOR_REQ" ]] || (( RECURSION > 0 )); then
			echo "$FEATURE_NEXT"
			break
		else
			# Implement major version skip feature available from 10.1
			FEATURE_SKIP=$(nextFeature $1 $FEATURE_NEXT $RECURSION) || return 1
			if [[ "$FEATURE_SKIP" == "Latest" ]] || [[ "$FEATURE_SKIP" == "Error" ]]; then
				echo "$FEATURE_NEXT"
			else
				echo "$FEATURE_SKIP"
			fi
			break
		fi
	fi
	if (( i < ORDER_MAX )); then
		i=$((i + 1))
	else
		break
	fi
done

if (( FOUND != 1 )); then
	echo "Latest"
fi

}

##########################################################################################################################################################################################
# Returns what the previous feature release is
##########################################################################################################################################################################################

prevFeature(){

local ORDER_CUR
local MAJOR_CUR
local INPUT_PREV_FOUND
local ORDER_MIN
local FOUND
local RECURSION

if [[ "$3" == "" ]]; then
        RECURSION=0
else
	RECURSION=$(( $3 + 1 ))
fi

while IFS="$SEP" read -r Order Name Major Type File Checksum
do
	if [[ "$Name" == "$2" ]]; then
		ORDER_CUR="$Order"
		MAJOR_CUR="$Major"
		INPUT_PREV_FOUND=1
		break
	fi
done < "$1"

if (( INPUT_PREV_FOUND != 1 )); then
	echo "Error"
	return 1
fi

ORDER_MIN=1
if (( ORDER_CUR > ORDER_MIN )); then
	i=$((ORDER_CUR - 1))
else
	i=$ORDER_MIN
fi

while true
do
	while IFS="$SEP" read -r Order2 Name2 Major2 Type2 File2 Checksum2
	do
		if (( Order2 == i )); then
			if [[ "$MAJOR_CUR" != "$Major2" ]]; then
				if [[ "$Type2" == "Feature" ]]; then
					FEATURE_NEXT="$Name2"
					FOUND=1
					break
				fi
			fi
		fi
	done < "$1"
	if (( FOUND == 1 )); then
		# No version skip if target major is <= 10.0 or there is only 1 hop to the target major
		if [[ "$2" =~ ^[0-9]\.[0-2]\. ]] || [[ "$2" =~ ^10\.[0-2]\. ]] || [[ "$Major2" == "$MAJOR_REQ" ]] || (( RECURSION > 0 )); then
			echo "$FEATURE_NEXT"
			break
		else
			# Implement major version skip feature available from 10.1 (minimum 11.0 for downgrades since we skip 2 majors)
			FEATURE_SKIP=$(prevFeature $1 $FEATURE_NEXT $RECURSION) || return 1
			if [[ "$FEATURE_SKIP" == "Earliest" ]] || [[ "$FEATURE_SKIP" == "Error" ]]; then
				echo "$FEATURE_NEXT"
			else
				echo "$FEATURE_SKIP"
			fi
			break
		fi
	fi
	if (( i > ORDER_MIN )); then
		i=$((i - 1))
	else
		break
	fi
done

if (( FOUND != 1 )); then
	echo "Earliest"
fi

}

##########################################################################################################################################################################################
# Returns the major version of the input version
##########################################################################################################################################################################################

majorOf(){

PRESENT=0

while IFS="$SEP" read -r Order Name Major Type File Checksum
do

	if [[ "$Name" == "$2" ]]; then
		echo "$Major"
		PRESENT=1
		break
	else
		continue
	fi
done < "$1"

if (( PRESENT == 0 )); then
	date +"%T In function majorOf(), incorrect input or unsupported software release. Input: $1 $2" >&2
	return 1
fi

}

##########################################################################################################################################################################################
# Returns the feature/maintenance status of the input version
##########################################################################################################################################################################################

isFeature(){

PRESENT=0

while IFS="$SEP" read -r Order Name Major Type File Checksum
do

	if [[ "$Name" == "$2" ]]; then
		echo "$Type"
		PRESENT=1
		break
	else
		continue
	fi
done < "$1"

if (( PRESENT == 0 )); then
	date +"%T In function isFeature(), incorrect input or unsupported software release. Input: $1 $2" >&2
	return 1
fi

}

##########################################################################################################################################################################################
# Returns the latest version of the input major
##########################################################################################################################################################################################

LatestPatchOf(){

while IFS="$SEP" read -r Order Name Major Type File Checksum
do
	PATCH_LATEST_ORDER=0
	if [[ "$Major" == "$2" ]]; then
		if [[ "$Type" == "Maintenance" ]]; then
			if (( Order > PATCH_LATEST_ORDER )); then
				PATCH_LATEST_ORDER="$Order"
				NAME="$Name"
			fi
		fi
	fi
done < "$1"

echo "$NAME"

}

##########################################################################################################################################################################################
# Checks and uploads the input file
##########################################################################################################################################################################################

upload(){

if (( DRY_RUN == 1 )); then
	if checkFirmwarePresent "$2"; then
		date +"%T Image file $2 already available on the firewall, not uploading..." >&2
		return 0
	fi
	if (( EASY != 1 )); then
		UPLOAD_CHECKSUM=$(fileChecksum "$PLATFORM".csv "$2") || return 1
	fi
	FILE_PATH=$(find "$1" -name "$2")
	if [[ "$FILE_PATH" == "" ]]; then
		date +"%T Image file $2 not found. Exiting..." >&2
		return 1
	fi
	if (( EASY != 1 )); then
		CALC_CHECKSUM=$(sha256sum "$FILE_PATH" | cut -d ' ' -f 1)
		shopt -s nocasematch
		if ! [[ "$UPLOAD_CHECKSUM" =~ $CALC_CHECKSUM ]]; then
			date +"%T Image file $FILE_PATH has invalid checksum. Exiting..." >&2
			echo "Required: $UPLOAD_CHECKSUM" >&2
			echo "File: $CALC_CHECKSUM" >&2
			return 1
		fi
		shopt -u nocasematch
		date +"%T Checksum matches" >&2
	fi
	date +"%T Would upload $FILE_PATH now" >&2
	return 0
fi

if [[ "$3" != "FORCE" ]]; then
	if checkFirmwarePresent "$2"; then
		date +"%T Image file $2 already available on the firewall, not uploading..." >&2
		return 0
	fi
fi

if (( EASY != 1 )); then
	UPLOAD_CHECKSUM=$(fileChecksum "$PLATFORM".csv "$2") || return 1
fi

FILE_PATH=$(find "$1" -name "$2")

if [[ "$FILE_PATH" == "" ]]; then
	date +"%T Image file $2 not found. Exiting..." >&2
	return 1
fi

if (( EASY != 1 )); then
	CALC_CHECKSUM=$(sha256sum "$FILE_PATH" | cut -d ' ' -f 1)
	shopt -s nocasematch
	if ! [[ "$UPLOAD_CHECKSUM" =~ $CALC_CHECKSUM ]]; then
		date +"%T Image file $FILE_PATH has invalid checksum. Exiting..." >&2
		echo "Required: $UPLOAD_CHECKSUM" >&2
		echo "File: $CALC_CHECKSUM" >&2
		return 1
	fi
	shopt -u nocasematch
fi

checkAutoCom "$FIREWALL_ADDRESS" || return 1

local RESULT_UPLOAD_1
RESULT_UPLOAD_1=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" "/response/@status" 10 ) || return 1

if [[ "$RESULT_UPLOAD_1" != "success" ]]; then
	date +"%T Firewall not up while preparing to upload software. Exiting..." >&2
	return 1
fi

date +"%T Firewall at ${FIREWALL_ADDRESS} is up. Uploading software image $2..." >&2

# Check for extra csrf protections in newer patches, use API instead

local USE_API_UPLOAD=0
local CURL_CALL_UPLOAD_00
if [[ "$FIREWALL_ADDRESS" =~ fe80 ]]; then
	CURL_CALL_UPLOAD_00=$(curl $CURL_CA_IGNORE -6 --interface "$NETWORK_INTERFACE" -s -D - --max-time 120 --connect-timeout 10 --retry 5 "https://$FIREWALL_ADDRESS/php/login.php?" --data-raw "prot=https:&server=$FIREWALL_ADDRESS&authType=init&challengeCookie=&user=${USERNAME}&passwd=${ACTIVE_PASSWORD}&challengePwd=&ok=Log+In" 2>/dev/null)
else
	CURL_CALL_UPLOAD_00=$(curl $CURL_CA_IGNORE -s -D - --max-time 120 --connect-timeout 10 --retry 5 "https://$FIREWALL_ADDRESS/php/login.php?" --data-raw "prot=https:&server=$FIREWALL_ADDRESS&authType=init&challengeCookie=&user=${USERNAME}&passwd=${ACTIVE_PASSWORD}&challengePwd=&ok=Log+In" 2>/dev/null)
fi

if [[ "$CURL_CALL_UPLOAD_00" == "" ]]; then
	date +"%T In function upload(), firewall not responding after 5 retries. Exiting..." >&2
	return 1
fi

if [[ "$CURL_CALL_UPLOAD_00" =~ ^.*302\ Found.* ]]; then
	date +"%T Using API to upload." >&2
	USE_API_UPLOAD=1
fi

if [[ "$CURRENT_VERSION" =~ ^[0-9]\.[0-2]\. ]] || [[ "$CURRENT_VERSION" =~ ^10\.0\. ]] && (( USE_API_UPLOAD == 0 )); then
	# Uploading firmware via API seems to be unreliable under certain conditions in older versions
	# There are also more CSRF checks starting from 10.1 which make the hack difficult to maintain
	# Tentatively use API to upload from 10.1 onwards
	
	date +"%T Using old method to upload." >&2

	local SANITY_CHECK
	SANITY_CHECK=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" "/response/@status" 10 ) || return 1
	
	# Generate cookies and token, upload file, move file to final directory (this is the way the browser uploads software)
	
	local CURL_CALL_UPLOAD_0
	if [[ "$FIREWALL_ADDRESS" =~ fe80 ]]; then
		CURL_CALL_UPLOAD_0=$(curl $CURL_CA_IGNORE -6 --interface "$NETWORK_INTERFACE" -s -D - --max-time 120 --connect-timeout 10 --retry 5 "https://$FIREWALL_ADDRESS/php/login.php?" --data-raw "prot=https:&server=$FIREWALL_ADDRESS&authType=init&challengeCookie=&user=${USERNAME}&passwd=${ACTIVE_PASSWORD}&challengePwd=&ok=Log+In" 2>/dev/null)
	else
		CURL_CALL_UPLOAD_0=$(curl $CURL_CA_IGNORE -s -D - --max-time 120 --connect-timeout 10 --retry 5 "https://$FIREWALL_ADDRESS/php/login.php?" --data-raw "prot=https:&server=$FIREWALL_ADDRESS&authType=init&challengeCookie=&user=${USERNAME}&passwd=${ACTIVE_PASSWORD}&challengePwd=&ok=Log+In" 2>/dev/null)
	fi
	
	if [[ "$CURL_CALL_UPLOAD_0" == "" ]]; then
		date +"%T In function upload(), firewall not responding after 5 retries. Exiting..." >&2
		return 1
	fi
	
	if ! [[ "$CURL_CALL_UPLOAD_0" =~ ^.*PHPSESSID\=([^\;\"]*)[\;\"].* ]]; then
		date +"%T In function upload(), missing PHPSESSID cookie in HTTP response. Exiting..." >&2
		return 1
	fi
	
	local COOKIE_PHP
	COOKIE_PHP=$(echo "$CURL_CALL_UPLOAD_0" | grep PHPSESSID | sed -r 's/.*PHPSESSID\=([^;"]*)[;"].*/\1/')
	
	local CURL_CALL_UPLOAD_1
	if [[ "$FIREWALL_ADDRESS" =~ fe80 ]]; then
		CURL_CALL_UPLOAD_1=$(curl $CURL_CA_IGNORE -6 --interface "$NETWORK_INTERFACE" -s -D - --max-time 120 --connect-timeout 10 --retry 5 -X GET -H "Cookie: PHPSESSID=$COOKIE_PHP" "https://$FIREWALL_ADDRESS/" )
	else
		CURL_CALL_UPLOAD_1=$(curl $CURL_CA_IGNORE -s -D - --max-time 120 --connect-timeout 10 --retry 5 -X GET -H "Cookie: PHPSESSID=$COOKIE_PHP" "https://$FIREWALL_ADDRESS/" )
	fi
	
	if ! [[ "$CURL_CALL_UPLOAD_1" =~ ^.*window\.Pan\.st\.st\.st[0-9]+\ \=\ \"[^\"]+\".* ]]; then
		date +"%T In function upload(), missing Pan.st cookie in HTTP response. Exiting..." >&2
		return 1
	fi
	
	# Cross-site request forgery protection tokens
	
	local COOKIE_RPC
	COOKIE_RPC=$(echo "$CURL_CALL_UPLOAD_1" | grep window\.Pan\.st\.st\.st | sed -r 's/^.*window\.Pan\.st\.st\.st[0-9]+\ \=\ \"([^\"]+)\".*/\1/')
	
	local TID
	TID="1"
	
	local TOKEN_RPC
	TOKEN_RPC=$(echo -n "$COOKIE_RPC$TID" | md5sum | awk "{ print \$1 }")
	
	local CURL_CALL_UPLOAD_2
	if [[ "$FIREWALL_ADDRESS" =~ fe80 ]]; then
		CURL_CALL_UPLOAD_2=$(curl $CURL_CA_IGNORE -6 --interface "$NETWORK_INTERFACE" --retry 5 --max-time 1800 --connect-timeout 10 -F ___tid="$TID" -F ___token="${TOKEN_RPC}" -F file_path=@"${FILE_PATH}" "https://$FIREWALL_ADDRESS/upload/upload_software.php" -H "Cookie: PHPSESSID=$COOKIE_PHP") || { date +"%T Software upload not done after 30 minutes. Exiting..." >&2; return 1; }
	else
		CURL_CALL_UPLOAD_2=$(curl $CURL_CA_IGNORE --retry 5 --max-time 1800 --connect-timeout 10 -F ___tid="$TID" -F ___token="${TOKEN_RPC}" -F file_path=@"${FILE_PATH}" "https://$FIREWALL_ADDRESS/upload/upload_software.php" -H "Cookie: PHPSESSID=$COOKIE_PHP") || { date +"%T Software upload not done after 30 minutes. Exiting..." >&2; return 1; }
	fi
	
	if ! ( [[ "$CURL_CALL_UPLOAD_2" =~ success[\"\ ]*\:[\"\ ]*true ]] || [[ "$CURL_CALL_UPLOAD_2" =~ status[\"\ ]*\:[\"\ ]*success ]] ); then
		date +"%T Software upload result not successful. Exiting..." >&2
		return 1
	fi
	
	local FILE_RPC
	FILE_RPC=$(echo "$CURL_CALL_UPLOAD_2" | grep file | sed -r 's/^.*file[" ]*\:[" ]*([^",}]+)[",}].*/\1/')
	
	local FILEPATH_RPC
	FILEPATH_RPC=$(echo "$CURL_CALL_UPLOAD_2" | grep filepath | sed -r 's/^.*filepath[" ]*\:[" ]*([^",}]+)[",}].*/\1/' )
	
	TID="1"
	TOKEN_RPC=$(echo -n "$COOKIE_RPC$TID" | md5sum | awk "{ print \$1 }")
	
	local CURL_CALL_UPLOAD_3
	if [[ "$FIREWALL_ADDRESS" =~ fe80 ]]; then
		CURL_CALL_UPLOAD_3=$(curl $CURL_CA_IGNORE -6 --interface "$NETWORK_INTERFACE" -s --retry 5 --max-time 240 --connect-timeout 10 "https://$FIREWALL_ADDRESS/php/utils/router.php/SoftwareAndContentUtils.importPackage" -H "Cookie: PHPSESSID=$COOKIE_PHP" -H "Content-Type: application/json" --data-raw "{\"action\":\"PanDirect\",\"method\":\"execute\",\"data\":[\"${TOKEN_RPC}\",\"SoftwareAndContentUtils.importPackage\",{\"deploy\":false,\"localFilePath\":\"${FILEPATH_RPC}\",\"clientFileName\":\"${FILE_RPC}\",\"packageType\":\"software\",\"syncToPeer\":\"no\"}],\"type\":\"rpc\",\"tid\":\"$TID\"}" 2>/dev/null)
	else
		CURL_CALL_UPLOAD_3=$(curl $CURL_CA_IGNORE -s --retry 5 --max-time 240 --connect-timeout 10 "https://$FIREWALL_ADDRESS/php/utils/router.php/SoftwareAndContentUtils.importPackage" -H "Cookie: PHPSESSID=$COOKIE_PHP" -H "Content-Type: application/json" --data-raw "{\"action\":\"PanDirect\",\"method\":\"execute\",\"data\":[\"${TOKEN_RPC}\",\"SoftwareAndContentUtils.importPackage\",{\"deploy\":false,\"localFilePath\":\"${FILEPATH_RPC}\",\"clientFileName\":\"${FILE_RPC}\",\"packageType\":\"software\",\"syncToPeer\":\"no\"}],\"type\":\"rpc\",\"tid\":\"$TID\"}" 2>/dev/null)
	fi
	
	if [[ "$CURL_CALL_UPLOAD_3" == "" ]]; then
		date +"%T Software upload result not successful. Exiting..." >&2
		return 1
	fi
	
	if ! ( [[ "$CURL_CALL_UPLOAD_3" =~ success[\"\ ]*\:[\"\ ]*true ]] || [[ "$CURL_CALL_UPLOAD_3" =~ status[\"\ ]*\:[\"\ ]*success ]] ); then
		date +"%T Software upload result not successful. Exiting..." >&2
		return 1
	fi
else
	# Hopefully this works fine post 10.1
	local RESULT_API_UPLOAD
	SILENT_CURL=""
	RESULT_API_UPLOAD=$(curler "https://${FIREWALL_ADDRESS}/api/?type=import&category=software" "/response/@status" 300 "-F" "file=@${FILE_PATH}") || { SILENT_CURL="-s"; return 1; }
	SILENT_CURL="-s"
	
	if [[ "$RESULT_API_UPLOAD" == "Resource temporarily unavailable" ]]; then
		date +"%T Resource temporarily unavailable after upload. Continuing..." >&2
		return 0
	elif [[ "$RESULT_API_UPLOAD" != "success" ]]; then
		date +"%T Software upload of file $FILE_PATH failed. Exiting..." >&2
		return 1
	fi
fi

sleep 1

# Software is sometimes not showing even after a successful upload
# checkFirmwarePresent "$2" || { date +"%T Software upload failed. Exiting..." >&2; return 1; }

}

##########################################################################################################################################################################################
# Installs the input version
##########################################################################################################################################################################################

install(){

if (( DRY_RUN == 1 )); then
	WOULD_INSTALL="$1"
	date +"%T Would install $1 now" >&2
	return 0
fi

checkAutoCom "$FIREWALL_ADDRESS" || return 1

local JOB_ID
JOB_ID=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<request><system><software><install><version>$1</version></install></software></system></request>" "/response/result/job" 30 ) || return 1

date +"%T Installing software version $1 on device ${FIREWALL_ADDRESS}. Job ID is ${JOB_ID}." >&2

local t
t=0
local DELETION_ATTEMPTED
DELETION_ATTEMPTED=0
local INSTALL_RETRIES_TYPE_1
INSTALL_RETRIES_TYPE_1=0
local JOB_STATUS
local JOB_STATUS_RESULT
local JOB_STATUS_MSG
local JOB_STATUS_PROGRESS
local JOB_STATUS_PROGRESS_1
JOB_STATUS=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><jobs><id>${JOB_ID}</id></jobs></show>" " " 10 " " " " "raw")
JOB_STATUS_RESULT=$(echo "$JOB_STATUS" | xmlstarlet sel -t -v "/response/result/job/result" 2>/dev/null)
while [[ "$JOB_STATUS_RESULT" != "OK" ]];
do
	if [[ "$JOB_STATUS_RESULT" == "FAIL" ]]; then
		JOB_STATUS_MSG=$(echo "$JOB_STATUS" | xmlstarlet sel -t -v "/response/result/job/details/line" 2>/dev/null)
		if [[ "$JOB_STATUS_MSG" =~ (has\ not\ been\ downloaded|not\ downloaded) ]] && (( DELETION_ATTEMPTED == 0 )); then
			date +"%T Software version $1 needs to be reuploaded. Attempting to delete corrupt image..." >&2
			DELETE_JOB=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<delete><software><version>$1</version></software></delete>" "/response/result/job" 30) || return 1
			DELETION_ATTEMPTED=1
			upload "$SOFTWARE_FOLDER" "$FILE_NAME" "FORCE" >&2 || return 1
			JOB_ID=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<request><system><software><install><version>$1</version></install></software></system></request>" "/response/result/job" 30 ) || return 1
			date +"%T Installing software version $1 on device ${FIREWALL_ADDRESS}. Job ID is ${JOB_ID}." >&2
		elif [[ "$JOB_STATUS_MSG" =~ Please\ reboot\ the\ system\ and\ try\ again ]]; then
			date +"%T Installation failed, PAN-OS requests a reboot..." >&2
			rebootSystem || return 1
			return 2
		# Issue #2
		elif [[ "$JOB_STATUS_MSG" =~ software\ manager\ is\ currently\ in\ use ]] && (( INSTALL_RETRIES_TYPE_1 < 16 )); then
			date +"%T Installation failed, software manager currently in use. Waiting 1 minute and trying again..." >&2
			(( INSTALL_RETRIES_TYPE_1++ ))
			sleep 60
			JOB_ID=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<request><system><software><install><version>$1</version></install></software></system></request>" "/response/result/job" 30 ) || return 1
			date +"%T Installing software version $1 on device ${FIREWALL_ADDRESS}. Job ID is ${JOB_ID}." >&2
			t=0
		else
			date +"%T Software version $1 installation failed with reason: \"${JOB_STATUS_MSG}\". Exiting..." >&2
			return 1
		fi
	fi
	((t++))
	sleep 5
	if (( t > 540 )); then
		date +"%T Firewall ${FIREWALL_ADDRESS} software version $1 installation not complete after 45 minutes. Exiting..." >&2
		return 1
	fi
	JOB_STATUS=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><jobs><id>${JOB_ID}</id></jobs></show>" " " 10 " " " " "raw")
	JOB_STATUS_RESULT=$(echo "$JOB_STATUS" | xmlstarlet sel -t -v "/response/result/job/result" 2>/dev/null)
	JOB_STATUS_PROGRESS=$(echo "$JOB_STATUS" | xmlstarlet sel -t -v "/response/result/job/progress" 2>/dev/null)
	if [[ "$JOB_STATUS_PROGRESS" != "$JOB_STATUS_PROGRESS_1" ]]; then
		if [[ "$JOB_STATUS_PROGRESS" =~ ^[0-9]+$ ]]; then
			date +"%T Firewall ${FIREWALL_ADDRESS} software installation is $JOB_STATUS_PROGRESS percent complete." >&2
			JOB_STATUS_PROGRESS_1="$JOB_STATUS_PROGRESS"
		elif [[ "$JOB_STATUS_PROGRESS" =~ ^[0-9\:]+$ ]]; then
			date +"%T Firewall ${FIREWALL_ADDRESS} software installation completed." >&2
			JOB_STATUS_PROGRESS_1="$JOB_STATUS_PROGRESS"
		fi
	fi
done

sleep 1

}

##########################################################################################################################################################################################
# Brings the system to a rebooting state
##########################################################################################################################################################################################

rebootSystem(){
if (( DRY_RUN == 1 )); then
	date +"%T Would reboot now" >&2
	return 0
fi

date +"%T Attempting firewall reboot..." >&2

local REBOOT_CURL_0
REBOOT_CURL_0=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<request><restart><system></system></restart></request>" "/response/@status" 10) || return 1
if [[ "$REBOOT_CURL_0" == "success" ]]; then
	sleep 5
fi

SECONDS=0
local REBOOT_CURL_1
if [[ "$FIREWALL_ADDRESS" =~ fe80 ]]; then
	REBOOT_CURL_1=$(curl -s $CURL_CA_IGNORE -6 --interface "$NETWORK_INTERFACE" -u "${USERNAME}":"${ACTIVE_PASSWORD}" --max-time 120 --connect-timeout 3 -X GET "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" | xmlstarlet sel -t -v "/response/@status" 2>/dev/null)
else
	REBOOT_CURL_1=$(curl -s $CURL_CA_IGNORE -u "${USERNAME}":"${ACTIVE_PASSWORD}" --max-time 120 --connect-timeout 3 -X GET "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" | xmlstarlet sel -t -v "/response/@status" 2>/dev/null)
fi

while [[ "$REBOOT_CURL_1" == "success" ]];
do
	if (( SECONDS > 300 )); then
		date +"%T Firewall reboot failed. Exiting..." >&2
		return 1
	fi
	sleep 5
	
	if [[ "$FIREWALL_ADDRESS" =~ fe80 ]]; then
		REBOOT_CURL_1=$(curl -s $CURL_CA_IGNORE -6 --interface "$NETWORK_INTERFACE" -u "${USERNAME}":"${ACTIVE_PASSWORD}" --max-time 120 --connect-timeout 3 -X GET "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" | xmlstarlet sel -t -v "/response/@status" 2>/dev/null)
	else
		REBOOT_CURL_1=$(curl -s $CURL_CA_IGNORE -u "${USERNAME}":"${ACTIVE_PASSWORD}" --max-time 120 --connect-timeout 3 -X GET "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" | xmlstarlet sel -t -v "/response/@status" 2>/dev/null)
	fi

done

JUST_REBOOTED=1
beep >&2
date +"%T Firewall ${FIREWALL_ADDRESS} is now rebooting..." >&2
return 0

}

##########################################################################################################################################################################################
# Brings the system to a shutdown state
##########################################################################################################################################################################################

shutdownSystem(){
if (( DRY_RUN == 1 )); then
	date +"%T Would shutdown now" >&2
	return 0
fi

date +"%T Attempting firewall shutdown..." >&2
local SHUTDOWN_CURL_0
SHUTDOWN_CURL_0=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<request><shutdown><system></system></shutdown></request>" "/response/msg/line" 10)
if [[ "$SHUTDOWN_CURL_0" == "Command succeeded with no output" ]]; then
	sleep 5
fi

SECONDS=0

local SHUTDOWN_CURL_1
if [[ "$FIREWALL_ADDRESS" =~ fe80 ]]; then
	SHUTDOWN_CURL_1=$(curl -s $CURL_CA_IGNORE -6 --interface "$NETWORK_INTERFACE" -u "${USERNAME}":"${ACTIVE_PASSWORD}" --max-time 1800 --connect-timeout 3 -X GET "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" | xmlstarlet sel -t -v "/response/@status" 2>/dev/null)
else
	SHUTDOWN_CURL_1=$(curl -s $CURL_CA_IGNORE -u "${USERNAME}":"${ACTIVE_PASSWORD}" --max-time 1800 --connect-timeout 3 -X GET "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" | xmlstarlet sel -t -v "/response/@status" 2>/dev/null)
fi

while [[ "$SHUTDOWN_CURL_1" == "success" ]];
do
	if (( SECONDS > 300 )); then
		date +"%T Firewall shutdown failed. Exiting..." >&2
		return 1
	fi
	sleep 5
	if [[ "$FIREWALL_ADDRESS" =~ fe80 ]]; then
		SHUTDOWN_CURL_1=$(curl -s $CURL_CA_IGNORE -6 --interface "$NETWORK_INTERFACE" -u "${USERNAME}":"${ACTIVE_PASSWORD}" --max-time 1800 --connect-timeout 3 -X GET "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" | xmlstarlet sel -t -v "/response/@status" 2>/dev/null)
	else
		SHUTDOWN_CURL_1=$(curl -s $CURL_CA_IGNORE -u "${USERNAME}":"${ACTIVE_PASSWORD}" --max-time 1800 --connect-timeout 3 -X GET "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" | xmlstarlet sel -t -v "/response/@status" 2>/dev/null)
	fi
	
done

date +"%T Firewall ${FIREWALL_ADDRESS} has been shut down." >&2
return 0

}

##########################################################################################################################################################################################
# Uploads and installs a content version compatible with the target firmware version
##########################################################################################################################################################################################

upgradeContent(){

PRESENT=0

while IFS="$SEP" read -r Major MinContent File Checksum
do
	if [[ "$Major" == "$2" ]]; then
		CONTENT_REQ="$MinContent"
		CONTENT_FILE="$File"
		PRESENT=1
		break
	else
		continue
	fi
done < "content.csv"

if (( PRESENT == 0 )); then
	date +"%T Unknown Major release. Exiting..." >&2
	return 1
fi

if (( $1 >= CONTENT_REQ )); then
	date +"%T Installed content version $1 is already compatible with the target release." >&2
	return 0
fi

date +"%T Installed content version $1 is not compatible with the target release. Upgrading..." >&2

if (( $1 < 1000 )); then
	date +"%T --- WARNING --- Installed content version $1 is very old and the content upgrade may fail (some bugs related to 3/4 digit content versions). Please upgrade the content manually in that case." >&2
fi

if (( DRY_RUN == 1 )); then
	
	if checkContentPresent "$CONTENT_FILE"; then
		date +"%T Content file $CONTENT_FILE is already available on the firewall." >&2
		date +"%T Would install $CONTENT_FILE now" >&2
		return 0
	fi
	
	UPLOAD_CHECKSUM=$(fileChecksumContent "content.csv" "$CONTENT_FILE") || return 1
	FILE_PATH=$(find "$SOFTWARE_FOLDER" -name "$CONTENT_FILE")
	if [[ "$FILE_PATH" == "" ]]; then
		date +"%T Content file $CONTENT_FILE not found. Exiting..." >&2
		return 1
	fi
	CALC_CHECKSUM=$(sha256sum "$FILE_PATH" | cut -d ' ' -f 1)
	shopt -s nocasematch
	if ! [[ "$UPLOAD_CHECKSUM" =~ $CALC_CHECKSUM ]]; then
		date +"%T Content file $FILE_PATH has invalid checksum. Exiting..." >&2
		echo "Required: $UPLOAD_CHECKSUM" >&2
		echo "File: $CALC_CHECKSUM" >&2
		return 1
	fi
	shopt -u nocasematch
	date +"%T Checksum matches" >&2
	date +"%T Would upload and install $FILE_PATH now" >&2
	return 0
fi

if checkContentPresent "$CONTENT_FILE"; then
	date +"%T Content file $CONTENT_FILE is already available on the firewall." >&2
else
	UPLOAD_CHECKSUM=$(fileChecksumContent "content.csv" "$CONTENT_FILE") || return 1
	
	FILE_PATH=$(find "$SOFTWARE_FOLDER" -name "$CONTENT_FILE")
	
	if [[ "$FILE_PATH" == "" ]]; then
		date +"%T Image file $CONTENT_FILE not found. Exiting..." >&2
		return 1
	fi
	CALC_CHECKSUM=$(sha256sum "$FILE_PATH" | cut -d ' ' -f 1)
	shopt -s nocasematch
	if ! [[ "$UPLOAD_CHECKSUM" =~ $CALC_CHECKSUM ]]; then
		date +"%T Image file $FILE_PATH has invalid checksum. Exiting..." >&2
		echo "Required: $UPLOAD_CHECKSUM" >&2
		echo "File: $CALC_CHECKSUM" >&2
		return 1
	fi
	shopt -u nocasematch
	
	# Proceed with uploading the file
	
	checkAutoCom "$FIREWALL_ADDRESS" || return 1
	
	local RESULT_CUPLOAD_1
	RESULT_CUPLOAD_1=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" "/response/@status" 10) || return 1
	
	if [[ "$RESULT_CUPLOAD_1" != "success" ]]; then
		date +"%T Firewall not up while preparing to upload content. Exiting..." >&2
		return 1
	fi
	
	date +"%T Firewall at ${FIREWALL_ADDRESS} is now up. Uploading content..." >&2
	
	local RESULT_CUPLOAD_2
	SILENT_CURL=""
	RESULT_CUPLOAD_2=$(curler "https://${FIREWALL_ADDRESS}/api/?type=import&category=content" "/response/@status" 300 "-F" "file=@${FILE_PATH}") || { SILENT_CURL="-s"; return 1; }
	SILENT_CURL="-s"
	
	# "request content upgrade info" doesn't properly show uploaded packages
	#checkContentPresent "$CONTENT_FILE" || { date +"%T Content upload failed. Exiting..." >&2; return 1; }
fi

# Proceed with installing the file

if (( DRY_RUN == 1 )); then
	WOULD_INSTALL_CONTENT="$CONTENT_REQ"
	date +"%T Would install $CONTENT_REQ now" >&2
	return 0
fi

local JOB_ID_CONTENT

# Older versions do not have the "skip-content-validity-check" keyword

if [[ "$MAJOR_CUR" == "7.1" || "$MAJOR_CUR" == "8.0" ]]; then
	JOB_ID_CONTENT=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<request><content><upgrade><install><file>$CONTENT_FILE</file></install></upgrade></content></request>" "/response/result/job" 30) || return 1
else
	JOB_ID_CONTENT=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<request><content><upgrade><install><skip-content-validity-check>yes</skip-content-validity-check><file>$CONTENT_FILE</file></install></upgrade></content></request>" "/response/result/job" 30) || return 1
fi

date +"%T Installing content $CONTENT_FILE on device ${FIREWALL_ADDRESS}. Job ID is ${JOB_ID_CONTENT}." >&2

local t
t=0
local JOB_STATUS_CONTENT
local JOB_STATUS_CONTENT_RESULT
local JOB_STATUS_CONTENT_MSG
local JOB_STATUS_CONTENT_PROGRESS
local JOB_STATUS_CONTENT_PROGRESS_1
JOB_STATUS_CONTENT=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><jobs><id>${JOB_ID_CONTENT}</id></jobs></show>" " " 10 " " " " "raw") || return 1
JOB_STATUS_CONTENT_RESULT=$(echo "$JOB_STATUS_CONTENT" | xmlstarlet sel -t -v "/response/result/job/result" 2>/dev/null)
while [[ "$JOB_STATUS_CONTENT_RESULT" != "OK" ]];
do
	if [[ "$JOB_STATUS_CONTENT_RESULT" == "FAIL" ]]; then
		JOB_STATUS_CONTENT_MSG=$(echo "$JOB_STATUS_CONTENT" | xmlstarlet sel -t -v "/response/result/job/details/line" 2>/dev/null)
		date +"%T Content $CONTENT_FILE installation failed with reason: \"${JOB_STATUS_CONTENT_MSG}\". Exiting..." >&2
		return 1
	fi
	((t++))
	sleep 5
	if (( t > 540 )); then
		date +"%T Firewall ${FIREWALL_ADDRESS} content $CONTENT_FILE installation not complete after 45 minutes. Exiting..." >&2
		return 1
	fi
	JOB_STATUS_CONTENT=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><jobs><id>${JOB_ID_CONTENT}</id></jobs></show>" " " 10 " " " " "raw") || return 1
	JOB_STATUS_CONTENT_RESULT=$(echo "$JOB_STATUS_CONTENT" | xmlstarlet sel -t -v "/response/result/job/result" 2>/dev/null)
	JOB_STATUS_CONTENT_PROGRESS=$(echo "$JOB_STATUS_CONTENT" | xmlstarlet sel -t -v "/response/result/job/progress" 2>/dev/null)
	if [[ "$JOB_STATUS_CONTENT_PROGRESS" != "$JOB_STATUS_CONTENT_PROGRESS_1" ]]; then
		if [[ "$JOB_STATUS_CONTENT_PROGRESS" =~ ^[0-9]+$ ]]; then
			date +"%T Firewall ${FIREWALL_ADDRESS} content installation is $JOB_STATUS_CONTENT_PROGRESS percent complete." >&2
			JOB_STATUS_CONTENT_PROGRESS_1="$JOB_STATUS_CONTENT_PROGRESS"
		elif [[ "$JOB_STATUS_CONTENT_PROGRESS" =~ ^[0-9\:]+$ ]]; then
			date +"%T Firewall ${FIREWALL_ADDRESS} content installation completed." >&2
			JOB_STATUS_CONTENT_PROGRESS_1="$JOB_STATUS_CONTENT_PROGRESS"
		fi
	fi
done

sleep 1

}

##########################################################################################################################################################################################
# Uploads and installs content for easy mode
##########################################################################################################################################################################################

upgradeEasyContent(){

if (( DRY_RUN == 1 )); then
	
	if checkContentPresent "$1"; then
		date +"%T Content file $1 is already available on the firewall." >&2
		date +"%T Would install $1 now" >&2
		return 0
	fi
	
	FILE_PATH=$(find "$SOFTWARE_FOLDER" -name "$1")
	if [[ "$FILE_PATH" == "" ]]; then
		date +"%T Content file $1 not found. Exiting..." >&2
		return 1
	fi
	date +"%T Would upload and install $FILE_PATH now" >&2
	return 0
fi

if checkContentPresent "$1"; then
	date +"%T Content file $1 is already available on the firewall." >&2
	return 0
fi

FILE_PATH=$(find "$SOFTWARE_FOLDER" -name "$1")

if [[ "$FILE_PATH" == "" ]]; then
	date +"%T Image file $1 not found. Exiting..." >&2
	return 1
fi

# Proceed with uploading the file

checkAutoCom "$FIREWALL_ADDRESS" || return 1

local RESULT_CUPLOAD_1
RESULT_CUPLOAD_1=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" "/response/@status" 10) || return 1

if [[ "$RESULT_CUPLOAD_1" != "success" ]]; then
	date +"%T Firewall not up while preparing to upload content. Exiting..." >&2
	return 1
fi

date +"%T Firewall at ${FIREWALL_ADDRESS} is now up. Uploading content..." >&2

local RESULT_CUPLOAD_2
SILENT_CURL=""
RESULT_CUPLOAD_2=$(curler "https://${FIREWALL_ADDRESS}/api/?type=import&category=content" "/response/@status" 300 "-F" "file=@${FILE_PATH}") || { SILENT_CURL="-s"; return 1; }
SILENT_CURL="-s"

# Proceed with installing the file

if (( DRY_RUN == 1 )); then
	WOULD_INSTALL_CONTENT="$1"
	date +"%T Would install $1 now" >&2
	return 0
fi

local JOB_ID_CONTENT

# Older versions do not have the "skip-content-validity-check" keyword

JOB_ID_CONTENT=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<request><content><upgrade><install><skip-content-validity-check>yes</skip-content-validity-check><file>$1</file></install></upgrade></content></request>" "/response/result/job" 30) || PRE_81=1
if (( PRE_81 == 1 )); then
	date +"%T Retrying pre-8.1 command syntax..." >&2
	JOB_ID_CONTENT=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<request><content><upgrade><install><file>$1</file></install></upgrade></content></request>" "/response/result/job" 30) || return 1
fi

date +"%T Installing content $1 on device ${FIREWALL_ADDRESS}. Job ID is ${JOB_ID_CONTENT}." >&2

local t
t=0
local JOB_STATUS_CONTENT
local JOB_STATUS_CONTENT_RESULT
local JOB_STATUS_CONTENT_MSG
local JOB_STATUS_CONTENT_PROGRESS
local JOB_STATUS_CONTENT_PROGRESS_1
JOB_STATUS_CONTENT=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><jobs><id>${JOB_ID_CONTENT}</id></jobs></show>" " " 10 " " " " "raw") || return 1
JOB_STATUS_CONTENT_RESULT=$(echo "$JOB_STATUS_CONTENT" | xmlstarlet sel -t -v "/response/result/job/result" 2>/dev/null)
while [[ "$JOB_STATUS_CONTENT_RESULT" != "OK" ]];
do
	if [[ "$JOB_STATUS_CONTENT_RESULT" == "FAIL" ]]; then
		JOB_STATUS_CONTENT_MSG=$(echo "$JOB_STATUS_CONTENT" | xmlstarlet sel -t -v "/response/result/job/details/line" 2>/dev/null)
		date +"%T Content $1 installation failed with reason: \"${JOB_STATUS_CONTENT_MSG}\". Exiting..." >&2
		return 1
	fi
	((t++))
	sleep 5
	if (( t > 540 )); then
		date +"%T Firewall ${FIREWALL_ADDRESS} content $1 installation not complete after 45 minutes. Exiting..." >&2
		return 1
	fi
	JOB_STATUS_CONTENT=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><jobs><id>${JOB_ID_CONTENT}</id></jobs></show>" " " 10 " " " " "raw") || return 1
	JOB_STATUS_CONTENT_RESULT=$(echo "$JOB_STATUS_CONTENT" | xmlstarlet sel -t -v "/response/result/job/result" 2>/dev/null)
	JOB_STATUS_CONTENT_PROGRESS=$(echo "$JOB_STATUS_CONTENT" | xmlstarlet sel -t -v "/response/result/job/progress" 2>/dev/null)
	if [[ "$JOB_STATUS_CONTENT_PROGRESS" != "$JOB_STATUS_CONTENT_PROGRESS_1" ]]; then
		if [[ "$JOB_STATUS_CONTENT_PROGRESS" =~ ^[0-9]+$ ]]; then
			date +"%T Firewall ${FIREWALL_ADDRESS} content installation is $JOB_STATUS_CONTENT_PROGRESS percent complete." >&2
			JOB_STATUS_CONTENT_PROGRESS_1="$JOB_STATUS_CONTENT_PROGRESS"
		elif [[ "$JOB_STATUS_CONTENT_PROGRESS" =~ ^[0-9\:]+$ ]]; then
			date +"%T Firewall ${FIREWALL_ADDRESS} content installation completed." >&2
			JOB_STATUS_CONTENT_PROGRESS_1="$JOB_STATUS_CONTENT_PROGRESS"
		fi
	fi
done

sleep 1

}

##########################################################################################################################################################################################
# Deals with the change password prompt at the GUI in versions >9.0.4
##########################################################################################################################################################################################

passwordChange(){

local COOKIE
local CSRF

# FIRST GET

local CURL_CALL_PWDCHANGE_00
if [[ "$FIREWALL_ADDRESS" =~ fe80 ]]; then
	CURL_CALL_PWDCHANGE_00=$(curl $CURL_CA_IGNORE -6 --interface "$NETWORK_INTERFACE" -s -D - --max-time 1800 --connect-timeout 3 --retry 5 "https://${FIREWALL_ADDRESS}/")
else
	CURL_CALL_PWDCHANGE_00=$(curl $CURL_CA_IGNORE -s -D - --max-time 1800 --connect-timeout 3 --retry 5 "https://${FIREWALL_ADDRESS}/")
fi

if [[ "$CURL_CALL_PWDCHANGE_00" == "" ]]; then
	date +"%T In function passwordChange(), firewall not responding after 5 retries. Exiting..." >&2
	return 1
fi

# Get cookie if sent
if [[ "$CURL_CALL_PWDCHANGE_00" =~ ^.*PHPSESSID\=([^\;\"]*)[\;\"].* ]]; then
	COOKIE=$(echo "$CURL_CALL_PWDCHANGE_00" | grep -m 1 PHPSESSID | sed -r 's/.*PHPSESSID\=([^;"]*)[;"].*/\1/')
fi

# Get token if sent
if [[ "$CURL_CALL_PWDCHANGE_00" =~ ^.*window\.Pan\.st\.st\.st[0-9]+\ \=\ \"[^\"]+\".* ]]; then
	CSRF=$(echo "$CURL_CALL_PWDCHANGE_00" | grep -m 1 window\.Pan\.st\.st\.st | sed -r 's/^.*window\.Pan\.st\.st\.st[0-9]+\ \=\ \"([^\"]+)\".*/\1/')
fi

# SECOND GET

local CURL_CALL_PWDCHANGE_0
if [[ "$FIREWALL_ADDRESS" =~ fe80 ]]; then
	CURL_CALL_PWDCHANGE_0=$(curl $CURL_CA_IGNORE -6 --interface "$NETWORK_INTERFACE" -s -D - --max-time 1800 --connect-timeout 3 --retry 5 -H "Cookie: PHPSESSID=${COOKIE}" "https://${FIREWALL_ADDRESS}/php/login.php?")
else
	CURL_CALL_PWDCHANGE_0=$(curl $CURL_CA_IGNORE -s -D - --max-time 1800 --connect-timeout 3 --retry 5 -H "Cookie: PHPSESSID=${COOKIE}" "https://${FIREWALL_ADDRESS}/php/login.php?")
fi

if [[ "$CURL_CALL_PWDCHANGE_0" == "" ]]; then
	date +"%T In function passwordChange(), firewall not responding after 5 retries. Exiting..." >&2
	return 1
fi

if ! [[ "$CURL_CALL_PWDCHANGE_0" =~ ^.*PHPSESSID\=([^\;\"]*)[\;\"].* ]]; then
	date +"%T In function passwordChange(), missing PHPSESSID cookie in HTTP response. Exiting..." >&2
	return 1
elif ! [[ "$CURL_CALL_PWDCHANGE_0" =~ ^.*window\.Pan\.st\.st\.st[0-9]+\ \=\ \"[^\"]+\".* ]]; then
	date +"%T In function passwordChange(), missing csrf in HTTP response. Exiting..." >&2
	return 1
fi

# Update if changed

local CSRF
CSRF=$(echo "$CURL_CALL_PWDCHANGE_0" | grep -m 1 window\.Pan\.st\.st\.st | sed -r 's/^.*window\.Pan\.st\.st\.st[0-9]+\ \=\ \"([^\"]+)\".*/\1/')

local COOKIE
COOKIE=$(echo "$CURL_CALL_PWDCHANGE_0" | grep -m 1 PHPSESSID | sed -r 's/.*PHPSESSID\=([^;"]*)[;"].*/\1/')

# POST LOGIN

local CURL_CALL_PWDCHANGE_1
if [[ "$FIREWALL_ADDRESS" =~ fe80 ]]; then
	CURL_CALL_PWDCHANGE_1=$(curl $CURL_CA_IGNORE -6 --interface "$NETWORK_INTERFACE" -s -D - --max-time 1800 --connect-timeout 3 --retry 5 "https://${FIREWALL_ADDRESS}/php/login.php?" -H "Cookie: PHPSESSID=${COOKIE}" --data-raw "prot=https:&server=${FIREWALL_ADDRESS}&authType=init&challengeCookie=&_csrf=${CSRF}&user=${USERNAME}&passwd=${ACTIVE_PASSWORD}&challengePwd=&ok=Log+In")
else
	CURL_CALL_PWDCHANGE_1=$(curl $CURL_CA_IGNORE -s -D - --max-time 1800 --connect-timeout 3 --retry 5 "https://${FIREWALL_ADDRESS}/php/login.php?" -H "Cookie: PHPSESSID=${COOKIE}" --data-raw "prot=https:&server=${FIREWALL_ADDRESS}&authType=init&challengeCookie=&_csrf=${CSRF}&user=${USERNAME}&passwd=${ACTIVE_PASSWORD}&challengePwd=&ok=Log+In")
fi

if [[ "$CURL_CALL_PWDCHANGE_1" == "" ]]; then
	date +"%T In function passwordChange(), firewall not responding after 5 retries. Exiting..." >&2
	return 1
elif ! [[ "$CURL_CALL_PWDCHANGE_1" =~ ^.*PHPSESSID\=([^\;\"]*)[\;\"].* ]]; then
	date +"%T In function passwordChange(), missing PHPSESSID cookie in HTTP response. Exiting..." >&2
	return 1
fi

# Update if changed

local CSRF
CSRF=$(echo "$CURL_CALL_PWDCHANGE_1" | grep -m 1 window\.Pan\.st\.st\.st | sed -r 's/^.*window\.Pan\.st\.st\.st[0-9]+\ \=\ \"([^\"]+)\".*/\1/')

local COOKIE
COOKIE=$(echo "$CURL_CALL_PWDCHANGE_1" | grep -m 1 PHPSESSID | sed -r 's/.*PHPSESSID\=([^;"]*)[;"].*/\1/')


date +"%T Attempting to change password for user \"$USERNAME\" to \"$BACKUP_PASSWORD\" as requested by PANOS. The change might not survive a reboot unless explicitly committed." >&2
beep >&2

# THIRD GET

local CURL_CALL_PWDCHANGE_2
if [[ "$FIREWALL_ADDRESS" =~ fe80 ]]; then
	CURL_CALL_PWDCHANGE_2=$(curl $CURL_CA_IGNORE -6 --interface "$NETWORK_INTERFACE" -s -D - --max-time 1800 --connect-timeout 3 --retry 5 -H "Cookie: PHPSESSID=${COOKIE}" "https://${FIREWALL_ADDRESS}/unauth/php/change_password.php")
else
	CURL_CALL_PWDCHANGE_2=$(curl $CURL_CA_IGNORE -s -D - --max-time 1800 --connect-timeout 3 --retry 5 -H "Cookie: PHPSESSID=${COOKIE}" "https://${FIREWALL_ADDRESS}/unauth/php/change_password.php")
fi

if [[ "$CURL_CALL_PWDCHANGE_2" == "" ]]; then
	date +"%T In function passwordChange(), firewall not responding after 5 retries. Exiting..." >&2
	return 1
fi

# Get cookie if sent
if [[ "$CURL_CALL_PWDCHANGE_2" =~ ^.*PHPSESSID\=([^\;\"]*)[\;\"].* ]]; then
	COOKIE=$(echo "$CURL_CALL_PWDCHANGE_2" | grep -m 1 PHPSESSID | sed -r 's/.*PHPSESSID\=([^;"]*)[;"].*/\1/')
fi

# Get token if sent
if [[ "$CURL_CALL_PWDCHANGE_2" =~ ^.*window\.Pan\.st\.st\.st[0-9]+\ \=\ \"[^\"]+\".* ]]; then
	CSRF=$(echo "$CURL_CALL_PWDCHANGE_2" | grep -m 1 window\.Pan\.st\.st\.st | sed -r 's/^.*window\.Pan\.st\.st\.st[0-9]+\ \=\ \"([^\"]+)\".*/\1/')
fi

# Change password POST

local CURL_CALL_PWDCHANGE_3
if [[ "$FIREWALL_ADDRESS" =~ fe80 ]]; then
	CURL_CALL_PWDCHANGE_3=$(curl $CURL_CA_IGNORE -6 --interface "$NETWORK_INTERFACE" -s --max-time 1800 --connect-timeout 3 --retry 5 -H "Cookie: PHPSESSID=${COOKIE}" "https://${FIREWALL_ADDRESS}/unauth/php/change_password.php" --data-raw "_csrf=${CSRF}&old_password=${ACTIVE_PASSWORD}&new_password=${BACKUP_PASSWORD}&new_password_confirm=${BACKUP_PASSWORD}&ok=Change+Password")
else
	CURL_CALL_PWDCHANGE_3=$(curl $CURL_CA_IGNORE -s --max-time 1800 --connect-timeout 3 --retry 5 -H "Cookie: PHPSESSID=${COOKIE}" "https://${FIREWALL_ADDRESS}/unauth/php/change_password.php" --data-raw "_csrf=${CSRF}&old_password=${ACTIVE_PASSWORD}&new_password=${BACKUP_PASSWORD}&new_password_confirm=${BACKUP_PASSWORD}&ok=Change+Password")
fi

}

##########################################################################################################################################################################################
# Returns the requested xml node value from the requested API call. Deals with timeouts and errors.
##########################################################################################################################################################################################

curler(){

local REBOOT_ENDING
REBOOT_ENDING=0
local RETRYING_CURLER
RETRYING_CURLER=0
local CURLER_EVALS_1
CURLER_EVALS_1=0
local CURLER_EVALS_2
CURLER_EVALS_2=0
local CURLER_SECONDS_3
CURLER_SECONDS_3=0
local API_SESS_RETRY
API_SESS_RETRY=0
local KEEPALIVE
local CURL
local CURL_2
local CURL_3
local CURL_4
local ARG3=$3
local CURL_RET_CODE


while true
do
	
	CURL=""
	CURL_2=""
	CURL_3=""
	CURL_4=""
	if (( RETRYING_CURLER != 1 )); then
		SECONDS=0
	fi
	RETRYING_CURLER=0
	KEEPALIVE=$(( SECONDS + 60 ))
	
	####################################### Timeouts Phase #######################################
	
	while (( SECONDS < ARG3 ))
	do
		
		if [[ "$1" =~ fe80 ]]; then
			CURL=$(curl $CURL_CA_IGNORE $SILENT_CURL -6 --interface "$NETWORK_INTERFACE" -u "${USERNAME}":"${ACTIVE_PASSWORD}" --max-time 1800 --connect-timeout 3 "$4" "$5" "$1")
		else
			CURL=$(curl $CURL_CA_IGNORE $SILENT_CURL -u "${USERNAME}":"${ACTIVE_PASSWORD}" --max-time 1800 --connect-timeout 3 "$4" "$5" "$1")
		fi
		
		CURL_RET_CODE=$?
		
		# Catch vm capacity license reboot
		
		if (( CURL_RET_CODE == 52 )) && [[ "$1" =~ type\=import\&category\=license ]]; then
			date +"%T WARNING: VM rebooting due to capacity license uploaded" >&2
			return 2
		fi
		
		# Catch TLS errors
		
		if (( CURL_RET_CODE == 60 )); then
			date +"%T TLS certificate error." >&2
			return 1
		fi
		
		# Response must be a valid API response. If rebooting, we sometimes receive random API errors or plain HTML.
		
		CURL_2=$(echo "$CURL" | xmlstarlet sel -t -v "/response/@status" 2>/dev/null)
		
		if [[ "$CURL_2" != "" ]]; then
			break
		fi
		
		# Wait longer if firewall is rebooting
		
		if (( JUST_REBOOTED == 1 )); then
			sleep 5
		else
			sleep 1
		fi
		
		# Print a courtesy message every 60 seconds of waiting
		
		if (( SECONDS >= KEEPALIVE )); then
			if [[ "$ACTIVITY" == "Upgrade" ]]; then
				date +"%T Current step: ${MAJOR_CUR} -> ${MAJOR_NEXT}, retrying for ${SECONDS}/${ARG3} seconds..." >&2
			elif [[ "$ACTIVITY" == "Downgrade" ]]; then
				date +"%T Current step: ${MAJOR_CUR} -> ${MAJOR_PREV}, retrying for ${SECONDS}/${ARG3} seconds..." >&2
			elif [[ "$ACTIVITY" == "Easy" ]]; then
				date +"%T Current step: ${MAJOR_CUR} -> ${MAJOR_NEXT}, retrying for ${SECONDS}/${ARG3} seconds..." >&2
			fi
			KEEPALIVE=$(( SECONDS + 60 ))
		fi
	done

	####################################### Evaluation Phase #######################################
	
	if [[ "$CURL" != "" ]] && [[ "$CURL_2" == "" ]]; then
		date +"%T Warning: received corrupt API response to API request. Discarding..." >&2
		CURL="###BKND_WAIT###"
	fi
	
	if [[ $(echo "$CURL" | xmlstarlet sel -t -v "/response/@status" 2>/dev/null) == "success" ]]; then
		local OUTPUT
		if [[ "$6" == "raw" ]]; then
			OUTPUT="$CURL"
		else
			OUTPUT=$(echo "$CURL" | xmlstarlet sel -t -v "$2" 2>/dev/null)
		fi
		echo "$OUTPUT"
		return 0
	elif [[ "$CURL" == "" && "$7" != "notimeout" ]]; then
		date +"%T Firewall API call response empty or timed out after ${ARG3} seconds." >&2
		return 1
	elif [[ $(echo "$CURL" | xmlstarlet sel -t -v "/response/@code" 2>/dev/null) == "16" ]]; then
		date +"%T User ${USERNAME} has insufficient API privileges to perform the operation. Exiting..." >&2
		return 1
	elif [[ $(echo "$CURL" | xmlstarlet sel -t -v "/response/result/msg" 2>/dev/null) =~ [Ii]nvalid\ [Cc]redential(s.)? ]]; then

		# Swap passwords and retry
		
		THIRD="$ACTIVE_PASSWORD"
		ACTIVE_PASSWORD="$BACKUP_PASSWORD"
		BACKUP_PASSWORD="$THIRD"
		
		
		
		if (( JUST_REBOOTED == 1 )); then
			
			# Ditch early (Issue #3) when using keygen to trigger password change post 10.2 as the logic is outside curler()
			
			if [[ "$1" =~ "type=keygen" ]]; then
				return 1
			fi
			
			# If rebooting, sometimes we get "Invalid Credentials." for primary and backup passwords even if they are correct
			
			if (( REBOOT_ENDING == 0 )); then
				SECONDS=0
				ARG3=600
				REBOOT_ENDING=1
				if (( JUST_STARTED != 1 )); then
					date +"%T Reboot is ending..." >&2
					JUST_STARTED=0
				fi
			fi
			
			# At every retry also check if credentials have reverted to factory, and ditch early (Issue #3)
			
			if [[ "$1" =~ fe80 ]]; then
				CURL_4=$(curl $CURL_CA_IGNORE $SILENT_CURL -6 --interface "$NETWORK_INTERFACE" --max-time 1800 --connect-timeout 3 "$4" "$5" "https://${FIREWALL_ADDRESS}/api/?type=keygen&user=${FACTORY_USERNAME}&password=${FACTORY_PASSWORD}")
			else
				CURL_4=$(curl $CURL_CA_IGNORE $SILENT_CURL --max-time 1800 --connect-timeout 3 "$4" "$5" "https://${FIREWALL_ADDRESS}/api/?type=keygen&user=${FACTORY_USERNAME}&password=${FACTORY_PASSWORD}")
			fi
			if [[ $(echo "$CURL_4" | xmlstarlet sel -t -v "/response/result/msg" 2>/dev/null) == "Please change your password." ]]; then
				return 4
			fi
			
			RETRYING_CURLER=1
			sleep 2
			continue
		else
			if (( CURLER_EVALS_1 < 2 )); then
				(( CURLER_EVALS_1++ ))
				RETRYING_CURLER=1
				continue
			else

				# Credentials really are wrong, unless they're inserted in the keygen query and we just changed passwords
				
				if [[ "$1" =~ "type=keygen" ]]; then
					return 0
				fi
				
				date +"%T Invalid Credentials. Exiting..." >&2
				return 1
			fi
		fi
	elif [[ $(echo "$CURL" | xmlstarlet sel -t -v "/response/result/msg" 2>/dev/null) == "Please change your password." ]]; then
		if (( CURLER_EVALS_2 < 2 )); then
			date +"%T Password change required." >&2
			passwordChange || return 1
			
			# Try again after password change function was successful
			
			(( CURLER_EVALS_2++ ))
			RETRYING_CURLER=1
			continue
		else
			date +"%T Password change attempt failed. Exiting..." >&2
			return 1
		fi
	elif [[ "$CURL" == "###BKND_WAIT###" ]] || [[ $(echo "$CURL" | xmlstarlet sel -t -v "/response/result/msg" 2>/dev/null) =~ .*Transport\ endpoint\ is\ not\ connected.* ]]; then
		
		if [[ "$PLATFORM" =~ ^[0-9]+$ ]] && (( PLATFORM < 800 )) && (( ( SECONDS - CURLER_SECONDS_3 ) > 2700 )); then
			date +"%T Management server not up after 45 minutes. Exiting..." >&2
			return 1
		else
			if (( ( SECONDS - CURLER_SECONDS_3 ) > 900 )); then
				date +"%T Management server not up after 15 minutes. Exiting..." >&2
				return 1
			fi
		fi
		
		# Try again until the firewall wakes up from booting
		
		date +"%T Management server not fully up yet. Retrying in 10 seconds..." >&2
		sleep 10
		CURLER_SECONDS_3=$SECONDS
		continue
	elif [[ $(echo "$CURL" | xmlstarlet sel -t -v "/response/msg/line" 2>/dev/null) =~ .*No\ update\ information\ available.* ]]; then
		date +"%T No software is currently available on the firewall." >&2
		return 1
	elif [[ $(echo "$CURL" | xmlstarlet sel -t -v "/response/msg/line" 2>/dev/null) =~ .*Command\ succeeded\ with\ no\ output.* ]]; then
		echo "Command succeeded with no output" >&2
		return 0
	elif [[ $(echo "$CURL" | xmlstarlet sel -t -v "/response/@code" 2>/dev/null) == "22" ]] && (( API_SESS_RETRY == 0 )); then
		date +"%T API session timeout. Retrying once..." >&2
		API_SESS_RETRY=1
		continue
	elif [[ $(echo "$CURL" | xmlstarlet sel -t -v "/response/@status" 2>/dev/null) != "success" ]]; then
		date +"%T Firewall return status unsuccessful" >&2
		echo "Response:" >&2
		echo "$CURL" >&2
		if [[ "$CURL" =~ .*set\ system\ ztp\ disable.* ]]; then
			echo "ZTP detected" >&2
			return 3
		fi
		if [[ "$CURL" =~ .*Resource\ temporarily\ unavailable.* ]] && [[ "$1" =~ type\=import ]]; then
			echo "Resource temporarily unavailable"
			return 0
		fi
		return 1
	else
		date +"%T Unspecified error in API response. Error:" >&2
		echo "$CURL" >&2
		date +"%T Exiting..." >&2
		return 1
	fi
done

}

##########################################################################################################################################################################################
# Ensures autocommit has finished after reboots
##########################################################################################################################################################################################

checkAutoCom(){

local AUTOCOM_STATUS
local RAW_RESPONSE
local FAILURE_REASON
SECONDS=0
local KEEPALIVE
KEEPALIVE=$(( SECONDS + 60 ))
while (( SECONDS < 1800 ))
do
	RAW_RESPONSE=$(curler "https://${1}/api/?type=op&cmd=<show><jobs><all></all></jobs></show>" " " 10 " " " " "raw") || return 1
	
	JOB_AMOUNT=$(echo "$RAW_RESPONSE" | xmlstarlet sel -t -c "count(/response/result/job)" 2>/dev/null)
	
	AUTOCOM_STATUS=$(echo "$RAW_RESPONSE" | xmlstarlet sel -t -m "/response/result/job[type='AutoCom']" -v result 2>/dev/null)
	if [[ "$AUTOCOM_STATUS" =~ "OK" ]]; then
		JUST_REBOOTED=0
		return 0
		# This show command goes up to 29 jobs and then hides older jobs, including the autocommit. We assume it completed.
	elif [[ "$AUTOCOM_STATUS" == "" ]] && (( JOB_AMOUNT > 28 )); then
		JUST_REBOOTED=0
		return 0
	elif [[ "$AUTOCOM_STATUS" =~ "FAIL" ]] && (( NON_INTERACTIVE == 1 )); then
		# The autocommit failed for whatever reason (could be OKOKFAILOKOK so use regex)
		FAILURE_REASON=$(echo "$RAW_RESPONSE" | xmlstarlet sel -t -m "/response/result/job[type='AutoCom']" -n -v details 2>/dev/null)
		echo "Autocommit is failing with reason:" >&2
		echo "$FAILURE_REASON" >&2
		if (( IGNORE_ERRORS == 1 )); then
			echo "Attempting to continue the activity due to -i flag" >&2
			JUST_REBOOTED=0
			return 0
		else
			echo "Exiting due to running in non-interactive mode and -i flag not set." >&2
			return 1
		fi
	elif [[ "$AUTOCOM_STATUS" =~ "FAIL" ]]; then
		FAILURE_REASON=$(echo "$RAW_RESPONSE" | xmlstarlet sel -t -m "/response/result/job[type='AutoCom']" -n -v details 2>/dev/null)
		echo "The autocommit is failing. Failure reason:" >&2
		beepbeep
		echo "$FAILURE_REASON" >&2
		if (( IGNORE_ERRORS == 1 )); then { echo "Attempting to continue the activity due to -i flag" >&2; JUST_REBOOTED=0; return 0; }; fi
		echo "Continue the activity anyway?" >&2
		while true; do
			read yn
			case $yn in
				[Yy]* ) echo "Attempting to continue the activity..." >&2; JUST_REBOOTED=0; return 0;;
				[Nn]* ) echo "Stopping the activity." >&2; return 1;;
				* ) echo "Please answer yes or no.";;
			esac
		done
	else
		date +"%T Autocommit not finished. Checking again in 10 seconds..." >&2
		sleep 4
		if (( SECONDS >= KEEPALIVE )); then
			if [[ "$ACTIVITY" == "Upgrade" ]]; then
				date +"%T Current step: ${MAJOR_CUR} -> ${MAJOR_NEXT}, retrying for ${SECONDS}/1800 seconds..." >&2
			elif [[ "$ACTIVITY" == "Downgrade" ]]; then
				date +"%T Current step: ${MAJOR_CUR} -> ${MAJOR_PREV}, retrying for ${SECONDS}/1800 seconds..." >&2
			fi
			KEEPALIVE=$(( SECONDS + 60 ))
		fi
		sleep 5
		continue
	fi
done

echo "Autocommit not successful after 30 minutes. Exiting..." >&2
return 1

}

##########################################################################################################################################################################################
# Returns 0 if firmware file is already present on the firewall
##########################################################################################################################################################################################

checkFirmwarePresent(){

# Look for presence, downloaded == yes, and file size > 0 kb

local FIRMWARE_STATUS
FIRMWARE_STATUS=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<request><system><software><info></info></software></system></request>" " " 10 " " " " "raw") || return 1
DOWNLOADED_STATUS=$(echo "$FIRMWARE_STATUS" | xmlstarlet sel -t -m "/response/result/sw-updates/versions/entry[filename=\"$1\"]" -v downloaded 2>/dev/null)
if [[ "$DOWNLOADED_STATUS" != "yes" ]]; then
	return 1
fi
FIRMWARE_STATUS=$(echo "$FIRMWARE_STATUS" | xmlstarlet sel -t -m "/response/result/sw-updates/versions/entry[filename=\"$1\"]" -v size-kb 2>/dev/null)
if [[ "$FIRMWARE_STATUS" == "" ]]; then
	return 1
elif ! [[ "$FIRMWARE_STATUS" =~ ^[0-9]+$ ]]; then
	return 1
elif (( FIRMWARE_STATUS > 0 )); then
	return 0
else
	return 1
fi

}

##########################################################################################################################################################################################
# Returns 0 if content file is already present on the firewall
##########################################################################################################################################################################################

checkContentPresent(){

# Look for presence and file size > 0 kb

local CONTENT_STATUS
CONTENT_STATUS=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<request><content><upgrade><info></info></upgrade></content></request>" " " 10 " " " " "raw") || return 1
CONTENT_STATUS=$(echo "$CONTENT_STATUS" | xmlstarlet sel -t -m "/response/result/content-updates/entry[filename=\"$1\"]" -v size-kb 2>/dev/null)
if [[ "$CONTENT_STATUS" == "" ]]; then
	return 1
elif ! [[ "$CONTENT_STATUS" =~ ^[0-9]+$ ]]; then
	return 1
elif (( CONTENT_STATUS > 0 )); then
	return 0
else
	return 1
fi

}

##########################################################################################################################################################################################
# Uploads and installs Antivirus packages
##########################################################################################################################################################################################

upgradeAntivirus(){
	
	if (( DRY_RUN == 1 )); then
		
		FILE_PATH=$(find "$SOFTWARE_FOLDER" -name "$1")
		if [[ "$FILE_PATH" == "" ]]; then
			date +"%T Antivirus file $1 not found. Exiting..." >&2
			return 1
		fi
		date +"%T Would upload and install $FILE_PATH now" >&2
		return 0
	fi
	
	FILE_PATH=$(find "$SOFTWARE_FOLDER" -name "$1")
	
	if [[ "$FILE_PATH" == "" ]]; then
		date +"%T Image file $1 not found. Exiting..." >&2
		return 1
	fi
	
	# Proceed with uploading the file
	
	checkAutoCom "$FIREWALL_ADDRESS" || return 1
	
	local RESULT_CUPLOAD_1
	RESULT_CUPLOAD_1=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" "/response/@status" 10) || return 1
	
	if [[ "$RESULT_CUPLOAD_1" != "success" ]]; then
		date +"%T Firewall not up while preparing to upload antivirus. Exiting..." >&2
		return 1
	fi
	
	date +"%T Firewall at ${FIREWALL_ADDRESS} is now up. Uploading antivirus..." >&2
	
	local RESULT_CUPLOAD_2
	SILENT_CURL=""
	RESULT_CUPLOAD_2=$(curler "https://${FIREWALL_ADDRESS}/api/?type=import&category=anti-virus" "/response/@status" 300 "-F" "file=@${FILE_PATH}") || { SILENT_CURL="-s"; return 1; }
	SILENT_CURL="-s"
	
	# Proceed with installing the file
	
	if (( DRY_RUN == 1 )); then
		date +"%T Would install $1 now" >&2
		return 0
	fi
	
	local JOB_ID_AV
	
	JOB_ID_AV=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<request><anti-virus><upgrade><install><file>$1</file></install></upgrade></anti-virus></request>" "/response/result/job" 30) || return 1
	
	date +"%T Installing antivirus $1 on device ${FIREWALL_ADDRESS}. Job ID is ${JOB_ID_AV}." >&2
	
	local t
	t=0
	local JOB_STATUS_AV
	local JOB_STATUS_AV_RESULT
	local JOB_STATUS_AV_MSG
	local JOB_STATUS_AV_PROGRESS
	local JOB_STATUS_AV_PROGRESS_1
	JOB_STATUS_AV=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><jobs><id>${JOB_ID_AV}</id></jobs></show>" " " 10 " " " " "raw") || return 1
	JOB_STATUS_AV_RESULT=$(echo "$JOB_STATUS_AV" | xmlstarlet sel -t -v "/response/result/job/result" 2>/dev/null)
	while [[ "$JOB_STATUS_AV_RESULT" != "OK" ]];
	do
		if [[ "$JOB_STATUS_AV_RESULT" == "FAIL" ]]; then
			JOB_STATUS_AV_MSG=$(echo "$JOB_STATUS_AV" | xmlstarlet sel -t -v "/response/result/job/details/line" 2>/dev/null)
			date +"%T Antivirus $1 installation failed with reason: \"${JOB_STATUS_AV_MSG}\". Exiting..." >&2
			return 1
		fi
		((t++))
		sleep 5
		if (( t > 540 )); then
			date +"%T Firewall ${FIREWALL_ADDRESS} antivirus $1 installation not complete after 45 minutes. Exiting..." >&2
			return 1
		fi
		JOB_STATUS_AV=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><jobs><id>${JOB_ID_AV}</id></jobs></show>" " " 10 " " " " "raw") || return 1
		JOB_STATUS_AV_RESULT=$(echo "$JOB_STATUS_AV" | xmlstarlet sel -t -v "/response/result/job/result" 2>/dev/null)
		JOB_STATUS_AV_PROGRESS=$(echo "$JOB_STATUS_AV" | xmlstarlet sel -t -v "/response/result/job/progress" 2>/dev/null)
		if [[ "$JOB_STATUS_AV_PROGRESS" != "$JOB_STATUS_AV_PROGRESS_1" ]]; then
			if [[ "$JOB_STATUS_AV_PROGRESS" =~ ^[0-9]+$ ]]; then
				date +"%T Firewall ${FIREWALL_ADDRESS} antivirus installation is $JOB_STATUS_AV_PROGRESS percent complete." >&2
				JOB_STATUS_AV_PROGRESS_1="$JOB_STATUS_AV_PROGRESS"
			elif [[ "$JOB_STATUS_AV_PROGRESS" =~ ^[0-9\:]+$ ]]; then
				date +"%T Firewall ${FIREWALL_ADDRESS} antivirus installation completed." >&2
				JOB_STATUS_AV_PROGRESS_1="$JOB_STATUS_AV_PROGRESS"
			fi
		fi
	done
	
	sleep 1
	
}


##########################################################################################################################################################################################
# Uploads license files
##########################################################################################################################################################################################

uploadLicenses(){
	
	# The function takes a serial number as argument and the second argument can optionally limit the upload to vm capacity license
	# License file format is $SERIAL-licensename.key
	
	local VM_REBOOTED=0
	local VM_REBOOT_RESULT
	
	# Results to array
	
	readarray -d '' licensearray < <(find "$SOFTWARE_FOLDER" -name "${1}-*.key" -print0)
	
	if (( ${#licensearray[@]} == 0 )); then
		date +"%T No license files with format \"${1}-*.key\" found. Exiting..." >&2
		return 1
	fi	
	
	if (( DRY_RUN == 1 )); then
		
		date +"%T Would upload licenses:" >&2
		printf '%s\n' "${licensearray[@]}"
		return 0
	fi
	
	# Proceed with uploading the files
	
	checkAutoCom "$FIREWALL_ADDRESS" || return 1
	
	local RESULT_CUPLOAD_1
	RESULT_CUPLOAD_1=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" "/response/@status" 10) || return 1
	
	if [[ "$RESULT_CUPLOAD_1" != "success" ]]; then
		date +"%T Firewall not up while preparing to upload licenses. Exiting..." >&2
		return 1
	fi
	
	date +"%T Firewall at ${FIREWALL_ADDRESS} is now up. Uploading licenses..." >&2
	
	local RESULT_CUPLOAD_2
	SILENT_CURL=""
	for i in "${licensearray[@]}"
	do
		if [[ "$2" == "vm_capacity_only" ]] && ! [[ "$i" =~ pa\-vm\.key ]]; then
			# Only install vm capacity license
			continue
		fi
		RESULT_CUPLOAD_2=$(curler "https://${FIREWALL_ADDRESS}/api/?type=import&category=license" "/response/@status" 300 "-F" "file=@${i}") || { if (( $? == 2 )); then VM_REBOOTED=1; else SILENT_CURL="-s"; return 1; fi; }
		if (( VM_REBOOTED == 1 )); then
			SILENT_CURL="-s"
			date +"%T The VM is rebooting to apply the capacity license. If hardware requirements are not met, the VM may enter maintenance mode."
			date +"%T Waiting up to 15 minutes for the reboot to complete."
			sleep 240
			# Use keygen to receive expired password notifications
			ESCAPED_PASS=$(echo "$ACTIVE_PASSWORD" | sed -r 's/(\{|\}|\[|\])/\\\1/g')
			VM_REBOOT_RESULT=$(curler "https://${FIREWALL_ADDRESS}/api/?type=keygen&user=${USERNAME}&password=${ESCAPED_PASS}" "/response/@status" 660) || VM_REBOOT_RESULT=$(curler "https://${FIREWALL_ADDRESS}/api/?type=keygen&user=${USERNAME}&password=${ESCAPED_PASS}" "/response/@status" 660) || endbeep
			if [[ "$VM_REBOOT_RESULT" != "success" ]]; then
				date +"%T VM capacity upgrade unsuccessful. Exiting..."
				return 1
			else
				sleep 10
				checkAutoCom "$FIREWALL_ADDRESS" || return 1
				date +"%T VM capacity upgrade complete. Uploading the remaining licenses."
			fi
		fi
		date +"%T Successfully uploaded license ${i}"
		sleep 1
	done
	
	SILENT_CURL="-s"
	
}

##########################################################################################################################################################################################
# Upload and load config
##########################################################################################################################################################################################

loadConfig(){
	
	# The function takes a serial number as argument
	# Config file format is $SERIAL-config.xml
	
	FILE_PATH=$(find "$SOFTWARE_FOLDER" -name "${1}-config.xml")
	if [[ "$FILE_PATH" == "" ]]; then
		date +"%T No config file with format \"${1}-config.xml\" found. Exiting..." >&2
		return 1
	fi
	
	if (( DRY_RUN == 1 )); then
		date +"%T Would upload config file $FILE_PATH now" >&2
		return 0
	fi
	
	# Proceed with uploading the files
	
	checkAutoCom "$FIREWALL_ADDRESS" || return 1
	
	local RESULT_CUPLOAD_1
	RESULT_CUPLOAD_1=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" "/response/@status" 10) || return 1
	
	if [[ "$RESULT_CUPLOAD_1" != "success" ]]; then
		date +"%T Firewall not up while preparing to upload config. Exiting..." >&2
		return 1
	fi
	
	date +"%T Firewall at ${FIREWALL_ADDRESS} is now up. Uploading config..." >&2
	
	local RESULT_CUPLOAD_2
	SILENT_CURL=""
	RESULT_CUPLOAD_2=$(curler "https://${FIREWALL_ADDRESS}/api/?type=import&category=configuration" "/response/@status" 300 "-F" "file=@${FILE_PATH}") || { SILENT_CURL="-s"; return 1; }
	SILENT_CURL="-s"
	
	# Try to load it
	
	local RESULT_CUPLOAD_3
	RESULT_CUPLOAD_3=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<load><config><from>${1}-config.xml</from></config></load>"  "/response/@status" 10) || return 1
	
	if [[ "$RESULT_CUPLOAD_3" != "success" ]]; then
		date +"%T Error loading config ${1}-config.xml to candidate on the firewall. Exiting..." >&2
		return 1
	fi
	
	date +"%T Config ${1}-config.xml successfully loaded to candidate on the firewall." >&2
	
	# Return config file for diffing
	
	echo "$FILE_PATH"
	
}

##########################################################################################################################################################################################
# Commits
##########################################################################################################################################################################################

commit(){
	
	if (( DRY_RUN == 1 )); then
		date +"%T Would commit the configuration now" >&2
		return 0
	fi
	
	local JOB_ID_COMMIT
	
	JOB_ID_COMMIT=$(curler "https://${FIREWALL_ADDRESS}/api/?type=commit&cmd=<commit></commit>" "/response/result/job" 30) || { if (( $? == 3 )); then return 2; else return 1; fi; }
		
	date +"%T Committing on device ${FIREWALL_ADDRESS}. Job ID is ${JOB_ID_COMMIT}." >&2
	
	local t
	t=0
	local JOB_STATUS_COMMIT
	local JOB_STATUS_COMMIT_RESULT
	local JOB_STATUS_COMMIT_MSG
	local JOB_STATUS_COMMIT_PROGRESS
	local JOB_STATUS_COMMIT_PROGRESS_1
	JOB_STATUS_COMMIT=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><jobs><id>${JOB_ID_COMMIT}</id></jobs></show>" " " 10 " " " " "raw") || return 1
	JOB_STATUS_COMMIT_RESULT=$(echo "$JOB_STATUS_COMMIT" | xmlstarlet sel -t -v "/response/result/job/result" 2>/dev/null)
	while [[ "$JOB_STATUS_COMMIT_RESULT" != "OK" ]];
	do
		if [[ "$JOB_STATUS_COMMIT_RESULT" == "FAIL" ]]; then
			JOB_STATUS_COMMIT_MSG=$(echo "$JOB_STATUS_COMMIT" | xmlstarlet sel -t -v "/response/result/job/details/line" 2>/dev/null)
			date +"%T Commit failed with reason: \"${JOB_STATUS_COMMIT_MSG}\". Exiting..." >&2
			return 1
		fi
		((t++))
		sleep 5
		if (( t > 90 )); then
			date +"%T Firewall ${FIREWALL_ADDRESS} commit not complete after 15 minutes. Exiting..." >&2
			return 1
		fi
		JOB_STATUS_COMMIT=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><jobs><id>${JOB_ID_COMMIT}</id></jobs></show>" " " 10 " " " " "raw") || return 1
		JOB_STATUS_COMMIT_RESULT=$(echo "$JOB_STATUS_COMMIT" | xmlstarlet sel -t -v "/response/result/job/result" 2>/dev/null)
		JOB_STATUS_COMMIT_PROGRESS=$(echo "$JOB_STATUS_COMMIT" | xmlstarlet sel -t -v "/response/result/job/progress" 2>/dev/null)
		if [[ "$JOB_STATUS_COMMIT_PROGRESS" != "$JOB_STATUS_COMMIT_PROGRESS_1" ]]; then
			if [[ "$JOB_STATUS_COMMIT_PROGRESS" =~ ^[0-9]+$ ]]; then
				date +"%T Firewall ${FIREWALL_ADDRESS} commit is $JOB_STATUS_COMMIT_PROGRESS percent complete." >&2
				JOB_STATUS_COMMIT_PROGRESS_1="$JOB_STATUS_COMMIT_PROGRESS"
			elif [[ "$JOB_STATUS_COMMIT_PROGRESS" =~ ^[0-9\:]+$ ]]; then
				date +"%T Firewall ${FIREWALL_ADDRESS} commit completed." >&2
				JOB_STATUS_COMMIT_PROGRESS_1="$JOB_STATUS_COMMIT_PROGRESS"
			fi
		fi
	done
	
}

##########################################################################################################################################################################################
# Checks for crashes on the firewall
##########################################################################################################################################################################################

healthChecks(){
	
	local SUCCESS_STREAK
	SUCCESS_STREAK=0
	
	date +"%T Checking process status on device ${FIREWALL_ADDRESS}..." >&2
	
	for i in {1..20};
	do
		unset SOFTWARE_STATUS
		
		if (( SUCCESS_STREAK > 4 )); then
			date +"%T All firewall processes are now running correctly." >&2
			return 0
		fi
		
		SOFTWARE_STATUS=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><software><status></status></software></system></show>" "/response/result" 10) || return 1
		# Check for not running
		SOFTWARE_STATUS=$(echo "$SOFTWARE_STATUS" | grep -E '(Process|Group)')
		SOFTWARE_STATUS=$(echo "$SOFTWARE_STATUS" | grep -v "running")
		
		if [[ "$SOFTWARE_STATUS" == "" ]]; then
			(( SUCCESS_STREAK++ ))
		else
			SUCCESS_STREAK=0
			date +"%T WARNING: found processes not running on ${FIREWALL_ADDRESS} (checking again in 1 seconds):" >&2
			date +"%T ${SOFTWARE_STATUS}" >&2
		fi
		sleep 1
	done
	
	date +"%T ERROR: some processes not up after 20 seconds." >&2
	return 1
	
}

##########################################################################################################################################################################################
# Main script
##########################################################################################################################################################################################

JUST_STARTED=1
JUST_REBOOTED=0
PATH_DIAMETER=0

# Set to "" to output curl stats in curler()
SILENT_CURL="-s"

if ! command -v xmlstarlet &> /dev/null; then
    echo "This script requires xmlstarlet to be installed. Try with \"sudo apt install xmlstarlet\". Exiting..."
	beepbeep
	echo "---FAILED---"
	exit 1
fi

if ! command -v curl &> /dev/null; then
    echo "This script requires curl to be installed. Try with \"sudo apt install curl\". Exiting..."
	beepbeep
	echo "---FAILED---"
	exit 1
fi

if (( DEBUG == 1 )); then
	set -x
fi

if (( EASY == 1 )); then
	if [[ "$LAZY" || "$NON_INTERACTIVE" || "$BATCH_MODE" ]]; then
		echo "Unsupported option combination with -e. Exiting..."
		beepbeep
		echo "---FAILED---"
		exit 1
	fi
fi

if (( NON_INTERACTIVE == 1 )); then
	FIREWALL_ADDRESS="$1"
	USERNAME="$2"
	ACTIVE_PASSWORD="$3"
	SOFTWARE_FOLDER="$4"
	DESIRED_VERSION="$5"
	NETWORK_INTERFACE="$6"
	
	# Check that optargs were passed to the script
	
	if (( INSTALL_THREATS == 1 )) && [[ "$THREAT_FILENAME" == "" ]]; then { echo "Threat file name was not passed to the script. Exiting..."; endbeep; }; fi
	if (( INSTALL_THREATS == 1 )) && [[ "$ANTIVIRUS_FILENAME" == "" ]]; then { echo "Antivirus file name was not passed to the script. Exiting..."; endbeep; }; fi
	if (( SET_PRA_AUTHKEY == 1 )) && [[ "$PANORAMA_AUTHKEY" == "" ]]; then { echo "Panorama authkey was not passed to the script. Exiting..."; endbeep; }; fi
	
	if [[ "$7" != "" ]]; then { echo "Too many arguments. Exiting..."; endbeep; }; fi
	
	if (( BATCH_MODE != 1 )); then
		# Don't need FIREWALL_ADDRESS in batch mode
		if ! [[ "$FIREWALL_ADDRESS" =~ ^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$ ]]; then
			if ! [[ "$FIREWALL_ADDRESS" =~ : ]]; then
				echo "Invalid IPv4 address. Exiting..."
				echo "---FAILED---"
				exit 1
			fi
		fi
	fi
	
	if (( INSTALL_CONFIG == 1 )); then
		echo "########### WARNING ###########"
		echo "You have selected to commit a custom configuration file after the upgrade."
	fi
	
else
	if (( BATCH_MODE != 1 )); then
		
		echo "Please input the Palo Alto's address:"
		
		read -r FIREWALL_ADDRESS
		
		if ! [[ "$FIREWALL_ADDRESS" =~ ^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$ ]]; then
			echo "Invalid IPv4 address. Exiting..."
			beepbeep
			exit 1
		fi
		
		echo "Please input Username:"
		
		read -r USERNAME
		
		if [[ "$USERNAME" == "" ]]; then
			echo "Invalid username. Exiting..."
			beepbeep
			exit 1
		fi
		
		echo "Please input Password:"
		
		read -r -s ACTIVE_PASSWORD
		
		if [[ "$ACTIVE_PASSWORD" == "" ]]; then
			echo "Invalid password. Exiting..."
			beepbeep
			exit 1
		fi
	fi
	
	echo "Please input the base firmware folder path without quoting or escaping spaces (/example/folder/, may contain subfolders). If the files are in the same folder as the script, just press ENTER:"
	
	read -r SOFTWARE_FOLDER
	
	if [[ "$SOFTWARE_FOLDER" == "" ]]; then
		SOFTWARE_FOLDER="./"
	fi
	
	if (( EASY != 1 )); then
		printf "\n\n\nPlease input the desired software release:\n\n\n"

		read -r DESIRED_VERSION
	fi
	
	if (( EASY == 1 )); then
		echo "Enter the file names that will be installed in order, separated by a space. Enter a capital \"R\" to indicate a reboot step, e.g:"
		echo "PanOS_800-9.1.9 PanOS_800-10.0.0 R PanOS_800-10.1.0 PanOS_800-10.1.4 R"
		echo "All filenames must be original as downloaded from the support website."
		
		# To array
		read -a EASY_PATH
		
		for i in "${EASY_PATH[@]}"
		do
			if ! [[ "$i" =~ $EASY_REGEX ]] && [[ "$i" != "R" ]]; then
				echo "Unexpected filename format for entry ${i}, unable to extract version. Custom filenames are not supported in this mode. Exiting..."
				beepbeep
				exit 1
			fi
		done
		
		echo "Enter the filename of the content file to install, otherwise press ENTER:"
		read -r EASY_CONTENT
	fi
	
	if (( INSTALL_THREATS == 1 )); then
		# The values can also come from getopts
		if [[ "$THREAT_FILENAME" == "" ]]; then
			echo "Enter the App&Threat file name that will be installed at the end of the upgrade procedure:"
			read -r THREAT_FILENAME
		fi
		if [[ "$ANTIVIRUS_FILENAME" == "" ]]; then
			echo "Enter the Antivirus file name that will be installed at the end of the upgrade procedure:"
			read -r ANTIVIRUS_FILENAME
		fi
	fi
	
	if (( SET_PRA_AUTHKEY == 1 )) && [[ "$PANORAMA_AUTHKEY" == "" ]]; then
		echo "Enter the Panorama authkey that will be set on the firewalls:"
		read -r PANORAMA_AUTHKEY
	fi
	
	if (( INSTALL_CONFIG == 1 )); then
		echo "########### WARNING ###########"
		echo "You have selected to commit a custom configuration file after the upgrade. Press ENTER to confirm:"
		read
	fi
		
fi

TIME_START=$(date "+%s")

# Branch out for batch mode

if (( BATCH_MODE == 1 )); then

	if ! command -v ip &> /dev/null; then
		echo "This feature requires iproute2 to be installed. Try with \"sudo apt install iproute2\". Exiting..."
		beepbeep
		exit 1
	fi
	
	# The script takes too long to check every serial with JUST_REBOOTED==1
	
	JUST_REBOOTED=0
	LAST_REFRESH=1
	USERNAME="admin"
	ACTIVE_PASSWORD="admin"
	
	if ! (( BATCH_MAX < 1001 && BATCH_MAX > 0 )); then
		echo "Please configure a BATCH_MAX size lower than 1000. Exiting..."
		beepbeep
		exit 1
	fi
	
	if (( NON_INTERACTIVE == 0 )); then
		echo "Please input the name of your network interface:"
		read -r NETWORK_INTERFACE
	fi
	
	if [[ "$NETWORK_INTERFACE" == "" ]]; then
		echo "Invalid interface. Exiting..."
		beepbeep
		exit 1
	fi
	
	test -f /proc/net/if_inet6 || { echo "Please enable IPv6 to use batch mode. Exiting..."; beepbeep; exit 1; }
	
	if [[ "$(ip -6 addr list dev $NETWORK_INTERFACE scope link | grep fe80 2>/dev/null)" == "" ]]; then
		echo "Please configure an IPv6 link-local address on interface ${NETWORK_INTERFACE} to use batch mode. Exiting..."
		beepbeep
		exit 1
	fi
	
	if (( NON_INTERACTIVE == 0 )); then
		read -p "Upgrade only MAC addresses that contain a Palo Alto OUI? (Answer N to let the script attempt to upgrade any MAC addresses seen on the L2 broadcast domain) Y/N: " -n 1 -r
		if [[ $REPLY =~ ^[Yy]$ ]]
		then
			echo ""
			echo "Filtering by OUI..."
			OUI_FILTER=1
		else
			echo ""
			echo "Continuing without OUI filter..."
			OUI_FILTER=0
		fi
	else
		if [[ "$DISABLE_OUI" == "1" ]]; then
			OUI_FILTER=0
		else
			OUI_FILTER=1
		fi
	fi
	
	if (( NON_INTERACTIVE == 0 )); then
		read -p "Please ensure all firewalls have finished booting and press ENTER" -n 1 -random
	fi
	
	echo "Beginning autodiscovery..."
	sleep 1
	
	PING6_REPLIES=$(ping6 -L -c 10 ff02::1%"${NETWORK_INTERFACE}") || { echo "Autodiscovery failed, no devices up. Try reinserting the cable on the MGMT port to regenerate LL. Exiting..."; beepbeep; exit 1; }

	PING6_REPLIES=$(echo -e "$PING6_REPLIES" | grep -E "fe80:[a-fA-F0-9:]+" | sed -r "s/^.*(fe80:[^%]+).*\$/\1/g" | sort | uniq)
	
	PING6_REPLIES=($PING6_REPLIES)
	
	if (( OUI_FILTER == 1 )); then
		shopt -s nocasematch
		for i in "${PING6_REPLIES[@]}"
		do
			NDP_ENTRY=$(ip -6 neigh show dev "$NETWORK_INTERFACE" "$i")
			for j in "${OUI_LIST[@]}"
			do
				if [[ "$NDP_ENTRY" =~ $j ]]; then
					TEMP_ARRAY+=( "$i" )
					break
				fi
			done
		done
		PING6_REPLIES=( "${TEMP_ARRAY[@]}" )
		shopt -u nocasematch
	fi
	
	FOUND_ADDRESSES="${#PING6_REPLIES[@]}"
	
	if (( FOUND_ADDRESSES < 1 )); then
		echo "Autodiscovery failed, no suitable addresses found. Try reinserting the cable on the MGMT port to regenerate LL. Exiting..."
		beepbeep
		exit 1
	elif (( FOUND_ADDRESSES > BATCH_MAX )); then
		echo "The number of discovered addresses is ${FOUND_ADDRESSES}, which exceeds the configured maximum of ${BATCH_MAX}. Exiting..."
		beepbeep
		exit 1
	fi
	
	echo "Autodiscovery complete. Found $FOUND_ADDRESSES addresses."
	
	LOG_FILE="PaloVersionBatch.log"
	
	echo "" > "$LOG_FILE"
	
	SERIAL_ARRAY=()
	STATUS_ARRAY=()
	
	MAIN_OPTS="-lz"
	
	# Append the optional features
	
	if (( SHUTDOWN == 1 )); then MAIN_OPTS="${MAIN_OPTS}s"; fi
	if (( DRY_RUN == 1 )); then MAIN_OPTS="${MAIN_OPTS}d"; fi
	if (( UPLOAD_LICENSES == 1 )); then MAIN_OPTS="${MAIN_OPTS}k"; fi
	if (( INSTALL_CONFIG == 1 )); then MAIN_OPTS="${MAIN_OPTS}c"; fi
	if [[ "$CURL_CA_IGNORE" == "" ]]; then MAIN_OPTS="${MAIN_OPTS}q"; fi
	if (( IGNORE_ERRORS == 1 )); then MAIN_OPTS="${MAIN_OPTS}i"; fi
	if (( DEBUG == 1 )); then MAIN_OPTS="${MAIN_OPTS}x"; fi
	
	EXTRA_OPTS=()
	if (( SET_PRA_AUTHKEY == 1 )); then EXTRA_OPTS+=("-p $PANORAMA_AUTHKEY "); fi
	if (( INSTALL_THREATS == 1 )); then EXTRA_OPTS+=("-t $THREAT_FILENAME "); EXTRA_OPTS+=("-a $ANTIVIRUS_FILENAME "); fi
	
	# Bootstrap loop
	
	for i in "${PING6_REPLIES[@]}"
	do
		
		# Curler can call functions that use FIREWALL_ADDRESS
		
		FIREWALL_ADDRESS="[${i}]"
		
		# Use the keygen function twice to ensure we get password change notifications post 10.2 and try both passwords
		ESCAPED_PASS=""
		ESCAPED_PASS=$(echo "$ACTIVE_PASSWORD" | sed -r 's/(\{|\}|\[|\])/\\\1/g')
		curler "https://[${i}]/api/?type=keygen&user=${USERNAME}&password=${ESCAPED_PASS}" "/response/@status" 10 1>/dev/null || curler "https://[${i}]/api/?type=keygen&user=${USERNAME}&password=${ESCAPED_PASS}" "/response/@status" 10 1>/dev/null || endbeep
		
		SERIAL_1=$(curler "https://[${i}]/api/?type=op&cmd=<show><system><info></info></system></show>" "/response/result/system/serial" 60 2> "${i}".log) || { SERIAL_ARRAY+=( "$i" ); STATUS_ARRAY+=( "FAILED" ); date +"%T Firewall at $i init failed. Skipping..." >> "$LOG_FILE"; date +"%T Firewall at $i init failed. Skipping..."; echo "---FAILED---" >> "${i}.log"; continue; }
		
		if [[ "$SERIAL_1" == "" ]]; then
			SERIAL_ARRAY+=( "$i" )
			STATUS_ARRAY+=( "FAILED" )
			date +"%T Firewall at $i is not responding. Skipping..."
			date +"%T Firewall at $i is not responding. Skipping..." >> "$LOG_FILE"
			echo "---FAILED---" > "${i}.log"
			continue
		fi
		
		SERIAL_ARRAY+=( "$SERIAL_1" )
		
		date +"%T Starting job for firewall with serial number ${SERIAL_1}..."
		date +"%T Starting job for firewall with serial number ${SERIAL_1}..." >> "$LOG_FILE"
		
		# Launch the actual upgrade
		
		("$0" ${EXTRA_OPTS[@]} "$MAIN_OPTS" "[""$i""]" "$USERNAME" "$ACTIVE_PASSWORD" "$SOFTWARE_FOLDER" "$DESIRED_VERSION" "$NETWORK_INTERFACE" > "${SERIAL_1}.log" 2>&1 &)
		
		STATUS_ARRAY+=( "ACTIVE" )
		
		date +"%T Started job for firewall with serial number $SERIAL_1"
		date +"%T Started job for firewall with serial number $SERIAL_1" >> "$LOG_FILE"
		
	done
	
	date +"%T All discovered firewalls have begun upgrading/downgrading."
	date +"%T All discovered firewalls have begun upgrading/downgrading." >> "$LOG_FILE"
	
	TIME_BATCH_START=$(date "+%s")
	
	sleep 2
	
	DEVICES_FINISHED_PREV=0
	DEVICES_FAILED_PREV=0
	
	while true
	do
		
		# Refresh terminal size
		
		SEPARATOR=""
		SCREEN_COLS=0
		SCREEN_COLS=$(tput cols)
		if [[ "$SCREEN_COLS" =~ [0-9]+ ]]; then
			if (( SCREEN_COLS < 50 || SCREEN_COLS > 5000 )); then
				SCREEN_COLS=50
			fi
		else
			SCREEN_COLS=100
		fi
		
		for ((c=1;c<=SCREEN_COLS;c++))
		do
			SEPARATOR+="-"
		done
		
		SCREEN_LINES=0
		SCREEN_LINES=$(tput lines)
		if [[ "$SCREEN_LINES" =~ [0-9]+ ]]; then
			if (( SCREEN_LINES > 5000 )); then
				SCREEN_LINES=50
			fi
		else
			SCREEN_LINES=50
		fi
		
		if (( ( $(date "+%s") - TIME_BATCH_START ) > TIME_BATCH_MAX )); then
			date +"%T Batch jobs not done after $TIME_BATCH_MAX seconds. Exiting..."
			endbeep
		fi
		
		# Status update
		
		for position in "${!SERIAL_ARRAY[@]}"
		do
			if [[ "$(grep "\-\-\-FINISHED\-\-\-" "${SERIAL_ARRAY[$position]}.log" 2>/dev/null)" != "" ]]; then
				STATUS_ARRAY[$position]="FINISHED"
			elif [[ "$(grep "\-\-\-FAILED\-\-\-" "${SERIAL_ARRAY[$position]}.log" 2>/dev/null)" != "" ]]; then
				STATUS_ARRAY[$position]="FAILED"
			fi
		done
		
		# Counters update
		
		DEVICES_ACTIVE=0
		DEVICES_FINISHED=0
		DEVICES_FAILED=0
		
		for member in "${STATUS_ARRAY[@]}"
		do
			if [[ "$member" == "ACTIVE" ]]; then
				(( DEVICES_ACTIVE++ ))
			elif [[ "$member" == "FINISHED" ]]; then
				(( DEVICES_FINISHED++ ))
			elif [[ "$member" == "FAILED" ]]; then
				(( DEVICES_FAILED++ ))
			fi
		done
		
		if (( DEVICES_FINISHED_PREV != DEVICES_FINISHED )); then
			beepbeep
			DEVICES_FINISHED_PREV=$DEVICES_FINISHED
		fi
		if (( DEVICES_FAILED_PREV != DEVICES_FAILED )); then
			beepbeep
			DEVICES_FAILED_PREV=$DEVICES_FAILED
		fi
		
		# Print logs
		
		# Check how much space we have on screen to tail the actual logs
		
		TAIL_LINES=$(( ( ( SCREEN_LINES - 6 ) / FOUND_ADDRESSES ) - 2 - 1 ))
		
		tput clear
		
		if (( TAIL_LINES < 1 )); then
			
			# Just print serial number and ACTIVE/FINISHED/FAILED
			
			for (( s=0; s<FOUND_ADDRESSES; s++ ))
			do
			
				echo -n "${SERIAL_ARRAY[$s]}: ${STATUS_ARRAY[$s]}; "
			done
			
			echo ""
			echo "$SEPARATOR"
			echo "Total devices: $FOUND_ADDRESSES"
			echo "Active: $DEVICES_ACTIVE"
			echo "Finished: $DEVICES_FINISHED"
			echo "Failed: $DEVICES_FAILED"
			echo "$SEPARATOR"
		else		
			for position in "${!SERIAL_ARRAY[@]}"
			do
				echo "-------------------Device ${SERIAL_ARRAY[$position]} at ${PING6_REPLIES[$position]}-------------------"
				
				# Make sure the file exists
				
				if [[ -f "${SERIAL_ARRAY[$position]}.log" ]]; then
	
					# Remove bell characters or tailing the file will ding every time
					
					tail -n $TAIL_LINES "${SERIAL_ARRAY[$position]}.log" | sed "s/\x7//g"
				else
					date +"%T Log file not found."
				fi
				
				echo "$SEPARATOR"
				
			done
			
			echo "$SEPARATOR"
			echo "Total devices: $FOUND_ADDRESSES"
			echo "Active: $DEVICES_ACTIVE"
			echo "Finished: $DEVICES_FINISHED"
			echo "Failed: $DEVICES_FAILED"
			echo "$SEPARATOR"
		fi
		
		sleep 2
		
		if (( DEVICES_ACTIVE == 0 )); then
			if (( LAST_REFRESH == 1 )); then
				
				# Wait a bit to get complete results
				
				sleep 5
				LAST_REFRESH=0
				continue
			fi
			printf "\n\n"
			date +"%T All jobs in the batch have ended."
			echo "Total jobs: $DEVICES_ACTIVE"
			echo "Finished: $DEVICES_FINISHED"
			echo "Failed: $DEVICES_FAILED"
			TIME_END=$(date "+%s")
			TIME_TAKEN=$(( TIME_END - TIME_START ))
			echo -n "Total time taken: "
			TZ=UTC0 printf '%(%Hh %Mm %Ss)T\n' "$TIME_TAKEN"
			if [[ "$ACTIVE_PASSWORD" != "admin" ]]; then
				echo "WARNING: the default password may have changed to: ${ACTIVE_PASSWORD}"
			fi
			echo "Exiting..."
			break
		fi
		
	done
	beepbeep
	beepbeep
	exit 0
fi

# Set active password the first time to avoid constant password swap, as curler is usually called in a subshell
# Use the keygen function to ensure we get password change notifications post 10.2
ESCAPED_PASS=""
ESCAPED_PASS=$(echo "$ACTIVE_PASSWORD" | sed -r 's/(\{|\}|\[|\])/\\\1/g')
curler "https://${FIREWALL_ADDRESS}/api/?type=keygen&user=${USERNAME}&password=${ESCAPED_PASS}" "/response/@status" 10 1>/dev/null || endbeep

checkAutoCom "$FIREWALL_ADDRESS" || endbeep

PLATFORM=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" "/response/result/system/family" 10) || endbeep

# Get current version

CURRENT_VERSION=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" "/response/result/system/sw-version" 10) || endbeep

# Get serial number

SERIAL_NUMBER=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" "/response/result/system/serial" 10) || endbeep

# Check if version is supported

if (( EASY != 1 )); then
	versionPresent "$PLATFORM".csv "$DESIRED_VERSION" || endbeep
fi

# Deal with ZTP

if ! [[ "$CURRENT_VERSION" =~ ^[0-9]\.0\. ]]; then
	ZTP_ACTIVE=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><ztp><status></status></ztp></system></show>" "/response/result" 10) || endbeep
fi

if [[ "$ZTP_ACTIVE" =~ connect\ to\ ztp\ service ]]; then
	if (( ZTP_DISABLED == 1 )); then
		echo "ERROR: unable to disable ztp. Exiting..."
		endbeep
	fi
	echo "Firewall has ztp enabled. Attempting to disable..."
	curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<set><system><ztp><disable></disable></ztp></system></set>" "/response/@status" 10 || endbeep
	ZTP_DISABLED=1
	date +"%T Disabling ZTP. Waiting up to 15 minutes for the reboot to complete."
	sleep 240
	JUST_REBOOTED=1
	# Disabling ZTP causes a factory reset
	USERNAME="$FACTORY_USERNAME"
	if [[ "$ACTIVE_PASSWORD" != "$FACTORY_PASSWORD" ]]; then BACKUP_PASSWORD="$ACTIVE_PASSWORD"; ACTIVE_PASSWORD="$FACTORY_PASSWORD"; fi
	if ! (curler "https://${FIREWALL_ADDRESS}/api/?type=keygen&user=${USERNAME}&password=${ACTIVE_PASSWORD}" "/response/@status" 660); then
		date +"%T Disabling ZTP caused a factory reset. Resetting password..."
		if [[ "$ACTIVE_PASSWORD" != "$FACTORY_PASSWORD" ]]; then BACKUP_PASSWORD="$ACTIVE_PASSWORD"; ACTIVE_PASSWORD="$FACTORY_PASSWORD"; fi
		passwordChange || endbeep
		if [[ "$ACTIVE_PASSWORD" == "$FACTORY_PASSWORD" ]]; then ACTIVE_PASSWORD="$BACKUP_PASSWORD"; BACKUP_PASSWORD="$FACTORY_PASSWORD"; fi
	fi
	checkAutoCom "$FIREWALL_ADDRESS" || { date +"%T ZTP disable unsuccessful. Exiting..."; endbeep; }
	ZTP_REBOOTED=1
	date +"%T ZTP disable complete."
fi

# Serial must be valid for the following modes

if (( UPLOAD_LICENSES == 1 || INSTALL_CONFIG == 1 )) && [[ "$SERIAL_NUMBER" == "unknown" ]]; then
	if (( NON_INTERACTIVE == 1 )); then
		date +"%T ERROR: serial is unknown (unprovisioned VM?) and mode is non-interactive. Exiting..."
		endbeep
	else
		date +"Serial number is unknown (unprovisioned VM?). Please input the serial number associated with the license/config files and press ENTER:"
		read -r SERIAL_NUMBER
		if [[ "$PLATFORM" == "vm" ]]; then
			date +"%T The VM needs a capacity license for the upgrade. Attempting to install it..."
			# Limit install to vm capacity license
			uploadLicenses "$SERIAL_NUMBER" "vm_capacity_only" || endbeep
		fi
	fi
fi

###################################################################
# Easy mode loop
###################################################################

if (( EASY == 1 )); then
	# Set for courtesy messages
	ACTIVITY="Easy"
	if [[ "$EASY_CONTENT" != "" ]]; then
		upgradeEasyContent "$EASY_CONTENT" || { date +"%T --- ERROR --- Content upgrade failed. Exiting..."; endbeep; }
	fi
	for i in "${EASY_PATH[@]}"
	do
		if (( DRY_RUN == 1 )); then
			date +"%T WARNING: Dry run does not guarantee the upgrade path is correct in Easy Mode"
		else
			date +"%T Current version: ${CURRENT_VERSION}"
		fi
		# Set for courtesy messages
		MAJOR_CUR="$CURRENT_VERSION"
		# Extract version number
		if [[ "$i" != "R" ]]; then
			[[ "$i" =~ $EASY_REGEX ]]
			EASY_NEXT="${BASH_REMATCH[1]}"
			# Set for courtesy messages
			MAJOR_NEXT="$EASY_NEXT"
		fi
		if (( JUST_REBOOTED == 1 )); then
			# Wait for bootup
			BOOT_WAIT=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" "/response/result/system/sw-version" 3600)
			if (( $? == 4 )); then
				# Catch factory resets (admin/admin)
				if [[ "$ACTIVE_PASSWORD" != "$FACTORY_PASSWORD" ]]; then BACKUP_PASSWORD="$ACTIVE_PASSWORD"; ACTIVE_PASSWORD="$FACTORY_PASSWORD"; fi
				date +"%T Possible factory reset or password revert. Retrying default credentials"
				ESCAPED_PASS=""
				ESCAPED_PASS=$(echo "$FACTORY_PASSWORD" | sed -r 's/(\{|\}|\[|\])/\\\1/g')
				curler "https://${FIREWALL_ADDRESS}/api/?type=keygen&user=${FACTORY_USERNAME}&password=${ESCAPED_PASS}" "/response/@status" 10 1>/dev/null
			fi
			date +"%T Firewall appears to be up"
			CURRENT_VERSION=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" "/response/result/system/sw-version" 10) || endbeep
			MAJOR_CUR="$CURRENT_VERSION"
			checkAutoCom "$FIREWALL_ADDRESS" || endbeep
			healthChecks || { date +"%T --- ERROR --- Detected process errors on the firewall. Exiting..."; if (( IGNORE_ERRORS == 0 )); then endbeep; fi; }
			if [[ "$CURRENT_VERSION" != "" ]]; then
				JUST_REBOOTED=0
				beep
				
				# Refresh active password
				curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" "/response/@status" 10 1>/dev/null || endbeep
				
			fi
		fi
		
		if [[ "$i" == "R" ]]; then
			rebootSystem || endbeep
		else
			upload "$SOFTWARE_FOLDER" "$i" || endbeep
			install "$EASY_NEXT" || { if (( $? == 2 )) && [[ "$VERSION_RETRIED" != "$EASY_NEXT" ]]; then VERSION_RETRIED="$EASY_NEXT"; continue; else date +"%T Installation failed. Exiting..."; endbeep; fi; }
		fi
	done
	
	if (( JUST_REBOOTED == 1 )); then
		# Wait for final bootup
		BOOT_WAIT=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" "/response/result/system/sw-version" 3600)
			if (( $? == 4 )); then
				# Catch factory resets (admin/admin)
				if [[ "$ACTIVE_PASSWORD" != "$FACTORY_PASSWORD" ]]; then BACKUP_PASSWORD="$ACTIVE_PASSWORD"; ACTIVE_PASSWORD="$FACTORY_PASSWORD"; fi
				date +"%T Possible factory reset or password revert. Retrying default credentials"
				ESCAPED_PASS=""
				ESCAPED_PASS=$(echo "$FACTORY_PASSWORD" | sed -r 's/(\{|\}|\[|\])/\\\1/g')
				curler "https://${FIREWALL_ADDRESS}/api/?type=keygen&user=${FACTORY_USERNAME}&password=${ESCAPED_PASS}" "/response/@status" 10 1>/dev/null
			fi
			date +"%T Firewall appears to be up"
		CURRENT_VERSION=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" "/response/result/system/sw-version" 10) || endbeep
		checkAutoCom "$FIREWALL_ADDRESS" || endbeep
		healthChecks || { date +"%T --- ERROR --- Detected process errors on the firewall. Use the -i flag to ignore."; if (( IGNORE_ERRORS == 0 )); then endbeep; fi; }
		if [[ "$CURRENT_VERSION" != "" ]]; then
			JUST_REBOOTED=0
			beep
			
			# Refresh active password
			curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" "/response/@status" 10 1>/dev/null || endbeep
			
		fi
	fi
	
	date +"%T Successfully brought ${FIREWALL_ADDRESS} to version ${CURRENT_VERSION}."
	
	if (( UPLOAD_LICENSES == 1 )); then
		date +"%T Uploading licenses on ${FIREWALL_ADDRESS}"
		uploadLicenses "$SERIAL_NUMBER" || endbeep
	fi
	
	if (( INSTALL_THREATS == 1 )); then
		date +"%T Installing content $THREAT_FILENAME on ${FIREWALL_ADDRESS}"
		upgradeEasyContent "$THREAT_FILENAME" || endbeep
		
		date +"%T Installing antivirus $ANTIVIRUS_FILENAME on ${FIREWALL_ADDRESS}"
		upgradeAntivirus "$ANTIVIRUS_FILENAME" || endbeep
	fi
	
	if (( SET_PRA_AUTHKEY == 1 )); then
		if (( DRY_RUN == 1 )); then
			date +"%T Would set Panorama authkey ${PANORAMA_AUTHKEY} on ${FIREWALL_ADDRESS} now"
		else
			date +"%T Setting Panorama authkey ${PANORAMA_AUTHKEY} on ${FIREWALL_ADDRESS}"
			curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<request><authkey><set>${PANORAMA_AUTHKEY}</set></authkey></request>" "/response/@status" 10 || endbeep
		fi
	fi
	
	if (( INSTALL_CONFIG == 1 )); then
		date +"%T Uploading config on ${FIREWALL_ADDRESS}"
		CONFIG_FILE=$(loadConfig "$SERIAL_NUMBER") || endbeep
		date +"%T Config loaded successfully. Committing..."
		# Wait for processes
		sleep 30
		commit || { echo "WARNING: communication with the firewall lost after commit. Exiting..."; endbeep; }
		date +"%T Config committed successfully. Running diff between source file and new running config. Ideally this should be empty."
		NEW_RUNNING_CONFIG=$(curler "https://${FIREWALL_ADDRESS}/api/?type=config&action=show" " " 120 " " " " "raw") || endbeep
		date +"%T ################ SOURCE FILE VS RUNNING CONFIG DIFF ################"
		if (( DRY_RUN != 1 )); then diff "$CONFIG_FILE" <(echo "$NEW_RUNNING_CONFIG"); else echo "DRY RUN"; fi
		date +"%T #############################################################"
		# Free the memory
		unset NEW_RUNNING_CONFIG
		# Print show system info
		date +"%T ##################### SHOW SYSTEM INFO ######################"
		curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" " " 10 " " " " "raw" || endbeep
		date +"%T #############################################################"
	fi
	
	healthChecks || { date +"%T --- ERROR --- Detected process errors on the firewall. Use the -i flag to ignore."; if (( IGNORE_ERRORS == 0 )); then endbeep; fi; }
	
	if (( SHUTDOWN == 1 )); then
		date +"%T Shutting down firewall ${FIREWALL_ADDRESS}"
		shutdownSystem || endbeep
	fi
	TIME_END=$(date "+%s")
	TIME_TAKEN=$(( TIME_END - TIME_START ))
	echo -n "Total time taken: "
	TZ=UTC0 printf '%(%Hh %Mm %Ss)T\n' "$TIME_TAKEN"
	beepbeep
	echo "---FINISHED---"
	exit 0
fi

###################################################################

if [[ "$CURRENT_VERSION" == "$DESIRED_VERSION" ]]; then
	date +"%T The required version is already installed."
	if (( UPLOAD_LICENSES == 1 )); then
		date +"%T Uploading licenses on ${FIREWALL_ADDRESS}"
		uploadLicenses "$SERIAL_NUMBER" || endbeep
	fi
	if (( INSTALL_THREATS == 1 )); then
		date +"%T Installing content $THREAT_FILENAME on ${FIREWALL_ADDRESS}"
		upgradeEasyContent "$THREAT_FILENAME" || endbeep
		
		date +"%T Installing antivirus $ANTIVIRUS_FILENAME on ${FIREWALL_ADDRESS}"
		upgradeAntivirus "$ANTIVIRUS_FILENAME" || endbeep
	fi
	if (( SET_PRA_AUTHKEY == 1 )); then
		if (( DRY_RUN == 1 )); then
			date +"%T Would set Panorama authkey ${PANORAMA_AUTHKEY} on ${FIREWALL_ADDRESS} now"
		else
			date +"%T Setting Panorama authkey ${PANORAMA_AUTHKEY} on ${FIREWALL_ADDRESS}"
			curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<request><authkey><set>${PANORAMA_AUTHKEY}</set></authkey></request>" "/response/@status" 10 || endbeep
		fi
	fi
	
	if (( INSTALL_CONFIG == 1 )); then
		date +"%T Uploading config on ${FIREWALL_ADDRESS}"
		CONFIG_FILE=$(loadConfig "$SERIAL_NUMBER") || endbeep
		date +"%T Config loaded successfully. Committing..."
		# Wait for processes
		sleep 30
		commit || { echo "WARNING: communication with the firewall lost after commit. Exiting..."; endbeep; }
		date +"%T Config committed successfully. Running diff between source file and new running config. Ideally this should be empty."
		NEW_RUNNING_CONFIG=$(curler "https://${FIREWALL_ADDRESS}/api/?type=config&action=show" " " 120 " " " " "raw") || endbeep
		date +"%T ################ SOURCE FILE VS RUNNING CONFIG DIFF ################"
		if (( DRY_RUN != 1 )); then diff "$CONFIG_FILE" <(echo "$NEW_RUNNING_CONFIG"); else echo "DRY RUN"; fi
		date +"%T #############################################################"
		# Free the memory
		unset NEW_RUNNING_CONFIG
		# Print show system info
		date +"%T ##################### SHOW SYSTEM INFO ######################"
		curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" " " 10 " " " " "raw" || endbeep
		date +"%T #############################################################"
	fi
	
	healthChecks || { date +"%T --- ERROR --- Detected process errors on the firewall. Use the -i flag to ignore."; if (( IGNORE_ERRORS == 0 )); then endbeep; fi; }
	
	if (( SHUTDOWN == 1 )); then
		date +"%T Shutting down firewall ${FIREWALL_ADDRESS}"
		shutdownSystem || endbeep
		beepbeep
		echo "---FINISHED---"
		exit 0
	fi
	beepbeep
	echo "---FINISHED---"
	exit 0
fi

MAJOR_CUR=$(majorOf "$PLATFORM".csv "$CURRENT_VERSION") || endbeep

MAJOR_REQ=$(majorOf "$PLATFORM".csv "$DESIRED_VERSION") || endbeep

# Check if upgrading or downgrading

ACTIVITY=$(majorCompare "$PLATFORM".csv "$CURRENT_VERSION" "$DESIRED_VERSION") || endbeep

date +"%T Starting activity: $ACTIVITY"

if [[ "$ACTIVITY" == "Error" ]]; then
	date +"%T Major version error. Exiting..."
	beepbeep
	echo "---FAILED---"
	exit 1
fi

while true
do
	# Count the reboots
	
	(( PATH_DIAMETER++ ))
	if (( PATH_DIAMETER > PATH_MAX )); then
		date +"%T Firewall reboots exceeded ${PATH_MAX}. Exiting to prevent loops..."
		endbeep
	fi

	# Re-check current version

	if (( DRY_RUN == 1 )); then
		if [[ "$WOULD_INSTALL" != "" ]]; then
			CURRENT_VERSION="$WOULD_INSTALL"
		fi
	else
		if (( JUST_REBOOTED == 1 )); then
			BOOT_WAIT=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" "/response/result/system/sw-version" 3600)
			if (( $? == 4 )); then
				# Catch factory resets (admin/admin)
				if [[ "$ACTIVE_PASSWORD" != "$FACTORY_PASSWORD" ]]; then BACKUP_PASSWORD="$ACTIVE_PASSWORD"; ACTIVE_PASSWORD="$FACTORY_PASSWORD"; fi
				date +"%T Possible factory reset or password revert. Retrying default credentials"
				ESCAPED_PASS=""
				ESCAPED_PASS=$(echo "$FACTORY_PASSWORD" | sed -r 's/(\{|\}|\[|\])/\\\1/g')
				curler "https://${FIREWALL_ADDRESS}/api/?type=keygen&user=${FACTORY_USERNAME}&password=${ESCAPED_PASS}" "/response/@status" 10 1>/dev/null
			fi
			date +"%T Firewall appears to be up"
			CURRENT_VERSION=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" "/response/result/system/sw-version" 10) || endbeep
			checkAutoCom "$FIREWALL_ADDRESS" || endbeep
			healthChecks || { date +"%T --- ERROR --- Detected process errors on the firewall. Use the -i flag to ignore."; if (( IGNORE_ERRORS == 0 )); then endbeep; fi; }
			if [[ "$CURRENT_VERSION" != "" ]]; then
				JUST_REBOOTED=0
				beep
				
				# Refresh active password
				
				curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" "/response/@status" 10 1>/dev/null || endbeep
				
			fi
		fi
	fi
	
	date +"%T Current version: ${CURRENT_VERSION}, target version: ${DESIRED_VERSION}"
	if [[ "$CURRENT_VERSION" == "$DESIRED_VERSION" ]]; then
		date +"%T Successfully ${ACTIVITY}d ${FIREWALL_ADDRESS} to version ${DESIRED_VERSION}."
		
		if (( UPLOAD_LICENSES == 1 )); then
			date +"%T Uploading licenses on ${FIREWALL_ADDRESS}"
			uploadLicenses "$SERIAL_NUMBER" || endbeep
		fi
		
		if (( INSTALL_THREATS == 1 )); then
			date +"%T Installing content $THREAT_FILENAME on ${FIREWALL_ADDRESS}"
			upgradeEasyContent "$THREAT_FILENAME" || endbeep
			
			date +"%T Installing antivirus $ANTIVIRUS_FILENAME on ${FIREWALL_ADDRESS}"
			upgradeAntivirus "$ANTIVIRUS_FILENAME" || endbeep
		fi
		
		if (( SET_PRA_AUTHKEY == 1 )); then
			if (( DRY_RUN == 1 )); then
				date +"%T Would set Panorama authkey ${PANORAMA_AUTHKEY} on ${FIREWALL_ADDRESS} now"
			else
				date +"%T Setting Panorama authkey ${PANORAMA_AUTHKEY} on ${FIREWALL_ADDRESS}"
				curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<request><authkey><set>${PANORAMA_AUTHKEY}</set></authkey></request>" "/response/@status" 10 || endbeep
			fi
		fi
		
		if (( INSTALL_CONFIG == 1 )); then
			date +"%T Uploading config on ${FIREWALL_ADDRESS}"
			CONFIG_FILE=$(loadConfig "$SERIAL_NUMBER") || endbeep
			date +"%T Config loaded successfully. Committing..."
			# Wait for processes
			sleep 30
			commit || { echo "WARNING: communication with the firewall lost after commit. Exiting..."; endbeep; }
			date +"%T Config committed successfully. Running diff between source file and new running config. Ideally this should be empty."
			NEW_RUNNING_CONFIG=$(curler "https://${FIREWALL_ADDRESS}/api/?type=config&action=show" " " 120 " " " " "raw") || endbeep
			date +"%T ################ SOURCE FILE VS RUNNING CONFIG DIFF ################"
			if (( DRY_RUN != 1 )); then diff "$CONFIG_FILE" <(echo "$NEW_RUNNING_CONFIG"); else echo "DRY RUN"; fi
			date +"%T #############################################################"
			# Free the memory
			unset NEW_RUNNING_CONFIG
			# Print show system info
			date +"%T ##################### SHOW SYSTEM INFO ######################"
			curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" " " 10 " " " " "raw" || endbeep
			date +"%T #############################################################"
		fi
		
		healthChecks || { date +"%T --- ERROR --- Detected process errors on the firewall. Use the -i flag to ignore."; if (( IGNORE_ERRORS == 0 )); then endbeep; fi; }
		
		if (( SHUTDOWN == 1 )); then
			date +"%T Shutting down firewall ${FIREWALL_ADDRESS}"
			shutdownSystem || endbeep
		fi
		TIME_END=$(date "+%s")
		TIME_TAKEN=$(( TIME_END - TIME_START ))
		echo -n "Total time taken: "
		TZ=UTC0 printf '%(%Hh %Mm %Ss)T\n' "$TIME_TAKEN"
		beepbeep
		echo "---FINISHED---"
		exit 0
	fi

	MAJOR_CUR=$(majorOf "$PLATFORM".csv "$CURRENT_VERSION") || endbeep
	
	# Re-check activity type in case there were extra reboots (install() returned 2) as it now could be a patching activity
	
	ACTIVITY=$(majorCompare "$PLATFORM".csv "$CURRENT_VERSION" "$DESIRED_VERSION") || endbeep
	
	if [[ "$ACTIVITY" == "Error" ]]; then
		date +"%T Major version error. Exiting..."
		beepbeep
		echo "---FAILED---"
		exit 1
	fi
	
	# Upgrade / Downgrade / Patch
	# The magic happens here

	case $ACTIVITY in

	Upgrade)

		# Check if target major has a higher content version requirement, and if so install it

		CURRENT_CONTENT_1=$(curler "https://${FIREWALL_ADDRESS}/api/?type=op&cmd=<show><system><info></info></system></show>" "/response/result/system/app-version" 10) || endbeep
		CURRENT_CONTENT_2=$(echo "$CURRENT_CONTENT_1" | cut -d '-' -f1)
		
		if (( DRY_RUN == 1 )); then
			if [[ "$WOULD_INSTALL_CONTENT" != "" ]]; then
				CURRENT_CONTENT_2="$WOULD_INSTALL_CONTENT"
			fi
		fi

		upgradeContent "$CURRENT_CONTENT_2" "$MAJOR_REQ" || date +"%T --- ERROR --- Content upgrade failed. Attempting software upgrade anyway..."
		
		if (( LAZY != 1 )); then
			
			# We install the latest patch as a best practice
	
			LATEST_PATCH_CUR=$(LatestPatchOf "$PLATFORM".csv "$MAJOR_CUR") || endbeep
	
			if [[ "$LATEST_PATCH_CUR" != "$CURRENT_VERSION" ]]; then
				
				# Fill MAJOR_NEXT for periodic status updates
				
				MAJOR_NEXT="$LATEST_PATCH_CUR"
				date +"%T Installing the most recent patch from ${MAJOR_CUR}..."
				FILE_NAME=$(fileName "$PLATFORM".csv "$LATEST_PATCH_CUR") || endbeep
				upload "$SOFTWARE_FOLDER" "$FILE_NAME" || endbeep
				
				# Return status 2 means the function rebooted the firewall as requested by PA, restart the loop to retry the install
				
				install "$LATEST_PATCH_CUR" || { if (( $? == 2 )) && [[ "$VERSION_RETRIED" != "$LATEST_PATCH_CUR" ]]; then VERSION_RETRIED="$LATEST_PATCH_CUR"; continue; else date +"%T Installation failed. Exiting..."; endbeep; fi; }
				rebootSystem || endbeep
				continue
			fi
		fi

		# Calculate and install base image for next major
		
		# Extra logic to deal with PAN-OS 9.2
		# PAN-OS 9.2 is a dead end, can only be accessed from 9.1
		
		if [[ "$MAJOR_CUR" == "9.1" && "$MAJOR_REQ" != "9.2" ]]; then
			
			# Must skip 9.2 to go to 10.0
			
			FEATURE_NEXT="10.0.0"
		else
			FEATURE_NEXT=$(nextFeature "$PLATFORM".csv "$CURRENT_VERSION") || endbeep
		fi
		
		# Check if the next major is the target
		
		MAJOR_NEXT=$(majorOf "$PLATFORM".csv "$FEATURE_NEXT") || endbeep
		if [[ "$MAJOR_NEXT" == "$MAJOR_REQ" ]]; then
		
			# If there are multiple feature releases for the target major and one of them is the final destination, skip the .0 version
			
			SKIP_BASE_UPGR=$(isFeature "$PLATFORM".csv "$DESIRED_VERSION") || endbeep
			if [[ "$SKIP_BASE_UPGR" == "Feature" ]]; then
				FEATURE_NEXT="$DESIRED_VERSION"
			fi
			
			# Upload and install feature release and patch release
			
			FILE_NAME=$(fileName "$PLATFORM".csv "$FEATURE_NEXT") || endbeep
			upload "$SOFTWARE_FOLDER" "$FILE_NAME" || endbeep
			install "$FEATURE_NEXT" || { if (( $? == 2 )) && [[ "$VERSION_RETRIED" != "$FEATURE_NEXT" ]]; then VERSION_RETRIED="$FEATURE_NEXT"; continue; else date +"%T Installation failed. Exiting..."; endbeep; fi; }

			# If no patches are required, we are done

			if [[ "$FEATURE_NEXT" == "$DESIRED_VERSION" ]]; then
				rebootSystem || endbeep
				continue
			fi

			# Else install the desired patch, and we are done

			FILE_NAME=$(fileName "$PLATFORM".csv "$DESIRED_VERSION") || endbeep
			upload "$SOFTWARE_FOLDER" "$FILE_NAME" || endbeep
			install "$DESIRED_VERSION" || { if (( $? == 2 )) && [[ "$VERSION_RETRIED" != "$DESIRED_VERSION" ]]; then VERSION_RETRIED="$DESIRED_VERSION"; continue; else date +"%T Installation failed. Exiting..."; endbeep; fi; }
			rebootSystem || endbeep
			continue
		fi

		# If there are other major steps, just install base image + the latest patch for that major

		if [[ "$MAJOR_NEXT" != "$MAJOR_REQ" ]]; then
			FILE_NAME=$(fileName "$PLATFORM".csv "$FEATURE_NEXT") || endbeep
			upload "$SOFTWARE_FOLDER" "$FILE_NAME" || endbeep
			install "$FEATURE_NEXT" || { if (( $? == 2 )) && [[ "$VERSION_RETRIED" != "$FEATURE_NEXT" ]]; then VERSION_RETRIED="$FEATURE_NEXT"; continue; else date +"%T Installation failed. Exiting..."; endbeep; fi; }
			
			# Lazy mode check
			
			if (( LAZY != 1 )); then			
				INSTALL_NEXT=$(LatestPatchOf "$PLATFORM".csv "$MAJOR_NEXT") || endbeep
				FILE_NAME=$(fileName "$PLATFORM".csv "$INSTALL_NEXT") || endbeep
				upload "$SOFTWARE_FOLDER" "$FILE_NAME" || endbeep
				install "$INSTALL_NEXT" || { if (( $? == 2 )) && [[ "$VERSION_RETRIED" != "$INSTALL_NEXT" ]]; then VERSION_RETRIED="$INSTALL_NEXT"; continue; else date +"%T Installation failed. Exiting..."; endbeep; fi; }
			fi
			rebootSystem || endbeep
			continue
		fi
		
		date +"%T Unknown error in upgrade loop. Exiting...."
		beepbeep
		echo "---FAILED---"
		exit 1

	;;

	Downgrade)

		# Find the feature release for the previous major
		
		# Extra logic to deal with PAN-OS 9.2
		# PAN-OS 9.2 is a dead end, can only be accessed from 9.1
		
		if [[ "$MAJOR_CUR" == "10.0" ]]; then
			
			# Must skip 9.2 to go to 9.1, or even 9.2
			
			FEATURE_PREV="9.1.0"
		else
			FEATURE_PREV=$(prevFeature "$PLATFORM".csv "$CURRENT_VERSION") || endbeep
		fi

		# Check if the previous major is the target
		MAJOR_PREV=$(majorOf "$PLATFORM".csv "$FEATURE_PREV") || endbeep
		if [[ "$MAJOR_PREV" == "$MAJOR_REQ" ]]; then

			# If there are multiple feature releases for the target major and one of them is the final destination, skip the .0 version
			
			SKIP_BASE_DOWNGR=$(isFeature "$PLATFORM".csv "$DESIRED_VERSION") || endbeep
			if [[ "$SKIP_BASE_DOWNGR" == "Feature" ]]; then
				FEATURE_PREV="$DESIRED_VERSION"
			fi
			
			# Upload and install feature release and patch release

			FILE_NAME=$(fileName "$PLATFORM".csv "$FEATURE_PREV") || endbeep
			upload "$SOFTWARE_FOLDER" "$FILE_NAME" || endbeep
			
			# Extra logic to deal with PAN-OS 10.2 downgrades
			# Must install 10.1.3 or superior first
			
			if [[ "$FEATURE_PREV" == "10.1.0" ]]; then
				# Install base image ignoring errors, so we know it's uploaded
				date +"%T Attempting 10.1.0 install to force image into software manager (see documentation regarding 10.2->10.1 downgrades)"
				install "$FEATURE_PREV"
				DOWNGR_1013_REGEX='^10\.1\.[0-2]$'
				if [[ "$DESIRED_VERSION" =~ ^10\.1\. ]] && ! [[ "$DESIRED_VERSION" =~ $DOWNGR_1013_REGEX ]]; then
					# Ultimate version is 10.1.3 or older so we can advance normally
					# Do nothing
					:
				else
					date +"%T Patching to 10.1.3 or later before downgrading (see documentation regarding 10.2->10.1 downgrades)"
					FEATURE_PREV=$(LatestPatchOf "$PLATFORM".csv "10.1") || endbeep
					if [[ "$FEATURE_PREV" =~ $DOWNGR_1013_REGEX ]]; then
						# We need at least 10.1.3 or later
						date +"%T Pan-OS 10.1.3 or later 10.1 patch not found (see documentation regarding 10.2->10.1 downgrades). Exiting..."
						beepbeep
						echo "---FAILED---"
						exit 1
					fi
					FILE_NAME=$(fileName "$PLATFORM".csv "$FEATURE_PREV") || endbeep
					upload "$SOFTWARE_FOLDER" "$FILE_NAME" || endbeep
					install "$FEATURE_PREV" || { if (( $? == 2 )) && [[ "$VERSION_RETRIED" != "$FEATURE_PREV" ]]; then VERSION_RETRIED="$FEATURE_PREV"; continue; else date +"%T Installation failed. Exiting..."; endbeep; fi; }
					rebootSystem || endbeep
					# The next cycle will use downgrade or patching logic as required
					continue
				fi
			else
				# Install base version as normal
				install "$FEATURE_PREV" || { if (( $? == 2 )) && [[ "$VERSION_RETRIED" != "$FEATURE_PREV" ]]; then VERSION_RETRIED="$FEATURE_PREV"; continue; else date +"%T Installation failed. Exiting..."; endbeep; fi; }
			fi
			
			# If no patches are required, we are done
			
			if [[ "$FEATURE_PREV" == "$DESIRED_VERSION" ]]; then
				rebootSystem || endbeep
				continue
			fi
			
			# Else install the desired patch, and we are done
			
			FILE_NAME=$(fileName "$PLATFORM".csv "$DESIRED_VERSION") || endbeep
			upload "$SOFTWARE_FOLDER" "$FILE_NAME" || endbeep
			install "$DESIRED_VERSION" || { if (( $? == 2 )) && [[ "$VERSION_RETRIED" != "$DESIRED_VERSION" ]]; then VERSION_RETRIED="$DESIRED_VERSION"; continue; else date +"%T Installation failed. Exiting..."; endbeep; fi; }
			rebootSystem || endbeep
			continue
		fi

		# If there are other major steps, just install and reboot with the base image

		if [[ "$MAJOR_PREV" != "$MAJOR_REQ" ]]; then
			FILE_NAME=$(fileName "$PLATFORM".csv "$FEATURE_PREV") || endbeep
			upload "$SOFTWARE_FOLDER" "$FILE_NAME" || endbeep

			# Extra logic to deal with PAN-OS 10.2 downgrades
			# Must install 10.1.3 or superior first
			
			if [[ "$FEATURE_PREV" == "10.1.0" ]]; then
				# Install base image ignoring errors, so we know it's uploaded
				date +"%T Attempting 10.1.0 install to force image into software manager (see documentation regarding 10.2->10.1 downgrades)"
				install "$FEATURE_PREV"
				DOWNGR_1013_REGEX='^10\.1\.[0-2]$'
				date +"%T Patching to 10.1.3 or later before downgrading (see documentation regarding 10.2->10.1 downgrades)"
				FEATURE_PREV=$(LatestPatchOf "$PLATFORM".csv "10.1") || endbeep
				if [[ "$FEATURE_PREV" =~ $DOWNGR_1013_REGEX ]]; then
					# We need at least 10.1.3 or later
					date +"%T Pan-OS 10.1.3 or later 10.1 patch not found (see documentation regarding 10.2->10.1 downgrades). Exiting..."
					beepbeep
					echo "---FAILED---"
					exit 1
				fi
				FILE_NAME=$(fileName "$PLATFORM".csv "$FEATURE_PREV") || endbeep
				upload "$SOFTWARE_FOLDER" "$FILE_NAME" || endbeep
				install "$FEATURE_PREV" || { if (( $? == 2 )) && [[ "$VERSION_RETRIED" != "$FEATURE_PREV" ]]; then VERSION_RETRIED="$FEATURE_PREV"; continue; else date +"%T Installation failed. Exiting..."; endbeep; fi; }
				rebootSystem || endbeep
				# The next cycle will use downgrade or patching logic as required
				continue
			else
				# Install base version as normal
				install "$FEATURE_PREV" || { if (( $? == 2 )) && [[ "$VERSION_RETRIED" != "$FEATURE_PREV" ]]; then VERSION_RETRIED="$FEATURE_PREV"; continue; else date +"%T Installation failed. Exiting..."; endbeep; fi; }
			fi
			
			rebootSystem || endbeep
			continue
		fi
		
		date +"%T Unknown error in downgrade loop. Exiting..."
		beepbeep
		echo "---FAILED---"
		exit 1
	;;

	Patch)

		# Install the desired patch, and we are done

		FILE_NAME=$(fileName "$PLATFORM".csv "$DESIRED_VERSION") || endbeep
		upload "$SOFTWARE_FOLDER" "$FILE_NAME" || endbeep
		install "$DESIRED_VERSION" || { if (( $? == 2 )) && [[ "$VERSION_RETRIED" != "$DESIRED_VERSION" ]]; then VERSION_RETRIED="$DESIRED_VERSION"; continue; else date +"%T Installation failed. Exiting..."; endbeep; fi; }
		rebootSystem || endbeep
		continue

	;;

	*)

		date +"%T Unknown error in patch loop. Exiting...."
		beepbeep
		echo "---FAILED---"
		exit 1

	;;

	esac

done
