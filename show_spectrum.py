#!/usr/bin/env python
# coding=utf-8

import wave
import os 
import argparse
import numpy as np
import matplotlib.pyplot as plt

num_bits_to_type = {
    1: np.int8,
    2: np.int16,
    4: np.int32,
    8: np.int64
}

def num_samples_to_num_frames(num_samples, frame_length, frame_shift):
    return int((num_samples - frame_length) / frame_shift + 1)

def time_to_num_samples(time_ms, sample_rate):
    return int(time_ms * 1e-3 * sample_rate)

def frame_length_to_fftsize(frame_length):
    fftsize = 1
    while fftsize < frame_length:
        fftsize = fftsize * 2
    return int(fftsize)

def sample_bits_to_decode_type(sample_bits):
    assert sample_bits in num_bits_to_type
    return num_bits_to_type[sample_bits]

def plot_or_save(stft):
    plt.imshow(stft, origin="lower", \
            cmap = "jet", aspect = "auto", interpolation = "none")
    _, num_frames = stft.shape
    xp = np.linspace(0, num_frames - 1, 5)
    plt.yticks([])
    plt.title(os.path.basename(args.src_path))
    plt.xticks(xp, ["%.02f" % t for t in (xp * args.frame_length * 1e-3)])
    plt.xlabel("time (s)")
    plt.show()

def main(args):
    src_wave = wave.open(args.src_path)
    num_channels, sample_bits, sample_rate, num_samples, _, _ = src_wave.getparams()
    frame_length = time_to_num_samples(args.frame_length, sample_rate)
    frame_shift  = time_to_num_samples(args.frame_shift, sample_rate)
    samples      = np.frombuffer(src_wave.readframes(num_samples), \
                        dtype=sample_bits_to_decode_type(sample_bits))
    num_frames   = num_samples_to_num_frames(num_samples, frame_length, frame_shift)
    log_stft     = []
    frames_padding = np.zeros(frame_length_to_fftsize(frame_length))
    ham_window   = np.hamming(frame_length)
    for index in range(num_frames):
        beg = index * frame_shift
        frames_padding[: frame_length] = samples[beg: beg + frame_length] * ham_window
        log_stft.append(np.log(np.abs(np.fft.rfft(frames_padding))))
    plot_or_save(np.transpose(np.asarray(log_stft)))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Plot spectrogram")
    parser.add_argument('src_path', help="input audio file in wav format")
    parser.add_argument('--frame-length', dest='frame_length', type=int, default=25,
                        help="frame length in ms")
    parser.add_argument('--frame-shift', dest='frame_shift', type=int, default=10,
                        help="frame shift in ms")
    args = parser.parse_args()
    main(args)