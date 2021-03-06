#!/bin/bash
# 														Hyungwon Yang
# 														hyung8758@gmail.com
# 														EMCS Labs

# This script buils Korean ASR model based on kaldi toolkit.
# Before running this script, corpus dataset needs to be divided into 
# two parts: train and test. Allocate datasets such as 'fv01', or 'mv07'
# to train and test folders. This script will detect folder names and 
# extract data features.

# RECOMMENDATION
# 1. Name your decoding directories as decode_train and decode_test.

# Remove all unrelated files.
# . local/unset_all.sh
# Set path and requisite variables.
# Kaldi root: Where is your kaldi directory?
kaldi=/Users/hyungwonyang/kaldi
# Source data: Where is your source (wavefile) data directory?
# In the source directory, datasets should be assigned in two directories: train, and test.
source=/Users/hyungwonyang/Documents/data/krs_data
# Current directory.
curdir=$PWD
# Log file: Log file will be saved with the name set below.
logfile=1st_test
# Log directory.
logdir=$curdir/log
# Result file name
resultfile=result.txt
# Number of jobs.
train_nj=2
test_nj=1

# Start logging.
mkdir -p $logdir
echo ====================================================================== | tee $logdir/$logfile.log
echo "                       Kaldi ASR Project	                		  " | tee -a $logdir/$logfile.log
echo ====================================================================== | tee -a $logdir/$logfile.log
echo Tracking the training procedure on: `date` | tee -a $logdir/$logfile.log
echo KALDI_ROOT: $kaldi | tee -a $logdir/$logfile.log
echo DATA_ROOT: $source | tee -a $logdir/$logfile.log
START=`date +%s`

# This step will generate path.sh based on written path above.
[ ! -f path.sh ] && bash local/make_path.sh $kaldi $curdir
source path.sh
. cmd.sh
. local/check_code.sh $kaldi


echo ====================================================================== | tee -a $logdir/$logfile.log
echo "                       Data Preparation	                		  " | tee -a $logdir/$logfile.log 
echo ====================================================================== | tee -a $logdir/$logfile.log 
start1=`date +%s`; log_s1=`date | awk '{print $4}'`
echo $log_s1 >> $logdir/$logfile.log 
echo START TIME: $log_s1 | tee -a $logdir/$logfile.log 

# Check source file is ready to be used. Does train and test folders exist inside the source folder?
if [ ! -d $source/train -o ! -d $source/test ] ; then
	echo "train and test folders are not present in $source directory." || exit 1
fi

# In each train and test data folder, distribute 'text', 'utt2spk', 'spk2utt', 'wav.scp', 'segments'.
for set in train test; do
	echo -e "Generating prerequisite files...\nSource directory:$source/$set" | tee -a $logdir/$logfile.log 
	local/krs_prep_data.sh \
		$source/$set \
		$curdir \
		$curdir/data/$set || exit 1
done

end1=`date +%s`; log_e1=`date | awk '{print $4}'`
taken1=`local/track_time.sh $start1 $end1`
echo END TIME: $log_e1  | tee -a $logdir/$logfile.log 
echo PROCESS TIME: $taken1 sec  | tee -a $logdir/$logfile.log


echo ====================================================================== | tee -a $logdir/$logfile.log 
echo "                       Language Modeling	                		  " | tee -a $logdir/$logfile.log 
echo ====================================================================== | tee -a $logdir/$logfile.log 
start2=`date +%s`; log_s2=`date | awk '{print $4}'`
echo $log_s2 >> $logdir/$logfile.log 
echo START TIME: $log_s2 | tee -a $logdir/$logfile.log 

# Generate lexicon, lexiconp, silence, nonsilence, optional_silence, extra_questions
# from the train dataset.
echo "Generating dictionary related files..." | tee -a $logdir/$logfile.log 
local/krs_prep_dict.sh \
	$source/train \
	$curdir \
	$curdir/data/local/dict || exit 1

# Insert <UNK> in the lexicon.txt and lexiconp.txt.
sed -i '1 i\<UNK> <UNK>' $curdir/data/local/dict/lexicon.txt
sed -i '1 i\<UNK> 1.0 <UNK>' $curdir/data/local/dict/lexiconp.txt

