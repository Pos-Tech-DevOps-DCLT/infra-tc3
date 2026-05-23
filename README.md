# Tech Challenge 2 — Infrastructure Guide

This guide walks you through provisioning the AWS infrastructure and deploying the five microservices from scratch. No prior Terraform experience required.

---

## What gets created

| Resource | Details |
|---|---|
| EKS Cluster | Kubernetes 1.31, 2 nodes (auto-scales 1–6) |
| RDS PostgreSQL | 3 independent instances — auth, flag, targeting |
| ElastiCache Redis | 1 Redis node — used by evaluation-service |
| DynamoDB | 1 table (`analytics-events`) — used by analytics-service |
| SQS | 1 queue (`evaluation-events`) + Dead Letter Queue |
| ECR | 5 repositories — one per microservice |

---

## Part 1 — Install the tools

Install these on your machine before starting.

### Terraform

```bash
# Linux
wget -O terraform.zip https://releases.hashicorp.com/terraform/1.9.0/terraform_1.9.0_linux_amd64.zip
unzip terraform.zip
sudo mv terraform /usr/local/bin/
terraform -version
```

### AWS CLI

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
aws --version
```

### kubectl

```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client
```

### Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

### Docker

Follow the official guide for your OS: https://docs.docker.com/get-docker/

---

## Part 2 — Configure AWS credentials

Go to **AWS Console → IAM → Users → your user → Security credentials → Create access key**.

Then run:

```bash
aws configure
```

Enter your Access Key ID, Secret Access Key, region (`us-east-1`), and output format (`json`).

Verify it works:

```bash
aws sts get-caller-identity
```

You should see your account ID and user ARN.

> **Account requirement:** Creating 3 RDS instances requires a standard AWS account (not the free-plan which limits you to 1 instance). Add a payment method in the AWS Console to remove that restriction before proceeding.

---

## Part 3 — Provision the infrastructure

All commands below must be run from inside the `terraform/` folder.

```bash
cd terraform
```

### Step 1 — Initialize Terraform

Downloads all required providers and modules. Run this once (and again if you ever change module sources).

```bash
terraform init
```

### Step 2 — Preview what will be created

```bash
terraform plan -out=tfplan
```

This saves the plan to a file. Review the output — you should see roughly 60 resources being created. Nothing is created yet.

### Step 3 — Apply the plan

```bash
terraform apply tfplan
```

This will take **20–30 minutes**. The EKS cluster and RDS instances take the longest. Leave the terminal open until it finishes.

When it completes you will see a summary of all outputs (endpoints, ARNs, etc.).

### Step 4 — Connect kubectl to the cluster

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name $(terraform output -raw eks_cluster_name)
```

Verify the nodes are ready:

```bash
kubectl get nodes
```

You should see 2 nodes with status `Ready`.

### Step 5 — Install Helm charts

Metrics Server, Nginx Ingress, and KEDA are installed via a script (not Terraform) to avoid provider timeout issues.

```bash
# Still inside the terraform/ folder:
KEDA_ROLE_ARN=$(terraform output -raw irsa_keda_role_arn)

# Go back to the project root and run the script:
cd ..
./scripts/helm-install.sh "$KEDA_ROLE_ARN"
```

The script adds the Helm repos, installs all three charts, and prints the load balancer hostname at the end. It takes about 3–5 minutes.

---

## Part 4 — Collect the connection strings

Run these commands inside the `terraform/` folder to retrieve all the values you will need for the Kubernetes manifests.

```bash
# Everything in one command (copy this output and save it)
terraform output -json connection_strings
```

To get individual values:

```bash
# ECR image URLs (one per service)
terraform output ecr_repository_urls

# RDS endpoints (host addresses)
terraform output -json rds_endpoints

# SQS queue URL
terraform output sqs_queue_url

# DynamoDB table name
terraform output dynamodb_table_name

# IRSA role ARNs (needed for evaluation-service and analytics-service manifests)
terraform output irsa_evaluation_service_role_arn
terraform output irsa_analytics_service_role_arn
```

### Retrieve database passwords from Secrets Manager

