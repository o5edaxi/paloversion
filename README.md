# paloversion

### What this does

This shell script is primarily intended as a quick and easy way to upgrade Palo Alto firewalls. The intention was to meet the following goals:

* WSL and WSL2 support
* Do not require user intervention, in particular be able to manage upgrade paths, reboots, and content versions automatically
* Remain forward compatible with any changes Palo Alto might make to the upgrade process
* Require only HTTPS access to the firewall, and no outbound connections from the firewall (FTP, SCP, etc.). If you can access the firewall GUI, you can most likely use this script
* Use the firewall's XML API whenever possible
* Support integration into other scripts (see **-z** flag below)
* Support plug-and-play style upgrades of single and multiple firewalls at once, i.e. no previous configuration required on the firewall to make the script work, as well as IP address autodiscovery
* Develop a simple GUI for the Raspberry Pi + Touchscreen (see [paloversion-gui](https://github.com/o5edaxi/paloversion-gui))
* (Most importantly) work without an Internet connection or an active support license. **This script works by locating, validating, and uploading the firmware from your computer in a fully automated manner.**

### NEW in v1.4

**Threat, config, and license support allows the script to fully prepare a firewall or batch of firewalls for production automatically, without user intervention.**

* Automated Threat and Antivirus package installation
* Per-serial license file upload
* Panorama authkey setting
* Per-serial configuration upload and commit with final diffing and "show system info" printout
* cURL certificate validation
* Firewall process health check at each upgrade step
* Batch and EZ mode support for new features

### Usage

```Usage: paloversion.sh [ -hdsxkcpmiq ] [ -e | -lzf ] [ -t threat_file ] [ -a antivirus_file ] [ -p panorama_authkey ] [ -z fw_address user password files_folder target_version [ network_interface ] ]```

When run in its basic form, the script will ask the user for a firewall IP, a working username and password (with sufficient privileges) for the firewall, the desired version, as well as the top folder where the firmware images are located on the computer. It will then perform the entire upgrade procedure and exit.

**Important:** 2 extra csv files are required, namely one to indicate the details of the software images, and the other to indicate the minimum content version required by each major Pan-OS release. You may construct your own or extract JSON from the support site and run it through the included [Python script](json-extractor.py) to generate it (see **CSV Structure** below for more details). Use **Easy mode** to avoid the need for the csv files.

Available options:

```-h	help```

Displays these instructions

```-d	dry-run```

Outputs the operations without performing any action on the firewall

```-s	shutdown```

Shuts down the firewall after performing the upgrades
	
```-l	lazy```
	
Skips installing patches during upgrades (ie. skip 9.0.10 when going 9.0.0 -> 9.1.0)
	
```-e	easy```
	
Allows the user to list the upgrade steps and files manually, and doesn't check file hashes
	
```-x	debug```
	
Bash debug mode
	
```-f	factory-batch mode```
	
This mode will search for one or more firewalls on the same L2 broadcast domain as the host, and automatically upgrade them by using their IPv6 link-local address
	
```-k	licenses```
	
Install license files before starting upgrade
	
```-t	threats```
	
Install App&Threats packages after upgrade (requires -a flag)
	
```-a	antivirus```
	
Install Antivirus packages after upgrade (requires -t flag)
	
```-c	configuration```
	
Upload and commit a configuration after upgrade
	
```-p	panorama authkey```
	
Set a Panorama authkey after upgrade (10.1 and above)
	
```-z	non-interactive mode```
	
Requires all input as arguments to the script, e.g.:
paloversion.sh -p "2:12345AUTHKEY" -t "panupv2-all-contents-1234-5678" -a "panup-all-antivirus-1234-5678"  -lzc "192.0.2.1" "admin" "password" "/home/PA/Firmware/" "8.1.15-h3"

Arguments are mandatory according to the features selected.
	
```-m disable batch mode MAC filter```
	
Disable checks for valid Palo Alto MAC addresses, upgrades all firewalls on broadcast domain (requires -f)
	
```-q validate firewall certificates```
	
Enforces trusted CAs for every HTTPS connection
	
```-i ignore autocommit and process errors```
	
Autocommit/Process errors during upgrades and downgrades will not stop the activity


### Requirements

This script requires **curl**, **xmlstarlet**, and **iproute2** to function. Most modern systems will already have curl and iproute2 on board. Install xmlstarlet with **sudo apt install xmlstarlet**

The script has been tested with PanOS 7.1 all the way to 10.2 on several different platform families including 220, 400, 800, 3000, 3200, 5000, 5200, and vm.

### Easy mode

Using the **-e** flag the script can bypass all the upgrade logic and let the user define the upgrade path, including reboots and content packages. This is useful when you need to upgrade a firewall quickly but don't have time to set the csv files up. The script works out of the box in this mode.

You will be prompted to enter the file names that will be installed in order, separated by a space. Enter a capital \"R\" to indicate a reboot step, e.g:

```PanOS_800-9.1.9 R PanOS_800-10.0.0 R PanOS_800-10.1.0 PanOS_800-10.1.4 R```

All filenames must be original as downloaded from the support website to allow the script to extract the version.

### Licenses

License files are searched for recursively in the general firmware folder, and must be in the format $SERIAL_NUMBER-$LICENSE.key as downloaded from the CSP, e.g. "01234567890-support.key".
Run the script with a target version identical to the current version to quickly install licenses without upgrading.
Supports multiple firewalls in batch mode by placing one or more license files for each serial number.

### Threat and Antivirus

App&Threat and Anti-Virus packages are searched for recursively in the general firmware folder with the name specified at run time.
A content file must be set even if the content.csv file already specifies App&Threat packages.
Run the script with a target version identical to the current version to quickly install packages without upgrading.
Supports multiple firewalls in batch mode.

### Configuration files

Configuration files are searched for recursively in the general firmware folder, and must be in the format $SERIAL_NUMBER-config.xml, e.g. "01234567890-config.xml".
Run the script with a target version identical to the current version to quickly install a config file without upgrading.
Supports multiple firewalls in batch mode by placing a different config file for each serial number (similarly to firewall bootstrapping).
	
### Panorama authkeys

The authkey is inserted at run time, and when using batch mode must work for all firewalls in the batch.
Please note that 88 character authkeys are bugged for firewalls <10.1.3, so it is recommended to target a more recent version if onboarding to Panorama.
Run the script with a target version identical to the current version to quickly set authkeys without upgrading.
The script will exit if the firewall refuses the authkey.

### CSV Structure

* The **content.csv** file must look like [this](content.csv). This file informs the script about the minimum content version required by each major software release (in addition to how to find the files on disk), and must be kept updated accordingly. The script will automatically upgrade the content versions on the firewall based on this file, if needed. The content csv must have the following columns:

```
Major (e.g. 7.1),Content version (the first number in the file name),Name of the file that will be installed if the firewall does not meet the minimum content version requirement (e.g. "panupv2-all-apps-8513-7178"),SHA256 hash of the content (this must match the hash of the file on disk)
```

* The **software** csv must be a separate file for each platform and be named accordingly (for example **220.csv**, **5200.csv**, **vm.csv**). The file name corresponds to the "family" in the "show system info" output on the firewall, with a .csv extension. This file tells the script which release is older and which is newer, so that upgrade or downgrade steps can be derived accordingly. It also contains the name of the file on disk and the expected hash. If you already know which files you will need during your upgrade, you can limit the csv to only those files and the script will work fine. The software csv must have the following columns:

```
Line number (ascending, higher=newer),Version (e.g. 7.1.0),Major (e.g. 7.1),Release type ("Maintenance" or "Feature"),File name on disk (e.g. "PanOS_200-7.1.0"),SHA256 hash of the software (this must match the hash of the file on disk)
```

* [Example file](200.csv.example).

**You can generate up to date versions of the software files by logging into the PA support portal and heading to the Software Updates section. Next, open the browser's developer tools and copy the server response to the POST that the browser makes to "/api/contentupdates/GetContentUpdates" whenever you select a firewall family in the upper menu. Put the JSON text in a file called "input.json" and run the [Python script](json-extractor.py) found in this repo to generate up to date csv files for the corresponding platform.**

Place all csv files in the same folder as the script.

### Batch Mode

When used with this option, the script supports a crude autodiscovery functionality. It will ping the all-nodes multicast address and then start the upgrade process for any IP that responds. Terminal window space usage is optimized based on the number of batches running. A MAC OUI filter for Palo Alto Networks is also available to prevent unnecessary traffic in networks that contain other devices. All Palo Alto Networks firewalls generate a EUI-64 link-local IPv6 address by default, which means they are unique and can be used to access the GUI to configure the firewall.

**This mode does not work with WSL as it requires link-local access and layer 2 visibility of the network the firewalls are connected to.**

### License

This project is licensed under the [MIT License](LICENSE).

