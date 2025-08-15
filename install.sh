#!/bin/bash

# NVIDIA VSS Blueprint Setup Script
# This script sets up a complete GPU-accelerated Kubernetes environment with NVIDIA's Vector Search Service

set -e  # Exit on any error

echo "============================================"
echo "NVIDIA VSS Blueprint Setup Script"
echo "============================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
   exit 1
fi

# Set NGC API Key (you may want to change this)
export NGC_API_KEY="aGthNTVxcGoxNTRraWdiN3V0MjB1cjZyc2o6Y2Y1YjJmMGUtMTg4Ni00NTdkLTg5MWEtY2U1NmIwMDA4ZjJh"

print_step "Starting NVIDIA VSS Blueprint Setup..."

# Part 1: Storage Setup
print_step "Setting up storage..."
sudo mkfs.ext4 /dev/vdb
sudo mkdir -p /mnt/vss-env
sudo mount /dev/vdb /mnt/vss-env
mount | grep "vss-env"
echo -e "${GREEN}✓${NC} Storage setup completed"

# Part 2: System Information Check
print_step "Checking system information..."
echo "Disk usage:"
df -h
echo "NVIDIA Driver version:"
nvidia-smi | grep "Driver Version" || print_warning "NVIDIA driver not found"
echo "Fabric Manager status:"
dpkg -l | grep fabricmanager || print_warning "Fabric Manager not installed"
echo -e "${GREEN}✓${NC} System check completed"

# Part 3: CUDA Installation
print_step "Installing CUDA toolkit..."
sudo apt update
sudo apt install -y cuda-toolkit-12-2 cuda-libraries-12-2
echo 'export PATH=/usr/local/cuda-12.2/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.2/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
source ~/.bashrc
echo -e "${GREEN}✓${NC} CUDA installation completed"

# Part 4: Kubernetes Setup
print_step "Installing and configuring MicroK8s..."
sudo snap install microk8s --classic
sudo microk8s enable nvidia
sudo microk8s enable hostpath-storage
sudo snap install kubectl --classic

# Wait for MicroK8s to be ready
print_step "Waiting for MicroK8s to be ready..."
sudo microk8s status --wait-ready

echo "Checking pods:"
sudo microk8s kubectl get pod -A
echo -e "${GREEN}✓${NC} Kubernetes setup completed"

# Part 5: API Key Setup
print_step "Setting up NGC API Key..."
echo "NGC_API_KEY is set to: $NGC_API_KEY"
echo -e "${GREEN}✓${NC} API key setup completed"

# Part 6: Kubernetes Secrets
print_step "Creating Kubernetes secrets..."
sudo microk8s kubectl create secret docker-registry ngc-docker-reg-secret \
    --docker-server=nvcr.io \
    --docker-username='$oauthtoken' \
    --docker-password=$NGC_API_KEY

sudo microk8s kubectl create secret generic graph-db-creds-secret \
    --from-literal=username=neo4j --from-literal=password=password

sudo microk8s kubectl create secret generic ngc-api-key-secret \
    --from-literal=NGC_API_KEY=$NGC_API_KEY

echo -e "${GREEN}✓${NC} Kubernetes secrets created"

# Part 7: Download Blueprint
print_step "Downloading NVIDIA VSS Blueprint..."
sudo microk8s helm fetch \
    https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-vss-2.3.1.tgz \
    --username='$oauthtoken' --password=$NGC_API_KEY

echo -e "${GREEN}✓${NC} Blueprint downloaded"

# Part 8: Create Configuration File
print_step "Creating overrides.yaml configuration..."
cat > overrides.yaml << 'EOF'
nim-llm:
  env:
  - name: NVIDIA_VISIBLE_DEVICES
    value: "0,1,2,3"
  resources:
    limits:
      nvidia.com/gpu: 0    # no limit
 
vss:
  applicationSpecs:
    vss-deployment:
      containers:
        vss:
          env:
          - name: VLM_MODEL_TO_USE
            value: nvila
          - name: MODEL_PATH
            value: "ngc:nvidia/tao/nvila-highres:nvila-lite-15b-highres-lita"
          - name: NVIDIA_VISIBLE_DEVICES
            value: "4,5"
  resources:
    limits:
      nvidia.com/gpu: 0    # no limit
 
 
nemo-embedding:
  applicationSpecs:
    embedding-deployment:
      containers:
        embedding-container:
          env:
          - name: NGC_API_KEY
            valueFrom:
              secretKeyRef:
                key: NGC_API_KEY
                name: ngc-api-key-secret
          - name: NVIDIA_VISIBLE_DEVICES
            value: '6'
  resources:
    limits:
      nvidia.com/gpu: 0    # no limit
 
nemo-rerank:
  applicationSpecs:
    ranking-deployment:
      containers:
        ranking-container:
          env:
          - name: NGC_API_KEY
            valueFrom:
              secretKeyRef:
                key: NGC_API_KEY
                name: ngc-api-key-secret
          - name: NVIDIA_VISIBLE_DEVICES
            value: '7'
  resources:
    limits:
      nvidia.com/gpu: 0    # no limit
EOF

echo -e "${GREEN}✓${NC} Configuration file created"

# Part 9: Deploy Application
print_step "Deploying VSS Blueprint..."
sudo microk8s helm install vss-blueprint nvidia-blueprint-vss-2.3.1.tgz \
    --set global.ngcImagePullSecretName=ngc-docker-reg-secret -f overrides.yaml

echo -e "${GREEN}✓${NC} VSS Blueprint deployed"

# Part 10: Monitor Deployment
print_step "Checking deployment status..."
echo "Kubernetes nodes:"
sudo microk8s kubectl get node

echo -e "\n${GREEN}============================================${NC}"
echo -e "${GREEN}Setup completed successfully!${NC}"
echo -e "${GREEN}============================================${NC}"

print_step "To monitor pods continuously, run:"
echo "sudo watch microk8s kubectl get pod"

print_step "To check specific VSS pods, run:"
echo "sudo microk8s kubectl get pod -l app=vss"

print_step "To view logs of a specific pod, run:"
echo "sudo microk8s kubectl logs <pod-name>"

print_warning "Note: It may take several minutes for all pods to become ready as they download large AI models."

echo -e "\n${YELLOW}Important:${NC} If you encounter any errors, check the pod logs and ensure your system has:"
echo "- Sufficient GPU memory (at least 8 GPUs as configured)"
echo "- Proper NVIDIA drivers installed"
echo "- Internet connectivity for downloading models"
