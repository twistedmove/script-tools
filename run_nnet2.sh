#!/bin/bash
#modify from run_nnet2_ms.sh and run_nnet2_common.sh
#wujian@2017.7.5

. ./path.sh


stage=0


gmm_dir=exp/sat1
ali_dir=exp/sat1_align
gph_dir=exp/sat1/graph
exp_dir=exp/nnet2_online/nnet2_ms

train_cmd=run.pl
decode_cmd=run.pl
train_stage=-10
splice_indexes="layer0/-2:-1:0:1:2 layer1/-1:2 layer2/-3:3 layer3/-7:2 layer4/-3:3"


parallel_opts="-l gpu=1"
num_threads=1
minibatch_size=512

common_egs_dir=
decode_nj=5

ivector_extractor=exp/nnet2_online/extractor

set -e
. parse_options.sh || exit 1

if [ $stage -le 1 ]; then
    
    echo "FEATURE EXTRACTING..."
    # train => train_hires/train_scaled_hires
    for dir in train train_scaled; do utils/copy_data_dir.sh data/train data/${dir}_hires; done
    # dev   => dev_hires
    utils/copy_data_dir.sh data/dev data/dev_hires 

    tr_hires="data/train_scaled_hires"

    # generate wav.scp in train_scaled_hires
    # different from hkust format
    cat $tr_hires/wav.scp | python -c "
import sys, random
lowb = 1.0 / 8
high = 2.0
for line in sys.stdin.readlines():
    token = line.strip().split()
    if len(token) == 0:
        continue
    print '{0} sox --vol {1} -t wav {2} -t wav - |'.format(token[0], random.uniform(lowb, high), token[1])
    "| sort -k1,1 -u  > $tr_hires/wav.scp_scaled || exit 1
    mv $tr_hires/wav.scp $tr_hires/wav.scp_nonorm
    mv $tr_hires/wav.scp_scaled $tr_hires/wav.scp

    # make hires_mfcc_pitch feats and cmvn
    # -3 to get no_pitch feats
    for dir in train_scaled_hires train_hires dev_hires; do
        
        steps/make_mfcc_pitch_online.sh --nj 10 --mfcc-config conf/mfcc_hires.conf --cmd "$train_cmd" \
            data/$dir exp/make_hires/$dir mfcc_hires || exit 1
        steps/compute_cmvn_stats.sh data/$dir exp/make_hires/$dir mfcc_hires || exit 1
        utils/fix_data_dir.sh data/$dir

        utils/data/limit_feature_dim.sh 0:39 data/$dir data/${dir}_nopitch || exit 1
    done

    steps/compute_cmvn_stats.sh data/train_scaled_hires_nopitch \
        exp/make_hires/train_scaled_hires_nopitch mfcc_hires  || exit 1
    # for ubm(10k/60k)
    utils/subset_data_dir.sh --first data/train_scaled_hires_nopitch 10000 data/train_scaled_hires_10k
    # LDA+MLLT
    utils/subset_data_dir.sh --first data/train_scaled_hires_nopitch 30000 data/train_scaled_hires_30k
fi

if [ $stage -le 2 ]; then
    echo "ALIGNING DATA[10K]..."
    # get original subset of data
    utils/subset_data_dir.sh --first data/train 30000 data/train_30k
    # align data use model triple-phone system
    steps/align_si.sh --cmd $train_cmd --nj 10 data/train_30k data/lang exp/tri1 exp/tri1_30k_align || exit 1
    
    echo "TRAINING LDA+MLLT[30K]..."
    # LDA+MLLT prepare for UBM
    steps/train_lda_mllt.sh --cmd "$train_cmd" --num-iters 13 --splice-opts "--left-context=3 --right-context=3" \
        5500 90000 data/train_scaled_hires_30k data/lang exp/tri1_30k_align exp/nnet2_online/lda_mllt

    echo "TRAINING UBM[10K]..."
    # use smaller data to get ubm
    steps/online/nnet2/train_diag_ubm.sh --cmd "$train_cmd" --nj 10 --num-frames 200000 \
        data/train_scaled_hires_10k 512 exp/nnet2_online/lda_mllt exp/nnet2_online/diag_ubm
fi

if [ $stage -le 3 ]; then
    # use 30k data to train ivector
    echo "TRAINING IVECTOR..."
    steps/online/nnet2/train_ivector_extractor.sh --cmd "$train_cmd" --nj 10 \
        data/train_scaled_hires_30k exp/nnet2_online/diag_ubm $ivector_extractor || exit 1

    steps/online/nnet2/copy_data_dir.sh --utts-per-spk-max 2 data/train_hires_nopitch data/train_hires_nopitch_max2
    
    echo "EXTRACTING IVECTORS ON TRAIN/DEV DATASET..."
    steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj 10 \
        data/train_hires_nopitch_max2 $ivector_extractor exp/nnet2_online/ivectors_train || exit 1

    steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj 10 \
        data/dev_hires_nopitch $ivector_extractor exp/nnet2_online/ivectors_dev || exit 1
fi

if [ $stage -le 4 ]; then
    echo "NNET2 TRAINING..."
    # increase jobs from 3 to 8, use multisplice and pnorm nnet
    steps/nnet2/train_multisplice_accel2.sh --stage $train_stage \
        --num-epochs 4 --num-jobs-initial 3 --num-jobs-final 8 \
        --num-hidden-layers 5 --splice-indexes "$splice_indexes" \
        --feat-type raw \
        --online-ivector-dir exp/nnet2_online/ivectors_train \
        --cmvn-opts "--norm-means=false --norm-vars=false" \
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
        data/train_hires data/lang $ali_dir $exp_dir || exit 1
fi

if [ $stage -le 5 ]; then
    echo "DECODING AND EVALUATING..."
    # jobs could not be too large cause HCLG size
    # offline
    steps/nnet2/decode.sh --nj $decode_nj --cmd "$decode_cmd" \
        --config conf/decode.config --online-ivector-dir exp/nnet2_online/ivectors_dev \
        $gph_dir data/dev_hires $exp_dir/decode || exit 1

    steps/online/nnet2/prepare_online_decoding.sh --mfcc-config conf/mfcc_hires.conf \
        --add-pitch true data/lang $ivector_extractor $exp_dir ${exp_dir}_online || exit 1
    # decoding online
    steps/online/nnet2/decode.sh --config conf/decode.config \
        --cmd "$decode_cmd" --nj $decode_nj $gph_dir data/dev_hires ${exp_dir}_online/decode || exit 1
    # decoding per-utt
    steps/online/nnet2/decode.sh --config conf/decode.config --per-utt true \
        --cmd "$decode_cmd" --nj $decode_nj $gph_dir data/dev_hires ${exp_dir}_online/decode_per_utt || exit 1
fi

exit 0
