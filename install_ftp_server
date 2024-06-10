#!/bin/bash

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

# Install vsftpd
echo "Installing vsftpd..."
wait_for_dpkg_lock
sudo apt-get install -y vsftpd

# Backup the original vsftpd configuration file
sudo cp /etc/vsftpd.conf /etc/vsftpd.conf.orig

# Configure vsftpd
echo "Configuring vsftpd..."
sudo bash -c 'cat > /etc/vsftpd.conf' << EOF
listen=YES
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
allow_writeable_chroot=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
rsa_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
rsa_private_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
ssl_enable=NO
pasv_min_port=10000
pasv_max_port=10100
EOF

# Restart vsftpd to apply changes
echo "Restarting vsftpd..."
sudo systemctl restart vsftpd
sudo systemctl enable vsftpd

# Open firewall for FTP traffic
echo "Configuring firewall to allow FTP traffic..."
sudo ufw allow 20/tcp
sudo ufw allow 21/tcp
sudo ufw allow 10000:10100/tcp
sudo ufw reload

# Create FTP users
echo "Creating FTP users..."
for i in {1..5}; do
    USERNAME="ftpuser$i"
    PASSWORD=$(openssl rand -base64 12)
    if id "$USERNAME" &>/dev/null; then
        echo "User $USERNAME already exists, deleting user."
        sudo deluser --remove-home "$USERNAME"
    fi
    sudo adduser --gecos "" --disabled-password "$USERNAME"
    echo "$USERNAME:$PASSWORD" | sudo chpasswd
    sudo mkdir -p /home/$USERNAME/ftp/upload
    sudo chown nobody:nogroup /home/$USERNAME/ftp
    sudo chmod a-w /home/$USERNAME/ftp
    sudo chown $USERNAME:$USERNAME /home/$USERNAME/ftp/upload
    echo "Created user $USERNAME with password $PASSWORD"
done

# Check if all.ini file exists
if [[ ! -f all.ini ]]; then
    echo "Error: 'all.ini' file not found. Please create the file with the list of users in the format '[ftp] user1_name=username user1_password=password'."
    exit 1
fi

# Read users from all.ini file
declare -A ftp_users
current_section=""
while IFS= read -r line; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    
    # Read section name
    if [[ "$line" =~ ^\[(.*)\]$ ]]; then
        current_section="${BASH_REMATCH[1]}"
    elif [[ "$current_section" == "ftp" && "$line" =~ ^([^=]+)=(.*)$ ]]; then
        key="${BASH_REMATCH[1]// /}"
        value="${BASH_REMATCH[2]// /}"
        if [[ "$key" =~ user[0-9]+_name ]]; then
            username="$value"
        elif [[ "$key" =~ user[0-9]+_password ]]; then
            password="$value"
            ftp_users["$username"]="$password"
        fi
    fi
done < all.ini

# Print users read from all.ini
echo "Read the following users from all.ini:"
for username in "${!ftp_users[@]}"; do
    echo "Username: $username, Password: ${ftp_users[$username]}"
done

# Create FTP users and directories
for username in "${!ftp_users[@]}"; do
    if id "$username" &>/dev/null; then
        echo "User $username already exists, deleting user."
        sudo deluser --remove-home "$username"
    fi
    sudo adduser --gecos "" --disabled-password "$username"
    echo "$username:${ftp_users[$username]}" | sudo chpasswd
    sudo mkdir -p /home/$username/ftp/upload
    sudo chown nobody:nogroup /home/$username/ftp
    sudo chmod a-w /home/$username/ftp
    sudo chown $username:$username /home/$username/ftp/upload
    echo "User $username created with password ${ftp_users[$username]}"
done

echo "vsftpd installation and configuration completed."
echo "FTP server is running and ready for use."

