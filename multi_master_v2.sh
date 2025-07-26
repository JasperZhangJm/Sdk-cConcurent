#!/bin/bash

# 创建log目录
mkdir -p ./log/master

# 最大并发数
MAX_CONCURRENT=5

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
    -H "Gz-Pid: glazero" \
    -H "Gz-Sign: 5e19b3fddf1600debff295aeaf3fade0" \
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

  sleep 0.5

  local END_TIME=$(date +%s%3N)
  local DURATION=$((END_TIME - START_TIME))

  echo -e "\033[32m🚀 Master 启动命令已发出：$CHANNEL（耗时 ${DURATION}ms，日志: $LOG_FILE）\033[0m"
}

# 从文件中读取 sn 和 channel 的映射，格式：sn channel
if [[ ! -f "sn_channel_list.txt" ]]; then
  echo "❌ 未找到 sn_channel_list.txt 文件"
  exit 1
fi

while read -r SN CHANNEL; do
  if [[ -z "$SN" || -z "$CHANNEL" ]]; then
    echo "⚠️ 跳过空行或格式不正确的行"
    continue
  fi

  start_master "$CHANNEL" "$SN" &

  ((job_count++))
  echo "🔄 当前并发数：$job_count"

  # 控制并发上限
  if (( job_count >= MAX_CONCURRENT )); then
    wait -n  # 等待任意一个任务完成
    ((job_count--))
    echo "✅ 有任务结束，当前并发数：$job_count"
  fi
done < sn_channel_list.txt

# 等待所有剩余任务完成
wait

# 记录总耗时
TOTAL_END=$(date +%s%3N)

TOTAL_DURATION=$((TOTAL_END - TOTAL_START))

echo "🎉 所有 Master 实例处理完成，总耗时：${TOTAL_DURATION}ms"