Passwords are never stored in Terraform — they are in AWS Secrets Manager.

```bash
# auth-service database
aws secretsmanager get-secret-value \
  --secret-id tech-challenge-prod/rds/auth \
  --query SecretString --output text | jq .

# flag-service database
aws secretsmanager get-secret-value \
  --secret-id tech-challenge-prod/rds/flag \
  --query SecretString --output text | jq .

# targeting-service database
aws secretsmanager get-secret-value \
  --secret-id tech-challenge-prod/rds/targeting \
  --query SecretString --output text | jq .

# Redis auth token and endpoint (evaluation-service)
aws secretsmanager get-secret-value \
  --secret-id tech-challenge-prod/elasticache/redis \
  --query SecretString --output text | jq .
```

Each command returns a JSON object with `host`, `port`, `username`, `password`, and `dbname`.

---

## Part 5 — Build and push Docker images

Run from the **project root** (not the `terraform/` folder).

```bash
# Get your AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Log in to ECR
aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin \
    $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# Build each service image
docker build -t auth-service:latest       ./auth-service
docker build -t flag-service:latest       ./flag-service
docker build -t targeting-service:latest  ./targeting-service
docker build -t evaluation-service:latest ./evaluation-service
docker build -t analytics-service:latest  ./analytics-service

# Push using the helper script
./scripts/publish-images.sh us-east-1 $AWS_ACCOUNT_ID latest
```

---

## Part 6 — Deploy to Kubernetes

### Step 1 — Fill in the placeholder values in the manifests

The files under `k8s/` contain placeholders that must be replaced with real values from the previous steps.

| Placeholder | How to get the value |
|---|---|
| `<ECR_URL>` | `terraform output -json ecr_repository_urls \| jq -r '.["auth-service"]'` (change service name as needed) |
| `<IRSA_ROLE_ARN>` in `evaluation-service/deployment.yaml` | `terraform output irsa_evaluation_service_role_arn` |
| `<IRSA_ROLE_ARN>` in `analytics-service/deployment.yaml` | `terraform output irsa_analytics_service_role_arn` |
| `<BASE64_DB_HOST>` | `echo -n "<host from Secrets Manager>" \| base64` |
| `<BASE64_DB_PASSWORD>` | `echo -n "<password from Secrets Manager>" \| base64` |
| `<BASE64_REDIS_HOST>` | `echo -n "<host from Secrets Manager>" \| base64` |
| `<BASE64_REDIS_AUTH_TOKEN>` | `echo -n "<auth_token from Secrets Manager>" \| base64` |
| `<BASE64_SQS_QUEUE_URL>` | `echo -n "$(terraform output -raw sqs_queue_url)" \| base64` |
| `<SQS_QUEUE_URL>` in `scaledobject.yaml` | `terraform output -raw sqs_queue_url` |

### Step 2 — Apply all manifests

```bash
# From the project root
./scripts/k8s-apply.sh
```

Or manually, in this order:

```bash
kubectl apply -f k8s/namespaces.yaml
kubectl apply -f k8s/auth-service/
kubectl apply -f k8s/flag-service/
kubectl apply -f k8s/targeting-service/
kubectl apply -f k8s/evaluation-service/
kubectl apply -f k8s/analytics-service/
kubectl apply -f k8s/ingress.yaml
```

### Step 3 — Get the public URL

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

The `EXTERNAL-IP` column shows the load balancer hostname. It may take 2–3 minutes to appear.

| Path | Service |
|---|---|
| `<EXTERNAL-IP>/auth/` | auth-service |
| `<EXTERNAL-IP>/flags/` | flag-service |
| `<EXTERNAL-IP>/targeting/` | targeting-service |
| `<EXTERNAL-IP>/evaluate/` | evaluation-service |
| `<EXTERNAL-IP>/analytics/` | analytics-service |

---

## Tear down

To delete all resources and stop incurring costs:

```bash
cd terraform
terraform plan -destroy -out=tfplan-destroy
terraform apply tfplan-destroy
```

> This permanently deletes all databases and their data. There are no automatic backups.
