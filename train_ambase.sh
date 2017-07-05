#!/bin/bash
#by wujian@2017.4.17

cmd_train="run.pl"

function score_report() {
    [ $# -ne 1 ] && echo "function param mismatch..." && exit 1
    if [[ $stage -le $1 && $score == true ]]; then
        steps/scoring/score_kaldi_cer.sh --cmd $cmd_train $dev_dir $gph_dir $dec_dir || exit 1
        # grep WER $dec_dir/cer_* | utils/best_wer.sh >> SCORE || exit 1
        cat $dec_dir/scoring_kaldi/best_cer >> SCORE
    fi 
}

function stop_or_continue() {
    [ $# -ne 1 ] && echo "function param mismatch..." && exit 1
    [ $stage -le $1 ] && [ $single_step == true ] && echo "step $stage done" && exit 
}

train=true
score=true
stage=1

single_step=false

[ -z $KALDI_ROOT ] && echo "export KALDI_ROOT first" && exit 1

source parse_options.sh || exit 1

echo "train = $train; score = $score; single_step = $single_step; stage = $stage;"

#if [ $stage -le 1 ]; then
#    echo "1. PREPARE FEATURE"
#    for x in train dev; do
#        steps/make_mfcc_pitch.sh --cmd $cmd_train --nj 10 data/$x exp/make_mfcc mfcc_pitch || exit 1    
#        steps/compute_cmvn_stats.sh data/$x exp/make_mfcc mfcc_pitch || exit 1
#    done
#fi
#
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
    steps/decode.sh --cmd $cmd_train --config conf/decode.config --nj 5 --skip_scoring true $gph_dir $dev_dir $dec_dir || exit 1
fi

score_report 2 && stop_or_continue 2

exp_dir="exp/tri0"
gph_dir="$exp_dir/graph"
dec_dir="$exp_dir/decode"
mdl_dir="exp/mono"
ali_dir="exp/mono_align"

if [[ $stage -le 3 && $train == true ]]; then
    echo "3. TRIPLE_PHONE TRAINING 0"
    steps/align_si.sh --cmd $cmd_train --nj 10 data/train data/lang $mdl_dir $ali_dir || exit 1
    steps/train_deltas.sh --cmd $cmd_train 2500 20000 data/train data/lang $ali_dir $exp_dir || exit 1 
    utils/mkgraph.sh data/lang_test $exp_dir $gph_dir || exit 1
    steps/decode.sh --cmd $cmd_train --config conf/decode.config --nj 5 --skip_scoring false $gph_dir $dev_dir $dec_dir || exit 1
fi

score_report 3 && stop_or_continue 3 

exp_dir="exp/tri1"
gph_dir="$exp_dir/graph"
dec_dir="$exp_dir/decode"
mdl_dir="exp/tri0"
ali_dir="exp/tri0_align"

if [[ $stage -le 4 && $train == true ]]; then
    echo "4. TRIPLE_PHONE TRAINING 1"
    steps/align_si.sh --cmd $cmd_train --nj 10 data/train data/lang $mdl_dir $ali_dir || exit 1
    steps/train_deltas.sh --cmd $cmd_train 2500 20000 data/train data/lang $ali_dir $exp_dir || exit 1 
    utils/mkgraph.sh data/lang_test $exp_dir $gph_dir || exit 1
    steps/decode.sh --cmd $cmd_train --config conf/decode.config --nj 5 --skip_scoring true $gph_dir $dev_dir $dec_dir || exit 1
fi

score_report 4 && stop_or_continue 4 

exp_dir="exp/lda_mllt"
gph_dir="$exp_dir/graph"
dec_dir="$exp_dir/decode"
# previous trained model
mdl_dir="exp/tri1"
# current output alignments direction
ali_dir="exp/tri1_align"

if [[ $stage -le 5 && $train == true ]]; then
    echo "5. LDA+MLLT TRAINING"
    steps/align_si.sh --cmd $cmd_train --nj 10 data/train data/lang $mdl_dir $ali_dir || exit 1
    # steps/align_si.sh --cmd $cmd_train --nj 10 data/tr100k data/lang $mdl_dir ${ali_dir}_100k || exit 1
    steps/train_lda_mllt.sh --cmd $cmd_train 2500 20000 data/train data/lang $ali_dir $exp_dir || exit 1
    utils/mkgraph.sh data/lang_test $exp_dir $gph_dir || exit 1
    steps/decode.sh --cmd $cmd_train --config conf/decode.config --nj 5 --skip_scoring true  $gph_dir $dev_dir $dec_dir || exit 1
fi

score_report 5 && stop_or_continue 5

# don't use align_si.sh for alignments and decode.sh for decoding
exp_dir="exp/sat0"
gph_dir="$exp_dir/graph"
dec_dir="$exp_dir/decode"
mdl_dir="exp/lda_mllt"
ali_dir="exp/lda_mllt_align"

if [[ $stage -le 6 && $train == true ]]; then
    echo "6. SAT[SMALL] TRAINING"
    steps/align_fmllr.sh --cmd $cmd_train --nj 10 data/train data/lang $mdl_dir $ali_dir || exit 1
    steps/train_sat.sh --cmd $cmd_train 2500 20000 data/train data/lang $ali_dir $exp_dir || exit 1
    utils/mkgraph.sh data/lang_test $exp_dir $gph_dir || exit 1
    steps/decode_fmllr.sh --cmd $cmd_train --config conf/decode.config --nj 5 --skip_scoring true  $gph_dir $dev_dir $dec_dir || exit 1
fi

score_report 6 && stop_or_continue 6

exp_dir="exp/sat1"
gph_dir="$exp_dir/graph"
dec_dir="$exp_dir/decode"
mdl_dir="exp/sat0"
ali_dir="exp/sat0_align"

if [[ $stage -le 7 && $train == true ]]; then
    echo "7. SAT[BIG] TRAINING"
    steps/align_fmllr.sh --cmd $cmd_train --nj 10 data/train data/lang $mdl_dir $ali_dir || exit 1
    steps/train_sat.sh --cmd $cmd_train 3500 100000 data/train data/lang $ali_dir $exp_dir || exit 1
    utils/mkgraph.sh data/lang_test $exp_dir $gph_dir || exit 1
    steps/decode_fmllr.sh --cmd $cmd_train --config conf/decode.config --nj 10 --skip_scoring true $gph_dir $dev_dir $dec_dir || exit 1
fi

score_report 7 && stop_or_continue 7


mdl_dir="exp/sat1"
ali_dir="exp/sat1_align"
steps/align_fmllr.sh --cmd $cmd_train --nj 10 data/train data/lang $mdl_dir $ali_dir || exit 1

echo "Done" && exit 0

# based on previous training

exp_dir="exp/sgmm"
ubm_dir="exp/ubm"
gph_dir="$exp_dir/graph"
dec_dir="$exp_dir/decode"
mdl_dir="exp/sat1"
ali_dir="exp/sgmm_align"


if [[ $stage -le 8 && $train == true ]]; then
    echo "8. SGMM TRAINING"
    steps/align_fmllr.sh --cmd $cmd_train --nj 10 data/train data/lang $mdl_dir $ali_dir || exit 1
    steps/train_ubm.sh --cmd $cmd_train 900 data/train data/lang $ali_dir $ubm_dir || exit 1
    steps/train_sgmm2.sh --cmd $cmd_train 14000 35000 data/train data/lang $ali_dir $ubm_dir/final.ubm $exp_dir || exit 1
    utils/mkgraph.sh data/lang_test $exp_dir $gph_dir || exit 1
    steps/decode_sgmm2.sh --cmd $cmd_train --nj 10 --config conf/decode.config --transform-dir exp/sat1/decode --skip_scoring true $gph_dir $dev_dir $dec_dir || exit 1;
fi

score_report 8 && stop_or_continue 8

