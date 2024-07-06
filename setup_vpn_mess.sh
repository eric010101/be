#!/bin/bash

# 自动检测服务器的外部IP地址
SERVER_IP=$(curl -4 -s http://ipv4.icanhazip.com)

# 更新并安装必要的软件包
sudo apt update
sudo apt install -y curl unzip ufw

# 下载并安装V2Ray
V2RAY_VERSION=$(curl -s https://api.github.com/repos/v2fly/v2ray-core/releases/latest | grep 'tag_name' | cut -d\" -f4)
curl -L -o v2ray.zip https://github.com/v2fly/v2ray-core/releases/download/${V2RAY_VERSION}/v2ray-linux-64.zip
unzip v2ray.zip -d /usr/local/bin/
rm v2ray.zip

# 创建V2Ray配置文件目录
sudo mkdir -p /usr/local/etc/v2ray

# 创建V2Ray配置文件
UUID='69a2406a-f1a4-4bde-ac73-d088d53d4b22'
#UUID=$(uuidgen)
sudo tee /usr/local/etc/v2ray/config.json > /dev/null <<EOF
{
  "inbounds": [{
    "port": 1080,
    "listen": "0.0.0.0",
    "protocol": "vmess",
    "settings": {
      "clients": [{
        "id": "${UUID}",
        "alterId": 0
      }]
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {}
  }]
}
EOF

# 创建V2Ray服务文件
sudo tee /etc/systemd/system/v2ray.service > /dev/null <<EOF
[Unit]
Description=V2Ray Service
After=network.target

[Service]
ExecStart=/usr/local/bin/v2ray run -config /usr/local/etc/v2ray/config.json
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF

# 启动并启用V2Ray服务
sudo systemctl daemon-reload
sudo systemctl start v2ray
sudo systemctl enable v2ray

# 配置防火墙，允许1080端口
sudo ufw allow 1080/tcp
sudo ufw enable

# 输出配置信息到/root/v2ray_info.txt
sudo tee /root/v2ray_info.txt > /dev/null <<EOF
V2Ray服务器已安装并运行。请在V2rayN客户端中使用以下配置信息：

服务器地址：${SERVER_IP}
端口：1080
UUID：${UUID}
额外ID：64
传输协议：TCP
EOF

# 显示完成信息
echo "配置文件已保存到 /root/v2ray_info.txt"
echo "你可以通过以下命令下载该文件："
echo "scp root@${SERVER_IP}:/root/v2ray_info.txt ."

#chmod +x setup_v2ray.sh
#./setup_v2ray.sh

echo "chmod +x setup_v2ray.sh"
echo "./setup_v2ray.sh"
