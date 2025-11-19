#!/bin/bash

# -----------------------------
# Important Pre-requisites
# -----------------------------
# Make sure you are logged in to AWS CLI (aws configure)
# and your IAM user has the required permissions to launch EC2 instances,
# manage security groups, and access key pairs.
# Without proper permissions, the script will fail.

# -----------------------------
# Configuration - UPDATE BEFORE USE
# -----------------------------

# AMI_ID: The Amazon Machine Image ID to launch your EC2 instances.
# Replace with a valid AMI ID for your region.
AMI_ID="ami-xxxxxxxxxxxxxxxxx"

# KEY_NAME: Name of the EC2 key pair you created in AWS.
# This key is used for SSH access to your instances.
KEY_NAME="your-key-name"

# SSH_KEY_PATH: Path to your private .pem file corresponding to KEY_NAME.
# Make sure the permissions are set correctly (chmod 400).
SSH_KEY_PATH="./your-key.pem"

# SECURITY_GROUP: The ID of the security group that allows required ports (22, 1935, etc.)
SECURITY_GROUP="sg-xxxxxxxxxxxxxxxxx"

# REGION: AWS region where your instances will be launched (e.g., eu-west-2)
REGION="your-region"

# STREAM_ID: Default stream identifier for load testing
STREAM_ID="stream1"

# OUTPUT_DIR: Directory where test logs and summaries will be saved locally
OUTPUT_DIR="./output"

# APP_NAME: If you don't plan to use ABR you can change it to one of the other default applications (live,WebRTCAppEE), otherwise leave it as is
APP_NAME="LiveApp"

# AMS_LICENSE: Your ant media license key
AMS_LICENSE="AMS-xxxxxxxxxxxxxxxx"


mkdir -p "$OUTPUT_DIR"

# -----------------------------
# User prompts for instance types
# -----------------------------
read -p "Enter instance type for Ant Media Server (default: c5.xlarge): " USER_INSTANCE_TYPE
read -p "Enter instance type for Load Tester (default: c5.large): " USER_TEST_INSTANCE_TYPE

INSTANCE_TYPE=${USER_INSTANCE_TYPE:-c5.xlarge}
TEST_INSTANCE_TYPE=${USER_TEST_INSTANCE_TYPE:-c5.large}

# Detect GPU instance
if [[ "$INSTANCE_TYPE" == g* ]]; then
  echo "[!] Using GPU instance type: $INSTANCE_TYPE"
fi

USE_ABR="n"
ABR_SETTINGS=""

select_abr() {
  read -p "Do you want to apply an ABR preset? (y/n): " USE_ABR
  if [[ "$USE_ABR" == "y" ]]; then
    echo "Select ABR preset to apply:"
    select ABR_OPTION in \
      "1080p" "720p" "480p" "360p" \
      "1080p,720p,480p,360p" "1080p,720p,480p" \
      "720p,480p" "1080p,720p"; do
      case $REPLY in
        1) ABR_SETTINGS='[{"videoBitrate":2500000,"forceEncode":true,"audioBitrate":256000,"height":1080}]'; break;;
        2) ABR_SETTINGS='[{"videoBitrate":2000000,"forceEncode":true,"audioBitrate":128000,"height":720}]'; break;;
        3) ABR_SETTINGS='[{"videoBitrate":1000000,"forceEncode":true,"audioBitrate":96000,"height":480}]'; break;;
        4) ABR_SETTINGS='[{"videoBitrate":800000,"forceEncode":true,"audioBitrate":64000,"height":360}]'; break;;
        5) ABR_SETTINGS='[{"videoBitrate":2500000,"forceEncode":true,"audioBitrate":256000,"height":1080},{"videoBitrate":2000000,"forceEncode":true,"audioBitrate":128000,"height":720},{"videoBitrate":1000000,"forceEncode":true,"audioBitrate":96000,"height":480},{"videoBitrate":800000,"forceEncode":true,"audioBitrate":64000,"height":360}]'; break;;
        6) ABR_SETTINGS='[{"videoBitrate":2500000,"forceEncode":true,"audioBitrate":256000,"height":1080},{"videoBitrate":2000000,"forceEncode":true,"audioBitrate":128000,"height":720},{"videoBitrate":1000000,"forceEncode":true,"audioBitrate":96000,"height":480}]'; break;;
        7) ABR_SETTINGS='[{"videoBitrate":2000000,"forceEncode":true,"audioBitrate":128000,"height":720},{"videoBitrate":1000000,"forceEncode":true,"audioBitrate":96000,"height":480}]'; break;;
        8) ABR_SETTINGS='[{"videoBitrate":2500000,"forceEncode":true,"audioBitrate":256000,"height":1080},{"videoBitrate":2000000,"forceEncode":true,"audioBitrate":128000,"height":720}]'; break;;
        *) echo "Invalid option, try again.";;
      esac
    done
  fi
}

