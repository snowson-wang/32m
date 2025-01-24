#!/bin/bash
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"

red() {
    echo -e "\033[31m\033[01m$1\033[0m"
}

green() {
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow() {
    echo -e "\033[33m\033[01m$1\033[0m"
}

if [[ -f "/root/Xray/xray" ]]; then
    green "xray文件已存在！"
else
    echo "正在获取xray最新版本号..."
    last_version=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases?include_prereleases=true | grep -o '"tag_name": *"[^"]*' | head -n 1 | sed 's/"tag_name": "//')
    yellow "xray最新版本号为： $last_version"
    echo "开始下载xray文件..."
    wget https://github.com/XTLS/Xray-core/releases/download/$last_version/Xray-linux-64.zip
    cd /root
    mkdir -p ./Xray
    unzip -d /root/Xray Xray-linux-64.zip
    rm Xray-linux-64.zip
    cd /root/Xray
    if [[ -f "xray" ]]; then
        green "下载成功！"
    else
        red "下载失败！"
        exit 1
    fi
fi

read -p "请输入reality端口号：" port
sign=false
until $sign; do
    if [[ -z $port ]]; then
        red "错误：端口号不能为空，请输入小鸡管家给定的可用端口号!"
        read -p "请重新输入reality端口号：" port
        continue
    fi
    if ! echo "$port" | grep -qE '^[0-9]+$';then
        red "错误：端口号必须是数字!"
        read -p "请重新输入reality端口号：" port
        continue
    fi
    if [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        red "错误：端口号必须介于1~65525之间!"
        read -p "请重新输入reality端口号：" port
        continue
    fi
    if [[ -z $(ss -tuln | grep ":$port ") ]]; then
        green "成功：端口号 $port 可用!"
        sign=true
    else
        red "错误：$port 已被占用！"
        read -p "请重新输入reality端口号：" port
    fi
done

UUID=$(cat /proc/sys/kernel/random/uuid)
read -rp "请输入回落域名[默认: www.microsoft.com]: " dest_server
[[ -z $dest_server ]] && dest_server="www.microsoft.com"
short_id=$(dd bs=4 count=2 if=/dev/urandom | xxd -p -c 8)
keys=$(/root/Xray/xray x25519)
private_key=$(echo $keys | awk -F " " '{print $3}')
public_key=$(echo $keys | awk -F " " '{print $6}')
green "private_key: $private_key"
green "public_key: $public_key"
green "short_id: $short_id"

rm -f /root/Xray/config.json
cat << EOF > /root/Xray/config.json
{
  "inbounds": [
      {
          "listen": "0.0.0.0",
          "port": $port,
          "protocol": "vless",
          "settings": {
              "clients": [
                  {
                      "id": "$UUID",
                      "flow": "xtls-rprx-vision"
                  }
              ],
              "decryption": "none"
          },
          "streamSettings": {
              "network": "tcp",
              "security": "reality",
              "realitySettings": {
                  "show": true,
                  "dest": "$dest_server:443",
                  "xver": 0,
                  "serverNames": [
                      "$dest_server"
                  ],
                  "privateKey": "$private_key",
                  "minClientVer": "",
                  "maxClientVer": "",
                  "maxTimeDiff": 0,
                  "shortIds": [
                  "$short_id"
                  ]
              }
          }
      }
  ],
  "outbounds": [
      {
          "protocol": "freedom",
          "tag": "direct"
      },
      {
          "protocol": "blackhole",
          "tag": "blocked"
      }
  ],
  "policy": {
    "handshake": 4,
    "connIdle": 300,
    "uplinkOnly": 2,
    "downlinkOnly": 5,
    "statsUserUplink": false,
    "statsUserDownlink": false,
    "bufferSize": 1024
  }
}
EOF

IP=$(wget -qO- --no-check-certificate -U Mozilla https://api.ip.sb/geoip | sed -n 's/.*"ip": *"\([^"]*\).*/\1/p')
green "您的IP为：$IP"

share_link="vless://$UUID@$IP:$port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$dest_server&fp=chrome&pbk=$public_key&sid=$short_id&type=tcp&headerType=none#32M-Reality"
echo ${share_link} > /root/Xray/share-link.txt

yellow "reality的分享链接已保存到：/root/Xray/share-link.txt"
green "reality的分享链接为："
red $share_link

# 创建 systemd 服务文件
rm -f /etc/systemd/system/xray.service
cat << EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
After=network.target

[Service]
ExecStart=/root/Xray/xray run -c /root/Xray/config.json
Restart=on-failure
User=nobody
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# 设置权限并启动服务
chmod 644 /etc/systemd/system/xray.service
systemctl daemon-reload
systemctl enable xray
systemctl restart xray
systemctl status xray
