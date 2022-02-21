import json
from operator import itemgetter
import csv
import re

input("Name your json file 'input.json' and press ENTER:")

with open('input.json', 'r') as f:
    releases_dict = json.load(f)

listoflist = []

# Extract information

for release in releases_dict:
    listoflist += [[[], release['versionNumber'], [], [], release['fileName'],
                    release['shA256Checksum']]]
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

outputName = releases_dict[0]['platform'] + ".csv"

with open(outputName, "w", newline="") as f:
    writer = csv.writer(f, delimiter=",")
    writer.writerows(finallist)
