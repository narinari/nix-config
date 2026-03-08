const spawn = require("child_process").spawn;
const ffmpeg = process.env.FFMPEG;
const opts = process.argv.slice(2);

const input = process.env.INPUT;
const output = process.env.OUTPUT;
const analyzedurationSize = "10M"; // Mirakurun の設定に応じて変更すること
const probesizeSize = "32M"; // Mirakurun の設定に応じて変更すること
const maxMuxingQueueSize = 1024;
const dualMonoMode = "main";
const videoHeight = parseInt(process.env.VIDEORESOLUTION, 10);
const isProgressive = process.env.VIDEORESOLUTION.endsWith("p");
const isDualMono = parseInt(process.env.AUDIOCOMPONENTTYPE, 10) == 2;
const audioBitrate = videoHeight > 720 ? "192k" : "128k";

const isSoftwareEncMode = opts[0] == "--software-encode";

// video stram params
// prettier-ignore
let videoCodecParams = [
  "-c:v", "h264_v4l2m2m",
  "-b:v", "5M",
  "-maxrate:v", "5M",
  "-bufsize:v", "5M",
]; // RaspberryPi4 hardware accelerator
if (isSoftwareEncMode) {
  videoCodecParams = ["-preset", "fast", "-c:v", "libx264"];
}

const crf = 32;

if (!isProgressive) {
  videoCodecParams.unshift("-flags", "+ildct+ilme"); // インターレースを保持する メタデーダなので先頭に追加している
}

// prettier-ignore
const args = [
  '-ss','4', // 冒頭をスキップ
  '-y',
  '-analyzeduration', analyzedurationSize,
  '-probesize', probesizeSize,
  '-fix_sub_duration',
];

// input 設定
Array.prototype.push.apply(args, ["-i", input]);

// メタ情報を先頭に置く
Array.prototype.push.apply(args, [
  "-movflags",
  // "frag_keyframe+empty_moov+faststart+default_base_moof",
  "faststart+write_colr",
]);

// 字幕データを含めたストリームをすべてマップ
// Array.prototype.push.apply(args, ['-map', '0', '-ignore_unknown', '-max_muxing_queue_size', maxMuxingQueueSize, '-sn']);

// ビデオストリーム設定
// video filter 設定
// let videoFilter = "yadif";
// Array.prototype.push.apply(args, ["-vf", videoFilter]);

args.push("-map", "0:v");

// オーディオストリーム設定
// prettier-ignore
if (isDualMono) {
  args.push(
    '-filter_complex',
    'channelsplit[FL][FR]',
    '-map', '[FL]',
    '-map', '[FR]',
    '-metadata:s:a:0', 'language=jpn',
    '-metadata:s:a:1', 'language=eng');
} else {
  args.push(
    '-map', '0:a:0',
    '-metadata:s:a:0', 'title=main',
    '-metadata:s:a:0', 'language=jpn');
}

// 字幕ストリーム設定
// prettier-ignore
// args.push('-map', '0:s?', '-metadata:s:s:0', 'title=main', '-metadata:s:s:0', 'language=jpn', '-c:s', 'mov_text');

Array.prototype.push.apply(args, videoCodecParams);

// その他設定
// prettier-ignore
Array.prototype.push.apply(args,[
  // '-tune', 'fastdecode,zerolatency',
  '-aspect', '16:9',
  '-crf', crf,
  '-f', 'mp4',
  '-c:a', 'aac',
  '-ar', '48000',
  '-ab', audioBitrate,
  '-ac', '2',
  output
]);

console.error(args.join(" "));

const child = spawn(ffmpeg, args);

child.stderr.on("data", (data) => {
  console.error(String(data));
});

child.on("error", (err) => {
  console.error(err);
  throw new Error(err);
});

process.on("SIGINT", () => {
  child.kill("SIGINT");
});
