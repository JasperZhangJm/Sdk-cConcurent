#!/bin/bash

log_dir="./log/viewer"
output_csv="viewer_log_analysis.csv"

# 内网IP
# ip_addr=$(hostname -I | awk '{print $1}')

# 获取公网IP
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)
PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4)

# 输出 CSV 表头
echo "host,channel,index,start_time,get_ice_config_signaling_call,connect_signaling_client,tls_handshake_time,offer_sent_to_answer_received_time,dtls_initialization_completion,ice_hole_punching_time,first_audio_time,audio_latency_ms,first_video_time,video_latency_ms,pull_success,stable_audio,stable_video" > "$output_csv"

# 判断帧时间是否稳定（±20%）
is_stable() {
    local expected_ms=$1
    shift
    local -a times=("$@")
    local lower=$((expected_ms * 8 / 10))
    local upper=$((expected_ms * 12 / 10))

    for ((i = 1; i < ${#times[@]}; i++)); do
        local diff=$((times[i] - times[i-1]))
        if (( diff < lower || diff > upper )); then
            return 1
        fi
    done
    return 0
}

# 主分析流程
for log_file in "$log_dir"/viewer_*.log; do
    filename=$(basename "$log_file")
    channel=$(echo "$filename" | cut -d'_' -f2)
    index=$(echo "$filename" | cut -d'_' -f3)

    # 用 awk 处理大文件只读一次，提取时间戳
    mapfile -t results < <(awk '
    function to_millis(t) {
        # 时间格式 2025-06-12 07:19:20.039
        split(t, a, /[- :\.]/);
        # mktime参数格式：YYYY MM DD HH MM SS
        sec = mktime(a[1] " " a[2] " " a[3] " " a[4] " " a[5] " " a[6]);
        ms = a[7];
        return sec * 1000 + ms;
    }
    BEGIN {
        audio_count = 0; video_count = 0;
    }
    # 记录起始时间和首帧时间（这里存原始时间字符串）
    /Initializing WebRTC library/ && !start {
        start = $1 " " $2;
        start_ms = to_millis(start);
    }
    /Get ICE config signaling call/ && !ice_config {
        match($0, /Time taken: ([0-9]+)/, m);
        if (m[1]) ice_config = m[1];
    }
    /Connect signaling client/ && !signaling_connect {
        match($0, /Time taken: ([0-9]+)/, m);
        if (m[1]) signaling_connect = m[1];
    }
    /TLS handshake time/ && !tls_handshake {
        match($0, /Time taken: ([0-9]+)/, m);
        if (m[1]) tls_handshake = m[1];
    }
    /Offer Sent to Answer Received time/ && !sdp_answer_delay {
        match($0, /Time taken: ([0-9]+)/, m);
        if (m[1]) sdp_answer_delay = m[1];
    }
    /DTLS initialization completion/ && !dtls_init {
        match($0, /Time taken: ([0-9]+)/, m);
        if (m[1]) dtls_init = m[1];
    }
    /ICE Hole Punching Time/ && !ice_punching {
        match($0, /Time taken: ([0-9]+)/, m);
        if (m[1]) ice_punching = m[1];
    }
    /Audio Frame received/ && $0 !~ /Size: 0/ {
        if (!audio_first) {
            audio_first = $1 " " $2;
            audio_first_ms = to_millis(audio_first);
        }
        if (audio_count < 30) {
            audio_ms[audio_count++] = to_millis($1 " " $2);
        }
    }
    /Video Frame received/ && $0 !~ /Size: 0/ {
        if (!video_first) {
            video_first = $1 " " $2;
            video_first_ms = to_millis(video_first);
        }
        if (video_count < 30) {
            video_ms[video_count++] = to_millis($1 " " $2);
        }
    }
    END {
        print start;
        print ice_config + 0;
        print signaling_connect + 0;
        print tls_handshake + 0;
        print sdp_answer_delay + 0;
        print dtls_init + 0;
        print ice_punching + 0;
        print audio_first;
        print video_first;
        print start_ms;
        print audio_first_ms;
        print video_first_ms;
        for (i = 0; i < audio_count; i++) print "A " audio_ms[i];
        for (i = 0; i < video_count; i++) print "V " video_ms[i];
    }' "$log_file")

    start_time="${results[0]}"
    ice_config_ms="${results[1]}"
    signaling_connect_ms="${results[2]}"
    tls_handshake_ms="${results[3]}"
    sdp_answer_delay_ms="${results[4]}"
    dtls_init_ms="${results[5]}"
    ice_punching_ms="${results[6]}"
    first_audio_time="${results[7]}"
    first_video_time="${results[8]}"

    # 转换为时间戳
    start_ms="${results[9]}"
    first_audio_ms="${results[10]}"
    first_video_ms="${results[11]}"

    # 延迟与拉流判断
    audio_latency=""
    video_latency=""
    pull_success="no"
    [[ $start_ms -gt 0 && $first_audio_ms -gt $start_ms ]] && audio_latency=$((first_audio_ms - start_ms))
    [[ $start_ms -gt 0 && $first_video_ms -gt $start_ms ]] && video_latency=$((first_video_ms - start_ms))
    [[ -n "$audio_latency" && -n "$video_latency" ]] && pull_success="yes"

    # 提取帧时间列表
    audio_times=()
    video_times=()
    for line in "${results[@]:12}"; do
        if [[ $line == A* ]]; then
            ts="${line:2}"
            audio_times+=("$ts")
        elif [[ $line == V* ]]; then
            ts="${line:2}"
            video_times+=("$ts")
        fi
    done

    stable_audio="no"
    stable_video="no"

    if (( ${#audio_times[@]} >= 5 )) && is_stable 20 "${audio_times[@]}"; then
        stable_audio="yes"
    fi
    if (( ${#video_times[@]} >= 5 )) && is_stable 40 "${video_times[@]}"; then
        stable_video="yes"
    fi

    # 写入结果
    echo "$PUBLIC_IP,$channel,$index,'$start_time',$ice_config_ms,$signaling_connect_ms,$tls_handshake_ms,$sdp_answer_delay_ms,$dtls_init_ms,$ice_punching_ms,'$first_audio_time',$audio_latency,'$first_video_time',$video_latency,$pull_success,$stable_audio,$stable_video" >> "$output_csv"
done

echo "分析完成，结果保存在：$output_csv"
