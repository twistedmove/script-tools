#!/bin/bash
#fbank feature nnet2 training
#wujian@2017.7.5

. ./path.sh


stage=0


gmm_dir=exp/sat1
ali_dir=exp/sat1_align
gph_dir=exp/sat1/graph
exp_dir=exp/nnet2/nnet2_fbank

train_cmd=run.pl
decode_cmd=run.pl
train_stage=-10
splice_indexes="layer0/-2:-1:0:1:2 layer1/-1:2 layer2/-3:3 layer3/-7:2 layer4/-3:3"


parallel_opts="-l gpu=1"
num_threads=1
minibatch_size=512

common_egs_dir=
decode_nj=5


set -e
. parse_options.sh || exit 1

if [ $stage -le 1 ]; then
    
    echo "FEATURE EXTRACTING..."
    # train => train_hires/train_scaled_hires
    for dir in train dev; do utils/copy_data_dir.sh data/$dir data/${dir}_fbank; done
    # make mfcc feats and cmvn
    for dir in train_fbank dev_fbank; do
        steps/make_fbank.sh --nj 10 --fbank-config conf/fbank.conf --cmd "$train_cmd" \
            data/$dir exp/make_fbank/$dir fbank || exit 1
        steps/compute_cmvn_stats.sh data/$dir exp/make_fbank/$dir fbank || exit 1
        utils/fix_data_dir.sh data/$dir
    done
fi


if [ $stage -le 2 ]; then
    echo "NNET2 TRAINING..."
    # increase jobs from 3 to 8, use multisplice and pnorm nnet
    steps/nnet2/train_multisplice_accel2.sh --stage $train_stage \
        --num-epochs 4 --num-jobs-initial 3 --num-jobs-final 8 \
        --num-hidden-layers 5 --splice-indexes "$splice_indexes" \
        --feat-type raw \
        --cmvn-opts "--norm-means=true --norm-vars=true" \
        --num-threads "$num_threads" \
        --minibatch-size "$minibatch_size" \
        --parallel-opts "$parallel_opts" \
        --io-opts "--max-jobs-run 12" \
        --add-layers-period 1 \
        --mix-up 20000 \
        --initial-effective-lrate 0.0015 --final-effective-lrate 0.00015 \
        --cmd "$train_cmd" \
        --egs-dir "$common_egs_dir" \
        --pnorm-input-dim 4000 \
        --pnorm-output-dim 400 \
        data/train_fbank data/lang $ali_dir $exp_dir || exit 1
fi

if [ $stage -le 3 ]; then
    echo "DECODING AND EVALUATING..."
    # jobs could not be too large cause HCLG size
    steps/nnet2/decode.sh --nj $decode_nj --cmd "$decode_cmd" \
        --config conf/decode.config $gph_dir data/dev_fbank $exp_dir/decode || exit 1
fi

exit 0
