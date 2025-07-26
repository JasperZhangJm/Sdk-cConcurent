#!/bin/bash

# 创建log目录
mkdir -p ./log/master

# channel 与 sn 一一对应
CHANNEL_NAMES=("lzgd5496a7907243e22d" "lzgd73052d21279230f4")
SN_LIST=("C2E2DA110017952" "C2E2DA110019719")

# 最大并发数
MAX_CONCURRENT=2

# 固定 Header
GZ_PID="glazero"
GZ_SIGN="5e19b3fddf1600debff295aeaf3fade0"

# 当前后台任务数量
job_count=0

# 总体开始时间（毫秒）
TOTAL_START=$(date +%s%3N)

# 启动一个 master 实例的函数
start_master() {
  local CHANNEL="$1"
  local SN="$2"

  local START_TIME=$(date +%s%3N)

  echo ">>> 正在处理 Channel: $CHANNEL, SN: $SN"

  UUID="launch-master-shell-auto"
  TIMESTAMP=$(date +%s)
  API_URL="https://api-test-cn.fm.aosulife.com/v1/firmware/sync?uuid=${UUID}&t=${TIMESTAMP}"

  response=$(curl -k -s -X POST "${API_URL}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "Gz-Pid: ${GZ_PID}" \
    -H "Gz-Sign: ${GZ_SIGN}" \
    --data-urlencode "sn=${SN}" \
    --data-urlencode "refreshSts=true"
  )

  ak=$(echo "$response" | jq -r '.data?.liveStream?.ak // empty')
  sk=$(echo "$response" | jq -r '.data?.liveStream?.sk // empty')
  token=$(echo "$response" | jq -r '.data?.liveStream?.token // empty')

  if [[ -z "$ak" || "$ak" == "null" ]]; then
    echo "❌ 获取 $SN 的 STS 失败，跳过"
    return
  fi

  local TS=$(date +%Y%m%d_%H%M%S_%3N)
  local BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
  local LOG_FILE="${BASE_DIR}/log/master/master_${CHANNEL}_${TS}.log"

  mkdir -p "$(dirname "$LOG_FILE")"
  
  (
    cd build
    AWS_ACCESS_KEY_ID="$ak" AWS_SECRET_ACCESS_KEY="$sk" AWS_SESSION_TOKEN="$token" \
    AWS_DEFAULT_REGION="cn-north-1" AWS_KVS_LOG_LEVEL=1 DEBUG_LOG_SDP=TRUE \
    nohup ./samples/kvsWebrtcClientMaster "$CHANNEL" > "$LOG_FILE" 2>&1 &
  )

  local END_TIME=$(date +%s%3N)
  local DURATION=$((END_TIME - START_TIME))

  echo -e "\033[32m🚀 Master 启动命令已发出：$CHANNEL（耗时 ${DURATION}ms，日志: $LOG_FILE）\033[0m"
}

# 遍历所有 channel/sn
for i in "${!CHANNEL_NAMES[@]}"; do
  CHANNEL="${CHANNEL_NAMES[$i]}"
  SN="${SN_LIST[$i]}"

  start_master "$CHANNEL" "$SN" &

  ((job_count++))

  echo "🔄 当前并发数：$job_count"

  # 控制并发上限
  if (( job_count >= MAX_CONCURRENT )); then
    wait -n  # 等待任意一个任务完成
    ((job_count--))
    echo "✅ 有任务结束，当前并发数：$job_count"
  fi
done

# 等待所有剩余任务完成
wait

# 记录总耗时
TOTAL_END=$(date +%s%3N)

TOTAL_DURATION=$((TOTAL_END - TOTAL_START))

echo "🎉 所有 Master 实例处理完成，总耗时：${TOTAL_DURATION}ms"
