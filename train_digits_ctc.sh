#!/bin/bash
#by wujian 2017.4.7

[ -z $KALDI_ROOT ] && [ -z $EESEN_ROOT ] && echo "export KALDI_ROOT/EESEN_ROOT first" && exit 1

stage=1

data_dir="data"
rate_cv=0.1
run_cmd="run.pl"

. parse_options.sh || exit 1

if [ $stage -le 1 ]; then
    echo "1. PREPARE DATA"
    [ ! -f $data_dir/wav.scp ] || [ ! -f $data_dir/text ] && echo "no wav.scp/text in $data_dir" && exit 1
    awk '{print $1 "\t" $1}' $data_dir/wav.scp | tee $data_dir/utt2spk $data_dir/spk2utt > /dev/null
    to_utt_num=$(cat $data_dir/wav.scp | wc -l)
    tr_utt_num=$(echo $to_utt_num $rate_cv | awk '{print int($1 * (1 - $2))}')
    utils/shuffle_list.pl $data_dir/wav.scp | split -l $tr_utt_num -d -a 1 - sp_ || exit 1
    cat sp_0 | sort > $data_dir/tr.scp && rm sp_0 || exit 1
    cat sp_1 | sort > $data_dir/cv.scp && rm sp_1 || exit 1
    echo "size of cv: $(cat $data_dir/cv.scp | wc -l) tr: $(cat $data_dir/tr.scp | wc -l)"
    utils/subset_data_dir.sh --utt-list $data_dir/tr.scp $data_dir $data_dir/train_tr || exit 1
    utils/subset_data_dir.sh --utt-list $data_dir/cv.scp $data_dir $data_dir/train_cv || exit 1
fi

if [ $stage -le 2 ]; then
    echo "2. MAKE FEATURE"
    feats_dir="fbank"
    steps/make_fbank.sh --cmd $run_cmd --nj 8 $data_dir/train_tr exp/make_fbank/train_tr $feats_dir || exit 1
    utils/fix_data_dir.sh $data_dir/train_tr || exit 1
    steps/compute_cmvn_stats.sh $data_dir/train_tr exp/make_fbank/train_tr $feats_dir || exit 1

    steps/make_fbank.sh --cmd $run_cmd $data_dir/train_cv exp/make_fbank/train_cv $feats_dir || exit 1
    utils/fix_data_dir.sh $data_dir/train_cv || exit 1
    steps/compute_cmvn_stats.sh $data_dir/train_cv exp/make_fbank/train_cv $feats_dir || exit 1
fi

if [ $stage -le 3 ]; then
    echo "3. CTC TRAINING"
    # with add-delta
    fea_dim=40
    hid_num=1
    hid_dim=128
    tgt_num=$[$(cat $data_dir/lexicon_numbers.txt | wc -l) + 1]
    exp_dir=exp/train_digits_l${hid_num}_c${hid_dim}_nosil_uni

    mkdir -p $exp_dir
    utils/model_topo.py --input-feat-dim $fea_dim --lstm-layer-num $hid_num \
        --lstm-cell-dim $hid_dim --target-num $tgt_num --lstm-type "uni" \
        --fgate-bias-init 1.0 > $exp_dir/nnet.proto || exit 1;

    utils/prep_ctc_trans.py $data_dir/lexicon_numbers.txt $data_dir/train_tr/text "<UNK>" | gzip -c - > $exp_dir/labels.tr.gz || exit 1
    utils/prep_ctc_trans.py $data_dir/lexicon_numbers.txt $data_dir/train_cv/text "<UNK>" | gzip -c - > $exp_dir/labels.cv.gz || exit 1
    #cat $data_dir/train_tr/text | gzip -c - > $exp_dir/labels.tr.gz
    #cat $data_dir/train_cv/text | gzip -c - > $exp_dir/labels.cv.gz

    steps/train_ctc_parallel.sh --add-deltas false --num-sequence 10 \
        --learn-rate 0.00004 --report-step 1000 --halving-after-epoch 12 \
        $data_dir/train_tr $data_dir/train_cv $exp_dir || exit 1;
fi

echo "done"
