#!/bin/bash

sudo apt-get install -y dos2unix

git clone https://github.com/eric010101/be.git

sudo cp /root/be/all.ini /root/all.ini
sudo cp /root/be/install-allinone-OK2.sh /root/install-allinone-OK2.sh
sudo cp /root/be/fix-https-cert.sh /root/fix-https-cert.sh

dos2unix install-allinone-OK2.sh
dos2unix fix-https-cert.sh


sudo chmod +x install-allinone-OK2.sh
sudo chmod +x fix-https-cert.sh

sudo ./install-allinone-OK2.sh
sudo ./fix-https-cert.sh
