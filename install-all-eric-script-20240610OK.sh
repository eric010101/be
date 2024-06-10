#!/bin/bash
#eric script
git clone https://github.com/eric010101/be.git /root/be

sudo apt-get update
sudo apt-get install -y dos2unix

sudo cp /root/be/install-allinone-OK2.sh /root/install-allinone-OK2.sh
sudo cp /root/be/fix-https-cert.sh /root/fix-https-cert.sh

sudo cp /root/be/all.ini /root/all.ini
dos2unix all.ini

sudo cp /root/be/run-all.sh /root/run-all.sh
dos2unix run-all.sh
sudo chmod +x run-all.sh
./run-all.sh

sudo cp /root/be/install_ftp_server.sh /root/install_ftp_server.sh
dos2unix install_ftp_server.sh
sudo chmod +x install_ftp_server.sh
./install_ftp_server.sh
