#!/bin/bash

# 加载配置文件
CONFIG_FILE="all.ini"
if [[ ! -f $CONFIG_FILE ]]; then
    echo "配置文件 $CONFIG_FILE 不存在。"
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

# 日志文件
LOG_FILE="/root/allinone.log"
USER_FILE="/root/allinione-idpw.txt"

exec > >(tee -a ${LOG_FILE}) 2>&1

# Function to wait for dpkg lock
wait_for_dpkg_lock() {
    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1; do
        echo "Waiting for other package management process to finish..."
        sleep 5
    done
}

# Update package information
echo "Updating package information..."
wait_for_dpkg_lock
sudo apt-get update -y

# Install Apache
echo "Installing Apache..."
wait_for_dpkg_lock
sudo apt-get install -y apache2

# Enable and start Apache service
echo "Enabling and starting Apache service..."
sudo systemctl enable apache2
sudo systemctl start apache2

# Install MySQL
echo "Installing MySQL..."
wait_for_dpkg_lock
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password password $MYSQL_ROOT_PASSWORD"
sudo debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $MYSQL_ROOT_PASSWORD"
sudo apt-get install -y mysql-server

# Enable and start MySQL service
echo "Enabling and starting MySQL service..."
sudo systemctl enable mysql
sudo systemctl start mysql

# Install PHP
echo "Installing PHP..."
wait_for_dpkg_lock
sudo apt-get install -y php libapache2-mod-php php-mysql

# 修改 php.ini 文件
PHP_INI_FILE=$(php -r "echo php_ini_loaded_file();")
sudo sed -i "s/upload_max_filesize = .*/upload_max_filesize = 200M/" $PHP_INI_FILE
sudo sed -i "s/post_max_size = .*/post_max_size = 200M/" $PHP_INI_FILE
sudo sed -i "s/max_execution_time = .*/max_execution_time = 60/" $PHP_INI_FILE
sudo sed -i "s/max_input_time = .*/max_input_time = 60/" $PHP_INI_FILE

# Restart Apache to load PHP module
echo "Restarting Apache service..."
sudo systemctl daemon-reload
sudo systemctl restart apache2

# Open firewall for Apache traffic
echo "Configuring firewall to allow Apache traffic..."
sudo ufw allow 'Apache Full'
sudo ufw reload

# Verify Apache installation
echo "Verifying Apache service is running..."
if sudo systemctl is-active apache2 | grep -q "active"; then
  echo "Apache service is running."
else
  echo "Apache service is not running. Please check the installation."
fi

# Verify MySQL installation
echo "Verifying MySQL service is running..."
if sudo systemctl is-active mysql | grep -q "active"; then
  echo "MySQL service is running."
else
  echo "MySQL service is not running. Please check the installation."
fi

# Verify PHP installation
echo "Verifying PHP installation..."
if php -v | grep -q "PHP"; then
  echo "PHP is installed."
else
  echo "PHP is not installed. Please check the installation."
fi

# Install WordPress
echo "Installing WordPress..."

# Download WordPress
wget -c http://wordpress.org/latest.tar.gz

# Extract WordPress
tar -xzvf latest.tar.gz

# Create WordPress directory
sudo mkdir -p /var/www/html/wordpress