# Make ./data/lang folder and other files.
echo "Generating language models..." | tee -a $logdir/$logfile.log 
utils/prepare_lang.sh \
	$curdir/data/local/dict \
	"<UNK>" \
	$curdir/data/local/lang \
	$curdir/data/lang

# Set ngram-count folder.
if [[ -z $(find $KALDI_ROOT/tools/srilm/bin -name ngram-count) ]]; then
	echo "SRILM might not be installed on your computer. Please find kaldi/tools/install_srilm.sh and install the package." #&& exit 1
else
	nc=`find $KALDI_ROOT/tools/srilm/bin -name ngram-count`
	# Make lm.arpa from textraw.
	$nc -text $curdir/data/train/textraw -lm $curdir/data/lang/lm.arpa
fi

# Make G.fst from lm.arpa.
echo "Generating G.fst from lm.arpa..." | tee -a $logdir/$logfile.log
cat $curdir/data/lang/lm.arpa | $KALDI_ROOT/src/lmbin/arpa2fst --disambig-symbol=#0 --read-symbol-table=$curdir/data/lang/words.txt - $curdir/data/lang/G.fst
# Check .fst is stochastic or not.
$KALDI_ROOT/src/fstbin/fstisstochastic $curdir/data/lang/G.fst


end2=`date +%s`; log_e2=`date | awk '{print $4}'`
taken2=`local/track_time.sh $start2 $end2`
echo END TIME: $log_e2  | tee -a $logdir/$logfile.log 
echo PROCESS TIME: $taken2 sec  | tee -a $logdir/$logfile.log


echo ====================================================================== | tee -a $logdir/$logfile.log 
echo "                   Acoustic Feature Extraction	             	  " | tee -a $logdir/$logfile.log 
echo ====================================================================== | tee -a $logdir/$logfile.log 
start3=`date +%s`; log_s3=`date | awk '{print $4}'`
echo $log_s3 >> $logdir/$logfile.log 
echo START TIME: $log_s3 | tee -a $logdir/$logfile.log 

### MFCC ###
# Generate mfcc configure.
mkdir -p conf
echo -e '--use-energy=false\n--sample-frequency=16000' > conf/mfcc.conf
# mfcc feature extraction.
mfccdir=$curdir/mfcc
for set in train test; do
	echo "Extracting $set data MFCC features..." | tee -a $logdir/$logfile.log
	 steps/make_mfcc.sh \
	 	$curdir/data/$set \
	 	$curdir/exp/make_mfcc/$set \
	 	$mfccdir
# Compute cmvn. (This steps should be processed right after mfcc features are extracted.)
	 echo "Computing CMVN on $set data MFCC..." | tee -a $logdir/$logfile.log 
	 steps/compute_cmvn_stats.sh \
	 	$curdir/data/$set \
	 	$curdir/exp/make_mfcc/$set \
	 	$mfccdir
done

# ### PLP ###
# # Generate plp configure.
# echo -e '--sample-frequency=16000' > $curdir/conf/plp.conf
# plpdir=$curdir/plp
# # plp feature extraction.
# for set in train test; do
# 		echo "Extracting $set data PLP features..." | tee -a $logdir/$logfile.log
# 	 	steps/make_plp.sh \
# 			$curdir/data/$set \
# 			$curdir/exp/make_plp/$set \
# 			$plpdir
# # Compute cmvn. (This steps should be processed right after plp features are extracted.)
# 	echo "Computing CMVN on $set data PLP..." | tee -a $logdir/$logfile.log 
# 	steps/compute_cmvn_stats.sh \
# 	 	$curdir/data/$set \
# 	 	$curdir/exp/make_plp/$set \
# 	 	$plpdir
# done

# data directories sanity check.
echo "Examining generated datasets..." | tee -a $logdir/$logfile.log 
utils/validate_data_dir.sh $curdir/data/train
utils/fix_data_dir.sh $curdir/data/train


