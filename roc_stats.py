#!/usr/bin/env python
# coding=utf-8
# wujian@2017.5.22

import sys

if len(sys.argv) != 3:
    error = "format error: {} [reference-list] [spottint-list]".format(sys.argv[0])
    raise SystemExit(error)

class DurToken():
    def __init__(self, beg_time, dur_time):
        self.beg_time = beg_time
        self.end_time = beg_time + dur_time

    def __str__(self):
        return  '    {}: {}'.format(self.beg_time, self.end_time)

    def hit(self, hit_time):
        return hit_time >= self.beg_time and hit_time <= self.end_time 


class ReferToken():
    def __init__(self):
        self.dur_set = dict()

    def dict(self):
        return self.dur_set

    def hit(self, utt_id, mid_time):
        if not self.dur_set.has_key(utt_id):
            return False 
        
        dur_token_list = self.dur_set[utt_id]
        for token in dur_token_list:
            if token.hit(mid_time):
                return True
        return False 
    
    def append(self, utt_id, beg_time, dur_time):
        if not self.dur_set.has_key(utt_id):
            self.dur_set[utt_id] = list()
        self.dur_set[utt_id].append(DurToken(beg_time, dur_time))
                
refer_list = dict()

with open(sys.argv[1], "r") as refer:
    while True:
        info_line = refer.readline().strip().split()
        if not info_line:
            break
        assert len(info_line) >= 4
        kwid = info_line[0]
        # new dict for each keyword
        if not refer_list.has_key(kwid):
            refer_list[kwid] = ReferToken()
        refer_list[kwid].append(info_line[1], float(info_line[2]), float(info_line[3]))

# score = float(sys.argv[3])

NR = 4324

with open(sys.argv[2], "r") as spot:
    info_list = spot.readlines()
    
    for n in range(100):
        score = float(n) / 100
        NA = NC = 0
        for line_id in range(len(info_list)):
            info_line = info_list[line_id].strip().split()

            kwid, utt_id = info_line[0], info_line[1]
            refer_token = refer_list[kwid]

            if float(info_line[3]) < score:
                continue
            NA += 1
            if refer_token.hit(utt_id, float(info_line[2])):
                NC += 1

        print 'score = {} P = {} R = {}'.format(score, float(NC) / NA, float(NC) / NR)
