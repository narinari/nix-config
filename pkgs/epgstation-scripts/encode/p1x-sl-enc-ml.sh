#!/bin/sh
# enc-libx-cpm.sh
# version 4.0 created on 2021-03-29 by simplelife0530
#
#パラメーターの設定
if [ $# = 3 ]; then
	crfValue=${1}
	presetValue=${2}
	modeValue=${3}
elif [ $# = 2 ]; then
	crfValue=${1}
	presetValue=${2}
	modeValue="L1"
elif [ $# = 1 ]; then
	crfValue=${1}
	presetValue="veryfast"
	modeValue="L1"
else
	crfValue=22
	presetValue="veryfast"
	modeValue="L1"
fi
#
#エンコード設定
inputPara=" -ss 4 -y -i "
videoCodec=" -preset ${presetValue} -c:v libx264"
videoOpt=" -crf ${crfValue} -f mp4"
if [ "${modeValue}" = "L1" ]; then
	mapOpt=' -map 0:v -map 0:a:0 -metadata:s:a:0 title="main" -metadata:s:a:0 language="jpn"'
elif [ "${modeValue}" = "M2" ]; then
	mapOpt=' -filter_complex channelsplit -metadata:s:a:0 title="Japanese" -metadata:s:a:0  language="jpn" -metadata:s:a:1 title="English" -metadata:s:a:1  language="eng"'
elif [ "${modeValue}" = "L2" ]; then
	mapOpt=' -map 0:v -map 0:a:0 -map 0:a:1 -ignore_unknown -sn -dn -metadata:s:a:0 title="Japanese" -metadata:s:a:0  language="jpn" -metadata:s:a:1 title="English" -metadata:s:a:1  language="eng"'
elif [ "${modeValue}" = "E2" ]; then
	mapOpt=' -map 0:v -map 0:a:0 -map 0:a:1 -ignore_unknown -sn -dn -metadata:s:a:0 title="main" -metadata:s:a:0  language="jpn" -metadata:s:a:1 title="exp" -metadata:s:a:1  language="jpn"'
elif [ "${modeValue}" = "S2" ]; then
	mapOpt=' -map 0:v -map 0:a:0 -map 0:a:1 -ignore_unknown -sn -dn -metadata:s:a:0 title="main" -metadata:s:a:0  language="jpn" -metadata:s:a:1 title="sub" -metadata:s:a:1  language="jpn"'
elif [ "${modeValue}" = "T0" ]; then
	mapOpt=" -map 0 -ignore_unknown -sn -dn"
else
	mapOpt=""
fi
audioCodec=" -c:a aac"
audioOpt=" -strict -2 -ar 48000 -ab 192k -ac 2"
advancedOpt=" -loglevel error "
#
command="$FFMPEG$inputPara\"$INPUT\"$videoCodec$videoOpt$mapOpt$audioCodec$audioOpt$advancedOpt\"$OUTPUT\""
#
#エンコード開始
eval "${command}"
#エンコード終了
exit