echo "[+] Launching EC2 instances..."

INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type $INSTANCE_TYPE \
  --key-name $KEY_NAME \
  --security-group-ids $SECURITY_GROUP \
  --region $REGION \
  --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":30,"VolumeType":"gp3"}}]' \
  --query 'Instances[0].InstanceId' \
  --output text 2>/tmp/ams_launch_err.log) || {
    echo "[✗] Failed to launch Ant Media instance."
    cat /tmp/ams_launch_err.log
    exit 1
}

TEST_INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type $TEST_INSTANCE_TYPE \
  --key-name $KEY_NAME \
  --security-group-ids $SECURITY_GROUP \
  --region $REGION \
  --query 'Instances[0].InstanceId' \
  --output text 2>/tmp/tester_launch_err.log) || {
    echo "[✗] Failed to launch Load Tester instance."
    cat /tmp/tester_launch_err.log
    echo "[!] Terminating Ant Media instance ($INSTANCE_ID)..."
    aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $REGION
    exit 1
}

echo "[+] Waiting for instances to be running..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID $TEST_INSTANCE_ID --region $REGION

ANTMEDIA_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
TEST_IP=$(aws ec2 describe-instances --instance-ids $TEST_INSTANCE_ID --region $REGION \
  --query "Reservations[0].Instances[0].PublicIpAddress" --output text)

echo "[+] Ant Media IP: $ANTMEDIA_IP"
echo "[+] Load Tester IP: $TEST_IP"

echo "[+] Waiting for Ant Media instance to pass status checks..."
aws ec2 wait instance-status-ok --instance-ids $INSTANCE_ID --region $REGION

echo "[+] Waiting for SSH to be ready on Ant Media..."
for attempt in {1..30}; do
  echo "[*] SSH attempt $attempt..."
  if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -i $SSH_KEY_PATH ubuntu@$ANTMEDIA_IP 'echo SSH Ready' &>/dev/null; then
    echo "[✓] SSH is ready."
    break
  fi
  sleep 10
done

echo "[+] Installing Ant Media Server..."
ssh -o StrictHostKeyChecking=no -i $SSH_KEY_PATH ubuntu@$ANTMEDIA_IP <<EOF
set -e
sudo apt-get update
sudo apt-get install -y openjdk-11-jdk wget
wget -O install_ant-media-server.sh https://raw.githubusercontent.com/ant-media/Scripts/master/install_ant-media-server.sh
chmod +x install_ant-media-server.sh
sudo ./install_ant-media-server.sh -l $AMS_LICENSE
EOF

# If GPU instance, install GPU drivers
if [[ "$INSTANCE_TYPE" == g* ]]; then
  echo "[+] GPU instance detected, installing NVIDIA CUDA runtime on Ant Media instance..."
  ssh -o StrictHostKeyChecking=no -i $SSH_KEY_PATH ubuntu@$ANTMEDIA_IP <<'EOF'
set -e
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
sudo dpkg -i cuda-keyring_1.1-1_all.deb
sudo apt-get update
sudo apt-get -y install cuda-toolkit-12-6
sudo apt-get install -y cuda-drivers

EOF

  echo "[+] Rebooting GPU instance via AWS CLI..."
  aws ec2 reboot-instances --instance-ids $INSTANCE_ID --region $REGION

  echo "[+] Waiting for Ant Media instance to come back online..."
  aws ec2 wait instance-status-ok --instance-ids $INSTANCE_ID --region $REGION

  echo "[+] Ant Media GPU instance is back online."

fi

echo "[+] Setting up Load Tester..."
ssh -o StrictHostKeyChecking=no -i $SSH_KEY_PATH ubuntu@$TEST_IP <<'EOF'
sudo apt-get update
sudo apt-get install -y wget ffmpeg
wget https://raw.githubusercontent.com/ant-media/Scripts/master/load-testing/rtmp_publisher.sh
chmod +x rtmp_publisher.sh
EOF

