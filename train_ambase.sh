#!/bin/bash
#by wujian@2017.4.17

cmd_train="run.pl"


function stop_or_continue() {
    [ $# -ne 1 ] && echo "function param mismatch..." && exit 1
    [ $stage -le $1 ] && [ $single_step == true ] && echo "step $stage done" && exit 
}

train=true
stage=1

single_step=false
decode_nj=10

[ -z $KALDI_ROOT ] && . ./path.sh

source parse_options.sh || exit 1

echo "train = $train; single_step = $single_step; stage = $stage;"

if [ $stage -le 1 ]; then
    echo "1. PREPARE FEATURE"
    for x in train dev; do
        steps/make_mfcc_pitch_online.sh --cmd $cmd_train --nj 10 data/$x exp/make_mfcc mfcc_pitch || exit 1    
        steps/compute_cmvn_stats.sh data/$x exp/make_mfcc mfcc_pitch || exit 1
    done
fi

#stop_or_continue 1
# [ $stage -le 1 ] && [ $single_step == true ] && echo "step $stage done" && exit 

dev_dir="data/dev"

# --------------------------------
# local definition

exp_dir="exp/mono"
gph_dir="$exp_dir/graph"
dec_dir="$exp_dir/decode"

if [[ $stage -le 2 && $train == true ]]; then
    echo "2. MONO_PHONE TRAINING"
    utils/fix_data_dir.sh data/train || exit 1
    # utils/subset_data_dir.sh --first data/train 100000 data/tr100k || exit 1
    steps/train_mono.sh --cmd $cmd_train --nj 10 data/train data/lang $exp_dir || exit 1
    utils/mkgraph.sh data/lang_test $exp_dir $gph_dir || exit 1
    # using local/score.sh at the last of the script
    steps/decode.sh --cmd $cmd_train --config conf/decode.config --nj $decode_nj $gph_dir $dev_dir $dec_dir || exit 1
fi

stop_or_continue 2

exp_dir="exp/tri0"
gph_dir="$exp_dir/graph"
dec_dir="$exp_dir/decode"
mdl_dir="exp/mono"
ali_dir="exp/mono_ali"

if [[ $stage -le 3 && $train == true ]]; then
    echo "3. TRIPLE_PHONE TRAINING 0"
    steps/align_si.sh --cmd $cmd_train --nj 10 data/train data/lang $mdl_dir $ali_dir || exit 1
    steps/train_deltas.sh --cmd $cmd_train 2500 20000 data/train data/lang $ali_dir $exp_dir || exit 1 
    utils/mkgraph.sh data/lang_test $exp_dir $gph_dir || exit 1
    steps/decode.sh --cmd $cmd_train --config conf/decode.config --nj $decode_nj $gph_dir $dev_dir $dec_dir || exit 1
fi

stop_or_continue 3 

exp_dir="exp/tri1"
gph_dir="$exp_dir/graph"
dec_dir="$exp_dir/decode"
mdl_dir="exp/tri0"
ali_dir="exp/tri0_ali"

if [[ $stage -le 4 && $train == true ]]; then
    echo "4. TRIPLE_PHONE TRAINING 1"
    steps/align_si.sh --cmd $cmd_train --nj 10 data/train data/lang $mdl_dir $ali_dir || exit 1
    steps/train_deltas.sh --cmd $cmd_train 2500 20000 data/train data/lang $ali_dir $exp_dir || exit 1 
    utils/mkgraph.sh data/lang_test $exp_dir $gph_dir || exit 1
    steps/decode.sh --cmd $cmd_train --config conf/decode.config --nj $decode_nj $gph_dir $dev_dir $dec_dir || exit 1
fi

stop_or_continue 4 

exp_dir="exp/lda_mllt"
gph_dir="$exp_dir/graph"
dec_dir="$exp_dir/decode"
# previous trained model
mdl_dir="exp/tri1"
# current output alignments direction
ali_dir="exp/tri1_ali"

if [[ $stage -le 5 && $train == true ]]; then
    echo "5. LDA+MLLT TRAINING"
    steps/align_si.sh --cmd $cmd_train --nj 10 data/train data/lang $mdl_dir $ali_dir || exit 1
    # steps/align_si.sh --cmd $cmd_train --nj 10 data/tr100k data/lang $mdl_dir ${ali_dir}_100k || exit 1
    steps/train_lda_mllt.sh --cmd $cmd_train 2500 20000 data/train data/lang $ali_dir $exp_dir || exit 1
    utils/mkgraph.sh data/lang_test $exp_dir $gph_dir || exit 1
    steps/decode.sh --cmd $cmd_train --config conf/decode.config --nj $decode_nj $gph_dir $dev_dir $dec_dir || exit 1
fi

stop_or_continue 5

# don't use align_si.sh for alignments and decode.sh for decoding
exp_dir="exp/sat0"
gph_dir="$exp_dir/graph"
dec_dir="$exp_dir/decode"
mdl_dir="exp/lda_mllt"
ali_dir="exp/lda_mllt_ali"

if [[ $stage -le 6 && $train == true ]]; then
    echo "6. SAT[SMALL] TRAINING"
    steps/align_fmllr.sh --cmd $cmd_train --nj 10 data/train data/lang $mdl_dir $ali_dir || exit 1
    steps/train_sat.sh --cmd $cmd_train 3500 20000 data/train data/lang $ali_dir $exp_dir || exit 1
    utils/mkgraph.sh data/lang_test $exp_dir $gph_dir || exit 1
    steps/decode_fmllr.sh --cmd $cmd_train --config conf/decode.config --nj $decode_nj $gph_dir $dev_dir $dec_dir || exit 1
fi

stop_or_continue 6

exp_dir="exp/sat1"
gph_dir="$exp_dir/graph"
dec_dir="$exp_dir/decode"
mdl_dir="exp/sat0"
ali_dir="exp/sat0_ali"

if [[ $stage -le 7 && $train == true ]]; then
    echo "7. SAT[BIG] TRAINING"
    steps/align_fmllr.sh --cmd $cmd_train --nj 10 data/train data/lang $mdl_dir $ali_dir || exit 1
    steps/train_sat.sh --cmd $cmd_train 5000 100000 data/train data/lang $ali_dir $exp_dir || exit 1
    utils/mkgraph.sh data/lang_test $exp_dir $gph_dir || exit 1
    steps/decode_fmllr.sh --cmd $cmd_train --config conf/decode.config --nj $decode_nj $gph_dir $dev_dir $dec_dir || exit 1
fi

stop_or_continue 7


mdl_dir="exp/sat1"
ali_dir="exp/sat1_ali"
echo "8. FINAL ALIGN USING SAT1"
steps/align_fmllr.sh --cmd $cmd_train --nj 10 data/train data/lang $mdl_dir $ali_dir || exit 1

echo "Done" && exit 0

# based on previous training

exp_dir="exp/sgmm"
ubm_dir="exp/ubm"
gph_dir="$exp_dir/graph"
dec_dir="$exp_dir/decode"
mdl_dir="exp/sat1"
ali_dir="exp/sgmm_ali"


if [[ $stage -le 8 && $train == true ]]; then
    echo "9. SGMM TRAINING"
    steps/align_fmllr.sh --cmd $cmd_train --nj 10 data/train data/lang $mdl_dir $ali_dir || exit 1
    steps/train_ubm.sh --cmd $cmd_train 900 data/train data/lang $ali_dir $ubm_dir || exit 1
    steps/train_sgmm2.sh --cmd $cmd_train 14000 35000 data/train data/lang $ali_dir $ubm_dir/final.ubm $exp_dir || exit 1
    utils/mkgraph.sh data/lang_test $exp_dir $gph_dir || exit 1
    steps/decode_sgmm2.sh --cmd $cmd_train --nj $decode_nj --config conf/decode.config --transform-dir exp/sat1/decode $gph_dir $dev_dir $dec_dir || exit 1;
fi

stop_or_continue 8

