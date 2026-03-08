{
  live = {
    ts = {
      hls = [
        {
          cmd = ''
            %FFMPEG% -re -dual_mono_mode main -i pipe:0 -sn -map 0 -threads 0 -ignore_unknown
            -max_muxing_queue_size 1024 -f hls -hls_time 3 -hls_list_size 17 -hls_allow_cache
            1 -hls_segment_filename %streamFileDir%/stream%streamNum%-%09d.ts -hls_flags
            delete_segments -c:a aac -ar 48000 -b:a 192k -ac 2 -c:v h264_v4l2m2m -vf yadif,scale=-2:720
            -b:v 3000k -preset veryfast -flags +loop-global_header %OUTPUT%
          '';
          name = "720p";
        }
        {
          cmd = ''
            %FFMPEG% -re -dual_mono_mode main -i pipe:0 -sn -map 0 -threads 0 -ignore_unknown
            -max_muxing_queue_size 1024 -f hls -hls_time 3 -hls_list_size 17 -hls_allow_cache
            1 -hls_segment_filename %streamFileDir%/stream%streamNum%-%09d.ts -hls_flags
            delete_segments -c:a aac -ar 48000 -b:a 128k -ac 2 -c:v h264_v4l2m2m -vf yadif,scale=-2:480
            -b:v 1500k -preset veryfast -flags +loop-global_header %OUTPUT%
          '';
          name = "480p";
        }
      ];
      m2ts = [
        {
          cmd = ''
            %FFMPEG% -re -dual_mono_mode main -i pipe:0 -sn -threads 0 -c:a aac
            -ar 48000 -b:a 192k -ac 2 -c:v h264_v4l2m2m -vf yadif,scale=-2:720 -b:v 3000k
            -preset veryfast -y -f mpegts pipe:1
          '';
          name = "720p";
        }
        {
          cmd = ''
            %FFMPEG% -re -dual_mono_mode main -i pipe:0 -sn -threads 0 -c:a aac
            -ar 48000 -b:a 128k -ac 2 -c:v h264_v4l2m2m -vf yadif,scale=-2:480 -b:v 1500k
            -preset veryfast -y -f mpegts pipe:1
          '';
          name = "480p";
        }
        {
          name = "無変換";
        }
      ];
      m2tsll = [
        {
          cmd = ''
            %FFMPEG% -dual_mono_mode main -f mpegts -analyzeduration 500000 -i pipe:0
            -map 0 -c:s copy -c:d copy -ignore_unknown -fflags nobuffer -flags low_delay
            -max_delay 250000 -max_interleave_delta 1 -threads 0 -c:a aac -ar 48000
            -b:a 192k -ac 2 -c:v h264_v4l2m2m -flags +cgop -vf yadif,scale=-2:720 -b:v 3000k
            -preset veryfast -y -f mpegts pipe:1
          '';
          name = "720p";
        }
        {
          cmd = ''
            %FFMPEG% -dual_mono_mode main -f mpegts -analyzeduration 500000 -i pipe:0
            -map 0 -c:s copy -c:d copy -ignore_unknown -fflags nobuffer -flags low_delay
            -max_delay 250000 -max_interleave_delta 1 -threads 0 -c:a aac -ar 48000
            -b:a 128k -ac 2 -c:v h264_v4l2m2m -flags +cgop -vf yadif,scale=-2:480 -b:v 1500k
            -preset veryfast -y -f mpegts pipe:1
          '';
          name = "480p";
        }
      ];
      mp4 = [
        {
          cmd = ''
            %FFMPEG% -re -dual_mono_mode main -i pipe:0 -sn -threads 0 -c:a aac
            -ar 48000 -b:a 192k -ac 2 -c:v h264_v4l2m2m -vf yadif -b:v 5M
            -preset veryfast -tune fastdecode,zerolatency -movflags
            frag_keyframe+empty_moov+faststart+default_base_moof -y -f mp4 pipe:1
          '';
          name = "1080p";
        }
        {
          cmd = ''
            %FFMPEG% -re -dual_mono_mode main -i pipe:0 -sn -threads 0 -c:a aac
            -ar 48000 -b:a 192k -ac 2 -c:v h264_v4l2m2m -vf yadif,scale=-2:720 -b:v 3000k
            -preset veryfast -tune fastdecode,zerolatency -movflags
            frag_keyframe+empty_moov+faststart+default_base_moof -y -f mp4 pipe:1
          '';
          name = "720p";
        }
        {
          cmd = ''
            %FFMPEG% -re -dual_mono_mode main -i pipe:0 -sn -threads 0 -c:a aac
            -ar 48000 -b:a 128k -ac 2 -c:v h264_v4l2m2m -vf yadif,scale=-2:480 -b:v 1500k
            -preset veryfast -tune fastdecode,zerolatency -movflags
            frag_keyframe+empty_moov+faststart+default_base_moof -y -f mp4 pipe:1
          '';
          name = "480p";
        }
      ];
      webm = [
        {
          cmd = ''
            %FFMPEG% -re -dual_mono_mode main -i pipe:0 -sn -threads 3 -c:a libvorbis
            -ar 48000 -b:a 192k -ac 2 -c:v libvpx-vp9 -vf yadif,scale=-2:720 -b:v 3000k
            -deadline realtime -speed 4 -cpu-used -8 -y -f webm pipe:1
          '';
          name = "720p";
        }
        {
          cmd = ''
            %FFMPEG% -re -dual_mono_mode main -i pipe:0 -sn -threads 2 -c:a libvorbis
            -ar 48000 -b:a 128k -ac 2 -c:v libvpx-vp9 -vf yadif,scale=-2:480 -b:v 1500k
            -deadline realtime -speed 4 -cpu-used -8 -y -f webm pipe:1
          '';
          name = "480p";
        }
      ];
    };
  };

  recorded = {
    encoded = {
      hls = [
        {
          cmd = ''
            %FFMPEG% -dual_mono_mode main -ss %SS% -i %INPUT% -sn -threads 0 -ignore_unknown
            -max_muxing_queue_size 1024 -f hls -hls_time 3 -hls_list_size 0 -hls_allow_cache
            1 -hls_segment_filename %streamFileDir%/stream%streamNum%-%09d.ts -hls_flags
            delete_segments -c:a aac -ar 48000 -b:a 192k -ac 2 -c:v h264_v4l2m2m -vf scale=-2:720
            -b:v 3000k -preset veryfast -flags +loop-global_header %OUTPUT%
          '';
          name = "720p";
        }
        {
          cmd = ''
              %FFMPEG% -dual_mono_mode main -ss %SS% -i %INPUT% -sn -threads 0 -ignore_unknown
              -max_muxing_queue_size 1024 -f hls -hls_time 3 -hls_list_size 0 -hls_allow_cache
            1 -hls_segment_filename %streamFileDir%/stream%streamNum%-%09d.ts -hls_flags
            delete_segments -c:a aac -ar 48000 -b:a 128k -ac 2 -c:v h264_v4l2m2m -vf scale=-2:480
              -b:v 3000k -preset veryfast -flags +loop-global_header %OUTPUT%
          '';
          name = "480p";
        }
      ];
      mp4 = [
        {
          cmd = ''
            %FFMPEG% -dual_mono_mode main -ss %SS% -i %INPUT% -sn -threads 0 -c:a
            aac -ar 48000 -b:a 192k -ac 2 -c:v h264_v4l2m2m -b:v 5M
            -preset veryfast -tune fastdecode,zerolatency -movflags frag_keyframe+empty_moov+faststart+default_base_moof
            -y -f mp4 pipe:1
          '';
          name = "1080p";
        }
        {
          cmd = ''
            %FFMPEG% -dual_mono_mode main -ss %SS% -i %INPUT% -sn -threads 0 -c:a
            aac -ar 48000 -b:a 192k -ac 2 -c:v h264_v4l2m2m -vf scale=-2:720 -b:v 3000k
            -preset veryfast -tune fastdecode,zerolatency -movflags frag_keyframe+empty_moov+faststart+default_base_moof
            -y -f mp4 pipe:1
          '';
          name = "720p";
        }
        {
          cmd = ''
            %FFMPEG% -dual_mono_mode main -ss %SS% -i %INPUT% -sn -threads 0 -c:a
            aac -ar 48000 -b:a 128k -ac 2 -c:v h264_v4l2m2m -vf scale=-2:480 -b:v 1500k
            -preset veryfast -tune fastdecode,zerolatency -movflags frag_keyframe+empty_moov+faststart+default_base_moof
            -y -f mp4 pipe:1
          '';
          name = "480p";
        }
      ];
      webm = [
        {
          cmd = ''
            %FFMPEG% -dual_mono_mode main -ss %SS% -i %INPUT% -sn -threads 3 -c:a
            libvorbis -ar 48000 -b:a 192k -ac 2 -c:v libvpx-vp9 -vf scale=-2:720 -b:v
            3000k -deadline realtime -speed 4 -cpu-used -8 -y -f webm pipe:1
          '';
          name = "720p";
        }
        {
          cmd = ''
              %FFMPEG% -dual_mono_mode main -ss %SS% -i %INPUT% -sn -threads 3 -c:a
            libvorbis -ar 48000 -b:a 128k -ac 2 -c:v libvpx-vp9 -vf scale=-2:480 -b:v
            1500k -deadline realtime -speed 4 -cpu-used -8 -y -f webm pipe:1
          '';
          name = "480p";
        }
      ];
      ts = {
        hls = [
          {
            cmd = ''
                %FFMPEG% -dual_mono_mode main -i pipe:0 -sn -map 0 -threads 0 -ignore_unknown
                -max_muxing_queue_size 1024 -f hls -hls_time 3 -hls_list_size 0 -hls_allow_cache
              1 -hls_segment_filename %streamFileDir%/stream%streamNum%-%09d.ts -hls_flags
              delete_segments -c:a aac -ar 48000 -b:a 192k -ac 2 -c:v h264_v4l2m2m -vf yadif,scale=-2:720
                -b:v 3000k -preset veryfast -flags +loop-global_header %OUTPUT%
            '';
            name = "720p";
          }
          {
            cmd = ''
                %FFMPEG% -dual_mono_mode main -i pipe:0 -sn -map 0 -threads 0 -ignore_unknown
                -max_muxing_queue_size 1024 -f hls -hls_time 3 -hls_list_size 0 -hls_allow_cache
              1 -hls_segment_filename %streamFileDir%/stream%streamNum%-%09d.ts -hls_flags
              delete_segments -c:a aac -ar 48000 -b:a 128k -ac 2 -c:v h264_v4l2m2m -vf yadif,scale=-2:480
                -b:v 1500k -preset veryfast -flags +loop-global_header %OUTPUT%
            '';
            name = "480p";
          }
        ];
        mp4 = [
          {
            cmd = ''
                %FFMPEG% -dual_mono_mode main -i pipe:0 -sn -threads 0 -c:a aac -ar
              48000 -b:a 192k -ac 2 -c:v h264_v4l2m2m -vf yadif -b:v 5M
              -preset veryfast -tune fastdecode,zerolatency -movflags frag_keyframe+empty_moov+faststart+default_base_moof
                -y -f mp4 pipe:1
            '';
            name = "1080p";
          }
          {
            cmd = ''
                %FFMPEG% -dual_mono_mode main -i pipe:0 -sn -threads 0 -c:a aac -ar
              48000 -b:a 192k -ac 2 -c:v h264_v4l2m2m -vf yadif,scale=-2:720 -b:v 3000k
              -preset veryfast -tune fastdecode,zerolatency -movflags frag_keyframe+empty_moov+faststart+default_base_moof
                -y -f mp4 pipe:1
            '';
            name = "720p";
          }
          {
            cmd = ''
                %FFMPEG% -dual_mono_mode main -i pipe:0 -sn -threads 0 -c:a aac -ar
              48000 -b:a 128k -ac 2 -c:v h264_v4l2m2m -vf yadif,scale=-2:480 -b:v 1500k
              -preset veryfast -tune fastdecode,zerolatency -movflags frag_keyframe+empty_moov+faststart+default_base_moof
                -y -f mp4 pipe:1
            '';
            name = "480p";
          }
        ];
        webm = [
          {
            cmd = ''
              %FFMPEG% -dual_mono_mode main -i pipe:0 -sn -threads 3 -c:a libvorbis
              -ar 48000 -b:a 192k -ac 2 -c:v libvpx-vp9 -vf yadif,scale=-2:720 -b:v 3000k
              -deadline realtime -speed 4 -cpu-used -8 -y -f webm pipe:1
            '';
            name = "720p";
          }
          {
            cmd = ''
              %FFMPEG% -dual_mono_mode main -i pipe:0 -sn -threads 3 -c:a libvorbis
              -ar 48000 -b:a 128k -ac 2 -c:v libvpx-vp9 -vf yadif,scale=-2:480 -b:v 1500k
              -deadline realtime -speed 4 -cpu-used -8 -y -f webm pipe:1
            '';
            name = "480p";
          }
        ];
      };
    };
  };
}
