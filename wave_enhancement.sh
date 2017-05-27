#!/bin/bash
#by wujian@2017.4.15

[ $# -ne 2 ] && echo "format error: $0: [enhance-model] [noisy-wave]" && exit 1
[ -z $KALDI_ROOT ] && echo "export KALDI_ROOT first!" && exit 1

wave_path=$2
base_name=$(basename $2)
base_path=$(dirname $2)
wave_name=${base_name%.*}

pyd="./"
mdl=$1

[ ! -f cmvn_noise ] && echo "cmvn_noise not exist" && exit 1
[ ! -f cmvn_clean ] && echo "cmvn_clean not exist" && exit 1

echo "$wave_name    $wave_path" > wav.scp

# compute-spectrogram-feats --window-type=hamming scp:wav.scp ark:${wave_name}.ark || exit 1

nnet-forward --apply-log=false $mdl "ark:compute-spectrogram-feats --window-type=hamming scp:wav.scp ark:-\\
    | apply-cmvn --norm-vars=true cmvn_noise ark:- ark:- | splice-feats --left-context=2 --right-context=2 ark:- ark:- |" \
    ark:- | apply-cmvn --norm-vars=true --reverse=true cmvn_clean ark:- ark:${wave_name}_enhance.ark || exit 1

echo "Running $pyd/reconstruct_spectrogram.py ${wave_name}_enhance.ark $wave_path $base_path/${wave_name}_rebuild.wav"

$pyd/reconstruct_spectrogram.py ${wave_name}_enhance.ark $wave_path $base_path/${wave_name}_enhance.wav || exit 1

rm *.ark *.scp 

echo "Done OK!"


