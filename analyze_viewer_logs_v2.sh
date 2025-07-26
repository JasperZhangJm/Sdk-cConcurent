#!/bin/bash

log_dir="./log/viewer"
output_csv="viewer_log_analysis.csv"

# 输出 CSV 表头
echo "channel,index,start_time,first_audio_time,audio_latency_ms,first_video_time,video_latency_ms,pull_success,stable_audio,stable_video" > "$output_csv"

# 使用 Linux 自带的 date 命令将时间转为毫秒时间戳
to_millis() {
    date -d "$1" +%s%3N 2>/dev/null || echo 0
}

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
    BEGIN {
        audio_count = 0; video_count = 0;
    }
    /Initializing WebRTC library/ && !start {
        start = $1 " " $2;
    }
    /Audio Frame received/ && $0 !~ /Size: 0/ {
        if (!audio_first) audio_first = $1 " " $2;
        if (audio_count < 15000) {
            audio_list[audio_count++] = $1 " " $2;
        }
    }
    /Video Frame received/ && $0 !~ /Size: 0/ {
        if (!video_first) video_first = $1 " " $2;
        if (video_count < 15000) {
            video_list[video_count++] = $1 " " $2;
        }
    }
    END {
        print start;
        print audio_first;
        print video_first;
        for (i = 0; i < audio_count; i++) print "A " audio_list[i];
        for (i = 0; i < video_count; i++) print "V " video_list[i];
    }' "$log_file")

    start_time="${results[0]}"
    first_audio_time="${results[1]}"
    first_video_time="${results[2]}"

    # 转换为时间戳
    start_ms=$(to_millis "$start_time")
    first_audio_ms=$(to_millis "$first_audio_time")
    first_video_ms=$(to_millis "$first_video_time")

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
    for line in "${results[@]:3}"; do
        if [[ $line == A* ]]; then
            ts=$(to_millis "${line:2}")
            audio_times+=("$ts")
        elif [[ $line == V* ]]; then
            ts=$(to_millis "${line:2}")
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
    echo "$channel,$index,'$start_time','$first_audio_time',$audio_latency,'$first_video_time',$video_latency,$pull_success,$stable_audio,$stable_video" >> "$output_csv"
done

echo "分析完成，结果保存在：$output_csv"