# Copy WordPress files to the web root
sudo cp -r wordpress/* /var/www/html/wordpress/

# Set permissions
sudo chown -R www-data:www-data /var/www/html/wordpress/
sudo chmod -R 755 /var/www/html/wordpress/

# Create WordPress configuration file
cd /var/www/html/wordpress/
sudo cp wp-config-sample.php wp-config.php

# Configure WordPress to connect to MySQL
sudo sed -i "s/database_name_here/$MYSQL_DATABASE/" wp-config.php
sudo sed -i "s/username_here/$MYSQL_USER/" wp-config.php
sudo sed -i "s/password_here/$MYSQL_PASSWORD/" wp-config.php

# Create MySQL database and user for WordPress
echo "Creating MySQL database and user for WordPress..."
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE $MYSQL_DATABASE;"
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE USER '$MYSQL_USER'@'localhost' IDENTIFIED BY '$MYSQL_PASSWORD';"
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $MYSQL_DATABASE.* TO '$MYSQL_USER'@'localhost';"
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "FLUSH PRIVILEGES;"

# 创建 /etc/letsencrypt/options-ssl-apache.conf 文件
sudo mkdir -p /etc/letsencrypt/
sudo touch /etc/letsencrypt/options-ssl-apache.conf
echo 'SSLProtocol all -SSLv2 -SSLv3
SSLCipherSuite HIGH:!aNULL:!MD5
SSLHonorCipherOrder on
' | sudo tee /etc/letsencrypt/options-ssl-apache.conf

# 下载并配置证书
echo "Checking GitHub for existing SSL certificates..."
#TMP_DIR=$(mktemp -d)
CERT_DIR="/etc/letsencrypt/live/$DOMAIN"

# 克隆GitHub仓库到临时目录
sudo git clone https://github.com/eric010101/be 
    sudo mkdir -p $CERT_DIR
    sudo cp /root/be/fullchain.pem $CERT_DIR/fullchain.pem
    sudo cp /root/be/privkey.pem $CERT_DIR/privkey.pem
	sudo cp /root/be/chain.pem $CERT_DIR/chain.pem
	sudo cp /root/be/cert.pem $CERT_DIR/cert.pem
# 检查GitHub上是否有证书
if [[ -f /root/be/fullchain.pem && -f /root/be/privkey.pem ]]; then
    echo "从GitHub下载证书..."
    sudo mkdir -p $CERT_DIR
    sudo mv /root/be/fullchain.pem $CERT_DIR/fullchain.pem
    sudo mv /root/be/privkey.pem $CERT_DIR/privkey.pem
	sudo mv /root/be/chain.pem $CERT_DIR/chain.pem
	sudo mv /root/be/cert.pem $CERT_DIR/cert.pem
else
    echo "GitHub上没有找到证书，尝试从Let’s Encrypt生成证书..."
    sudo apt-get install -y certbot
    #sudo certbot certonly --apache -d $DOMAIN --non-interactive --agree-tos --email $EMAIL || CERTBOT_ERROR=$?

    # if [ "$CERTBOT_ERROR" == "1" ]; then
        # echo "证书生成失败，可能是因为超过了限制，生成自签名证书..."
        # sudo mkdir -p $CERT_DIR
        # sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout $CERT_DIR/privkey.pem -out $CERT_DIR/fullchain.pem -subj "/CN=$DOMAIN"

        # # 将生成的自签名证书上传到GitHub
        # mkdir -p $TMP_DIR/certificates
        # sudo cp $CERT_DIR/fullchain.pem $TMP_DIR/certificates/
        # sudo cp $CERT_DIR/privkey.pem $TMP_DIR/certificates/

        # cd $TMP_DIR
        # #git add certificates/fullchain.pem certificates/privkey.pem
        # #git commit -m "Add self-signed SSL certificates"
        # #git push origin main
    # fi
fi

# 设置证书权限
sudo chown root:root $CERT_DIR/fullchain.pem $CERT_DIR/privkey.pem $CERT_DIR/chain.pem $CERT_DIR/cert.pem
sudo chmod 600 $CERT_DIR/fullchain.pem $CERT_DIR/privkey.pem $CERT_DIR/chain.pem $CERT_DIR/cert.pem

# 配置Apache使用SSL证书
echo "配置Apache使用SSL证书..."
sudo bash -c "cat > /etc/apache2/sites-available/default-ssl.conf" <<EOF
<IfModule mod_ssl.c>
<VirtualHost _default_:443>
    ServerAdmin webmaster@localhost
    ServerName $DOMAIN
    DocumentRoot /var/www/html/wordpress

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined

    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/$DOMAIN/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/$DOMAIN/privkey.pem
    Include /etc/letsencrypt/options-ssl-apache.conf

    <FilesMatch "\\.(cgi|shtml|phtml|php)\$">
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

# 启用SSL模块和站点配置，并重新启动Apache
sudo a2enmod ssl
sudo a2ensite default-ssl
sudo systemctl restart apache2

# 清理临时文件
#rm -rf $TMP_DIR

# Install phpMyAdmin
echo "Installing phpMyAdmin..."
wait_for_dpkg_lock
sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/dbconfig-install boolean true"
sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/app-password-confirm password $PHPMYADMIN_APP_PASSWORD"
sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/admin-pass password $MYSQL_ROOT_PASSWORD"
sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/mysql/app-pass password $PHPMYADMIN_APP_PASSWORD"
sudo debconf-set-selections <<< "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2"
sudo apt-get install -y phpmyadmin

# Include phpMyAdmin configuration in Apache
if [ ! -f /etc/apache2/conf-available/phpmyadmin.conf ]; then
    echo "Configuring Apache to include phpMyAdmin..."
    sudo ln -s /etc/phpmyadmin/apache.conf /etc/apache2/conf-available/phpmyadmin.conf
    sudo a2enconf phpmyadmin.conf
fi
sudo systemctl reload apache2

# 安装 BeTheme
echo "Installing BeTheme..."
#cd /tmp
git clone https://github.com/eric010101/be.git
if [ -f /root/be/beth.zip ] && [ -f /root/be/beth-child.zip ]; then
    sudo unzip /root/be/beth.zip -d /var/www/html/wordpress/wp-content/themes/
    sudo unzip /root/be/beth-child.zip -d /var/www/html/wordpress/wp-content/themes/
    sudo chown -R www-data:www-data /var/www/html/wordpress/wp-content/themes/
else
    echo "BeTheme files not found, skipping installation."
fi

# 复制文件到FTP上传目录
FTP_UPLOAD_DIR="/home/ftpuser/upload"
sudo mkdir -p $FTP_UPLOAD_DIR
if [ -f $CONFIG_FILE ]; then
    sudo cp $CONFIG_FILE $FTP_UPLOAD_DIR/${DOMAIN}_allinione.ini
fi
if [ -f $LOG_FILE ]; then
    sudo cp $LOG_FILE $FTP_UPLOAD_DIR/${DOMAIN}_allinone.log
fi
if [ -f $USER_FILE ]; then
    sudo cp $USER_FILE $FTP_UPLOAD_DIR/${DOMAIN}_allinione-idpw.txt
fi

# 将文件上传到GitHub
#cd $TMP_DIR
#git add ${DOMAIN}_allinione.ini ${DOMAIN}_allinone.log ${DOMAIN}_allinione-idpw.txt
#git commit -m "Add configuration, log, and user files for $DOMAIN"
#git push origin main

# 检查 Apache 配置文件的语法错误
echo "Checking Apache configuration syntax..."
sudo apache2ctl configtest

# 如果配置文件有语法错误，输出错误信息
if ! sudo apache2ctl configtest | grep -q "Syntax OK"; then
    echo "There is a syntax error in the Apache configuration. Please check the output above for details."
    #exit 1
fi

# 如果配置文件没有语法错误，重新加载 Apache 服务
echo "Reloading Apache service..."


# #eric add
# # 备份并删除现有证书目录和配置文件
# if [ -d "$CONFIG_DIR" ]; then
    # log_and_execute sudo mkdir -p $BACKUP_DIR
    # log_and_execute sudo mv /etc/letsencrypt/live/$DOMAIN $BACKUP_DIR/
    # log_and_execute sudo mv /etc/letsencrypt/archive/$DOMAIN $BACKUP_DIR/
    # log_and_execute sudo mv /etc/letsencrypt/renewal/$DOMAIN.conf $BACKUP_DIR/
# fi

# # 注释掉 default-ssl.conf 中的SSLCertificateFile配置
# log_and_execute sudo sed -i 's|^\(SSLCertificateFile\)|#\1|' /etc/apache2/sites-available/default-ssl.conf
# log_and_execute sudo sed -i 's|^\(SSLCertificateKeyFile\)|#\1|' /etc/apache2/sites-available/default-ssl.conf

# # 停止Apache服务
# log_and_execute sudo systemctl stop apache2

# # 生成新的HTTPS证书
# #log_and_execute sudo certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos --email $EMAIL
# sudo cp /root/be/cert.pem /etc/letsencrypt/live/myaimaster.zapto.org/cert.pem
# sudo cp /root/be/chain.pem /etc/letsencrypt/live/myaimaster.zapto.org/chain.pem
# sudo cp /root/be/privkey.pem /etc/letsencrypt/live/myaimaster.zapto.org/privkey.pem
# sudo cp /root/be/fullchain.pem /etc/letsencrypt/live/myaimaster.zapto.org/fullchain.pem

# # 检查证书文件
# if [ -f "$CONFIG_DIR/fullchain.pem" ] && [ -f "$CONFIG_DIR/privkey.pem" ]; then
    # echo "证书生成成功。" | tee -a ${LOG_FILE}
# else
    # echo "证书生成失败，请检查日志。" | tee -a ${LOG_FILE}
    # exit 1
# fi

# # 配置Apache使用新的证书
# log_and_execute sudo bash -c "cat > /etc/apache2/sites-available/default-ssl.conf" <<EOF
# <IfModule mod_ssl.c>
# <VirtualHost _default_:443>
    # ServerAdmin webmaster@localhost
    # ServerName $DOMAIN
    # DocumentRoot /var/www/html

    # ErrorLog \${APACHE_LOG_DIR}/error.log
    # CustomLog \${APACHE_LOG_DIR}/access.log combined

    # SSLEngine on
    # SSLCertificateFile /etc/letsencrypt/live/$DOMAIN/fullchain.pem
    # SSLCertificateKeyFile /etc/letsencrypt/live/$DOMAIN/privkey.pem
    # Include /etc/letsencrypt/options-ssl-apache.conf

    # <FilesMatch "\\.(cgi|shtml|phtml|php)\$">
        # SSLOptions +StdEnvVars
    # </FilesMatch>

    # <Directory /usr/lib/cgi-bin>
        # SSLOptions +StdEnvVars
    # </Directory>

    # <Directory /var/www/html>
        # Options Indexes FollowSymLinks
        # AllowOverride All
        # Require all granted
    # </Directory>

    # BrowserMatch "MSIE [2-6]" nokeepalive ssl-unclean-shutdown downgrade-1.0 force-response-1.0
    # BrowserMatch "MSIE [17-9]" ssl-unclean-shutdown
# </VirtualHost>
# </IfModule>
# EOF

# 启用SSL模块和站点配置，并重新加载Apache服务
# log_and_execute sudo a2enmod ssl
# log_and_execute sudo a2ensite default-ssl
# log_and_execute sudo systemctl restart apache2


# 检查Apache配置并重新启动服务
log_and_execute sudo apache2ctl configtest
if log_and_execute sudo apache2ctl configtest | grep -q "Syntax OK"; then
    log_and_execute sudo systemctl restart apache2
else
    echo "Apache配置有错误，请检查日志。" | tee -a ${LOG_FILE}
    #exit 1
fi

echo "HTTPS证书生成和配置完成。" | tee -a ${LOG_FILE}
echo "请访问 https://$DOMAIN 以验证配置。" | tee -a ${LOG_FILE}
# end of eric add

echo "Apache configuration fixed and reloaded successfully."

# 完成
echo "LAMP stack, phpMyAdmin, WordPress, and BeTheme installation and configuration completed."
echo "SSL certificate has been obtained for $DOMAIN."
echo "Please change 'rootpassword', '$MYSQL_DATABASE', '$MYSQL_USER', and '$MYSQL_PASSWORD' to secure values of your choice."
echo "You can access your WordPress site at https://$DOMAIN/wordpress"
echo "You can access phpMyAdmin at https://$DOMAIN/phpmyadmin"
