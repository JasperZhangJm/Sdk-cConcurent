#!/bin/bash

set -euo pipefail

# ==== 配置项 ====
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
export BASE_DIR

LOG_DIR="${BASE_DIR}/log/viewer"
ERROR_LOG="${LOG_DIR}/error.log"
mkdir -p "$LOG_DIR"
: > "$ERROR_LOG"

VIEWERS_PER_CHANNEL=3
MAX_PARALLEL=5
BATCH_SIZE=10  # 每次最多请求10个sn

# ==== 从文件读取 sn 和 channel ====
SN_LIST=()
CHANNEL_LIST=()

while read -r SN CHANNEL; do
  if [[ -n "$SN" && -n "$CHANNEL" ]]; then
    SN_LIST+=("$SN")
    CHANNEL_LIST+=("$CHANNEL")
  fi
done < "${BASE_DIR}/sn_channel_list.txt"

# ==== 登录获取 sid uid ====
UUID=$(uuidgen)
TIMESTAMP=$(date +%s)
LOGIN_URL="https://api-test-cn.aosulife.com/v1/user/login?uuid=${UUID}&t=${TIMESTAMP}"

login_response=$(curl -ks "$LOGIN_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "Gz-Pid: glazero" \
  -H "Gz-Sign: 309a2e34497e5da0f892bc754c8fb2d9" \
  -H "Gz-Imei: b7235aaeb830185c" \
  --data-urlencode "countryAbbr=CN" \
  --data-urlencode "countryCode=86" \
  --data-urlencode "email=1499405887@qq.com" \
  --data-urlencode "password=2c654e5020adb124f9f34e2963308737" \
  --data-urlencode "region=CN" \
  --data-urlencode "type=1"
)

sid=$(echo "$login_response" | jq -r '.data.sid')
uid=$(echo "$login_response" | jq -r '.data.uid')

if [[ -z "$sid" || "$sid" == "null" ]]; then
  echo "❌ 登录失败，sid 获取失败" | tee -a "$ERROR_LOG"
  exit 1
fi

# ==== 启动 viewer 的函数 ====
start_viewer() {
  local start_time=$(date +%s%3N)

  local channel="$1"
  local index="$2"

  local ts=$(date +%Y%m%d_%H%M%S_%3N)
  local log_file="${BASE_DIR}/log/viewer/viewer_${channel}_${index}_${ts}.log"

  mkdir -p "$(dirname "$log_file")"

  (
    cd build || exit 1
    AWS_ACCESS_KEY_ID="$ak" AWS_SECRET_ACCESS_KEY="$sk" AWS_SESSION_TOKEN="$token" \
    AWS_DEFAULT_REGION="cn-north-1" AWS_KVS_LOG_LEVEL=1 DEBUG_LOG_SDP=TRUE \
    nohup ./samples/kvsWebrtcClientViewer "$channel" > "$log_file" 2>&1 &
  ) || echo "❌ Failed: $channel" >> "$ERROR_LOG"

  sleep 0.2

  local end_time=$(date +%s%3N)
  local duration=$((end_time - start_time))
  echo "✅ viewer 启动完成: channel=$channel index=$index 耗时=${duration}ms"
}

export -f start_viewer
export LOG_DIR ERROR_LOG

# ==== 分批处理 SN 和 channel ====
echo "🚀 开始分批启动 viewer..."
total_start=$(date +%s%3N)

total=${#SN_LIST[@]}
for ((start=0; start<total; start+=BATCH_SIZE)); do
  end=$((start + BATCH_SIZE))
  [[ $end -gt $total ]] && end=$total

  UUID=$(uuidgen)
  TIMESTAMP=$(date +%s)
  STS_URL="https://api-test-cn.aosulife.com/v1/sts/getPlayInfo?uuid=${UUID}&t=${TIMESTAMP}"

  # 构造当前批次 SN 参数
  sts_curl_args=(
    -k -s "$STS_URL"
    -H "Content-Type: application/x-www-form-urlencoded"
    -H "Gz-Sid: $sid"
    -H "Gz-Uid: $uid"
    -H "Gz-Pid: glazero"
    -H "Gz-Sign: 309a2e34497e5da0f892bc754c8fb2d9"
    -H "Gz-Imei: b7235aaeb830185c"
    --data-urlencode "refresh=true"
  )

  BATCH_CHANNELS=()

  for ((i=start; i<end; i++)); do
    sts_curl_args+=( --data-urlencode "sn[]=${SN_LIST[i]}" )
    BATCH_CHANNELS+=("${CHANNEL_LIST[i]}")
  done

  # 获取本批次 STS
  sts_response=$(curl "${sts_curl_args[@]}")
  ak=$(echo "$sts_response" | jq -r '.data.ak')
  sk=$(echo "$sts_response" | jq -r '.data.sk')
  token=$(echo "$sts_response" | jq -r '.data.token')

  if [[ -z "$ak" || "$ak" == "null" ]]; then
    echo "❌ STS 获取失败" | tee -a "$ERROR_LOG"
    exit 1
  fi

  export ak sk token

  # 构造任务文件
  TASK_FILE="${BASE_DIR}/viewer_tasks_batch_${start}.txt"
  : > "$TASK_FILE"

  for channel in "${BATCH_CHANNELS[@]}"; do
    for i in $(seq 1 "$VIEWERS_PER_CHANNEL"); do
      echo "$channel $i" >> "$TASK_FILE"
    done
  done

  parallel --delay 0.1 -j "$MAX_PARALLEL" --colsep ' ' start_viewer {1} {2} < "$TASK_FILE"

done

total_end=$(date +%s%3N)
total_duration=$((total_end - total_start))

echo "🎉 所有 viewer 启动完成，总耗时：${total_duration}ms，日志目录：$LOG_DIR"
