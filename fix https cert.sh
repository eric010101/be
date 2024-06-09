#!/bin/bash


# 配置
DOMAIN="myaimaster.zapto.org"
EMAIL="007.aimaster@gmail.com"
CONFIG_DIR="/etc/letsencrypt/live/$DOMAIN"
BACKUP_DIR="/etc/letsencrypt/backup_$DOMAIN"

git clone https://github.com/eric010101/be.git

# 日志文件
LOG_FILE="/root/generate-ssl-certificate.log"
exec > >(tee -a ${LOG_FILE}) 2>&1
exec 2> >(tee -a ${LOG_FILE} >&2)

# 记录命令执行到日志
log_and_execute() {
    echo "Executing: $@" | tee -a ${LOG_FILE}
    "$@"
}

# 备份并删除现有证书目录和配置文件
if [ -d "$CONFIG_DIR" ]; then
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

# 生成新的HTTPS证书
#log_and_execute sudo certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos --email $EMAIL
sudo unzip /root/be/beth.zip -d /var/www/html/wordpress/wp-content/themes/
sudo unzip /root/be/beth-child.zip -d /var/www/html/wordpress/wp-content/themes/
sudo chown -R www-data:www-data /var/www/html/wordpress/wp-content/themes/

mkdir -p /etc/letsencrypt/live/myaimaster.zapto.org
sudo cp /root/be/cert.pem /etc/letsencrypt/live/myaimaster.zapto.org/cert.pem
sudo cp /root/be/chain.pem /etc/letsencrypt/live/myaimaster.zapto.org/chain.pem
sudo cp /root/be/privkey.pem /etc/letsencrypt/live/myaimaster.zapto.org/privkey.pem
sudo cp /root/be/fullchain.pem /etc/letsencrypt/live/myaimaster.zapto.org/fullchain.pem

# 检查证书文件
if [ -f "$CONFIG_DIR/fullchain.pem" ] && [ -f "$CONFIG_DIR/privkey.pem" ]; then
    echo "证书生成成功。" | tee -a ${LOG_FILE}
else
    echo "证书生成失败，请检查日志。" | tee -a ${LOG_FILE}
    #exit 1
fi

# 配置Apache使用新的证书
log_and_execute sudo bash -c "cat > /etc/apache2/sites-available/default-ssl.conf" <<EOF
<IfModule mod_ssl.c>
<VirtualHost _default_:443>
    ServerAdmin webmaster@localhost
    ServerName $DOMAIN
    DocumentRoot /var/www/html

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

    <Directory /var/www/html>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    BrowserMatch "MSIE [2-6]" nokeepalive ssl-unclean-shutdown downgrade-1.0 force-response-1.0
    BrowserMatch "MSIE [17-9]" ssl-unclean-shutdown
</VirtualHost>
</IfModule>
EOF

# 启用SSL模块和站点配置，并重新加载Apache服务
log_and_execute sudo a2enmod ssl
log_and_execute sudo a2ensite default-ssl
log_and_execute sudo systemctl reload apache2
log_and_execute sudo systemctl restart apache2

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
