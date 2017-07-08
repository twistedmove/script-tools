#!/bin/bash
# wujian@2017.7.8
# map alignments from phone_id to syllable_id

cmd=run.pl
stage=1

. ./path.sh || exit 1
. parse_options.sh || exit 1

[ $# -ne 1 ] && echo "format error: $0: [ali-dir]" && exit 1
ali=$1

if [ $stage -le 1 ]; then
    echo "1. COUNT SYLLABLES..."
    $cmd JOB=1:10 $ali/log/count_syllable.JOB.log \
        ali-to-phones $ali/final.mdl "ark:gunzip -c $ali/ali.JOB.gz |" ark,t:- \| \
        local/apply_map.pl --permissive data/lang/id2phone \| \
        grep -v "warning!" \| local/count_syllable.py - $ali/log/JOB.syllable || exit 1
    cat $ali/log/*.syllable | sort -u > $ali/syllable.txt || exit 1
    echo "Get $(wc -l < $ali/syllable.txt) syllables!"
fi

if [ $stage -le 2 ]; then
    echo "2. ALIGN TO SYLLABLES..."
    $cmd JOB=1:10 $ali/log/ali_to_syllable.JOB.log \
        ali-to-phones --write-lengths=true $ali/final.mdl "ark:gunzip -c $ali/ali.JOB.gz |" ark,t:- \| \
        local/prepare_phone_length.py $ali/phones.txt - - \| \
        local/generate_syllable_alignments.py $ali/syllable.txt - $ali/ali.JOB.sy || exit 1

    for n in $(seq 10); do gzip $ali/ali.$n.sy; done
fi

echo "Done!"
