#!/bin/bash
# modified from run_ivector_common.sh and train_tdnn.sh
# train ivector, extract feature and tdnn training, testing
# wujian@2017.7.5

stage=0

gmm_dir=exp/sat1
ali_dir=exp/nnet3/sat1_sp_ali
exp_dir=exp/nnet3/tdnn_sp
gph_dir=exp/sat1/graph
train_cmd=run.pl
ivector_extractor=exp/nnet3/extractor

train_stage=-10
common_egs_dir=

initial_effective_lrate=0.0015
final_effective_lrate=0.00015
num_epochs=4
num_jobs_initial=2
num_jobs_final=8
remove_egs=true

set -e
. ./path.sh || exit 1
. parse_options.sh || exit 1

# 准备dev_hires, train_hires 调整音量
# 特征是mfcc+online+pitch 
# 还准备了去除pitch信息的特征
if [ $stage -le 1 ]; then
    echo "$0: 1. PREPARE ONLINE-MFCC-HIRES..."
    for dir in train dev; do utils/copy_data_dir.sh data/train data/${dir}_hires; done
    tr_hires="data/train_hires"

    cat $tr_hires/wav.scp | python -c "
import sys, random
lowb = 1.0 / 8
high = 2.0
for line in sys.stdin.readlines():
    token = line.strip().split()
    if len(token) == 0:
        continue
    print '{0} sox --vol {1} -t wav {2} -t wav - |'.format(token[0], random.uniform(lowb, high), token[1])
    "| sort -k1,1 -u  > $tr_hires/wav.scp_scaled || exit 1;
    mv $tr_hires/wav.scp $tr_hires/wav.scp_nonorm
    mv $tr_hires/wav.scp_scaled $tr_hires/wav.scp

    for dir in train_hires dev_hires; do

        steps/make_mfcc_pitch_online.sh --nj 10 --mfcc-config conf/mfcc_hires.conf --cmd "$train_cmd" \
            data/$dir exp/make_hires/$dir mfcc_hires || exit 1;
        steps/compute_cmvn_stats.sh data/$dir exp/make_hires/$dir mfcc_hires || exit 1;

        # make MFCC data dir without pitch to extract iVector
        utils/data/limit_feature_dim.sh 0:39 data/$dir data/${dir}_nopitch || exit 1;
        steps/compute_cmvn_stats.sh data/${dir}_nopitch exp/make_hires/$dir mfcc_hires  || exit 1;
    done
fi

# 使用nopitch信息训练一个LDA+MLLT模型
# nopitch信息和LDA+MLLT模型训练一个ubm
# nopitch和ubm训练ivector

if [ $stage -le 2 ]; then
    echo "$0: 2.1 LDA-MLLT TRAINING FOR MFCC-HIRES..."
    steps/train_lda_mllt.sh --cmd "$train_cmd" --num-iters 13 --realign-iters "" \
        --splice-opts "--left-context=3 --right-context=3" \
        5000 10000 data/train_hires_nopitch data/lang ${gmm_dir}_ali exp/nnet3/lda_mllt || exit 1

    echo "$0: 2.2 TRAINING UBM..."
    steps/online/nnet2/train_diag_ubm.sh --cmd "$train_cmd" --nj 10 \
        --num-frames 700000 data/train_hires_nopitch 512 exp/nnet3/lda_mllt exp/nnet3/diag_ubm || exit 1

    echo "$0: 2.3 TRAINING IVECTOR..."
    steps/online/nnet2/train_ivector_extractor.sh --cmd "$train_cmd" --nj 10 \
        data/train_hires_nopitch exp/nnet3/diag_ubm $ivector_extractor || exit 1;
fi


# 准备变速训练集合 train_sp
# 准备online的pitch和nopitch信息
if [ $stage -le 3 ]; then
    echo "$0: 3. PREPARE TRAIN_SP..."
    # train + speed pertrub => train_sp
    speed=(0.9 1.0 1.1)
    for idx in $(seq 0 2); do utils/perturb_data_dir_speed.sh ${speed[$idx]} data/train data/temp${idx}; done

    utils/combine_data.sh --extra-files utt2uniq data/train_sp data/temp0 data/temp1 data/temp2
    rm -r data/temp0 data/temp1 data/temp2

    for dir in train_sp; do
        steps/make_mfcc_pitch_online.sh --cmd "$train_cmd" --nj 10 \
            data/$dir exp/make_mfcc/$dir mfcc_perturbed || exit 1;
        steps/compute_cmvn_stats.sh data/$dir exp/make_mfcc/$dir mfcc_perturbed || exit 1;
    done
    
    # align train_sp
    utils/fix_data_dir.sh data/train_sp

    # speed perturb => high resolution
    utils/copy_data_dir.sh data/train_sp data/train_sp_hires
    for dir in train_sp_hires; do
        steps/make_mfcc_pitch_online.sh --cmd "$train_cmd" --nj 10 --mfcc-config conf/mfcc_hires.conf \
            data/$dir exp/make_hires/$dir mfcc_perturbed_hires || exit 1;
        steps/compute_cmvn_stats.sh data/$dir exp/make_hires/$dir mfcc_perturbed_hires || exit 1;

        utils/data/limit_feature_dim.sh 0:39 data/$dir data/${dir}_nopitch || exit 1;
        steps/compute_cmvn_stats.sh data/${dir}_nopitch exp/make_hires/$dir mfcc_perturbed_hires || exit 1;
    done

    utils/fix_data_dir.sh data/train_sp_hires