end3=`date +%s`; log_e3=`date | awk '{print $4}'`
taken3=`local/track_time.sh $start3 $end3`
echo END TIME: $log_e3  | tee -a $logdir/$logfile.log 
echo PROCESS TIME: $taken3 sec  | tee -a $logdir/$logfile.log


echo ====================================================================== | tee -a $logdir/$logfile.log 
echo "                    Train & Decode: Monophone	                 	  " | tee -a $logdir/$logfile.log 
echo ====================================================================== | tee -a $logdir/$logfile.log 
start4=`date +%s`; log_s4=`date | awk '{print $4}'`
echo $log_s4 >> $logdir/$logfile.log 
echo START TIME: $log_s4 | tee -a $logdir/$logfile.log 

# Monophone option setting.
mono_train_opt="--boost-silence 1.25 --nj $train_nj --cmd $train_cmd"
mono_align_opt="--nj $train_nj --cmd $decode_cmd"
mono_decode_opt="--nj $train_nj --cmd $decode_cmd"

echo "Monophone trainig options: $mono_train_opt" 	| tee -a $logdir/$logfile.log
echo "Monophone aligning options: $mono_align_opt" 	| tee -a $logdir/$logfile.log
echo "Monophone decoding options: $mono_decode_opt" | tee -a $logdir/$logfile.log

# Monophone train.
echo "Training monophone..." | tee -a $logdir/$logfile.log 
steps/train_mono.sh \
	$mono_train_opt \
	$curdir/data/train \
	$curdir/data/lang \
	$curdir/exp/mono || exit 1

# # Graph structuring.
# # make HCLG graph (optional! train과는 무관, 오직 decode만을 위해.)
# # This script creates a fully expanded decoding graph (HCLG) that represents
# # all the language-model, pronunciation dictionary (lexicon), context-dependency,
# # and HMM structure in our model.  The output is a Finite State Transducer
# # that has word-ids on the output, and pdf-ids on the input (these are indexes
# # that resolve to Gaussian Mixture Models).
# # exp/mono/graph에 가면 결과 graph가 만들어져 있음
echo "Generating monophone graph..." | tee -a $logdir/$logfile.log 
utils/mkgraph.sh $curdir/data/lang $curdir/exp/mono $curdir/exp/mono/graph 

# Monophone aglinment.
# train된 model파일인 mdl과 occs로부터 새로운 align을 생성
echo "Aligning..." | tee -a $logdir/$logfile.log 
steps/align_si.sh \
	$mono_align_opt \
	$curdir/data/train \
	$curdir/data/lang \
	$curdir/exp/mono \
	$curdir/exp/mono_ali || exit 1

# Data decoding.
# (This is just decoding the trained model, not part of training process.)
# echo "Decoding with monophone model..." | tee -a $logdir/$logfile.log 
# echo "Decoding train data..." | tee -a $logdir/$logfile.log
# steps/decode.sh \
# 	$mono_decode_opt \
# 	$curdir/exp/mono/graph \
# 	$curdir/data/train \
# 	$curdir/exp/mono/decode_train
# echo "Decoding test data..." | tee -a $logdir/$logfile.log
steps/decode.sh \
	$mono_decode_opt \
	$curdir/exp/mono/graph \
	$curdir/data/test \
	$curdir/exp/mono/decode_test

### Optional ###
# tree structuring.
# $KALDI_ROOT/src/bin/draw-tree $curdir/data/lang/phones.txt $curdir/exp/mono/tree \
# | dot -Tps -Gsize=8,10.5 | ps2pdf - tree.pdf 2>/dev/null


end4=`date +%s`; log_e4=`date | awk '{print $4}'`
taken4=`local/track_time.sh $start4 $end4`
echo END TIME: $log_e4  | tee -a $logdir/$logfile.log 
echo PROCESS TIME: $taken4 sec  | tee -a $logdir/$logfile.log


echo ====================================================================== | tee -a $logdir/$logfile.log 
echo "           Train & Decode: Triphone1 [delta+delta-delta]	       	  " | tee -a $logdir/$logfile.log 
echo ====================================================================== | tee -a $logdir/$logfile.log 
start5=`date +%s`; log_s5=`date | awk '{print $4}'`
echo $log_s5 >> $logdir/$logfile.log 
echo START TIME: $log_s5 | tee -a $logdir/$logfile.log 

