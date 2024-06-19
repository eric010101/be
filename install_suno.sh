#!/bin/bash
sudo apt  install npm -y
git clone https://github.com/gcui-art/suno-api.git
cp /be/suno.env /suno-api/.env
cd suno-api
npm install
