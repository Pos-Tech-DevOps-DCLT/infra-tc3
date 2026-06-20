# Manual Completo — ToggleMaster Fase 2
> Deploy de microsserviços no EKS com HPA, KEDA, RDS, Redis, DynamoDB e SQS  
> Conta pessoal AWS — Região `us-east-1`

---

## Índice

1. [Pré-requisitos](#1-pré-requisitos)
2. [Clonar o repositório](#2-clonar-o-repositório)
3. [Baixar imagens Docker da conta origem](#3-baixar-imagens-docker-da-conta-origem)
4. [Configurar credenciais AWS](#4-configurar-credenciais-aws)
5. [Criar repositórios ECR e subir imagens](#5-criar-repositórios-ecr-e-subir-imagens)
6. [Provisionar infraestrutura com Terraform](#6-provisionar-infraestrutura-com-terraform)
7. [Conectar kubectl ao cluster EKS](#7-conectar-kubectl-ao-cluster-eks)
8. [Instalar Metrics Server, Nginx Ingress e KEDA](#8-instalar-metrics-server-nginx-ingress-e-keda)
9. [Atualizar Account ID nos manifests](#9-atualizar-account-id-nos-manifests)
10. [Preencher secrets e configmaps](#10-preencher-secrets-e-configmaps)
11. [Criar tabelas nos bancos de dados](#11-criar-tabelas-nos-bancos-de-dados)
12. [Aplicar manifests Kubernetes](#12-aplicar-manifests-kubernetes)
13. [Configurar HPA e KEDA ScaledObjects](#13-configurar-hpa-e-keda-scaledobjects)
14. [Criar API key, flag e regra de targeting](#14-criar-api-key-flag-e-regra-de-targeting)
15. [Testes de carga e escalabilidade](#15-testes-de-carga-e-escalabilidade)
16. [Verificar DynamoDB](#16-verificar-dynamodb)
17. [Destruir infraestrutura](#17-destruir-infraestrutura)
18. [Problemas conhecidos e upgrades necessários](#18-problemas-conhecidos-e-upgrades-necessários)

---

## 1. Pré-requisitos

Instalar todas as ferramentas necessárias:

```bash
# Terraform
wget -O terraform.zip https://releases.hashicorp.com/terraform/1.9.0/terraform_1.9.0_linux_amd64.zip
unzip terraform.zip && sudo mv terraform /usr/local/bin/
terraform -version

# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip && sudo ./aws/install
aws --version

# kubectl
snap install kubectl --classic
kubectl version --client

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version

# hey (teste de carga)
sudo apt-get install -y golang-go
go install github.com/rakyll/hey@latest
export PATH=$PATH:$(go env GOPATH)/bin

# ab (Apache Benchmark)
sudo apt-get install -y apache2-utils

# psql (cliente PostgreSQL)
sudo apt-get install -y postgresql-client

# jq
sudo apt-get install -y jq
```

---

## 2. Clonar o repositório

```bash
git clone <URL_DO_REPOSITORIO>
cd infra_techchallenge_2
```

---

## 3. Baixar imagens Docker da conta origem

> Só necessário se as imagens vierem de outra conta AWS. Pule esta etapa se já tiver as imagens localmente.

**No CloudShell da conta ORIGEM:**

```bash
# Autenticar no ECR origem
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 375546530898.dkr.ecr.us-east-1.amazonaws.com

# Pull das 5 imagens
docker pull 375546530898.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/analytics-service
docker pull 375546530898.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/auth-service
docker pull 375546530898.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/evaluation-service
docker pull 375546530898.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/flag-service
docker pull 375546530898.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/targeting-service

# Exportar como .tar
docker save 375546530898.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/analytics-service   -o analytics-service.tar
docker save 375546530898.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/auth-service         -o auth-service.tar
docker save 375546530898.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/evaluation-service   -o evaluation-service.tar
docker save 375546530898.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/flag-service         -o flag-service.tar
docker save 375546530898.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/targeting-service    -o targeting-service.tar
```

Baixar cada `.tar` via **Actions → Download file** no CloudShell:
```
/home/cloudshell-user/analytics-service.tar
/home/cloudshell-user/auth-service.tar
/home/cloudshell-user/evaluation-service.tar
/home/cloudshell-user/flag-service.tar
/home/cloudshell-user/targeting-service.tar
```

> ⚠️ O CloudShell tem limite de 1GB. Delete cada `.tar` após o download: `rm analytics-service.tar`

---

## 4. Configurar credenciais AWS

```bash
# Criar perfil para a conta destino
aws configure --profile pessoal_ezequiel
# Preencher: Access Key ID, Secret Access Key, região us-east-1, formato json

# Verificar conta
aws sts get-caller-identity --profile pessoal_ezequiel

# Exportar como padrão da sessão
export AWS_PROFILE=pessoal_ezequiel
```

---

## 5. Criar repositórios ECR e subir imagens

```bash
# Criar repositórios
aws ecr create-repository --repository-name tech-challenge-prod/analytics-service --region us-east-1 --profile pessoal_ezequiel
aws ecr create-repository --repository-name tech-challenge-prod/auth-service --region us-east-1 --profile pessoal_ezequiel
aws ecr create-repository --repository-name tech-challenge-prod/evaluation-service --region us-east-1 --profile pessoal_ezequiel
aws ecr create-repository --repository-name tech-challenge-prod/flag-service --region us-east-1 --profile pessoal_ezequiel
aws ecr create-repository --repository-name tech-challenge-prod/targeting-service --region us-east-1 --profile pessoal_ezequiel

# Autenticar no ECR destino
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com

# Carregar imagens
docker load -i analytics-service.tar
docker load -i auth-service.tar
docker load -i evaluation-service.tar
docker load -i flag-service.tar
docker load -i targeting-service.tar

# Retag e push
docker tag 375546530898.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/analytics-service $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/analytics-service
docker tag 375546530898.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/auth-service $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/auth-service
docker tag 375546530898.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/evaluation-service $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/evaluation-service
docker tag 375546530898.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/flag-service $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/flag-service
docker tag 375546530898.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/targeting-service $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/targeting-service

docker push $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/analytics-service
docker push $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/auth-service
docker push $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/evaluation-service
docker push $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/flag-service
docker push $AWS_ACCOUNT_ID.dkr.ecr.us-east-1.amazonaws.com/tech-challenge-prod/targeting-service
```

---

## 6. Provisionar infraestrutura com Terraform

### 6.1 ECR via Terraform

```bash
cd terraform/ecr
terraform init

# Importar repositórios já existentes
terraform import 'module.ecr.aws_ecr_repository.repos["analytics-service"]' tech-challenge-prod/analytics-service
terraform import 'module.ecr.aws_ecr_repository.repos["auth-service"]' tech-challenge-prod/auth-service
terraform import 'module.ecr.aws_ecr_repository.repos["evaluation-service"]' tech-challenge-prod/evaluation-service
terraform import 'module.ecr.aws_ecr_repository.repos["flag-service"]' tech-challenge-prod/flag-service
terraform import 'module.ecr.aws_ecr_repository.repos["targeting-service"]' tech-challenge-prod/targeting-service

terraform apply -auto-approve
```

### 6.2 Infraestrutura principal

> ⚠️ Verificar `terraform.tfvars` antes de aplicar. Pontos de atenção:
> - `rds_engine_version = "15.13"` (não 15.8)
> - `eks_node_instance_types = ["t3.medium"]`
> - `eks_node_desired_size = 2`
> - `eks_node_min_size = 1`
> - `eks_node_max_size = 6`

```bash
cd ../  # volta para terraform/
terraform init

# Criar arquivo de imports para os repositórios ECR
cat > imports.tf << 'EOF'
import {
  to = module.ecr.aws_ecr_repository.repos["analytics-service"]
  id = "tech-challenge-prod/analytics-service"
}
import {
  to = module.ecr.aws_ecr_repository.repos["auth-service"]
  id = "tech-challenge-prod/auth-service"
}
import {
  to = module.ecr.aws_ecr_repository.repos["evaluation-service"]
  id = "tech-challenge-prod/evaluation-service"
}
import {
  to = module.ecr.aws_ecr_repository.repos["flag-service"]
  id = "tech-challenge-prod/flag-service"
}
import {
  to = module.ecr.aws_ecr_repository.repos["targeting-service"]
  id = "tech-challenge-prod/targeting-service"
}
EOF

terraform apply -auto-approve
```

> ⏱️ Leva 20-30 minutos. Cria: EKS, 3 RDS, Redis, DynamoDB, SQS, VPC, NAT Gateways, IAM roles.

### 6.3 Anotar outputs importantes

```bash
terraform output -raw irsa_evaluation_service_role_arn
terraform output -raw irsa_analytics_service_role_arn
terraform output -raw sqs_queue_url
terraform output -raw irsa_keda_role_arn
terraform output -raw eks_cluster_name

aws secretsmanager get-secret-value --secret-id tech-challenge-prod/rds/auth --query SecretString --output text | jq .
aws secretsmanager get-secret-value --secret-id tech-challenge-prod/rds/flag --query SecretString --output text | jq .
aws secretsmanager get-secret-value --secret-id tech-challenge-prod/rds/targeting --query SecretString --output text | jq .
aws secretsmanager get-secret-value --secret-id tech-challenge-prod/elasticache/redis --query SecretString --output text | jq .
```

---

## 7. Conectar kubectl ao cluster EKS

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name $(cd terraform && terraform output -raw eks_cluster_name)

# Verificar
kubectl get nodes
# Deve aparecer 2 nodes com status Ready
```

---

## 8. Instalar Metrics Server, Nginx Ingress e KEDA

```bash
cd ~/infra_techchallenge_2
KEDA_ROLE_ARN=$(cd terraform && terraform output -raw irsa_keda_role_arn)
chmod +x scripts/*.sh
./scripts/helm-install.sh "$KEDA_ROLE_ARN"
```

> ⏱️ Leva ~5 minutos. **Anote o hostname do Load Balancer** que aparece no final.

---

## 9. Atualizar Account ID nos manifests

```bash
cd ~/infra_techchallenge_2
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Substituir account ID antigo pelo novo em todos os arquivos k8s
grep -rl "375546530898" k8s/ | xargs sed -i "s/375546530898/$AWS_ACCOUNT_ID/g"

# Verificar que não sobrou nenhum ID antigo
grep -r "375546530898" k8s/
# Deve retornar vazio
```

---

## 10. Preencher secrets e configmaps

> Substitua os valores abaixo pelos obtidos no passo 6.3

```bash
cd ~/infra_techchallenge_2

# Preencher serviceaccounts
sed -i "s|<IRSA_EVALUATION_SERVICE_ROLE_ARN>|arn:aws:iam::$AWS_ACCOUNT_ID:role/tech-challenge-prod-evaluation-service|g" k8s/evaluation-service/serviceaccount.yaml
sed -i "s|<IRSA_ANALYTICS_SERVICE_ROLE_ARN>|arn:aws:iam::$AWS_ACCOUNT_ID:role/tech-challenge-prod-analytics-service|g" k8s/analytics-service/serviceaccount.yaml

# Preencher configmaps com account ID
sed -i "s|<AWS_ACCOUNT_ID>|$AWS_ACCOUNT_ID|g" k8s/analytics-service/configmap.yaml
sed -i "s|<AWS_ACCOUNT_ID>|$AWS_ACCOUNT_ID|g" k8s/evaluation-service/configmap.yaml

# auth-service secret (usar URL-encode na senha se tiver caracteres especiais)
python3 -c "
import base64, urllib.parse
senha = 'SENHA_RDS_AUTH'
senha_encoded = urllib.parse.quote(senha, safe='')
url = f'postgres://dbadmin:{senha_encoded}@ENDPOINT_RDS_AUTH:5432/authdb'
val = base64.b64encode(url.encode()).decode()
import re
content = open('k8s/auth-service/secret.yaml').read()
content = re.sub(r'DATABASE_URL:.*', f'DATABASE_URL: {val}', content)
open('k8s/auth-service/secret.yaml', 'w').write(content)
print('auth-service OK')
"

# flag-service secret
python3 -c "
import base64, urllib.parse
senha = 'SENHA_RDS_FLAG'
senha_encoded = urllib.parse.quote(senha, safe='')
url = f'postgres://dbadmin:{senha_encoded}@ENDPOINT_RDS_FLAG:5432/flagdb'
val = base64.b64encode(url.encode()).decode()
import re
content = open('k8s/flag-service/secret.yaml').read()
content = re.sub(r'DATABASE_URL:.*', f'DATABASE_URL: {val}', content)
open('k8s/flag-service/secret.yaml', 'w').write(content)
print('flag-service OK')
"

# targeting-service secret
python3 -c "
import base64, urllib.parse
senha = 'SENHA_RDS_TARGETING'
senha_encoded = urllib.parse.quote(senha, safe='')
url = f'postgres://dbadmin:{senha_encoded}@ENDPOINT_RDS_TARGETING:5432/targetingdb'
val = base64.b64encode(url.encode()).decode()
import re
content = open('k8s/targeting-service/secret.yaml').read()
content = re.sub(r'DATABASE_URL:.*', f'DATABASE_URL: {val}', content)
open('k8s/targeting-service/secret.yaml', 'w').write(content)
print('targeting-service OK')
"

# evaluation-service secret (Redis)
python3 -c "
import base64
token = 'AUTH_TOKEN_REDIS'
endpoint = 'ENDPOINT_REDIS_PRIMARY'
url = f'rediss://:{token}@{endpoint}:6379'
val = base64.b64encode(url.encode()).decode()
api_key = base64.b64encode(b'changeme-api-key').decode()
import re
content = open('k8s/evaluation-service/secret.yaml').read()
content = re.sub(r'REDIS_URL:.*', f'REDIS_URL: {val}', content)
content = re.sub(r'SERVICE_API_KEY:.*', f'SERVICE_API_KEY: {api_key}', content)
open('k8s/evaluation-service/secret.yaml', 'w').write(content)
print('evaluation-service OK')
"

# Verificar se sobrou algum placeholder
grep -r "<BASE64\|<AWS_ACCOUNT\|<IRSA" k8s/
```

---

## 11. Criar tabelas nos bancos de dados

> Os bancos RDS estão em subnet privada — rodar via pod temporário dentro do cluster.

```bash
# Criar pod temporário
kubectl run psql-temp --image=postgres:15 --restart=Never -- sleep 300
kubectl wait --for=condition=ready pod/psql-temp --timeout=60s

# auth-service — tabela api_keys
kubectl exec psql-temp -- env PGPASSWORD='SENHA_RDS_AUTH' psql \
  -h ENDPOINT_RDS_AUTH \
  -U dbadmin -d authdb \
  -c "CREATE TABLE IF NOT EXISTS api_keys (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    key_hash VARCHAR(64) NOT NULL UNIQUE,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  );"

# flag-service — tabela flags
kubectl exec psql-temp -- env PGPASSWORD='SENHA_RDS_FLAG' psql \
  -h ENDPOINT_RDS_FLAG \
  -U dbadmin -d flagdb \
  -c "CREATE TABLE IF NOT EXISTS flags (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    is_enabled BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  );"

# targeting-service — tabela targeting_rules
kubectl exec psql-temp -- env PGPASSWORD='SENHA_RDS_TARGETING' psql \
  -h ENDPOINT_RDS_TARGETING \
  -U dbadmin -d targetingdb \
  -c "CREATE TABLE IF NOT EXISTS targeting_rules (
    id SERIAL PRIMARY KEY,
    flag_name VARCHAR(100) UNIQUE NOT NULL,
    is_enabled BOOLEAN NOT NULL DEFAULT true,
    rules JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
  );"

# Limpar pod temporário
kubectl delete pod psql-temp
```

---

## 12. Aplicar manifests Kubernetes

```bash
cd ~/infra_techchallenge_2

# Aplicar namespaces, deployments, services, secrets, configmaps
./scripts/k8s-apply.sh

# Aplicar ingress
kubectl apply -f k8s/ingress.yaml

# Verificar pods
kubectl get pods -A | grep -v kube-system | grep -v ingress | grep -v keda
# Todos devem estar Running
```

---

## 13. Configurar HPA e KEDA ScaledObjects

```bash
# Deletar HPAs manuais (conflitam com KEDA)
kubectl delete hpa analytics-service-hpa -n analytics-service
kubectl delete hpa evaluation-service-hpa -n evaluation-service

# Aplicar ScaledObjects do KEDA
kubectl apply -f k8s/evaluation-service/scaledobject.yaml
kubectl apply -f k8s/analytics-service/scaledobject.yaml

# Verificar
kubectl get scaledobject -A
kubectl get hpa -A
# ScaledObjects devem estar READY: True
```

---

## 14. Criar API key, flag e regra de targeting

```bash
INGRESS="<HOSTNAME_DO_LOAD_BALANCER>"
BASE="http://$INGRESS"

# 1. Criar API key no auth-service
curl -s -X POST "$BASE/auth/admin/keys" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer changeme-master-key" \
  -d '{"name": "test-key"}'
# Anote o valor de "key" retornado — ex: tm_key_abc123...

API_KEY="tm_key_VALOR_RETORNADO"

# 2. Atualizar o secret do evaluation-service com a API key real
NEW_API_KEY=$(echo -n "$API_KEY" | base64 -w 0)
kubectl patch secret evaluation-service-secret -n evaluation-service \
  --type='json' \
  -p="[{\"op\": \"replace\", \"path\": \"/data/SERVICE_API_KEY\", \"value\": \"$NEW_API_KEY\"}]"
kubectl rollout restart deployment/evaluation-service -n evaluation-service
kubectl rollout status deployment/evaluation-service -n evaluation-service

# 3. Criar feature flag
curl -s -X POST "$BASE/flags/flags" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"name": "enable-new-dashboard", "description": "flag de teste", "is_enabled": true}'

# 4. Criar regra de targeting (50% dos usuários)
curl -s -X POST "$BASE/targeting/rules" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"flag_name": "enable-new-dashboard", "is_enabled": true, "rules": {"type": "PERCENTAGE", "value": 50}}'

# 5. Testar evaluate
curl -s "$BASE/evaluate/evaluate?user_id=user-123&flag_name=enable-new-dashboard"
# Deve retornar: {"flag_name":"enable-new-dashboard","user_id":"user-123","result":true}
```

---

## 15. Testes de carga e escalabilidade

### 15.1 Verificar estado inicial

```bash
kubectl get nodes
kubectl get pods -A | grep -v kube-system | grep -v ingress | grep -v keda
kubectl get hpa -A
kubectl get scaledobject -A
```

### 15.2 Abrir terminais de monitoramento

**Terminal 1 — Monitor contínuo:**
```bash
cd ~/infra_techchallenge_2
./scripts/monitor.sh 10
```

**Terminal 2 — Watch pods:**
```bash
watch -n 3 "kubectl get pods -n evaluation-service && echo '---' && kubectl get pods -n analytics-service"
```

### 15.3 Teste de carga no evaluation-service (HPA por CPU)

```bash
export PATH=$PATH:$(go env GOPATH)/bin
INGRESS="<HOSTNAME_DO_LOAD_BALANCER>"
hey -z 120s -c 100 "http://$INGRESS/evaluate/health"
```

> Aguarde ~2 minutos para o HPA reagir e escalar os pods.

### 15.4 Enviar mensagens manualmente no SQS

```bash
export AWS_PROFILE=pessoal_ezequiel
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

for i in $(seq 1 50); do
  aws sqs send-message \
    --queue-url "https://sqs.us-east-1.amazonaws.com/$AWS_ACCOUNT_ID/tech-challenge-prod-evaluation-events" \
    --message-body "{\"event_id\": \"manual-$i\", \"flag_name\": \"enable-new-dashboard\", \"user_id\": \"user-$i\", \"result\": true}" \
    --region us-east-1
  echo "Mensagem $i enviada"
done
```

### 15.5 Teste de carga real para escalar analytics via KEDA

**Terminal 3 — Carga 1:**
```bash
export AWS_PROFILE=pessoal_ezequiel
INGRESS="<HOSTNAME_DO_LOAD_BALANCER>"
BASE="http://$INGRESS"
END=$((SECONDS+300))
COUNT=0
while [ $SECONDS -lt $END ]; do
  for i in $(seq 1 50); do
    curl -s "$BASE/evaluate/evaluate?user_id=user-$RANDOM&flag_name=enable-new-dashboard" > /dev/null &
  done
  wait
  COUNT=$((COUNT+50))
  echo "[T1] $COUNT req - $(date '+%H:%M:%S')"
done
```

**Terminal 4 — Carga 2:**
```bash
export AWS_PROFILE=pessoal_ezequiel
INGRESS="<HOSTNAME_DO_LOAD_BALANCER>"
BASE="http://$INGRESS"
END=$((SECONDS+300))
COUNT=0
while [ $SECONDS -lt $END ]; do
  for i in $(seq 1 50); do
    curl -s "$BASE/evaluate/evaluate?user_id=user-$RANDOM&flag_name=enable-new-dashboard" > /dev/null &
  done
  wait
  COUNT=$((COUNT+50))
  echo "[T2] $COUNT req - $(date '+%H:%M:%S')"
done
```

> O KEDA detecta mensagens na fila e escala o analytics-service de 1 para até 5 pods automaticamente.

---

## 16. Verificar DynamoDB

```bash
export AWS_PROFILE=pessoal_ezequiel

# Contar itens
aws dynamodb scan \
  --table-name tech-challenge-prod-analytics-events \
  --select COUNT \
  --region us-east-1

# Ver 3 itens de exemplo
aws dynamodb scan \
  --table-name tech-challenge-prod-analytics-events \
  --max-items 3 \
  --region us-east-1
```

> ⚠️ O `ItemCount` do console AWS pode demorar horas para atualizar — use o `scan` para ver os dados reais.

---

## 17. Destruir infraestrutura

> ⚠️ Faça isso ao terminar os testes para não gerar custo (~$8-10/dia).

```bash
# 1. Remover Nginx Ingress primeiro (senão bloqueia destruição da VPC)
helm uninstall ingress-nginx -n ingress-nginx
kubectl delete namespace ingress-nginx --ignore-not-found
sleep 30

# 2. Destruir toda a infraestrutura
cd ~/infra_techchallenge_2/terraform
terraform destroy
```

---

## Referência rápida — Comandos úteis

```bash
# Ver todos os pods
kubectl get pods -A

# Ver logs de um serviço
kubectl logs -n evaluation-service -l app=evaluation-service --tail=50

# Ver HPA
kubectl get hpa -A

# Ver ScaledObjects KEDA
kubectl get scaledobject -A

# Forçar scale down
kubectl scale deployment analytics-service -n analytics-service --replicas=1
kubectl scale deployment evaluation-service -n evaluation-service --replicas=1

# Limpar fila SQS
aws sqs purge-queue \
  --queue-url "https://sqs.us-east-1.amazonaws.com/<ACCOUNT_ID>/tech-challenge-prod-evaluation-events" \
  --region us-east-1

# Ver nodes
kubectl get nodes

# Ver uso de recursos
kubectl top pods -n evaluation-service
kubectl top pods -n analytics-service
kubectl top nodes
```

---

## Valores de referência do projeto

| Recurso | Valor |
|---|---|
| Região AWS | `us-east-1` |
| Cluster EKS | `tech-challenge-prod-eks` |
| Node type | `t3.medium` |
| Nodes desejados | `2` |
| Nodes máximos | `6` |
| RDS engine | `postgres 15.13` |
| RDS instance | `db.t3.micro` |
| Redis node | `cache.t3.micro` |
| DynamoDB table | `tech-challenge-prod-analytics-events` |
| SQS queue | `tech-challenge-prod-evaluation-events` |
| KEDA cooldown | `60s` |
| KEDA polling | `15s` |
| KEDA threshold | `5 mensagens/pod` |
| HPA min replicas | `1` |
| HPA max replicas | `5` |

---

## Arquitetura dos data stores

| Store | Serviço | Por quê |
|---|---|---|
| **RDS PostgreSQL** | auth, flag, targeting | Dados estruturados, relacionais, consistência forte |
| **ElastiCache Redis** | evaluation | Cache de baixíssima latência, TTL curto, milhões de req/s |
| **DynamoDB** | analytics | Alto volume de escrita, NoSQL, escala automática, sem schema fixo |

---

*Manual gerado com base no deploy realizado em junho de 2026.*

---

## 18. Problemas conhecidos e upgrades necessários

Esta seção documenta os problemas encontrados durante o deploy e como resolvê-los. **Leia antes de começar** para evitar retrabalho.

---

### 18.1 Versão do PostgreSQL indisponível

**Problema:** O `terraform.tfvars` usa `rds_engine_version = "15.8"` mas essa versão não existe na AWS.

**Solução:** Antes de rodar o `terraform apply`, corrija o valor:

```bash
# Verificar versões disponíveis
aws rds describe-db-engine-versions \
  --engine postgres \
  --query 'DBEngineVersions[].EngineVersion' \
  --output table | grep "15\."

# Corrigir no tfvars
sed -i 's/rds_engine_version = "15.8"/rds_engine_version = "15.13"/' terraform/terraform.tfvars
```

---

### 18.2 Node t3.micro — Too many pods

**Problema:** O `terraform.tfvars` define `eks_node_instance_types = ["t3.micro"]` mas o t3.micro suporta apenas 4 pods no EKS. Os pods do sistema (coredns, vpc-cni, kube-proxy) já ocupam todos os slots.

**Solução:** Antes de rodar o `terraform apply`, corrija para `t3.medium`:

```bash
sed -i 's/eks_node_instance_types = \["t3.micro"\]/eks_node_instance_types = ["t3.medium"]/' terraform/terraform.tfvars
```

---

### 18.3 Node t3.small — também insuficiente

**Problema:** O t3.small suporta 11 pods mas com 5 microsserviços + sistema + KEDA + ingress fica no limite, especialmente durante o escalonamento.

**Solução:** Use diretamente `t3.medium` (passo 18.2 já resolve isso).

---

### 18.4 Nodes insuficientes para escalonamento

**Problema:** Com apenas 1 node `t3.medium`, ao tentar escalar para 5 pods de evaluation + 5 de analytics simultaneamente, os pods extras ficam `Pending` por falta de recursos.

**Solução:** Usar 2 nodes. Corrija o `terraform.tfvars` **antes** do apply:

```bash
sed -i 's/eks_node_desired_size   = 1/eks_node_desired_size   = 2/' terraform/terraform.tfvars
```

Se já aplicou com 1 node, force a recriação do node group:

```bash
cd terraform
terraform taint 'module.eks.aws_eks_node_group.main'
terraform apply -auto-approve
```

---

### 18.5 Conflito HPA manual vs KEDA

**Problema:** O script `k8s-apply.sh` aplica os `hpa.yaml` manuais E os `scaledobject.yaml` do KEDA para os mesmos deployments. Isso gera erro:

```
admission webhook "vscaledobject.kb.io" denied the request: the workload is already managed by the hpa
```

E o HPA fica com status `AmbiguousSelector` — nenhum dos dois funciona corretamente.

**Solução:** Após aplicar os manifests, deletar os HPAs manuais e manter apenas o KEDA:

```bash
kubectl delete hpa analytics-service-hpa -n analytics-service
kubectl delete hpa evaluation-service-hpa -n evaluation-service

kubectl apply -f k8s/evaluation-service/scaledobject.yaml
kubectl apply -f k8s/analytics-service/scaledobject.yaml
```

---

### 18.6 Migrations dos bancos não rodam automaticamente

**Problema:** Os microsserviços não criam as tabelas automaticamente ao subir. O auth-service loga `relation "api_keys" does not exist` e fica em CrashLoopBackOff.

**Solução:** Criar as tabelas manualmente via pod temporário (ver seção 11).

> ⚠️ Os bancos RDS estão em subnet privada — não é possível conectar diretamente do seu computador. Use o pod temporário dentro do cluster.

---

### 18.7 Senhas com caracteres especiais na connection string

**Problema:** Senhas geradas pelo Terraform podem conter caracteres como `+`, `[`, `(`, `<`, `!`, `>` que quebram a URL de conexão PostgreSQL.

**Solução:** Sempre usar URL-encode na senha ao montar a connection string:

```bash
python3 -c "
import base64, urllib.parse, re
senha = 'SUA_SENHA_AQUI'
senha_encoded = urllib.parse.quote(senha, safe='')
url = f'postgres://dbadmin:{senha_encoded}@ENDPOINT:5432/DBNAME'
val = base64.b64encode(url.encode()).decode()
content = open('k8s/auth-service/secret.yaml').read()
content = re.sub(r'DATABASE_URL:.*', f'DATABASE_URL: {val}', content)
open('k8s/auth-service/secret.yaml', 'w').write(content)
print('OK:', val[:40], '...')
"
```

---

### 18.8 SERVICE_API_KEY desatualizada no evaluation-service

**Problema:** O secret `evaluation-service-secret` é criado com `SERVICE_API_KEY: changeme-api-key` (placeholder). O evaluation-service usa essa chave para se autenticar no flag-service e targeting-service. Com a chave errada, retorna `flag-service retornou status 401`.

**Solução:** Após criar a API key real no auth-service (seção 14), atualizar o secret:

```bash
API_KEY="tm_key_VALOR_REAL"
NEW_API_KEY=$(echo -n "$API_KEY" | base64 -w 0)
kubectl patch secret evaluation-service-secret -n evaluation-service \
  --type='json' \
  -p="[{\"op\": \"replace\", \"path\": \"/data/SERVICE_API_KEY\", \"value\": \"$NEW_API_KEY\"}]"
kubectl rollout restart deployment/evaluation-service -n evaluation-service
kubectl rollout status deployment/evaluation-service -n evaluation-service
```

---

### 18.9 `hey` não encontrado no PATH

**Problema:** Após instalar o `hey` com `go install`, ele não está no PATH em novos terminais.

**Solução:** Exportar o PATH antes de usar:

```bash
export PATH=$PATH:$(go env GOPATH)/bin
```

Ou adicionar permanentemente ao `~/.bashrc`:

```bash
echo 'export PATH=$PATH:$(go env GOPATH)/bin' >> ~/.bashrc
source ~/.bashrc
```

---

### 18.10 AWS_PROFILE não definido em novos terminais

**Problema:** O `export AWS_PROFILE=pessoal_ezequiel` precisa ser feito em cada novo terminal aberto.

**Solução:** Exportar em cada terminal antes de rodar comandos AWS:

```bash
export AWS_PROFILE=pessoal_ezequiel
```

Ou adicionar permanentemente ao `~/.bashrc`:

```bash
echo 'export AWS_PROFILE=pessoal_ezequiel' >> ~/.bashrc
source ~/.bashrc
```

---

### 18.11 Scripts sem permissão de execução

**Problema:** Os scripts em `scripts/` não têm permissão de execução após o clone.

**Solução:**

```bash
chmod +x scripts/*.sh
```

---

### 18.12 Resumo — tfvars corretos antes do apply

Para evitar todos os problemas acima, o `terraform/terraform.tfvars` deve ter estes valores antes do primeiro `terraform apply`:

```hcl
eks_node_instance_types = ["t3.medium"]
eks_node_desired_size   = 2
eks_node_min_size       = 1
eks_node_max_size       = 6
rds_engine_version      = "15.13"
```