# Triphone1 option setting.
tri1_train_opt="--cmd $train_cmd"
tri1_align_opt="--nj $train_nj --cmd $decode_cmd"
tri1_decode_opt="--nj $train_nj --cmd $decode_cmd"

echo "Triphone1 training options: $tri1_train_opt"	| tee -a $logdir/$logfile.log
echo "Triphone1 aligning options: $tri1_align_opt"	| tee -a $logdir/$logfile.log
echo "Triphone1 decoding options: $tri1_decode_opt"	| tee -a $logdir/$logfile.log

# Triphone1 training.
echo "Training delta+double-delta..." | tee -a $logdir/$logfile.log 
steps/train_deltas.sh \
	$tri1_train_opt \
	2000 \
	10000 \
	$curdir/data/train \
	$curdir/data/lang \
	$curdir/exp/mono_ali \
	$curdir/exp/tri1 || exit 1

# Graph drawing.
echo "Generating delta+double-delta graph..." | tee -a $logdir/$logfile.log 
utils/mkgraph.sh \
	$curdir/data/lang \
	$curdir/exp/tri1 \
	$curdir/exp/tri1/graph

# Triphone1 aglining.
echo "Aligning..." | tee -a $logdir/$logfile.log 
steps/align_si.sh \
	$tri1_align_opt \
	$curdir/data/train \
	$curdir/data/lang \
	$curdir/exp/tri1 \
	$curdir/exp/tri1_ali ||  exit 1

# Data decoding.
# echo "Decoding with delta+double-delta model..." | tee -a $logdir/$logfile.log 
# echo "Decoding train data..." | tee -a $logdir/$logfile.log
# steps/decode.sh \
# 	$tri1_decode_opt \
# 	$curdir/exp/tri1/graph \
# 	$curdir/data/train \
# 	$curdir/exp/tri1/decode_train
# echo "Decoding test data..." | tee -a $logdir/$logfile.log
# steps/decode.sh \
# 	$tri1_decode_opt \
# 	$curdir/exp/tri1/graph \
# 	$curdir/data/test \
# 	$curdir/exp/tri1/decode_test

end5=`date +%s`; log_e5=`date | awk '{print $4}'`
taken5=`local/track_time.sh $start5 $end5`
echo END TIME: $log_e5  | tee -a $logdir/$logfile.log 
echo PROCESS TIME: $taken5 sec  | tee -a $logdir/$logfile.log


echo ====================================================================== | tee -a $logdir/$logfile.log 
echo "               Train & Decode: Triphone2 [LDA+MLLT]	         	  " | tee -a $logdir/$logfile.log 
echo ====================================================================== | tee -a $logdir/$logfile.log 
start6=`date +%s`; log_s6=`date | awk '{print $4}'`
echo $log_s6 >> $logdir/$logfile.log 
echo START TIME: $log_s6 | tee -a $logdir/$logfile.log 

# Triphone2 option setting.
tri2_train_opt="--cmd $train_cmd"
tri2_align_opt="--nj $train_nj --cmd $decode_cmd"
tri2_decode_opt="--nj $train_nj --cmd $decode_cmd"

echo "Triphone2 trainig options: $tri2_train_opt"	| tee -a $logdir/$logfile.log
echo "Triphone2 aligning options: $tri2_align_opt"	| tee -a $logdir/$logfile.log
echo "Triphone2 decoding options: $tri2_decode_opt"	| tee -a $logdir/$logfile.log

# Triphone2 training.
echo "Training LDA+MLLT..." | tee -a $logdir/$logfile.log 
steps/train_lda_mllt.sh \
	$tri2_train_opt \
	2500 \
	15000 \
	$curdir/data/train \
	$curdir/data/lang \
	$curdir/exp/tri1_ali \
	$curdir/exp/tri2 ||  exit 1

