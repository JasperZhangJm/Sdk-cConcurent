# ==== 配置项 ====
EMAIL="1499405887@qq.com"
PASSWORD="2c654e5020adb124f9f34e2963308737"
REGION="CN"
SNS=("C2E2DA110019719" "C2E2DA110017952")

# query
UUID="launch-master-shell-auto"
TIMESTAMP=$(date +%s)
LOGIN_URL="https://api-test-cn.aosulife.com/v1/user/login?uuid=${UUID}&t=${TIMESTAMP}"
TIMESTAMP=$(date +%s)
STS_URL="https://api-test-cn.aosulife.com/v1/sts/getPlayInfo?uuid=${UUID}&t=${TIMESTAMP}"

# ==== 登录获取 sid 和 uid ====
login_response=$(curl -k -s "$LOGIN_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "Gz-Pid: glazero" \
  -H "Gz-Sign: 309a2e34497e5da0f892bc754c8fb2d9" \
  -H "Gz-Imei: b7235aaeb830185c" \
  --data-urlencode "countryAbbr=CN" \
  --data-urlencode "countryCode=86" \
  --data-urlencode "email=${EMAIL}" \
  --data-urlencode "password=${PASSWORD}" \
  --data-urlencode "region=${REGION}" \
  --data-urlencode "type=1"
)

sid=$(echo "$login_response" | jq -r '.data.sid')
uid=$(echo "$login_response" | jq -r '.data.uid')

if [[ -z "$sid" || "$sid" == "null" ]]; then
  echo "❌ 登录失败，sid 获取失败" | tee -a "$ERROR_LOG"
  exit 1
fi

# ==== 获取 STS 密钥 ====
curl_args=(
  -k -s "$STS_URL"
  -H "Content-Type: application/x-www-form-urlencoded"
  -H "Gz-Sid: $sid"
  -H "Gz-Uid: $uid"
  -H "Gz-Pid: glazero"
  -H "Gz-Sign: 309a2e34497e5da0f892bc754c8fb2d9"
  -H "Gz-Imei: b7235aaeb830185c"
  --data-urlencode "refresh=true"
)

for sn in "${SNS[@]}"; do
  curl_args+=( --data-urlencode "sn[]=$sn" )
done

sts_response=$(curl "${curl_args[@]}")

ak=$(echo "$sts_response" | jq -r '.data.ak')
sk=$(echo "$sts_response" | jq -r '.data.sk')
token=$(echo "$sts_response" | jq -r '.data.token')

if [[ -z "$ak" || "$ak" == "null" ]]; then
  echo "❌ STS 获取失败" | tee -a "$ERROR_LOG"
  exit 1
fi

echo "ak: $ak"
echo "sk: $sk"
echo "token: $token"
