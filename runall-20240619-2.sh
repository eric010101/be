#!/bin/bash

# 日志文件
LOG_FILE="/root/allinone06.log"
USER_FILE="/root/allinone-idpw.txt"

exec > >(tee -a ${LOG_FILE}) 2>&1

# Function to log and execute commands
log_and_execute() {
    echo "Executing: $@" | tee -a ${LOG_FILE}
    "$@" | tee -a ${LOG_FILE}
}

# Function to wait for dpkg lock
wait_for_dpkg_lock() {
    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
        echo "Waiting for other package management process to finish..." | tee -a ${LOG_FILE}
        sleep 5
    done
}

# Function to check Apache configuration
check_apache_config() {
    log_and_execute sudo apache2ctl configtest
    if ! sudo apache2ctl configtest | grep -q "Syntax OK"; then
        echo "There is a syntax error in the Apache configuration. Please check the output above for details." | tee -a ${LOG_FILE}
        sudo tail -n 50 /var/log/apache2/error.log | tee -a ${LOG_FILE}
        #exit 1
    fi
}


# 更新系统包信息并安装必要工具
log_and_execute sudo apt-get update
log_and_execute sudo apt-get install -y dos2unix git wget unzip

# 克隆GitHub仓库
log_and_execute git clone https://github.com/eric010101/be.git /root/be

# 复制并转换配置文件格式
log_and_execute sudo cp /root/be/all20240619.ini /root/all20240619.ini
log_and_execute dos2unix /root/all20240619.ini

log_and_execute cp /root/be/install-allinone-OK2.sh /root/install-allinone-OK2.sh
log_and_execute chmod +x /root/install-allinone-OK2.sh
log_and_execute dos2unix /root/install-allinone-OK2.sh

log_and_execute cp /root/be/install-allinone-OK2.sh /root/fix-https-cert.sh
log_and_execute chmod +x /root/fix-https-cert.sh
log_and_execute dos2unix /root/fix-https-cert.sh

# 更新系统包信息
log_and_execute sudo apt-get update -y

# 加载配置文件
CONFIG_FILE="/root/all20240619.ini"
if [[ ! -f $CONFIG_FILE ]]; then
    echo "配置文件 $CONFIG_FILE 不存在。" | tee -a ${LOG_FILE}
    #exit 1
fi

GITHUB_USERNAME=$(awk -F ' = ' '/username/ {print $2}' $CONFIG_FILE)
GITHUB_PASSWORD=$(awk -F ' = ' '/password/ {print $2}' $CONFIG_FILE)
GITHUB_REPO=$(awk -F ' = ' '/repository/ {print $2}' $CONFIG_FILE)
DOMAIN=$(awk -F ' = ' '/domain/ {print $2}' $CONFIG_FILE)
EMAIL=$(awk -F ' = ' '/email/ {print $2}' $CONFIG_FILE)
MYSQL_ROOT_PASSWORD=$(awk -F ' = ' '/root_password/ {print $2}' $CONFIG_FILE)
MYSQL_DATABASE=$(awk -F ' = ' '/database_name/ {print $2}' $CONFIG_FILE)
MYSQL_USER=$(awk -F ' = ' '/database_user/ {print $2}' $CONFIG_FILE)
MYSQL_PASSWORD=$(awk -F ' = ' '/database_password/ {print $2}' $CONFIG_FILE)
PHPMYADMIN_APP_PASSWORD=$(awk -F ' = ' '/app_password/ {print $2}' $CONFIG_FILE)
# 安装Apache
log_and_execute wait_for_dpkg_lock
log_and_execute sudo apt-get install -y apache2
log_and_execute sudo systemctl enable apache2
log_and_execute sudo systemctl start apache2

# 验证Apache配置
check_apache_config

# 安装MySQL
log_and_execute wait_for_dpkg_lock
log_and_execute sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password $MYSQL_ROOT_PASSWORD"
log_and_execute sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD"
log_and_execute sudo apt-get install -y mysql-server
log_and_execute sudo systemctl enable mysql
log_and_execute sudo systemctl start mysql

# 安装PHP
log_and_execute wait_for_dpkg_lock
log_and_execute sudo apt-get install -y php libapache2-mod-php php-mysql
PHP_INI_FILE=$(php -r "echo php_ini_loaded_file();")
log_and_execute sudo sed -i "s/upload_max_filesize = .*/upload_max_filesize = 200M/" $PHP_INI_FILE
log_and_execute sudo sed -i "s/post_max_size = .*/post_max_size = 200M/" $PHP_INI_FILE
log_and_execute sudo sed -i "s/max_execution_time = .*/max_execution_time = 60/" $PHP_INI_FILE
log_and_execute sudo sed -i "s/max_input_time = .*/max_input_time = 60/" $PHP_INI_FILE
log_and_execute sudo systemctl restart apache2

# 配置防火墙
log_and_execute sudo ufw allow 'Apache Full'
log_and_execute sudo ufw reload