# Graph drawing.
echo "Generating LDA+MLLT graph..." | tee -a $logdir/$logfile.log
utils/mkgraph.sh \
	$curdir/data/lang \
	$curdir/exp/tri2 \
	$curdir/exp/tri2/graph

# Triphone2 aglining.
echo "Aligning..." | tee -a $logdir/$logfile.log
steps/align_si.sh \
	$tri2_align_opt \
	$curdir/data/train \
	$curdir/data/lang \
	$curdir/exp/tri2 \
	$curdir/exp/tri2_ali ||  exit 1

# Data decoding.
# echo "Decoding with LDA+MLLT model..." | tee -a $logdir/$logfile.log
# echo "Decoding train data..." | tee -a $logdir/$logfile.log
# steps/decode.sh \
# 	$tri2_decode_opt \
# 	$curdir/exp/tri2/graph \
# 	$curdir/data/train \
# 	$curdir/exp/tri2/decode_train
# echo "Decoding test data..." | tee -a $logdir/$logfile.log
# steps/decode.sh \
# 	$tri2_decode_opt \
# 	$curdir/exp/tri2/graph \
# 	$curdir/data/test \
# 	$curdir/exp/tri2/decode_test

end6=`date +%s`; log_e6=`date | awk '{print $4}'`
taken6=`local/track_time.sh $start6 $end6`
echo END TIME: $log_e6  | tee -a $logdir/$logfile.log 
echo PROCESS TIME: $taken6 sec  | tee -a $logdir/$logfile.log


echo ====================================================================== | tee -a $logdir/$logfile.log 
echo "             Train & Decode: Triphone3 [LDA+MLLT+SAT]	         	  " | tee -a $logdir/$logfile.log 
echo ====================================================================== | tee -a $logdir/$logfile.log 
start7=`date +%s`; log_s7=`date | awk '{print $4}'`
echo $log_s7 >> $logdir/$logfile.log 
echo START TIME: $log_s7 | tee -a $logdir/$logfile.log 

# Triphone3 option setting.
tri3_train_opt="--cmd $train_cmd"
tri3_align_opt="--nj $train_nj --cmd $decode_cmd"
tri3_train_decode_opt="--nj $train_nj --cmd $decode_cmd"
tri3_test_decode_opt="--nj $test_nj --cmd $decode_cmd"

echo "Triphone3 trainig options: $tri3_train_opt"				| tee -a $logdir/$logfile.log
echo "Triphone3 aligning options: $tri3_align_opt"				| tee -a $logdir/$logfile.log
echo "Tirphone3 train-decoding options: $tri3_train_decode_opt"	| tee -a $logdir/$logfile.log
echo "Tirphone3 test-decoding options: $tri3_test_decode_opt"	| tee -a $logdir/$logfile.log

# Triphone3 training.
echo "Training LDA+MLLT+SAT..." | tee -a $logdir/$logfile.log
steps/train_sat.sh \
	$tri3_train_opt \
	2500 \
	15000 \
	$curdir/data/train \
	$curdir/data/lang \
	$curdir/exp/tri2_ali \
	$curdir/exp/tri3 ||  exit 1

# Graph drawing.
echo "Generating LDA+MLLT+SAT graph..." | tee -a $logdir/$logfile.log
utils/mkgraph.sh \
	$curdir/data/lang \ 
	$curdir/exp/tri3 \
	$curdir/exp/tri3/graph

# Triphone3 aglining.
echo "Aligning..." | tee -a $logdir/$logfile.log
steps/align_fmllr.sh \
	$tri3_align_opt \
	$curdir/data/train \
	$curdir/data/lang \
	$curdir/exp/tri3 \
	$curdir/exp/tri3_ali ||  exit 1

# Data decoding: train and test datasets.
echo "Decoding with Training LDA+MLLT+SAT model..." | tee -a $logdir/$logfile.log
echo "Decoding train data..." | tee -a $logdir/$logfile.log
steps/decode_fmllr.sh \
	$tri3_train_decode_opt \
	$curdir/exp/tri3/graph \
	$curdir/data/train \
	$curdir/exp/tri3/decode_train
