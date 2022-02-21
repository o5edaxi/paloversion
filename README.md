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

### Usage

When run in its basic form, the script will ask the user for a firewall IP, a working username and password (with sufficient privileges) for the firewall, the desired version, as well as the top folder where the firmware images are located on the computer. It will then perform the entire upgrade procedure and exit.

**Important:** 2 extra csv files are required, namely one to indicate the details of the software images, and the other to indicate the minimum content version required by each major Pan-OS release. You may construct your own or extract JSON from the support site and run it through the included [Python script](json-extractor.py) to generate it (see **CSV Structure** below for more details).

Use the ```-h``` option to print these instructions to your terminal.

Available options:

```-d	dry-run```

Prints the necessary operations without performing any action on the firewall.

```-s	shutdown```

Shuts down the firewall after performing the upgrades.
	
```-l	lazy```
	
Skips installing the "latest" patches during upgrades (ie. skip 9.0.10 when going 9.0.0 -> 9.1.0)
	
```-x  debug```
	
Bash debug mode
	
```-f  factory-batch mode```
	
This mode will search for one or more firewalls on the same L2 broadcast domain as the host, and automatically upgrade them by using their IPv6 link-local address.
	
```-z  non-interactive mode```
	
Allows passing all input as arguments to the script (eg. ./paloversion.sh -l -z "192.0.2.1" "admin" "password" "/home/PA/Firmware/" "9.1.6")
	
```-m```
	
Disable checks for valid Palo Alto MAC addresses, attempts to upgrade all devices on the L2 broadcast domain (factory-batch mode only)

### Requirements

This script requires **curl**, **xmlstarlet**, and **iproute2** to function. Most modern systems will already have curl and iproute2 on board. Install xmlstarlet with **sudo apt install xmlstarlet**

The script has been tested with PanOS 7.1 all the way to 10.1 on several different platform families including 220, 400, 800, 3000, 3200, 5000, 5200, and vm.

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

