#!/bin/bash

CHANNEL="lzgd5496a7907243e22d"

# query
UUID="launch-master-shell-auto"
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

# 打印原始响应（可选）
# echo "响应内容: $response"

# 提取 ak、sk、token
ak=$(echo "$response" | jq -r '.data.liveStream.ak')
sk=$(echo "$response" | jq -r '.data.liveStream.sk')
token=$(echo "$response" | jq -r '.data.liveStream.token')

# 打印结果
echo "AK: $ak"
echo "SK: $sk"
echo "Token: $token"

TS=$(date +%Y%m%d_%H%M%S_%3N)
LOG_FILE="../log/master/master_${CHANNEL}_${TS}.log"

cd build
# nohup ./build/samples/kvsWebrtcClientMaster "$CHANNEL" > "$LOG_FILE" 2>&1 &
#./build/samples/kvsWebrtcClientMaster "$CHANNEL"
AWS_ACCESS_KEY_ID="$ak" AWS_SECRET_ACCESS_KEY="$sk" AWS_SESSION_TOKEN="$token" \
AWS_DEFAULT_REGION="cn-north-1" AWS_KVS_LOG_LEVEL=1 DEBUG_LOG_SDP=TRUE \
nohup ./samples/kvsWebrtcClientMaster "$CHANNEL" > "$LOG_FILE" 2>&1 &
