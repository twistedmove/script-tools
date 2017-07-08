#!/usr/bin/env python
# coding=utf-8

# wujian@2017.7.8

import sys

def main(argv):

    with open(argv[1], "r") as phones:
        phn_map = phones.read().strip().split()
    phone_decoder = dict(enumerate(phn_map[0::2]))
    src = sys.stdin if argv[2] == '-' else open(argv[2], "r")
    dst = sys.stdout if argv[3] == '-' else open(argv[3], "w")

    while True:
        utt = src.readline().strip().split()
        if not utt:
            break
        dst.write(utt[0])
        for phone_id, nframe in zip(utt[1::3], utt[2::3]):
            phone = phone_decoder[int(phone_id)]
            dst.write(' ' + phone + ' ' + nframe)
        dst.write('\n')
        
    src.close()
    dst.close()

if __name__ == '__main__':
    if len(sys.argv) != 4:
        raise SystemExit('format error: {} [phones.txt] [ali-lengths] [phone-length]'.format(sys.argv[0]))
    main(sys.argv)