run_test() {
  RTMP_URL="rtmp://${ANTMEDIA_IP}:1935/${APP_NAME}/${STREAM_ID}"
  echo "[+] RTMP URL: $RTMP_URL"

  UPLOAD_FILE="yes"

  if [[ -z "$LAST_VIDEO_FILE" ]]; then
    echo "Available .mp4 videos in current directory:"
    select VIDEO_FILE in *.mp4; do
      if [[ -n "$VIDEO_FILE" ]]; then
        LAST_VIDEO_FILE="$VIDEO_FILE"
        break
      fi
    done
  else
    echo "Previous video file: $LAST_VIDEO_FILE"
    read -p "Use the same video file? (y/n): " USE_SAME
    if [[ "$USE_SAME" != "y" ]]; then
      echo "Available .mp4 videos in current directory:"
      select VIDEO_FILE in *.mp4; do
        if [[ -n "$VIDEO_FILE" ]]; then
          LAST_VIDEO_FILE="$VIDEO_FILE"
          break
        fi
      done
    else
      UPLOAD_FILE="no"
    fi
  fi

  if [[ "$UPLOAD_FILE" == "yes" ]]; then
    echo "[+] Uploading $LAST_VIDEO_FILE to load tester..."
    scp -o StrictHostKeyChecking=no -i $SSH_KEY_PATH "$LAST_VIDEO_FILE" ubuntu@$TEST_IP:~/uploaded.mp4
  else
    echo "[*] Reusing already uploaded video file on load tester."
  fi

  read -p "Enter number of publishers: " COUNT
  TIMESTAMP=$(date +%F-%H%M%S)
  CPU_LOG_FILE="$OUTPUT_DIR/cpu_usage_${TIMESTAMP}.log"
  SUMMARY_FILE="$OUTPUT_DIR/summary_${TIMESTAMP}.txt"

  ssh -o StrictHostKeyChecking=no -i $SSH_KEY_PATH ubuntu@$TEST_IP "bash -s" <<EOF &
#!/bin/bash
pkill -u ubuntu ffmpeg || true
pkill -f rtmp_publisher.sh || true
pkill -f top || true
rm -f keep_streaming.flag cpu_usage.log

top -b -d 1 -n 600 > cpu_usage.log &
CPU_PID=\$!

sleep 10
./rtmp_publisher.sh uploaded.mp4 $RTMP_URL $COUNT &
PUB_PID=\$!

touch keep_streaming.flag
while [ -f keep_streaming.flag ]; do sleep 1; done

pkill -u ubuntu ffmpeg || true
kill -9 \$CPU_PID 2>/dev/null || true
kill -9 \$PUB_PID 2>/dev/null || true
EOF

  echo "Press ENTER to stop streaming..."
  read
  ssh -o StrictHostKeyChecking=no -i $SSH_KEY_PATH ubuntu@$TEST_IP "rm -f keep_streaming.flag"
  scp -o StrictHostKeyChecking=no -i $SSH_KEY_PATH ubuntu@$TEST_IP:~/cpu_usage.log "$CPU_LOG_FILE"

  MAX_CPU=$(awk 'NR>7 { if ($9+0 > max) max=$9 } END { print max }' "$CPU_LOG_FILE")
  AVG_CPU=$(awk 'NR>7 { total+=$9; count++ } END { print total/count; }' "$CPU_LOG_FILE")

  cat <<EOF2 > "$SUMMARY_FILE"
==== RTMP Load Test Summary ====

Timestamp              : $TIMESTAMP
Video File             : $LAST_VIDEO_FILE
Number of Publishers   : $COUNT
App Name               : $APP_NAME
Instance Type (Tester) : $TEST_INSTANCE_TYPE
RTMP URL               : $RTMP_URL
Max CPU (%)            : $MAX_CPU
Avg CPU (%)            : $AVG_CPU

Logs saved to $CPU_LOG_FILE
EOF2

  cat "$SUMMARY_FILE"
}


while true; do
  select_abr

  if [[ "$USE_ABR" == "y" ]]; then
    echo "[+] Uploading ABR config to Ant Media..."
    sed "s|__ENCODER_SETTINGS__|$ABR_SETTINGS|g" red5-web.template > red5-web.properties
    scp -o StrictHostKeyChecking=no -i $SSH_KEY_PATH red5-web.properties ubuntu@$ANTMEDIA_IP:/tmp/
    ssh -o StrictHostKeyChecking=no -i $SSH_KEY_PATH ubuntu@$ANTMEDIA_IP <<EOF
sudo mv /tmp/red5-web.properties /usr/local/antmedia/webapps/WebRTCAppEE/WEB-INF/red5-web.properties
sudo service antmedia restart
EOF
    APP_NAME="WebRTCAppEE"
  else
    APP_NAME="LiveApp"
  fi

  run_test

  read -p "Run another test? (y/n): " AGAIN
  if [[ "$AGAIN" != "y" ]]; then
    read -p "Terminate EC2 instances? (y/n): " TERMINATE
    if [[ "$TERMINATE" == "y" ]]; then
      aws ec2 terminate-instances --instance-ids $INSTANCE_ID $TEST_INSTANCE_ID --region $REGION
      echo "[✓] Instances terminated."
    else
      echo "[*] Instances left running."
    fi
    break
  fi
done

echo "[✓] Script complete."

