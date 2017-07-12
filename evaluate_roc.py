#!/usr/bin/env python
# @wujian

"""Draw ROC curves by input script"""

import sys
import numpy as np
import matplotlib.pyplot as plt


NP = 100

def draw_roc(mat, name=""):
    """draw a line by mat"""
    tot, cnt = mat.shape
    assert cnt == 2
    n_pos = (mat[:, cnt - 1] == 1).sum()
    n_neg = tot - n_pos
    state = mat[:, cnt - 1]

    vec = mat[:, 0]
    dn_bound = np.min(vec)
    up_bound = np.max(vec)
    false_reject = [(state[np.where(vec < th)] == 1).sum() / float(n_pos) \
        for th in np.linspace(dn_bound, up_bound, NP)]
    false_alarm = [(state[np.where(vec > th)] == 0).sum() / float(n_neg) \
        for th in np.linspace(dn_bound, up_bound, NP)]
    if name == "":
        plt.plot(false_alarm, false_reject) 
    else:
        plt.plot(false_alarm, false_reject, label=name)


def main():
    """process scp file"""
    with open(sys.argv[1], "rb") as scp:
        while True:
            str_line = scp.readline()
            if not str_line:
                break
            token = [string for string in str_line.strip().split()]
            if len(token) == 1:
                draw_roc(np.loadtxt(token[0]))
            else:
                draw_roc(np.loadtxt(token[0]), '-'.join(token[1:]))

if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("format error: {} [score.scp] [curves-title]".format(sys.argv[0]))
    main()
    plt.xlabel("False Alarm Rate")
    plt.ylabel("False Reject Rate")
    plt.title(sys.argv[2])
    plt.xlim(0, 0.5)
    plt.ylim(0, 0.5)
    plt.legend()
    plt.show()
