#!/usr/bin/env python
# coding=utf-8
# wujian@2017.7.8

import sys

initials = ['b', 'p', 'm', 'f', 'd', 't', 'n', 'l', 'g', 'k', 'h', 
        'j', 'q', 'x', 'zh', 'ch', 'sh', 'r', 'z', 'c', 's', 'y', 'w']


def main(argv):
    stats = set()
    key = ''
    seq = sys.stdin if argv[1] == '-' else open(argv[1], "r")
    while True:
        utt_seq = seq.readline().strip().split()
        if not utt_seq:
            break
        idx = 1
        while idx < len(utt_seq):
            cur_phone = utt_seq[idx]
            if cur_phone not in initials:
                stats.add(cur_phone)
            else:
                next_phone = utt_seq[idx + 1]
                stats.add(cur_phone + next_phone)
                idx += 1
            idx += 1
    seq.close()
    out = sys.stdout if argv[2] == '-' else open(argv[2], "w")
    for v in stats:
        out.write(v + "\n")
    out.close()
    
if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('format error: {} [phone-seq] [syllable-out]'.format(sys.argv[0]))
    main(sys.argv)