echo "Decoding test data..." | tee -a $logdir/$logfile.log
steps/decode_fmllr.sh \
	$tri3_test_decode_opt \
	$curdir/exp/tri3/graph \
	$curdir/data/test \
	$curdir/exp/tri3/decode_test


end7=`date +%s`; log_e7=`date | awk '{print $4}'`
taken7=`local/track_time.sh $start7 $end7`
echo END TIME: $log_e7  | tee -a $logdir/$logfile.log 
echo PROCESS TIME: $taken7 sec  | tee -a $logdir/$logfile.log


echo ====================================================================== | tee -a $logdir/$logfile.log 
echo "                       Train & Decode: SGMM2 	               	      " | tee -a $logdir/$logfile.log 
echo ====================================================================== | tee -a $logdir/$logfile.log 
start8=`date +%s`; log_s8=`date | awk '{print $4}'`
echo $log_s8 >> $logdir/$logfile.log 
echo START TIME: $log_s8 | tee -a $logdir/$logfile.log 

# SGMM training, with speaker vectors.  This script would normally be called on
# top of fMLLR features obtained from a conventional system, but it also works
# on top of any type of speaker-independent features (based on
# deltas+delta-deltas or LDA+MLLT).  For more info on SGMMs, see the paper "The
# subspace Gaussian mixture model--A structured model for speech recognition".
# (Computer Speech and Language, 2011).

# SGMM2 option setting.
sgmm2_train_opt="--cmd $train_cmd"
sgmm2_align_opt="--nj $train_nj --cmd $decode_cmd --transform-dir $curdir/exp/tri3_ali"
sgmm2_train_decode_opt="--nj $train_nj --cmd $decode_cmd --transform-dir $curdir/exp/tri3_ali"
sgmm2_test_decode_opt="--nj $test_nj --cmd $decode_cmd --transform-dir $curdir/exp/tri3/decode_test"

echo "SGMM2 trainig options: $sgmm2_train_opt"					| tee -a $logdir/$logfile.log
echo "SGMM2 aligning options: $sggm2_align_opt"					| tee -a $logdir/$logfile.log
echo "SGMM2 train-decoding options: $sgmm2_train_decode_opt"	| tee -a $logdir/$logfile.log
echo "SGMM2 test-decoding options: $sgmm2_test_decode_opt"		| tee -a $logdir/$logfile.log

# UBM training.
echo "Training UBM..." | tee -a $logdir/$logfile.log
steps/train_ubm.sh \
	400 \
	$curdir/data/train \
	$curdir/data/lang \
	$curdir/exp/tri3_ali \
	$curdir/exp/ubm ||  exit 1

# SGMM2 training.
echo "Training SGMM2..." | tee -a $logdir/$logfile.log
steps/train_sgmm2.sh \
	$sgmm2_train_opt \
	5000 \
	8000 \
	$curdir/data/train \
	$curdir/data/lang \
	$curdir/exp/tri3_ali \
	$curdir/exp/ubm/final.ubm \
	$curdir/exp/sgmm ||  exit 1

# Graph drawing.
echo "Generating SGMM2 graph..." | tee -a $logdir/$logfile.log
utils/mkgraph.sh \
	$curdir/data/lang \
	$curdir/exp/sgmm \
	$curdir/exp/sgmm/graph

# SGMM2 aglining.
echo "Aligning..." | tee -a $logdir/$logfile.log
steps/align_sgmm2.sh \
	$sgmm2_align_opt \
	$curdir/data/train \
	$curdir/data/lang \
	$curdir/exp/sgmm \
	$curdir/exp/sgmm_ali ||  exit 1

Data decoding: train and test datasets.
echo "Decoding with SGMM2 model..." | tee -a $logdir/$logfile.log
# echo "Decoding train data..." | tee -a $logdir/$logfile.log
# steps/decode_sgmm2.sh \
# 	$sgmm2_train_decode_opt \
# 	$curdir/exp/sgmm/graph \
# 	$curdir/data/train \
# 	$curdir/exp/sgmm/decode_train
echo "Decoding test data..." | tee -a $logdir/$logfile.log
steps/decode_sgmm2.sh \
	$sgmm2_test_decode_opt \
	$curdir/exp/sgmm/graph \
	$curdir/data/test \
	$curdir/exp/sgmm/decode_test


