#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ------------------------------
# Load OS info
# ------------------------------
. /etc/os-release  # same as source /etc/os-release
. /etc/fstab-bak/fstab-var &> /dev/null || true  # Load MOUNT_POINT if backup exists, ignore if not

if [[ "${1:-}" == "-restore" ]]; then
    read -n 1 -p "Are you sure you want to restore the original fstab? This will undo any changes made by this script. (y/n): " CONFIRM
    echo

    if [[ "$CONFIRM" != "y" ]]; then
        echo "✅ Restoration cancelled. No changes were made."
        exit 1
    fi

    if [[ ! -f /etc/fstab-bak/fstab-org/fstab ]]; then
        echo "⚠️ No backup found. Nothing to restore."
        exit 1
    fi

    # Check for active processes using the mount point
    if mountpoint -q "$MOUNT_POINT" && lsof +f -- "$MOUNT_POINT" >/dev/null 2>&1; then
        echo "❌ Cannot restore: active processes are using $MOUNT_POINT"
        echo "👉 Please stop the processes using this mount point and rerun the script."
        exit 1
    fi

    echo "⏳ Restoring fstab from original backup..."
    sudo cp /etc/fstab-bak/fstab-org/fstab /etc/fstab
    sudo umount "$MOUNT_POINT" &> /dev/null || {
        echo "❌ Error: Failed to unmount $MOUNT_POINT after restoration. Please check your fstab manually."
        exit 1
    }
    sudo systemctl daemon-reload
    echo "✅ fstab restored successfully!"
    echo "! The backup of the original fstab is still available at /etc/fstab-bak if needed."
    exit 1
fi

if [[ "${1:-}" == "-help" ]]; then
    echo "Usage: $0 [restore|help]"
    echo
    echo "Commands:"
    echo "  -restore - Restore the original /etc/fstab from backup and unmount the EFS."
    echo "  -help    - Display this help message."
    echo
    echo "If no command is provided, the script will proceed to mount the EFS as configured."
    exit 1
fi

# If no argument, continue normal script
# ------------------------------
# Welcome message
# ------------------------------
echo "---Mounting EFS---"
echo "Note: Ensure that the EFS security group allows inbound NFS traffic (port 2049) from this instance's security group."
echo "Also ensure that the EFS is in the same VPC and availability zone as this instance."
echo

# ------------------------------
# User input with validation
# ------------------------------

read -p "Enter the full EFS ID (e.g., fs-12345678): " EFS_ID
if [[ -z "$EFS_ID" ]]; then
    echo "Error: EFS ID cannot be empty"
    exit 1
fi

read -p "Enter the EFS Access Point ID (fsap-xxxx): " ACCESS_POINT_ID
if [[ ! "$ACCESS_POINT_ID" =~ ^fsap-[a-zA-Z0-9]+$ ]]; then
    echo "Error: Invalid Access Point ID format"
    exit 1
fi

read -p "Enter the mount point (e.g., /mnt/efs): " MOUNT_POINT
if [[ -z "$MOUNT_POINT" ]]; then
    echo "Error: Mount point cannot be empty"
    exit 1
fi

echo

# ------------------------------
# Backup fstab
# ------------------------------
if [[ ! -f /etc/fstab-bak ]]; then
    sudo mkdir -p /etc/fstab-bak
    sudo mkdir -p /etc/fstab-bak/fstab-org
    echo "MOUNT_POINT=$MOUNT_POINT" | sudo tee -a /etc/fstab-bak/fstab-var > /dev/null
    
else
    echo "⚠️ Backup of /etc/fstab already exists at /etc/fstab-bak. Skipping backup creation."
fi

sudo cp /etc/fstab /etc/fstab-bak

if [[ -f /etc/fstab-bak/fstab-org/fstab ]]; then
    echo ""
else
    sudo cp /etc/fstab /etc/fstab-bak/fstab-org
fi
echo "✅ Backups of /etc/fstab created at /etc/fstab-bak"

# ------------------------------
# Create mount point directory
# ------------------------------
sudo mkdir -p "$MOUNT_POINT" || {
    echo "⚠️ Error: Failed to create mount point directory $MOUNT_POINT"
    exit 1
}
echo "✅ Mount point directory created at $MOUNT_POINT"

# ------------------------------
# Install amazon-efs-utils
# ------------------------------
echo "⏳ Installing amazon-efs-utils package..."
if [[ $ID == "ubuntu" || $ID == "debian" ]]; then
    sudo apt update -y &> /dev/null
    curl -s https://packagecloud.io/install/repositories/meter/public/script.deb.sh | sudo bash &> /dev/null
    sudo apt-get install amazon-efs-utils -y &> /dev/null
elif command -v dnf &> /dev/null; then
    sudo dnf install -y amazon-efs-utils &> /dev/null
else
    sudo yum install -y amazon-efs-utils &> /dev/null
fi
echo "✅ amazon-efs-utils installed successfully"

# ------------------------------
# Append EFS entry to fstab if not already present
# ------------------------------
FSTAB_LINE="$EFS_ID:/ $MOUNT_POINT efs _netdev,noresvport,tls,accesspoint=$ACCESS_POINT_ID 0 0"

if ! grep -Fxq "$FSTAB_LINE" /etc/fstab; then
    echo "$FSTAB_LINE" | sudo tee -a /etc/fstab > /dev/null
    echo "✅ Added EFS mount entry to /etc/fstab"
else
    echo "⚠️ EFS mount entry already exists in /etc/fstab"
    echo "✅ skipped fstab modification to avoid duplicates."
    echo "⚠️ Please verify /etc/fstab manually if needed."
    exit 1
fi

# ------------------------------
# Mount EFS
# ------------------------------
sudo mount -a &> /dev/null || {
    echo "❌ Error: Failed to mount EFS. ⏳Restoring fstab backup..."
    sudo cp /etc/fstab-bak/fstab /etc/fstab
    echo "✅ Original fstab restored."
    echo "⚠️ Please check EFS configuration and try again."
    exit 1
}

sudo systemctl daemon-reload
echo "✅ EFS mounted successfully at $MOUNT_POINT"
echo ":: You can verify the mount with 'df -h'"
echo