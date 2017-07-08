#!/bin/bash

[ $# -ne 2 ] && echo "format error: $0 [keyword-text] [rttm-file]" && exit 1

kwlist=$1
kwrttm=$2

column_cmd=" | column -t"
[ $LC_ALL == "C" ] && column_cmd=""

cat $kwlist | while read token; do
    ID=$(echo $token | awk '{print $1}')
    grep $(echo $token | awk '{print $2}') $kwrttm | cut -d ' ' -f 2,4-6 | sed "s/^/$ID &/g" $column_cmd 
done > refer.list

echo "Done with $(wc -l < refer.list) lines!" 
