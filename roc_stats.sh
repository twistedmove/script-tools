#!/bin/bash
# wujian@2017.5.23

[ $# -ne 2 ] && echo "format error: $0 [kws-dir] [kwslist-in]" && exit 1

kws_dir=$1

[ ! -f refer.list ] && create_refer.sh $kws_dir/keywords.txt $kws_dir/rttm

parse_kwslist.py $2 > spotting.list || exit 1

roc_stats.py refer.list spotting.list | cut -d ' ' -f 6,9 | column -t || exit 1 

rm refer.list spotting.list