end8=`date +%s`; log_e8=`date | awk '{print $4}'`
taken8=`local/track_time.sh $start8 $end8`
echo END TIME: $log_e8  | tee -a $logdir/$logfile.log 
echo PROCESS TIME: $taken8 sec  | tee -a $logdir/$logfile.log


echo ====================================================================== | tee -a $logdir/$logfile.log 
echo "                     Train & Decode: SGMM2+MMI 	           	      " | tee -a $logdir/$logfile.log 
echo ====================================================================== | tee -a $logdir/$logfile.log 
start9=`date +%s`; log_s9=`date | awk '{print $4}'`
echo $log_s9 >> $logdir/$logfile.log 
echo START TIME: $log_s9 | tee -a $logdir/$logfile.log 

# SGMM training, with speaker vectors.  This script would normally be called on
# top of fMLLR features obtained from a conventional system, but it also works
# on top of any type of speaker-independent features (based on
# deltas+delta-deltas or LDA+MLLT).  For more info on SGMMs, see the paper "The
# subspace Gaussian mixture model--A structured model for speech recognition".
# (Computer Speech and Language, 2011).

# SGMM2 option setting.
sgmm_denlats_opt="--nj $train_nj --sub-split 40 --transform-dir $curdir/exp/tri3_ali"
sgmmi_train_opt="--cmd $train_cmd --transform-dir $curdir/exp/tri3_ali"
sgmmi_train_decode_opt="--transform-dir $curdir/exp/tri3/decode_train"
sgmmi_test_decode_opt="--transform-dir $curdir/exp/tri3/decode_test"

echo "SGMM2_denlats options: $sgmm_denlats_opt"						| tee -a $logdir/$logfile.log
echo "SGMM2+MMI trainig options: $sgmmi_train_opt"					| tee -a $logdir/$logfile.log
echo "SGMM2+MMI train-decoding options: $sgmmi_train_decode_opt"	| tee -a $logdir/$logfile.log
echo "SGMM2+MMI test-decoding options: $sgmmi_test_decode_opt"		| tee -a $logdir/$logfile.log

# SGMM2+MMI training.
echo "Training SGMM2+MMI..." | tee -a $logdir/$logfile.log
# In mac, copy issue occurred, so the lang directory needs to be copied.
mkdir -p $curdir/exp/sgmm_denlats; cp -r $curdir/data/lang $curdir/exp/sgmm_denlats
echo "Running make_denlats_sgmm2.sh..." | tee -a $logdir/$logfile.log
steps/make_denlats_sgmm2.sh \
	$sgmm_denlats_opt \
	$curdir/data/train \
	$curdir/data/lang \
	$curdir/exp/sgmm_ali \
	$curdir/exp/sgmm_denlats ||  exit 1
echo "Running train_mmi_sgmm2.sh..." | tee -a $logdir/$logfile.log
steps/train_mmi_sgmm2.sh \
	$sgmmi_train_opt \
	$curdir/data/train \
	$curdir/data/lang \
	$curdir/exp/sgmm_ali \
	$curdir/exp/sgmm_denlats \
	$curdir/exp/sgmm_mmi ||  exit 1

# Data decoding: train and test datasets.
echo "Decoding with SGMM2+MMI model..." | tee -a $logdir/$logfile.log
echo "Decoding train data..." | tee -a $logdir/$logfile.log
steps/decode_sgmm2_rescore.sh \
	$sgmmi_train_decode_opt \
	$curdir/data/lang \
	$curdir/data/train \
	$curdir/exp/sgmm/decode_train \
	$curdir/exp/sgmm_mmi/decode_train
echo "Decoding test data..." | tee -a $logdir/$logfile.log
steps/decode_sgmm2_rescore.sh \
	$sgmmi_test_decode_opt \
	$curdir/data/lang \
	$curdir/data/test \
	$curdir/exp/sgmm/decode_test \
	$curdir/exp/sgmm_mmi/decode_test


