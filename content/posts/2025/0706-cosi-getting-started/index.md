---
title: "Getting Started with COSI: Simplifying Object Storage in Kubernetes"
date: 2025-07-06
summary: |
  Learn how to integrate the Container Object Storage Interface (COSI) with Kubernetes to automate object storage provisioning, access management, and application integration.
tags: ["Go", "Kubernetes", "Container Object Storage Interface"]
series: ["Container Object Storage Interface"]
series_order: 1
authors:
  - "shanduur"
---

The **Container Object Storage Interface (COSI)** is a Kubernetes-native standard for managing object storage buckets and credentials. By abstracting provider-specific details, COSI enables dynamic provisioning, secure access management, and seamless integration with applications. In this guide, we’ll deploy COSI on a Kubernetes cluster, configure a Linode driver, and deploy a sample app that leverages automated object storage workflows.

## Step 1: Install the COSI Controller and CRDs

COSI requires a controller and Custom Resource Definitions (CRDs) to extend Kubernetes' API for object storage operations. Install them using the official Helm chart:

```bash
kubectl apply \
  -k 'https://github.com/kubernetes-sigs/container-object-storage-interface//?ref=v0.2.1'
```

This deploys the COSI controller and registers CRDs like `BucketClass`, `BucketClaim`, and `BucketAccess`.

Alternatively, you can preview the resources before applying them:

```bash
kubectl apply \
  --dry-run=client -o=yaml \
  -k 'https://github.com/kubernetes-sigs/container-object-storage-interface//?ref=v0.2.1'
```

## Step 2: Install the COSI Driver for Linode

Providers implement COSI through drivers. Here, we’ll use the **Linode COSI Driver** to manage Linode Object Storage buckets:

1. Add the Helm repository:
   ```bash
   helm repo add linode-cosi-driver \
       https://linode.github.io/linode-cosi-driver
   ```

2. Install the driver, substituting your Linode API token. The token must be configured with the following permissions `Object Storage - Read/Write`. Make sure to replace `<your-linode-api-token>` with your actual token:
   ```bash
   helm install linode-cosi-driver \
       linode-cosi-driver/linode-cosi-driver \
       --set=apiToken="<your-linode-api-token>" \
       --namespace=linode-cosi-driver \
       --create-namespace
   ```

## Step 3: Configure BucketClass and BucketAccessClass

### Define a BucketClass
A `BucketClass` specifies storage policies. Below, we create two classes—one that deletes buckets automatically and another that retains them:

```yaml
# delete-policy.yaml
apiVersion: objectstorage.k8s.io/v1alpha1
kind: BucketClass
metadata:
  name: linode-objectstorage
driverName: objectstorage.cosi.linode.com
deletionPolicy: Delete
parameters:
  cosi.linode.com/v1/region: us-east
```

```yaml
# retain-policy.yaml
apiVersion: objectstorage.k8s.io/v1alpha1
kind: BucketClass
metadata:
  name: linode-objectstorage-retain
driverName: objectstorage.cosi.linode.com
deletionPolicy: Retain
parameters:
  cosi.linode.com/v1/region: us-east
```

### Define a BucketAccessClass
A `BucketAccessClass` controls how applications authenticate to buckets. Here, we use API keys:

```yaml
# bucket-access-class.yaml
apiVersion: objectstorage.k8s.io/v1alpha1
kind: BucketAccessClass
metadata:
  name: linode-objectstorage
driverName: objectstorage.cosi.linode.com
authenticationType: Key
parameters: {}
```

Apply these manifests with `kubectl apply -f <file>.yaml`.

## Step 4: Deploy a Sample Application

Let’s deploy an app that writes logs to a COSI-managed bucket. The deployment includes:
- A `logger` sidecar container that generates logs.
- An `uploader` container that syncs logs to object storage.
- A `BucketClaim` to request a bucket.
- A `BucketAccess` to manage credentials.

