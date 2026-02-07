#!/bin/bash

# remove color codes from host.sh


set -euo pipefail
IFS=$'\n\t'


# This script is designed to serve static files using either Apache HTTPD or Nginx, based on the user's choice. 
# It detects the operating system to determine the appropriate web root and package names for the services. 
# The script also prompts the user for a repository link containing the web files, 
# clones the repository, and serves the files through the chosen web server.

# Tested on Ubuntu 24.04 and Amazon Linux 2023.03

# Load OS info
. /etc/os-release

# common variables
WEBROOT="/var/www/html"

# service for hosting static file
echo
echo "Which service do you want to use? (Default: Nginx)"
echo "1 - Apache HTTPD"
read -n 1 -p "2 - Nginx (1 or 2)? " SRV
echo

if [[ "$SRV" == "1" ]]; then
    SRV="apache2"
elif [[ "$SRV" == "2" ]]; then
    SRV="nginx"
else
    echo "Invalid input. Defaulting to Nginx."
    SRV="nginx"
fi

# takes the user's input - webfile repos link
read -p "Input the webfiles repository link: " LINK
echo


# checks OS information as some distros have different web roots and package names for the services
if [[ "$SRV" == "apache2" ]]; then

    # install apache httpd based on the distro
    
    if [[ "$ID" == "ubuntu" || "$ID" == "debian" ]]; then
        echo "Updating and installing git, $SRV ..."
        sudo apt update &>/dev/null && sudo apt install -y $SRV git &>/dev/null
        echo "Successfully installed :)"
    else
        SRV="httpd"
        echo "installing git, $SRV ..."
        sudo dnf install -y httpd git &>/dev/null 
        echo "Successfully installed :)"
    fi

else
    # install nginx based on the distro 
    if [[ "$ID" == "ubuntu" || "$ID" == "debian" ]]; then
        echo "Updating and installing git, $SRV ..."
        sudo apt update &>/dev/null && sudo apt install -y $SRV git &>/dev/null
        echo "Successfully installed :)"

        # sudo rm -r "$WEBROOT"/*
        # echo "Cleaned default files in $WEBROOT"

    else
        WEBROOT=/usr/share/nginx/html

        # Install packages
        echo "installing git, $SRV ..."
        sudo dnf install -y $SRV git &>/dev/null
        echo "Successfully installed :)"

        # Clean default files
        sudo rm -r "$WEBROOT"/*
        echo "Cleaned default files in $WEBROOT"
    fi
    
fi

# Enable and start service
sudo systemctl enable --now $SRV &>/dev/null 
echo "Started $SRV service and enabled it to start on boot."

# Clone repo
git clone $LINK /tmp/webfiles &>/dev/null 
echo "Cloned repository successfully :)"

# Copy website
sudo cp -r /tmp/webfiles/* "$WEBROOT"
echo "Successfully copied website files to $WEBROOT"

# Clean clone
sudo rm -rf /tmp/webfiles
echo "Cleaned up temporary files."

# Restart Service
sudo systemctl restart $SRV
echo "Restarted $SRV to apply changes. Your website should now be accessible."