fi


# 由train_sp_hires_nopitch生成一个max2数据
# 提取train/dev ivector
if [ $stage -le 4 ]; then
    echo "$0: 4.1 EXTRACT IVECTOR FOR TRAIN_SP/DEV..."

    steps/online/nnet2/copy_data_dir.sh --utts-per-spk-max 2 \
        data/train_sp_hires_nopitch data/train_sp_hires_nopitch_max2

    steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj 10 \
        data/train_sp_hires_nopitch_max2 $ivector_extractor exp/nnet3/ivectors_train_sp \
        || (echo "$0: error extracting ivectors on training set" && exit 1);

    steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj 10 \
        data/dev_hires_nopitch $ivector_extractor exp/nnet3/ivectors_dev \
        || (echo "$0: error extracting ivectors on dev set" && exit 1);

    # lowres + sp的对齐结果，因为gmm_dir是低分辨率的
    echo "$0: 4.2 PREPARE ALIGNMENTS FOR TRAIN_SP..."
    steps/align_fmllr.sh --nj 10 --cmd "$train_cmd" data/train_sp data/lang $gmm_dir $ali_dir || exit 1
fi


# 对齐，训练
if [ $stage -le 5 ]; then 
    echo "$0: 5. TRAINING NNET3..."

    num_targets=$(tree-info $ali_dir/tree | grep num-pdfs | awk '{print $2}')
    mkdir -p $exp_dir/configs

    cat <<EOF > $exp_dir/configs/network.xconfig
    input dim=100 name=ivector
    input dim=43 name=input
    fixed-affine-layer name=lda input=Append(-2,-1,0,1,2,ReplaceIndex(ivector, t, 0)) affine-transform-file=$exp_dir/configs/lda.mat
    relu-batchnorm-layer name=tdnn1 dim=850
    relu-batchnorm-layer name=tdnn2 dim=850 input=Append(-1,0,2)
    relu-batchnorm-layer name=tdnn3 dim=850 input=Append(-3,0,3)
    relu-batchnorm-layer name=tdnn4 dim=850 input=Append(-7,0,2)
    relu-batchnorm-layer name=tdnn5 dim=850 input=Append(-3,0,3)
    relu-batchnorm-layer name=tdnn6 dim=850
    output-layer name=output input=tdnn6 dim=$num_targets max-change=1.5
EOF

  steps/nnet3/xconfig_to_configs.py --xconfig-file $exp_dir/configs/network.xconfig --config-dir $exp_dir/configs/

#    has been deplicated
#    python steps/nnet3/tdnn/make_configs.py  \
#        --feat-dir data/train_sp_hires \
#        --ivector-dir exp/nnet3/ivectors_train_sp \
#        --ali-dir $ali_dir \
#        --relu-dim 850 \
#        --splice-indexes "-2,-1,0,1,2 -1,2 -3,3 -7,2 -3,3 0 0"  \
#        --use-presoftmax-prior-scale true \
#        $exp_dir/configs || exit 1;


    steps/nnet3/train_dnn.py --stage=$train_stage \
        --cmd="run.pl" \
        --feat.online-ivector-dir exp/nnet3/ivectors_train_sp \
        --feat.cmvn-opts="--norm-means=false --norm-vars=false" \
        --trainer.num-epochs $num_epochs \
        --trainer.optimization.num-jobs-initial $num_jobs_initial \
        --trainer.optimization.num-jobs-final $num_jobs_final \
        --trainer.optimization.initial-effective-lrate $initial_effective_lrate \
        --trainer.optimization.final-effective-lrate $final_effective_lrate \
        --egs.dir "$common_egs_dir" \
        --cleanup.remove-egs $remove_egs \
        --cleanup.preserve-model-interval 500 \
        --use-gpu true \
        --feat-dir=data/train_sp_hires \
        --ali-dir $ali_dir \
        --lang data/lang \
        --dir=$exp_dir  || exit 1;

#    has been deplicated
#    steps/nnet3/train_tdnn.sh --num-epochs 4 --num-jobs-initial 2 --num-jobs-final 8 \
#        --splice-indexes "-2,-1,0,1,2 -1,2 -3,3 -7,2 -3,3 0 0" \
#        --feat-type raw \
#        --online-ivector-dir exp/nnet3/ivectors_train_sp \
#        --cmvn-opts "--norm-means=false --norm-vars=false" \
#        --initial-effective-lrate 0.0015 --final-effective-lrate 0.00015 \
#        --cmd "run.pl" \
#        --relu-dim 850 \
#        --stage -3 \
#        data/train_sp_hires data/lang $ali_dir $exp_dir || exit 1;
fi 

if [ $stage -le 6 ]; then
    echo "$0: 6. ONLINE-DECODING..."
    steps/online/nnet3/prepare_online_decoding.sh --mfcc-config conf/mfcc_hires.conf 
        --add-pitch true data/lang exp/nnet3/extractor $exp_dir ${exp_dir}_online || exit 1;

    steps/online/nnet3/decode.sh --config conf/decode.config --cmd run.pl --nj 10 \
        $gph_dir data/dev_hires ${exp_dir}_online/decode || exit 1;

    steps/online/nnet3/decode.sh --config conf/decode.config --cmd run.pl --nj 10 \
        --per-utt true $gph_dir data/dev_hires ${exp_dir}_online/decode_per_utt || exit 1;
fi

echo "Done!"