```yaml
# cosi-resources.yaml
apiVersion: objectstorage.k8s.io/v1alpha1
kind: BucketAccess
metadata:
  name: cosi-sample-app
  namespace: cosi-sample
spec:
  bucketAccessClassName: linode-objectstorage
  bucketClaimName: cosi-sample-app
  credentialsSecretName: s3-credentials
  protocol: S3
---
apiVersion: objectstorage.k8s.io/v1alpha1
kind: BucketClaim
metadata:
  name: cosi-sample-app
  namespace: cosi-sample
spec:
  bucketClassName: linode-objectstorage
  protocols:
  - S3
```

```yaml
# cosi-sample-app.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: cosi-sample
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cosi-sample-app
  namespace: cosi-sample
spec:
  selector:
    matchLabels:
      app: uploader
  template:
    metadata:
      labels:
        app: uploader
    spec:
      containers:
      - args:
        - --upload-interval=240
        - --file=/mnt/logs/log.txt
        image: ghcr.io/anza-labs/cosi-sample-app:latest
        imagePullPolicy: IfNotPresent
        name: uploader
        resources:
          requests:
            cpu: 100m
            memory: 256Mi
        securityContext:
          readOnlyRootFilesystem: true
          runAsNonRoot: true
        volumeMounts:
        - mountPath: /mnt/logs
          name: logs
        - mountPath: /cosi
          name: cosi-secret
      initContainers:
      - args:
        - -c
        - |
          #!/bin/ash

          while true; do
              echo "$(date +'%Y-%m-%d %H:%M:%S') - Log entry" | tee -a "$LOG_FILE"

              # Check file size and trim if needed
              if [ -f "$LOG_FILE" ] && [ $(stat -c %s "$LOG_FILE") -gt $MAX_SIZE ]; then
                  echo "$(date +'%Y-%m-%d %H:%M:%S') - Rotating" | tee -a "$LOG_FILE.tmp"
                  mv "$LOG_FILE.tmp" "$LOG_FILE"
              fi

              sleep 10
          done
        command:
        - sh
        env:
        - name: LOG_FILE
          value: /mnt/logs/log.txt
        - name: MAX_SIZE
          value: "4194304"
        image: alpine:3.21
        name: logger
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
        restartPolicy: Always
        securityContext:
          readOnlyRootFilesystem: true
          runAsGroup: 1000
          runAsNonRoot: true
          runAsUser: 1000
        volumeMounts:
        - mountPath: /mnt/logs
          name: logs
      volumes:
      - name: cosi-secret
        secret:
          secretName: s3-credentials
      - emptyDir: {}
        name: logs
```

### Key Components Explained:
1. **BucketClaim**: Requests a bucket using the `linode-objectstorage` class.
2. **BucketAccess**: References the `BucketAccessClass` to generate credentials stored in a `s3-credentials` Secret.
3. **Volumes**: The `cosi-secret` volume mounts the credentials, while the `logs` volume is a temporary `emptyDir` for log storage.

## COSI vs. Manual Object Storage Management

### Without COSI:
- **Manual Steps**: Create buckets via provider UIs/CLIs, manage credentials, and hardcode them in manifests.
- **Risk**: Credentials exposed in code; no lifecycle management.

### With COSI:
- **Dynamic Provisioning**: Buckets and credentials created on-demand via Kubernetes API.
- **Automated Cleanup**: Set `deletionPolicy: Delete` to remove unused buckets.
- **Security**: Credentials injected via Secrets, never stored in plaintext.

## Conclusion

COSI brings the flexibility of Kubernetes-native resource management to object storage. By defining policies through `BucketClass` and `BucketAccessClass`, teams can streamline storage operations while enforcing security and lifecycle rules. The Linode driver example demonstrates how easily COSI integrates with cloud providers, but the same principles apply to AWS S3, Google Cloud Storage, and more.

Ready to try it? Deploy the sample app and watch COSI automate the heavy lifting! 🚀
