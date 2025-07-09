#!/bin/bash

# Disk formatting and mounting
sudo mkfs.ext4 /dev/vdb
sudo mkdir -p /mnt/vss-env
sudo mount /dev/vdb /mnt/vss-env
mount | grep "vss-env"

# System checks
df -h
nvidia-smi | grep "Driver Version"
dpkg -l | grep fabricmanager

# CUDA installation
sudo apt install -y cuda-toolkit-12-2 cuda-libraries-12-2
echo 'export PATH=/usr/local/cuda-12.2/bin:$PATH' >> ~/.bashrc
echo 'export LD_LIBRARY_PATH=/usr/local/cuda-12.2/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
source ~/.bashrc

# MicroK8s installation and setup
sudo snap install microk8s --classic
sudo microk8s enable nvidia
sudo microk8s enable hostpath-storage
sudo snap install kubectl --classic
sudo microk8s kubectl get pod -A

# NGC API Key setup
export NGC_API_KEY="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"
echo $NGC_API_KEY 

# Kubernetes secrets creation
sudo microk8s kubectl create secret docker-registry ngc-docker-reg-secret --docker-server=nvcr.io --docker-username='$oauthtoken' --docker-password=$NGC_API_KEY
sudo microk8s kubectl create secret generic graph-db-creds-secret --from-literal=username=neo4j --from-literal=password=password
sudo microk8s kubectl create secret generic ngc-api-key-secret --from-literal=NGC_API_KEY=$NGC_API_KEY

# Helm chart setup
sudo microk8s helm fetch \
    https://helm.ngc.nvidia.com/nvidia/blueprint/charts/nvidia-blueprint-vss-2.3.0.tgz \
    --username='$oauthtoken' --password=$NGC_API_KEY

# Create override.yaml
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

# Helm installation
sudo microk8s helm install vss-blueprint nvidia-blueprint-vss-2.3.0.tgz \
    --set global.ngcImagePullSecretName=ngc-docker-reg-secret -f overrides.yaml

# Verification commands
sudo microk8s kubectl get node
sudo watch microk8s kubectl get pod
