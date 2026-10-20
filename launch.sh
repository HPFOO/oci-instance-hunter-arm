#!/usr/bin/env bash
# ==============================================================================
# OCI Free Tier ARM Instance Hunter (Custom Shape & Storage)
# Repository: oci-instance-hunter-arm
# ==============================================================================

set -e

echo "=================================================="
echo "    OCI Free Tier ARM Instance Auto-Provisioner   "
echo "=================================================="

# 1. Instance Naming
MY_NAME="${VM_NAME:-$1}"
if [ -z "$MY_NAME" ]; then
  read -r -p "Enter instance name [Default: oci-arm-vm]: " input_name
  MY_NAME="${input_name:-oci-arm-vm}"
fi

# 2. Hardware Resource Sizing
read -r -p "Enter OCPUs [Default: 2]: " input_ocpu
OCPUS="${input_ocpu:-2}"

read -r -p "Enter Memory in GBs [Default: 12]: " input_ram
RAM_GBS="${input_ram:-12}"

read -r -p "Enter Boot Volume size in GB [50-200, Default: 100]: " input_boot
BOOT_GBS="${input_boot:-100}"

echo ">> Configured: ${OCPUS} OCPU | ${RAM_GBS} GB RAM | ${BOOT_GBS} GB Boot Volume"

# 3. SSH Key Handling (Named per instance & FIPS Compliant)
PUB_KEY="${SSH_KEY:-$2}"
KEY_AUTO_GENERATED=0
INSTANCE_KEY_PATH="$HOME/.ssh/${MY_NAME}_id_rsa"

