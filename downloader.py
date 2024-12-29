import os
import re
import csv
import argparse
import sys
import hashlib
import xml.etree.ElementTree
from operator import itemgetter
from panos.firewall import Firewall
from panos.panorama import Panorama
from panos.errors import PanDeviceError
from panos.errors import PanDeviceXapiError

HASH_BUF_SIZE = 65536

parser = argparse.ArgumentParser(description='Create the software csv and download images for the paloversion script, '
                                             'using a Palo Alto firewall or Panorama that has Internet access and a valid '
                                             'support license. The firewall must have an SCP profile that connects it to '
                                             'the machine this tool is running on.')
parser.add_argument('device', type=str, help='Firewall or Panorama IP address or hostname')
parser.add_argument('scp_profile', type=str, help='Name of SCP Profile configured on firewall or Panorama')
parser.add_argument('api_key', type=str, help='Firewall or Panorama API Key')
parser.add_argument('-p', '--scp-path', action='store', type=str, default='.',
                    help='Where to find the firmware files exported from the device, to calculate the checksum. '
                    'Default: the script directory')
parser.add_argument('-v', '--firmware-regex', action='store', type=str, default='^PanOS_',
                    help='Regex to limit the script to certain firmware file names. Default: "^PanOS_"')
args = parser.parse_args()
dvc = Firewall(args.device, api_key=args.api_key)
platform = dvc.op('show system info').find('.//family').text
if platform == 'pc':
    dvc = Panorama(args.device, api_key=args.api_key)
    pc = True
    cmd_pra = 'batch'
    print("Device is a Panorama. Only firmware versions up to the Panorama's running major will be available.")
else:
    print('Device is a firewall.')
    pc = False
    cmd_pra = 'system'
response = dvc.op(f'request {cmd_pra} software check')
releases_dict_list = []
if not response.findall('.//sw-updates/versions/entry'):
    print('No releases found.')
    sys.exit(1)
for version in response.findall('.//sw-updates/versions/entry'):
    release = {}
    if pc:
        release['platform'] = version.find('./platform').text  # FW doesn't give this
        release['sha256Checksum'] = version.find('./sha256').text  # FW doesn't give this either...
    else:
        release['platform'] = platform
    release['versionNumber'] = version.find('./version').text
    release['fileName'] = version.find('./filename').text
    if re.match(args.firmware_regex, release['fileName']):
        print(f"Version {release['fileName']} matched regex {args.firmware_regex}")
        releases_dict_list.append(release)
if not releases_dict_list:
    print(f'No releases matched regex {args.firmware_regex}')
    sys.exit(1)
for idx, release in enumerate(releases_dict_list):
    if os.path.isfile(os.path.join(args.scp_path, release['fileName'])):
        print(f"File {release['fileName']} for {release['platform']} already on disk, not downloading")
    else:
        print(f"Downloading version {release['versionNumber']} for {release['platform']} and placing on SCP server")
        try:
            if pc:
                response = dvc.op(f"request {cmd_pra} software download file \"{release['fileName']}\"")
                """
                As it does
                https://pan-os-python.readthedocs.io/en/latest/_modules/panos/updater.html#SoftwareUpdater.download
                """
                result = dvc.syncjob(response)
                if not result["success"]:
                    print(f'Error during Panorama download: {result["messages"]}')
                    sys.exit(1)
            else:
                # Not available for Panorama...
                dvc.software.download(release['versionNumber'], sync_to_peer=False, sync=True)
        except PanDeviceError as e:
            if 'base image must be loaded before' in e.message:
                pass
            else:
                raise
        dvc.op(f"<request><{cmd_pra}><software><scp-export><file>{release['fileName']}</file>"
              f"<profile-name>{args.scp_profile}</profile-name></scp-export></software></{cmd_pra}></request>",
              cmd_xml=False)
        print(f"Exported file {release['fileName']} from PA device")
        try:
            if pc:
                dvc.op(f"request batch software delete file \"{release['fileName']}\"")
            else:
                dvc.op(f"delete software version \"{release['versionNumber']}\"")
            print(f"Deleted file {release['fileName']} from PA device")
        except PanDeviceXapiError as e:
            if 'not downloaded' in str(e):
                pass
            else:
                raise
    if not pc:
        sha256 = hashlib.sha256()
        with open(os.path.join(args.scp_path, release['fileName']), 'rb') as f:
            while True:
                data = f.read(HASH_BUF_SIZE)
                if not data:
                    break
                sha256.update(data)
        releases_dict_list[idx]['sha256Checksum'] = format(sha256.hexdigest())

platforms = {dicti["platform"] for dicti in releases_dict_list}
for plat in platforms:
    filtered_dict_list = [item for item in releases_dict_list if item["platform"] == plat]
    
    # Extract information

    listoflist = []
    for release in filtered_dict_list:
        listoflist += [[[], release['versionNumber'], [], [], release['fileName'],
                        release['sha256Checksum']]]
    split = []
    for sublist in listoflist:
        split += [re.split(r'\.|-', sublist[1], maxsplit=3)]
        if len(split[-1]) == 3:
            split[-1] += 'c'
        split[-1] += [sublist[1]]

    for sublist in split:
        sublist[0] = int(sublist[0])
        sublist[1] = int(sublist[1])
        sublist[2] = int(sublist[2])

    # Sort releases

    split.sort(key=itemgetter(3))
    split.sort(key=itemgetter(2))
    split.sort(key=itemgetter(1))
    split.sort(key=itemgetter(0))

    for sublist in split:
        if sublist[3] == 'c':
            sublist.pop(3)
    i = 1
    for sublist in split:
        sublist += [i]
        i += 1

    for sublist in listoflist:
        for sublist2 in split:
            if sublist[1] == sublist2[-2]:
                sublist[0] = sublist2[-1]

    listoflist.sort(key=itemgetter(0))

    # Evaluate if a Major or a Minor release

    for sublist in listoflist:
        sublist[2] = sublist[1].split('.')[0] + "." + sublist[1].split('.')[1]
        sublist[3] = 'Feature' if re.split(r'\.|-', sublist[1], maxsplit=3)[2] == "0" else 'Maintenance'

    finallist = []

    # Don't support earlier than PAN-OS 7.1

    for sublist in listoflist:
        if float(sublist[2]) >= 7.1:
            finallist += [sublist]

    outputName = plat + ".csv"

    with open(outputName, "w", newline="") as f:
        writer = csv.writer(f, delimiter=",")
        writer.writerows(finallist)
print('Done.')