end9=`date +%s`; log_e9=`date | awk '{print $4}'`
taken9=`local/track_time.sh $start9 $end9`
echo END TIME: $log_e9  | tee -a $logdir/$logfile.log 
echo PROCESS TIME: $taken9 sec  | tee -a $logdir/$logfile.log


echo ====================================================================== | tee -a $logdir/$logfile.log 
echo "                       Train & Decode: DNN  	            	      " | tee -a $logdir/$logfile.log 
echo ====================================================================== | tee -a $logdir/$logfile.log 
start10=`date +%s`; log_s10=`date | awk '{print $4}'`
echo $log_s10 >> $logdir/$logfile.log 
echo START TIME: $log_s10 | tee -a $logdir/$logfile.log 

# SGMM training, with speaker vectors.  This script would normally be called on
# top of fMLLR features obtained from a conventional system, but it also works
# on top of any type of speaker-independent features (based on
# deltas+delta-deltas or LDA+MLLT).  For more info on SGMMs, see the paper "The
# subspace Gaussian mixture model--A structured model for speech recognition".
# (Computer Speech and Language, 2011).

# SGMM2 option setting.
dnn1_train_opt=""
dnn1_train_decode_opt="--nj $train_nj --transform-dir $curdir/exp/tri3/decode_train"
dnn1_test_decode_opt="--nj $test_nj --transform-dir $curdir/exp/tri3/decode_test"
dnn_function="train_tanh_fast.sh"

echo "DNN($dnn_function) trainig options: $dnn1_train_opt"					| tee -a $logdir/$logfile.log
echo "DNN($dnn_function) train-decoding options: $dnn1_train_decode_opt"	| tee -a $logdir/$logfile.log
echo "DNN($dnn_function) test-decoding options: $dnn1_test_decode_opt"		| tee -a $logdir/$logfile.log

# DNN training.
# train_tanh_fast.sh
echo "Training DNN..." | tee -a $logdir/$logfile.log
steps/nnet2/$dnn_function \
	$dnn1_train_opt \
	$curdir/data/train \
	$curdir/data/lang \
	$curdir/exp/tri3_ali \
	$curdir/exp/tri4 ||  exit 1

# train_multisplice_accel2.sh

# train_tdnn.sh

# Data decoding: train dataset.
echo "Decoding with DNN model..." | tee -a $logdir/$logfile.log
echo "Decoding train data..." | tee -a $logdir/$logfile.log
steps/nnet2/decode.sh \
	$dnn1_train_decode_opt \
	$curdir/exp/tri3/graph \
	$curdir/data/train \
	$curdir/exp/tri4/decode_train
echo "Decoding test data..." | tee -a $logdir/$logfile.log
steps/nnet2/decode.sh \
	$dnn1_test_decode_opt \
	$curdir/exp/tri3/graph \
	$curdir/data/test \
	$curdir/exp/tri4/decode_test


end10=`date +%s`; log_e10=`date | awk '{print $4}'`
taken10=`local/track_time.sh $start10 $end10`
echo END TIME: $log_e10  | tee -a $logdir/$logfile.log 
echo PROCESS TIME: $taken10 sec  | tee -a $logdir/$logfile.log


echo ====================================================================== | tee -a $logdir/$logfile.log 
echo "                             RESULTS  	                	      " | tee -a $logdir/$logfile.log 
echo ====================================================================== | tee -a $logdir/$logfile.log 
echo "Displaying results" | tee -a $logdir/$logfile.log

# Save result in the log folder.
echo "Displaying results" | tee -a $logdir/$logfile.log
local/make_result.sh $curdir/exp $curdir/log $resultfile
echo "Reporting results..." | tee -a $logdir/$logfile.log
cat $curdir/log/$resultfile | tee -a $logdir/$logfile.log

##########################################################
# This is for final log.
echo "Training procedure finished successfully..." | tee -a $logdir/$logfile.log
END=`date +%s`
taken=`. $curdir/local/track_time.sh $START $END`
echo TOTAL TIME: $taken sec  | tee -a $logdir/$logfile.log 

