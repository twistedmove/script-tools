#!/usr/bin/env python
#by wujian@2017.4.15

"""transform spectrogram to waveform"""

import sys
import wave
import numpy as np

import kaldi_io
import wave_io


if len(sys.argv) != 4:
    print "format error: %s [spectrum] [origin-wave] [reconst-wave]" % sys.argv[0]
    sys.exit(1)

WAVE_WARPPER = wave_io.WaveWrapper(sys.argv[2])
WAVE_RECONST = wave.open(sys.argv[3], "wb")

WND_SIZE = WAVE_WARPPER.get_wnd_size()
WND_RATE = WAVE_WARPPER.get_wnd_rate()

REAL_IFFT = np.fft.irfft

HAM_WND = np.hamming(WND_SIZE)

with open(sys.argv[1], "rb") as ark:
    SPECT_ENHANCE = kaldi_io.next_mat_ark(ark)
    SPECT_ROWS, SPECT_COLS = SPECT_ENHANCE.shape
    assert WAVE_WARPPER.get_frames_num() == SPECT_ROWS
    INDEX = 0
    SPECT = np.zeros(SPECT_COLS)
    RECONST_POOL = np.zeros((SPECT_ROWS - 1) * WND_RATE + WND_SIZE)
    for phase in WAVE_WARPPER.next_frame_phase():
        # exclude energy
        SPECT[1: ] = np.sqrt(np.exp(SPECT_ENHANCE[INDEX][1: ]))
        RECONST_POOL[INDEX * WND_RATE: INDEX * WND_RATE + WND_SIZE] += \
                    REAL_IFFT(SPECT * phase)[: WND_SIZE] * HAM_WND
        INDEX += 1
    for x in range(1, RECONST_POOL.size):
        RECONST_POOL[x] += 0.97 * RECONST_POOL[x - 1]
    RECONST_POOL = RECONST_POOL / np.max(RECONST_POOL) * WAVE_WARPPER.get_upper_bound()

    WAVE_RECONST.setnchannels(1)
    WAVE_RECONST.setnframes(RECONST_POOL.size)
    WAVE_RECONST.setsampwidth(2)
    WAVE_RECONST.setframerate(WAVE_WARPPER.get_sample_rate())
    WAVE_RECONST.writeframes(np.array(RECONST_POOL, dtype=np.int16).tostring())
    WAVE_RECONST.close()
