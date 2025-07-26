#!/bin/bash

log_dir="./log/master"
output_csv="master_log_analysis.csv"

# 输出 CSV 表头
echo "channel,start_time,ready_time,streaming_time,setup_duration(s),setup_status,stream_status" > "$output_csv"

# 遍历所有日志文件
for logfile in "$log_dir"/master_*.log; do
    filename=$(basename -- "$logfile")
    channel=$(echo "$filename" | cut -d'_' -f2)

    # 原始时间字符串（带毫秒）
    start_line=$(grep -m1 "Initializing WebRTC library" "$logfile")
    ready_line=$(grep -m1 "Channel $channel set up done" "$logfile")

    start_time=$(echo "$start_line" | awk '{print $1 " " $2}')
    ready_time=$(echo "$ready_line" | awk '{print $1 " " $2}')

    # 默认空值和状态
    streaming_time=""
    duration=""
    stream_status="NO_STREAM"
    setup_status="FAIL"

    # 只有当启动和就绪都有时间才认为 setup 成功
    if [[ -n "$start_time" && -n "$ready_time" ]]; then
        setup_status="✅ Setup OK"

        # 计算启动耗时（保留毫秒）
        start_ts=$(date -d "${start_time}" +%s.%3N)
        ready_ts=$(date -d "${ready_time}" +%s.%3N)
        duration=$(echo "$ready_ts - $start_ts" | bc)
    else
        setup_status="❌ No Setup"
    fi

    # 判断是否推流成功（packets>0 && bytes>0）
    sender_line=$(grep -m1 "sender report" "$logfile")
    if [[ -n "$sender_line" ]]; then
        packets=$(echo "$sender_line" | sed -n 's/.*: \([0-9]*\) packets.*/\1/p')
        bytes=$(echo "$sender_line" | sed -n 's/.*packets \([0-9]*\) bytes.*/\1/p')
        if [[ "$packets" -gt 0 && "$bytes" -gt 0 ]]; then
            streaming_time=$(echo "$sender_line" | awk '{print $1 " " $2}')
            stream_status="✅ Stream OK"
        else
            stream_status="❌ No Stream"
        fi
    fi

    # 写入 CSV（保留毫秒格式）
    echo "$channel,'$start_time','$ready_time','$streaming_time',$duration,$setup_status,$stream_status" >> "$output_csv"

done
