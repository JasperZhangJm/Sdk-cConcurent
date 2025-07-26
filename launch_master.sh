#!/bin/bash

# channel
CHANNEL_NAMES=("lzgd5496a7907243e22d" "lzgd73052d21279230f4")

# sn, 与channel一一对应
SN=("C2E2DA110017952" "C2E2DA110019719")

# 获取master端sts信息
CREDENTIALS_API="https://your-api.example.com/get-aws-credentials"

# 并发启动 master 实例
for CHANNEL in "${CHANNEL_NAMES[@]}"; do
  echo ">>> 启动 Master: $CHANNEL"

  # query
  UUID="master shell auto"
  TIMESTAMP=$(date +%s)
  API_URL="https://api-test-cn.fm.aosulife.com/v1/firmware/sync?uuid=${UUID}&t=${TIMESTAMP}"

  # 请求体参数
  SN="C2E2DA110017952"
  REFRESH_STS="true"

  # Header
  GZ_PID="glazero"
  GZ_SIGN="5e19b3fddf1600debff295aeaf3fade0"

  # 发起 POST 请求并保存响应
  response=$(curl -k -s -X POST "${API_URL}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -H "Gz-Pid: ${GZ_PID}" \
    -H "Gz-Sign: ${GZ_SIGN}" \
    --data-urlencode "sn=${SN}" \
    --data-urlencode "refreshSts=${REFRESH_STS}"
  )

  # 提取 ak、sk、token
  ak=$(echo "$response" | jq -r '.data.liveStream.ak')
  sk=$(echo "$response" | jq -r '.data.liveStream.sk')
  token=$(echo "$response" | jq -r '.data.liveStream.token')

  # 打印结果
  echo "AK: $ak"
  echo "SK: $sk"
  echo "Token: $token"


  # 获取 AWS 临时密钥
  # CREDENTIALS_JSON=$(curl -s -X POST "$CREDENTIALS_API" -d "channelName=$CHANNEL")

  export AWS_ACCESS_KEY_ID=ak
  export AWS_SECRET_ACCESS_KEY=sk
  export AWS_SESSION_TOKEN=token

  # 检查密钥是否正确获取
  if [[ -z "$AWS_ACCESS_KEY_ID" || "$AWS_ACCESS_KEY_ID" == "null" ]]; then
    echo "获取 $CHANNEL 的凭证失败，跳过"
    continue
  fi

  echo "AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID"

  # 启动 master 进程（假设你编译后的可执行文件在 build 目录下）
  # ./kvsWebRTCClientMaster "$CHANNEL" &
  nohup ./samples/kvsWebrtcClientMaster "$CHANNEL" > "master_$CHANNEL_$(date +%Y%m%d_%H%M%S).log" 2>&1 &

  # 可选：延迟启动下一个（防止接口并发压力）
  sleep 1
done

echo ">>> 所有 Master 启动命令已发出"
