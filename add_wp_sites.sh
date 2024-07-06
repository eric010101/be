#!/bin/bash

# 定义 log_and_execute 函数
log_and_execute() {
    echo "Executing: $@" | tee -a ${LOG_FILE}
    "$@" | tee -a ${LOG_FILE}
}

# 加载配置文件
CONFIG_FILE="/root/all20240619.ini"
LOG_FILE="/root/deployment.log"
if [[ ! -f $CONFIG_FILE ]]; then
    echo "配置文件 $CONFIG_FILE 不存在。" | tee -a ${LOG_FILE}
    exit 1
fi

EMAIL=$(awk -F ' = ' '/email/ {print $2}' $CONFIG_FILE)
MYSQL_ROOT_PASSWORD=$(awk -F ' = ' '/root_password/ {print $2}' $CONFIG_FILE)
MYSQL_DATABASE=$(awk -F ' = ' '/database_name/ {print $2}' $CONFIG_FILE)
MYSQL_USER=$(awk -F ' = ' '/database_user/ {print $2}' $CONFIG_FILE)
MYSQL_PASSWORD=$(awk -F ' = ' '/database_password/ {print $2}' $CONFIG_FILE)
PHPMYADMIN_APP_PASSWORD=$(awk -F ' = ' '/app_password/ {print $2}' $CONFIG_FILE)

# WordPress 源文件路径
WORDPRESS_SRC="/root/wordpress"


# 安装多个 WordPress 实例 wp1 - wp20
for i in {1..20}; do
  WP_DATABASE="wp${i}_database"
  WP_USER="wp${i}_user"
  WP_PASSWORD="wp${i}_password"
  WP_DIR="/var/www/html/wordpress/wp${i}"

  # 删除旧的数据库和用户
  log_and_execute mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS $WP_DATABASE;"
  log_and_execute mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "DROP USER IF EXISTS '$WP_USER'@'localhost';"
  log_and_execute mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"
  
  log_and_execute sudo mkdir -p $WP_DIR
  log_and_execute sudo cp -r $WORDPRESS_SRC/* $WP_DIR/
  log_and_execute sudo chown -R www-data:www-data $WP_DIR/
  log_and_execute sudo chmod -R 755 $WP_DIR/
  (cd $WP_DIR && log_and_execute sudo cp wp-config-sample.php wp-config.php && \
  log_and_execute sudo sed -i "s/database_name_here/$WP_DATABASE/" wp-config.php && \
  log_and_execute sudo sed -i "s/username_here/$WP_USER/" wp-config.php && \
  log_and_execute sudo sed -i "s/password_here/$WP_PASSWORD/" wp-config.php)
  log_and_execute mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE $WP_DATABASE;"
  log_and_execute mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "CREATE USER '$WP_USER'@'localhost' IDENTIFIED BY '$WP_PASSWORD';"
  log_and_execute mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON $WP_DATABASE.* TO '$WP_USER'@'localhost';"
  log_and_execute mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"

  # 安装 BeTheme
  if [ -f /root/be/beth.zip ] && [ -f /root/be/beth-child.zip ]; then
    log_and_execute sudo unzip /root/be/beth.zip -d $WP_DIR/wp-content/themes/
    log_and_execute sudo unzip /root/be/beth-child.zip -d $WP_DIR/wp-content/themes/
    log_and_execute sudo chown -R www-data:www-data $WP_DIR/wp-content/themes/
  else
    echo "BeTheme files not found, skipping installation for wp${i}." | tee -a ${LOG_FILE}
  fi
done