# 验证服务
if sudo systemctl is-active apache2 | grep -q "active"; then
    echo "Apache service is running." | tee -a ${LOG_FILE}
else
    echo "Apache service is not running. Please check the installation." | tee -a ${LOG_FILE}
fi

if sudo systemctl is-active mysql | grep -q "active"; then
    echo "MySQL service is running." | tee -a ${LOG_FILE}
else
    echo "MySQL service is not running. Please check the installation." | tee -a ${LOG_FILE}
fi

if php -v | grep -q "PHP"; then
    echo "PHP is installed." | tee -a ${LOG_FILE}
else
    echo "PHP is not installed. Please check the installation." | tee -a ${LOG_FILE}
fi

# 安装WordPress
log_and_execute wget -c http://wordpress.org/latest.tar.gz
log_and_execute tar -xzvf latest.tar.gz
log_and_execute sudo mkdir -p /var/www/html/wordpress
log_and_execute sudo cp -r wordpress/* /var/www/html/wordpress/
log_and_execute sudo chown -R www-data:www-data /var/www/html/wordpress/
log_and_execute sudo chmod -R 755 /var/www/html/wordpress/
cd /var/www/html/wordpress/
log_and_execute sudo cp wp-config-sample.php wp-config.php
log_and_execute sudo sed -i "s/database_name_here/$MYSQL_DATABASE/" wp-config.php
log_and_execute sudo sed -i "s/username_here/$MYSQL_USER/" wp-config.php
log_and_execute sudo sed -i "s/password_here/$MYSQL_PASSWORD/" wp-config.php
log_and_execute mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE $MYSQL_DATABASE;"
log_and_execute mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE USER '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';"
log_and_execute mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $MYSQL_DATABASE.* TO '$MYSQL_USER'@'localhost';"
log_and_execute mysql -u root -p$MYSQL_ROOT_PASSWORD -e "FLUSH PRIVILEGES;"

# 创建和配置 /etc/apache2/sites-available/default-ssl.conf 文件
echo "Creating and configuring /etc/apache2/sites-available/default-ssl.conf"
sudo rm -f /etc/apache2/sites-available/default-ssl.conf
sudo bash -c "cat > /etc/apache2/sites-available/default-ssl.conf" <<EOF
<IfModule mod_ssl.c>
<VirtualHost _default_:443>
    ServerAdmin webmaster@localhost
    ServerName myaimaster.zapto.org
    DocumentRoot /var/www/html/wordpress

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/myaimaster.zapto.org/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/myaimaster.zapto.org/privkey.pem
    Include /etc/letsencrypt/options-ssl-apache.conf

    <FilesMatch "\\.(cgi|shtml|phtml|php)$">
        SSLOptions +StdEnvVars
    </FilesMatch>

    <Directory /usr/lib/cgi-bin>
        SSLOptions +StdEnvVars
    </Directory>

    <Directory /var/www/html/wordpress>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    BrowserMatch "MSIE [2-6]" \
      nokeepalive ssl-unclean-shutdown \
      downgrade-1.0 force-response-1.0
    BrowserMatch "MSIE [17-9]" ssl-unclean-shutdown
</VirtualHost>
</IfModule>
EOF

# 创建和配置 /etc/letsencrypt/options-ssl-apache.conf 文件
echo "Creating and configuring /etc/letsencrypt/options-ssl-apache.conf"
sudo rm -f /etc/letsencrypt/options-ssl-apache.conf
sudo mkdir -p /etc/letsencrypt
sudo bash -c "cat > /etc/letsencrypt/options-ssl-apache.conf" <<EOF
SSLProtocol all -SSLv2 -SSLv3
SSLCipherSuite HIGH:!aNULL:!MD5
SSLHonorCipherOrder on
EOF

# 验证Apache配置
check_apache_config

# 启用SSL模块和站点配置，并重新加载Apache服务
log_and_execute sudo a2enmod ssl
log_and_execute sudo a2ensite default-ssl
log_and_execute sudo systemctl restart apache2

# 验证Apache配置
check_apache_config

# 下载并配置证书
CERT_DIR="/etc/letsencrypt/live/$DOMAIN"
BACKUP_DIR="/etc/letsencrypt/backup_$DOMAIN"

# 备份并删除现有证书目录和配置文件
if [ -d "$CERT_DIR" ]; then
    log_and_execute sudo mkdir -p $BACKUP_DIR
    log_and_execute sudo mv /etc/letsencrypt/live/$DOMAIN $BACKUP_DIR/
    log_and_execute sudo mv /etc/letsencrypt/archive/$DOMAIN $BACKUP_DIR/
    log_and_execute sudo mv /etc/letsencrypt/renewal/$DOMAIN.conf $BACKUP_DIR/
fi

# 注释掉 default-ssl.conf 中的SSLCertificateFile配置
log_and_execute sudo sed -i 's|^\(SSLCertificateFile\)|#\1|' /etc/apache2/sites-available/default-ssl.conf
log_and_execute sudo sed -i 's|^\(SSLCertificateKeyFile\)|#\1|' /etc/apache2/sites-available/default-ssl.conf

# 停止Apache服务
log_and_execute sudo systemctl stop apache2

# 下载并配置证书
log_and_execute sudo mkdir -p $CERT_DIR
log_and_execute sudo cp /root/be/fullchain.pem $CERT_DIR/fullchain.pem
log_and_execute sudo cp /root/be/privkey.pem $CERT_DIR/privkey.pem
log_and_execute sudo cp /root/be/chain.pem $CERT_DIR/chain.pem
log_and_execute sudo cp /root/be/cert.pem $CERT_DIR/cert.pem

# 设置证书权限
log_and_execute sudo chown root:root $CERT_DIR/fullchain.pem $CERT_DIR/privkey.pem $CERT_DIR/chain.pem $CERT_DIR/cert.pem
log_and_execute sudo chmod 600 $CERT_DIR/fullchain.pem $CERT_DIR/privkey.pem $CERT_DIR/chain.pem $CERT_DIR/cert.pem

# 启用SSL模块和站点配置，并重新加载Apache服务
log_and_execute sudo a2enmod ssl
log_and_execute sudo a2ensite default-ssl
log_and_execute sudo systemctl restart apache2

# 验证Apache配置
check_apache_config

# 安装phpMyAdmin
log_and_execute wait_for_dpkg_lock
log_and_execute sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/dbconfig-install boolean true"
log_and_execute sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/app-password-confirm password $PHPMYADMIN_APP_PASSWORD"
log_and_execute sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/admin-pass password $MYSQL_ROOT_PASSWORD"
log_and_execute sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/app-pass password $PHPMYADMIN_APP_PASSWORD"
log_and_execute sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2"
log_and_execute sudo apt-get install -y phpmyadmin

# Include phpMyAdmin configuration in Apache
if [ ! -f /etc/apache2/conf-available/phpmyadmin.conf ]; then
    log_and_execute sudo ln -s /etc/phpmyadmin/apache.conf /etc/apache2/conf-available/phpmyadmin.conf
    log_and_execute sudo a2enconf phpmyadmin.conf
fi
log_and_execute sudo systemctl reload apache2

# 安装BeTheme
if [ -f /root/be/beth.zip ] && [ -f /root/be/beth-child.zip ]; then
    log_and_execute sudo unzip /root/be/beth.zip -d /var/www/html/wordpress/wp-content/themes/
    log_and_execute sudo unzip /root/be/beth-child.zip -d /var/www/html/wordpress/wp-content/themes/
    log_and_execute sudo chown -R www-data:www-data /var/www/html/wordpress/wp-content/themes/
else
    echo "BeTheme files not found, skipping installation." | tee -a ${LOG_FILE}
fi

# 复制文件到FTP上传目录
FTP_UPLOAD_DIR="/home/ftpuser/upload"
log_and_execute sudo mkdir -p $FTP_UPLOAD_DIR
if [ -f $CONFIG_FILE ]; then
    log_and_execute sudo cp $CONFIG_FILE $FTP_UPLOAD_DIR/${DOMAIN}_all20240619.ini
fi
if [ -f $LOG_FILE ]; then
    log_and_execute sudo cp $LOG_FILE $FTP_UPLOAD_DIR/${DOMAIN}_allinone06.log
fi
if [ -f $USER_FILE ]; then
    log_and_execute sudo cp $USER_FILE $FTP_UPLOAD_DIR/${DOMAIN}_allinone-idpw.txt
fi

# install suno api
sudo apt install npm -y
git clone https://github.com/gcui-art/suno-api.git
cp /be/suno.env /suno-api/.env
cd suno-api
npm install

# install suno web
mkdir -p /var/www/html/wordpress/suno/
cp -r /be/sunoweb/* /var/www/html/wordpress/suno/

echo "HTTPS证书生成和配置完成。" | tee -a ${LOG_FILE}
echo "请访问 https://$DOMAIN 以验证配置。" | tee -a ${LOG_FILE}

echo "Apache configuration fixed and reloaded successfully." | tee -a ${LOG_FILE}
echo "LAMP stack, phpMyAdmin, WordPress, and BeTheme installation and configuration completed." | tee -a ${LOG_FILE}
echo "SSL certificate has been obtained for $DOMAIN." | tee -a ${LOG_FILE}
echo "Please change 'rootpassword', '$MYSQL_DATABASE', '$MYSQL_USER', and '$MYSQL_PASSWORD' to secure values of your choice." | tee -a ${LOG_FILE}
echo "You can access your WordPress site at https://$DOMAIN/wordpress" | tee -a ${LOG_FILE}
echo "You can access phpMyAdmin at https://$DOMAIN/phpmyadmin" | tee -a ${LOG_FILE}