if [ -z "$PUB_KEY" ]; then
  if [ -f "${INSTANCE_KEY_PATH}.pub" ]; then
    echo ">> Detected existing key for this instance: ${INSTANCE_KEY_PATH}.pub"
    PUB_KEY=$(cat "${INSTANCE_KEY_PATH}.pub")
    GENERATED_KEY_PATH="$INSTANCE_KEY_PATH"
    KEY_AUTO_GENERATED=1
  elif [ -f "$HOME/.ssh/id_rsa.pub" ]; then
    echo ">> Detected general key: ~/.ssh/id_rsa.pub"
    PUB_KEY=$(cat "$HOME/.ssh/id_rsa.pub")
  elif [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
    echo ">> Detected general key: ~/.ssh/id_ed25519.pub"
    PUB_KEY=$(cat "$HOME/.ssh/id_ed25519.pub")
  else
    echo ">> No default SSH key detected."
    echo "   1) Specify custom key file path (e.g., ~/.ssh/my_key.pub)"
    echo "   2) Paste public key string directly"
    echo "   3) Auto-generate a dedicated RSA 4096-bit key pair for this instance"
    read -r -p "Select option [1/2/3, Default: 3]: " key_choice
    key_choice="${key_choice:-3}"

    if [ "$key_choice" == "1" ]; then
      while true; do
        read -r -p "Enter full path to your .pub file: " user_key_path
        eval expanded_path="$user_key_path"
        if [ -f "$expanded_path" ]; then
          PUB_KEY=$(cat "$expanded_path")
          echo ">> Successfully loaded key from: $expanded_path"
          break
        else
          echo "File not found at: $expanded_path. Please try again."
        fi
      done
    elif [ "$key_choice" == "2" ]; then
      read -r -p "Paste your full SSH Public Key string: " PUB_KEY
    else
      GENERATED_KEY_PATH="$INSTANCE_KEY_PATH"
      echo ">> Generating a new dedicated RSA 4096-bit key pair at $GENERATED_KEY_PATH..."
      mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
      ssh-keygen -t rsa -b 4096 -N "" -f "$GENERATED_KEY_PATH" -C "${MY_NAME}-key"
      PUB_KEY=$(cat "${GENERATED_KEY_PATH}.pub")
      KEY_AUTO_GENERATED=1
      echo ">> Dedicated key created successfully!"
    fi
  fi
fi

if [ -z "$PUB_KEY" ]; then
  echo "Error: No valid SSH public key provided."
  exit 1
fi

echo ">> Target Instance Name : $MY_NAME"
echo ">> Target VNIC Name     : ${MY_NAME}-vnic"

# 4. Fetch Tenancy & Availability Domain
echo ">> Querying OCI tenancy & availability domain..."
COMP_ID=$(oci iam tenancy get --tenancy-id "$OCI_TENANCY" --query "data.id" --raw-output)
AD_NAME=$(oci iam availability-domain list --compartment-id "$COMP_ID" --query "data[0].name" --raw-output)

# 5. Check or Create Dedicated Isolated VCN (Fully Idempotent)
VCN_NAME="${MY_NAME}-vcn"
echo ">> Verifying isolated network: ${VCN_NAME}..."

VCN_ID=$(oci network vcn list --compartment-id "$COMP_ID" --display-name "$VCN_NAME" --query "data[0].id" --raw-output 2>/dev/null || true)
if [ -z "$VCN_ID" ] || [ "$VCN_ID" == "None" ] || [ "$VCN_ID" == "null" ]; then
  echo ">> Creating dedicated VCN (192.168.0.0/16)..."
  VCN_ID=$(oci network vcn create --compartment-id "$COMP_ID" --cidr-block "192.168.0.0/16" --display-name "$VCN_NAME" --query "data.id" --raw-output)
else
  echo ">> Reusing existing VCN ($VCN_ID)..."
fi

IG_NAME="${MY_NAME}-igw"
IG_ID=$(oci network internet-gateway list --compartment-id "$COMP_ID" --vcn-id "$VCN_ID" --display-name "$IG_NAME" --query "data[0].id" --raw-output 2>/dev/null || true)
if [ -z "$IG_ID" ] || [ "$IG_ID" == "None" ] || [ "$IG_ID" == "null" ]; then
  echo ">> Creating Internet Gateway ($IG_NAME)..."
  IG_ID=$(oci network internet-gateway create --compartment-id "$COMP_ID" --vcn-id "$VCN_ID" --is-enabled true --display-name "$IG_NAME" --query "data.id" --raw-output)
else
  echo ">> Reusing existing Internet Gateway ($IG_ID)..."
fi

RT_ID=$(oci network route-table list --compartment-id "$COMP_ID" --vcn-id "$VCN_ID" --query "data[0].id" --raw-output)
oci network route-table update --rt-id "$RT_ID" --route-rules "[{\"cidrBlock\":\"0.0.0.0/0\",\"networkEntityId\":\"$IG_ID\"}]" --force > /dev/null 2>&1 || true

SUB_NAME="${MY_NAME}-subnet"
SUB_ID=$(oci network subnet list --compartment-id "$COMP_ID" --vcn-id "$VCN_ID" --display-name "$SUB_NAME" --query "data[0].id" --raw-output 2>/dev/null || true)
if [ -z "$SUB_ID" ] || [ "$SUB_ID" == "None" ] || [ "$SUB_ID" == "null" ]; then
  echo ">> Creating Public Subnet (192.168.1.0/24)..."
  SUB_ID=$(oci network subnet create --compartment-id "$COMP_ID" --vcn-id "$VCN_ID" --cidr-block "192.168.1.0/24" --display-name "$SUB_NAME" --query "data.id" --raw-output)
else
  echo ">> Reusing existing Public Subnet ($SUB_ID)..."
fi

# 6. Resolve Canonical Ubuntu 22.04 LTS ARM64 (aarch64) Image
echo ">> Resolving latest Ubuntu 22.04 LTS aarch64 image..."
IMG_ID=$(oci compute image list --compartment-id "$COMP_ID" \
  --operating-system "Canonical Ubuntu" \
  --shape "VM.Standard.A1.Flex" \
  --sort-by TIMECREATED --sort-order DESC \
  --query 'data[?contains("display-name", '\''22.04'\'') && contains("display-name", '\''aarch64'\'')].id | [0]' --raw-output)

if [ -z "$IMG_ID" ] || [ "$IMG_ID" == "None" ] || [ "$IMG_ID" == "null" ]; then
  echo ">> Warning: Exact match for 22.04 aarch64 failed. Fetching latest available Ubuntu aarch64 image..."
  IMG_ID=$(oci compute image list --compartment-id "$COMP_ID" \
    --operating-system "Canonical Ubuntu" \
    --shape "VM.Standard.A1.Flex" \
    --sort-by TIMECREATED --sort-order DESC \
    --query 'data[?contains("display-name", '\''aarch64'\'')].id | [0]' --raw-output)
