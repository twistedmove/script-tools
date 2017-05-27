#!/usr/bin/env python

"""compute spectrogram according to kaldi"""

import sys
import wave
import math
import numpy as np


if len(sys.argv) != 2:
    print "format error: %s [wave-in]" % sys.argv[0]
    sys.exit(1)


SRC_WAVE = wave.open(sys.argv[1], "rb")
SRC_SAMPLE_RATE, TOT_SAMPLE = SRC_WAVE.getparams()[2: 4]

WND_SIZE = int(SRC_SAMPLE_RATE * 0.001 * 25)
WND_OFFSET = int(SRC_SAMPLE_RATE * 0.001 * 10)
WAVE_DATA = np.fromstring(SRC_WAVE.readframes(TOT_SAMPLE), np.int16)

FRAME_NUM = (WAVE_DATA.size - WND_SIZE) / WND_OFFSET + 1
# FRAME_VEC = np.zeros(WND_SIZE)

SPECT_LEN = 257
SPECT_VEC = np.zeros(SPECT_LEN)

HAMMING = np.hamming(WND_SIZE)

print FRAME_NUM

for index in range(FRAME_NUM):
    BASE_PNT = index * WND_OFFSET
    # get frame
    FRAME_VEC = np.array(WAVE_DATA[BASE_PNT: BASE_PNT + WND_SIZE], dtype=np.float)
    # dither...
    # remove dc mean
    FRAME_VEC -= (np.sum(FRAME_VEC) / WND_SIZE)
    # calculate log energy
    energy = math.log(np.sum(FRAME_VEC ** 2))
    # preemphasize
    FRAME_VEC[1: ] -= 0.97 * FRAME_VEC[: -1]
    FRAME_VEC[0] -= 0.97 * FRAME_VEC[0]

    # buffer
    DFT_VALUE = np.zeros((SPECT_LEN - 1) * 2)
    # hamming
    DFT_VALUE[: WND_SIZE] = FRAME_VEC * HAMMING
    # power log
    SPECT_VEC[0] = energy
    SPECT_VEC[1: ] = np.log(np.abs(np.fft.rfft(DFT_VALUE)[1: ]) ** 2)
    print SPECT_VEC
    # print np.log(np.abs(np.fft.rfft(DFT_VALUE)) ** 2)



