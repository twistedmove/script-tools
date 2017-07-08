#!/usr/bin/env python
# coding=utf-8
# wujian@2017.7.8

import sys

initials = ['b', 'p', 'm', 'f', 'd', 't', 'n', 'l', 'g', 'k', 'h', 
        'j', 'q', 'x', 'zh', 'ch', 'sh', 'r', 'z', 'c', 's', 'y', 'w']


def main(argv):

    with open(argv[1], "r") as sfile:
        sset = sfile.read().strip().split()
    # index: syllable
    decoder = dict(enumerate(sset))
    # syllable: index 
    encoder = {value: key for key, value in decoder.items()}

    src = sys.stdin if argv[2] == '-' else open(argv[2], "r") 
    dst = sys.stdout if argv[3] == '-' else open(argv[3], "w")
    
    while True:
        utt_lengths = src.readline().strip().split()
        if not utt_lengths:
            break
        phones = utt_lengths[1::2]; durs = utt_lengths[2::2]

        idx = 0
        dst.write(utt_lengths[0])
        while idx < len(phones):
            cur_phone = phones[idx]; cur_dur = durs[idx]
            if cur_phone not in initials:
                syllable_id = encoder[cur_phone]
                for _ in range(int(cur_dur)):
                    dst.write(' ' + str(syllable_id))
            else:
                next_phone = phones[idx + 1]; next_dur = durs[idx + 1]
                syllable_id = encoder[cur_phone + next_phone]
                for _ in range(int(cur_dur) + int(next_dur)):
                    dst.write(' ' + str(syllable_id))
                idx += 1
            idx += 1
        dst.write('\n')

    src.close()
    dst.close()

if __name__ == '__main__':
    if len(sys.argv) != 4:
        raise SystemExit('format error: {} [syllable-set] [ali-phone-length] [syllable-seq]'.format(sys.argv[0]))
    main(sys.argv)
