#!/bin/bash
#wujian@2017.7.7


gmm_dir=exp/sat1
ali_dir=exp/sat1_align
gph_dir=$gmm_dir/graph
exp_dir=exp/nnet3/nnet3_std_pnorm

initial_effective_lrate=0.0015
final_effective_lrate=0.00015
num_epochs=4
num_jobs_initial=2
num_jobs_final=8
remove_egs=true
train_stage=-10

stage=2

. ./path.sh
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
    echo "CREATING NNET3 CONFIGS...";

    #--relu-dim 850 \
    python steps/nnet3/tdnn/make_configs.py  \
        --feat-dir data/train_fbank \
        --ali-dir $ali_dir \
        --pnorm-input-dim 4000 \
        --pnorm-output-dim 400 \
        --splice-indexes "-5,-4,-3,-2,-1,0,1,2,3,4,5 0 0 0 0"  \
        --use-presoftmax-prior-scale true \
        $exp_dir/configs || exit 1;
fi

if [ $stage -le 3 ]; then
    steps/nnet3/train_dnn.py --stage=$train_stage \
        --cmd="run.pl" \
        --feat.cmvn-opts="--norm-means=true --norm-vars=true" \
        --trainer.num-epochs $num_epochs \
        --trainer.optimization.num-jobs-initial $num_jobs_initial \
        --trainer.optimization.num-jobs-final $num_jobs_final \
        --trainer.optimization.initial-effective-lrate $initial_effective_lrate \
        --trainer.optimization.final-effective-lrate $final_effective_lrate \
        --egs.dir "$common_egs_dir" \
        --cleanup.remove-egs $remove_egs \
        --cleanup.preserve-model-interval 500 \
        --use-gpu true \
        --feat-dir=data/train_fbank \
        --ali-dir $ali_dir \
        --lang data/lang \
        --dir=$exp_dir || exit 1
fi

if [ $stage -le 4 ]; then
    echo "DECODING AND EVALUATING..."
    # jobs could not be too large cause HCLG size
    steps/nnet3/decode.sh --nj 5 --cmd run.pl \
        --config conf/decode.config $gph_dir data/dev_fbank $exp_dir/decode || exit 1
fi

echo "Done!"
