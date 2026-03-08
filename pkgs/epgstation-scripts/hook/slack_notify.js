const args = process.argv.slice(2);

const envFile = args[0];
const event = args[1];

const fs = require("fs");
const slackUrl = fs.readFileSync(envFile, "utf-8");

const {env} = require("process");

const https = require("https");
let req = https.request(slackUrl, {method: "POST"});
req.on("error", (err) => {
  console.log("Error: " + err.message);
});

function notifyEncodingFinished(req, env) {
  let params = {
    recordedid: env.RECORDEDID, // recorded id
    videofileid: env.VIDEOFILEID, // video file id
    outputpath: env.OUTPUTPATH, // エンコードしたビデオファイルのフルパス
    mode: env.MODE, // エンコードモード名
    channelid: env.CHANNELID, // channel id
    channelname: env.CHANNELNAME, // 放送局名
    halfWidthChannelname: env.HALF_WIDTH_CHANNELNAME, // 放送局名(半角)
    name: env.NAME, // 番組名
    halfWidthName: env.HALF_WIDTH_NAME, // 番組名(半角)
    description: env.DESCRIPTION, // 番組概要
    halfWidthDescription: env.HALF_WIDTH_DESCRIPTION, // 番組概要(半角)
    extended: env.EXTENDED, // 番組詳細
    halfWidthExtended: env.HALF_WIDTH_EXTENDED, // 番組詳細(半角)
  };

  let msg = JSON.stringify({
    blocks: [
      {
        type: "section",
        text: {
          type: "plain_text",
          text: "変換が終ったよ!",
          emoji: true,
        },
      },
      {
        type: "section",
        text: {
          type: "plain_text",
          text: params.name,
          emoji: true,
        },
      },
      {
        type: "section",
        fields: [
          {
            type: "mrkdwn",
            text: "*channel name*",
          },
          {
            type: "plain_text",
            text: params.channelname,
            emoji: true,
          },
        ],
      },
    ],
  });

  req.write(msg);
}

function recordingParams(env) {
  return {
    recordedid: env.RECORDEDID, // recorded id
    programid: env.PROGRAMID, // program id
    channeltype: env.CHANNELTYPE, // 'GR' | 'BS' | 'CS' | 'SKY'
    channelid: env.CHANNELID, // channel id
    channelname: env.CHANNELNAME, // 放送局名
    halfWidthChannelname: env.HALF_WIDTH_CHANNELNAME, // 放送局名(半角)
    startat: env.STARTAT, // 開始時刻 (UNIX time)
    endat: env.ENDAT, // 終了時刻 (UNIX time)
    duration: env.DURATION, // 長さ (ms)
    name: env.NAME, // 番組名
    halfWidthName: env.HALF_WIDTH_NAME, // 番組名(半角)
    description: env.DESCRIPTION, // 番組概要
    halfWidthDescription: env.HALF_WIDTH_DESCRIPTION, // 番組概要(半角)
    extended: env.EXTENDED, // 番組詳細
    halfWidthExtended: env.HALF_WIDTH_EXTENDED, // 番組詳細(半角)
    recpath: env.RECPATH, // 録画ファイルのフルパス
    logpath: env.LOGPATH, // ログファイルのフルパス
    errorCnt: env.ERROR_CNT, // エラーカウント
    dropCnt: env.DROP_CNT, // ドロップカウント
    scramblingCnt: env.SCRAMBLING_CNT, // スクランブルカウント
  };
}

function notifyRecordingEvent(req, env, event) {
  let params = recordingParams(env);

  var txt = "録画イベントが発生しました。";
  switch (event) {
    case "recording-start":
      txt = "録画始めました!";
      break;
    case "recording-finish":
      txt = "録画終わりました!";
      break;
    case "recording-failed":
      txt = "録画失敗しました!";
      break;
  }

  let msg = JSON.stringify({
    blocks: [
      {
        type: "section",
        text: {
          type: "plain_text",
          text: txt,
          emoji: true,
        },
      },
      {
        type: "section",
        text: {
          type: "plain_text",
          text: params.name,
          emoji: true,
        },
      },
      {
        type: "section",
        fields: [
          {
            type: "mrkdwn",
            text: "*channel name*",
          },
          {
            type: "plain_text",
            text: params.channelname,
            emoji: true,
          },
        ],
      },
    ],
  });

  req.write(msg);
}

if (event === "encoding-finish") {
  notifyEncodingFinished(req, env);
}
if (/recording-.+/.test(event)) {
  notifyRecordingEvent(req, env, event);
}
req.end();
