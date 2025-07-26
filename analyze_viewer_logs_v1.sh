#!/bin/bash

log_dir="./log/viewer"
output_csv="viewer_log_analysis.csv"

# 输出表头
echo "channel,index,start_time,first_audio_time,audio_latency_ms,first_video_time,video_latency_ms,pull_success,stable_audio,stable_video" > "$output_csv"

# 函数：将时间转为毫秒时间戳（兼容macOS和Linux）
to_millis() {
    t="$1"  # 格式示例："2025-06-12 07:19:38.699"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS 用 gdate（需 brew install coreutils）
        gdate -j -f "%Y-%m-%d %H:%M:%S.%3N" "$t" +%s%3N 2>/dev/null || echo 0
    else
        date -d "$t" +%s%3N 2>/dev/null || echo 0
    fi
}

# 函数：判断时间间隔数组是否都在期望范围±20%
# 参数1: 期望间隔（ms）
# 参数后续: 时间戳数组(ms)
is_stable_stream() {
    local expected_ms=$1
    shift
    local lower=$(awk "BEGIN {printf \"%d\", $expected_ms * 0.8}")
    local upper=$(awk "BEGIN {printf \"%d\", $expected_ms * 1.2}")
    local times=("$@")
    for ((i=1; i<${#times[@]}; i++)); do
        local diff=$(( times[i] - times[i-1] ))
        if (( diff < lower || diff > upper )); then
            return 1
        fi
    done
    return 0
}

# 函数：提取前N个时间戳并转成毫秒数组
# 参数1: 文件名
# 参数2: 关键字（"Audio"或"Video"）
# 参数3: 取多少帧
get_frame_times_ms() {
    local file="$1"
    local frame_type="$2"
    local count="$3"
    local lines
    lines=$(grep "${frame_type} Frame received" "$file" | grep -v "Size: 0" | head -n "$count" | awk '{print $1, $2}')
    local times_ms=()
    while IFS= read -r line; do
        times_ms+=("$(to_millis "$line")")
    done <<< "$lines"
    echo "${times_ms[@]}"
}

for log_file in "$log_dir"/viewer_*.log; do
    filename=$(basename "$log_file")
    
    channel=$(echo "$filename" | cut -d'_' -f2)
    index=$(echo "$filename" | cut -d'_' -f3)

    # 提取起始时间
    start_line=$(grep "Initializing WebRTC library" "$log_file" | head -n1)
    start_time=$(echo "$start_line" | awk '{print $1, $2}')
    start_ms=$(to_millis "$start_time")

    # 首帧音频
    first_audio_line=$(grep "Audio Frame received" "$log_file" | grep -v "Size: 0" | head -n1)
    first_audio_time=$(echo "$first_audio_line" | awk '{print $1, $2}')
    first_audio_ms=$(to_millis "$first_audio_time")

    # 首帧视频
    first_video_line=$(grep "Video Frame received" "$log_file" | grep -v "Size: 0" | head -n1)
    first_video_time=$(echo "$first_video_line" | awk '{print $1, $2}')
    first_video_ms=$(to_millis "$first_video_time")

    # 计算延迟
    audio_latency_ms=""
    video_latency_ms=""
    pull_success="no"

    if [[ -n "$first_audio_line" && "$first_audio_line" =~ TrackId.*Size.*Flags ]] && [[ -n "$start_ms" && -n "$first_audio_ms" && "$start_ms" -ne 0 && "$first_audio_ms" -ne 0 ]]; then
        audio_latency_ms=$((first_audio_ms - start_ms))
    fi

    if [[ -n "$first_video_line" && "$first_video_line" =~ TrackId.*Size.*Flags ]] && [[ -n "$start_ms" && -n "$first_video_ms" && "$start_ms" -ne 0 && "$first_video_ms" -ne 0 ]]; then
        video_latency_ms=$((first_video_ms - start_ms))
    fi

    if [[ -n "$audio_latency_ms" && -n "$video_latency_ms" && "$audio_latency_ms" -ge 0 && "$video_latency_ms" -ge 0 ]]; then
        pull_success="yes"
    fi

    # 判断是否稳定拉流（基于时间间隔 ±20%）
    stable_audio="no"
    stable_video="no"

    # 音频帧间隔理论值约20ms，视频帧间隔约36ms
    audio_times=($(get_frame_times_ms "$log_file" "Audio" 30))
    video_times=($(get_frame_times_ms "$log_file" "Video" 30))

    if (( ${#audio_times[@]} >= 5 )); then
        if is_stable_stream 20 "${audio_times[@]}"; then
            stable_audio="yes"
        fi
    fi

    if (( ${#video_times[@]} >= 5 )); then
        if is_stable_stream 36 "${video_times[@]}"; then
            stable_video="yes"
        fi
    fi

    echo "$channel,$index,'$start_time','$first_audio_time',$audio_latency_ms,'$first_video_time',$video_latency_ms,$pull_success,$stable_audio,$stable_video" >> "$output_csv"
done

echo "分析完成，结果保存在：$output_csv"
