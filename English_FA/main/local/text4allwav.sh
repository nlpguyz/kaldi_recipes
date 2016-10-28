#!/bin/bash
# 														Hyungwon Yang
# 														EMCS Labs
#														10.12.16
#
# This script duplicates a givien text file that transcribed wav file 
# along with the names of all wave files. 
# Let's say you have 100 wave files recorded "I want to go to school".
# All the wave files are written in their distinctive labels such as test01.wav, test02.wav and so on.
# And you have one text file that transrbied "I want to go to school", then you can use this script
# for generating all the transcribed text files that corresponds to the name of each wave file.

# Argument setting.
if [ $# -ne 2 ]; then
   echo "Input arguements are incorrectly provided. Please follow the direction belows."
   echo "Input Argument:"
   echo "1. Text file."
   echo "2. Wave file directory." && exit 1
fi

# Text file
txt_file=$1
# Wave file directory
wav_dir=$2


# Get the text file.
txt_snt=`cat $txt_file`

# Get the name of wave files
# Wave list
wav_list=`ls $wav_dir`

for turn in $wav_list; do

	txt_name=`echo $turn | tr -s '.wav' '.txt'`
	echo $txt_snt > $wav_dir/$txt_name
done

echo "Text files are generated."