fi

echo ">> Target Image OCID: $IMG_ID"

# 7. Write Metadata JSON Safely
cat << EOF > metadata.json
{"ssh_authorized_keys": "$PUB_KEY"}
EOF

# 8. Capacity Hunting Loop
COUNT=0
FDS=("FAULT-DOMAIN-1" "FAULT-DOMAIN-2" "FAULT-DOMAIN-3")

echo "--------------------------------------------------"
echo "Hunting for ARM capacity. Press Ctrl+C to terminate."
echo "--------------------------------------------------"

while true; do
  FD=${FDS[$((COUNT % 3))]}
  echo "[Attempt $COUNT] Probing capacity in $FD..."

  OUTPUT=$(oci compute instance launch \
    --compartment-id "$COMP_ID" \
    --availability-domain "$AD_NAME" \
    --fault-domain "$FD" \
    --shape "VM.Standard.A1.Flex" \
    --shape-config "{\"ocpus\":$OCPUS,\"memoryInGBs\":$RAM_GBS}" \
    --boot-volume-size-in-gbs "$BOOT_GBS" \
    --subnet-id "$SUB_ID" \
    --assign-public-ip true \
    --vnic-display-name "${MY_NAME}-vnic" \
    --image-id "$IMG_ID" \
    --display-name "$MY_NAME" \
    --metadata file://metadata.json \
    2>&1) || true

  if echo "$OUTPUT" | grep -qi 'PROVISIONING'; then
    echo "=================================================="
    echo "SUCCESS: ARM Instance provisioned successfully!"
    echo "=================================================="
    rm -f metadata.json

    # Fetch public IP
    INST_ID=$(echo "$OUTPUT" | grep -oE '"id": "ocid1.instance.oc1.[^"]+' | head -n 1 | cut -d'"' -f4 || true)
    if [ -n "$INST_ID" ]; then
      PUB_IP=$(oci compute instance list-vnics --instance-id "$INST_ID" --query 'data[0]."public-ip"' --raw-output 2>/dev/null || echo "<YOUR_PUBLIC_IP>")
    else
      PUB_IP="<YOUR_PUBLIC_IP>"
    fi

    echo ">> Public IP: $PUB_IP"
    echo "--------------------------------------------------"

    if [ "$KEY_AUTO_GENERATED" -eq 1 ] && [ -n "$GENERATED_KEY_PATH" ]; then
      echo "🔑 SSH KEY NOTICE:"
      echo "A dedicated private key was generated at: $GENERATED_KEY_PATH"
      echo "To display the private key content to copy to your local machine, run:"
      echo "   cat $GENERATED_KEY_PATH"
      echo ""
      echo "On your local Mac / Linux machine, save it as a file (e.g. ~/.ssh/${MY_NAME}_key) and connect:"
      echo "   chmod 600 ~/.ssh/${MY_NAME}_key"
      echo "   ssh -i ~/.ssh/${MY_NAME}_key ubuntu@$PUB_IP"
    else
      echo "Connect via SSH:"
      echo "   ssh -i /path/to/your/private_key ubuntu@$PUB_IP"
    fi
    echo "=================================================="
    break
  fi

  if echo "$OUTPUT" | grep -q "TooManyRequests"; then
    SLEEP=$((RANDOM % 60 + 120))
    echo ">> Rate limit hit. Backing off for ${SLEEP}s..."
    sleep "$SLEEP"
  elif echo "$OUTPUT" | grep -iq "Out of host capacity"; then
    SLEEP=$((RANDOM % 45 + 45))
    echo ">> Out of capacity in $FD. Retrying next FD in ${SLEEP}s..."
    sleep "$SLEEP"
  else
    echo ">> Non-capacity error encountered:"
    echo "$OUTPUT"
    rm -f metadata.json
    exit 1
  fi

  COUNT=$((COUNT + 1))
done
