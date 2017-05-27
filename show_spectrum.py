#!/usr/bin/env python
# coding=utf-8

import scipy.io.wavfile as wav
import numpy as np
import matplotlib.pyplot as plt
import sys
import re
import math


if len(sys.argv) != 2:
    raise SystemExit("Format error: {} [src wave]".format(sys.argv[0]))

wavpath = sys.argv[1]
rate, samples =  wav.read(wavpath)

m = re.match('(.*)/(.*).wav', wavpath)

wavname = m.group(2)
print "process %s.wav..." % wavname

wave = np.array(samples, dtype = "float")

frame_off = 160
frame_len = 400
spect_len = 512
frame_num = (wave.size - frame_len) / frame_off + 1

hamwindow = np.hamming(frame_len)
spect = np.zeros((frame_num, spect_len / 2 + 1))
z = np.zeros(spect_len - frame_len)
# seq = []
# vad = vad.VAD(6000, 5)

for idx in range(frame_num):
    base = idx * frame_off
    frame = wave[base: base + frame_len]
    # e = math.sqrt(np.dot(frame, frame))
    # vad.state_trans(e)
    # seq.append(int(vad.active()))
    # seq.append(int(e > 6000))
    frame = np.append(frame * hamwindow, z)
    spect[idx:] = np.log(np.abs(np.fft.rfft(frame)))


plt.title(wavname  + ".wav")
plt.imshow(np.transpose(spect), origin="lower", cmap = "jet", aspect = "auto", interpolation = "none")

xlocs = np.linspace(0, frame_num - 1, 5)
frame_dur = 1 / float(rate) * frame_off
plt.yticks([])
plt.xticks(xlocs, ["%.02f" % l for l in (xlocs * frame_dur)])
plt.xlabel("time (s)")

plt.show()
# plt.savefig("./devide_vad/" + wavname + ".png")
