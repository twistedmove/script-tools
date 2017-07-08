#!/usr/bin/env python
# coding=utf-8

import xml.etree.ElementTree as et 
import sys

if len(sys.argv) != 2:
    print "format error: %s [kwslist.xml]" % sys.argv[0]
    sys.exit(1)

tree = et.ElementTree(file=sys.argv[1])

root = tree.getroot()
for kw in root:
    kwid = kw.attrib['kwid']
    for spot in kw:
        beg_time = float(spot.attrib['tbeg'])
        dur_time = float(spot.attrib['dur'])
        token = '{} {} {} {}'.format(kwid, spot.attrib['file'], str(beg_time + dur_time / 2), spot.attrib['score'])
        print token
