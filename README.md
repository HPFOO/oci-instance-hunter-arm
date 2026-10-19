# 👨🏻‍💻 OCI Free Tier ARM Instance Hunter

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-Oracle%20Cloud-red.svg)](https://cloud.oracle.com/)
[![Shape](https://img.shields.io/badge/Shape-VM.Standard.A1.Flex-blue.svg)]()

An automated, zero-dependency Bash script to hunt and provision an **Oracle Cloud Infrastructure (OCI) Always Free ARM instance (`VM.Standard.A1.Flex`)**.

It features interactive hardware sizing (OCPU, RAM, Boot Storage), automated network isolation, smart SSH key generation/detection, and automated cross-Fault-Domain capacity cycling with randomized jitter backoff.

---

## ⚡ Quick Start (1-Line Command)

1. Sign in to your **Oracle Cloud Console**.
2. Open **Cloud Shell** (the terminal icon `>_` in the top-right header).
3. Paste and run this command:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/hpfoo/oci-instance-hunter-arm/main/launch.sh)"
```

---

## ⚙️ Custom Hardware Sizing

When you execute the script, it prompts you to enter your desired compute hardware (or simply press `Enter` to accept standard defaults):

* **OCPUs:** Choose CPU cores (Default: `2`).
* **RAM (GB):** Choose memory allocation (Default: `12`).
* **Boot Storage (GB):** Select boot volume size between 50 and 200 GB (Default: `100`).

---

### 🔑 How SSH Keys Work (Beginner Guide)

If you are new to SSH or do not have a key, don't worry—the script handles everything:

1. **Option 3 (Auto-Generate - Recommended for Beginners)**:
   - The script creates a new, FIPS-compliant RSA 4096-bit key pair on the fly inside Cloud Shell at `~/.ssh/id_rsa`.

2. **How to get the key onto your local Mac / PC**:
   - **Method A (Copy-Paste Text)**: In Cloud Shell, run:
     ```bash
     cat ~/.ssh/id_rsa
     ```
     Copy the entire output starting from `-----BEGIN OPENSSH PRIVATE KEY-----` to `-----END OPENSSH PRIVATE KEY-----`. Save it on your local machine (e.g., `~/.ssh/oci_arm_key`) and set strict permissions:
     ```bash
     chmod 600 ~/.ssh/oci_arm_key
     ```

   - **Method B (Download File via Web GUI)**: 
     Click the **Gear / Ellipsis icon** in the Cloud Shell top-right menu -> select **Download File** -> enter `/home/<your-user>/.ssh/id_rsa` (or simply `.ssh/id_rsa`).

3. **Connect to your server**:
   ```bash
   ssh -i ~/.ssh/oci_arm_key ubuntu@<YOUR_PUBLIC_IP>


---

## 🕒 Running in Background (`tmux` - Recommended)

ARM instances in high-demand regions (e.g., Singapore, Tokyo, Frankfurt) frequently hit `Out of host capacity`. Since Oracle Cloud Shell automatically disconnects after 20 minutes of inactivity, keep it hunting 24/7 inside `tmux`:

```bash
# 1. Start a persistent session
tmux new -s hunt-arm

# 2. Run the 1-line script inside tmux
bash -c "$(curl -fsSL https://raw.githubusercontent.com/hpfoo/oci-instance-hunter-arm/main/launch.sh)"

# 3. Detach safely: press 'Ctrl + B', then press 'D'
```

*To check progress later:*
```bash
tmux attach -t hunt-arm
```

---

## 🛠️ Architecture & Isolation

* **Isolated Network:** Deploys a dedicated VCN (`192.168.0.0/16`), custom Internet Gateway, Route Table (`0.0.0.0/0`), and a Public Subnet (`192.168.1.0/24`). It will not alter or conflict with your existing production networks.
* **OS Image:** Automatically identifies and installs the latest Canonical Ubuntu 22.04 LTS for ARM64 (`aarch64`).
* **Adaptive Capacity Hunting:**
  - Cycles across `FAULT-DOMAIN-1`, `FAULT-DOMAIN-2`, and `FAULT-DOMAIN-3`.
  - Randomized sleep intervals (40–81s on capacity limits, 108–162s on API rate limits) prevent tenant-level OCI API restrictions.

---

## 💻 Retrieve Public IP After Provisioning

Once provisioned, run this in Cloud Shell to fetch your instance's public IP:

```bash
oci compute instance list-vnics \
  --instance-id $(oci compute instance list --display-name "oci-arm-vm" --query "data[0].id" --raw-output) \
  --query "data[0].\"public-ip\"" --raw-output
```

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
