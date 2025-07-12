# 🕐 Get DateTime - API de Data Atual

## 📋 Descrição do Projeto

Este projeto implementa uma API REST simples que retorna a data e hora atual do sistema. A arquitetura utiliza **AWS Lambda** para processamento e **API Gateway** para exposição HTTP, rodando localmente no **LocalStack** para desenvolvimento.

## 🏗️ Arquitetura

```
Cliente HTTP
    ↓
API Gateway (GET /data)
    ↓
AWS Lambda (Python 3.9)
    ↓
Resposta JSON com data/hora
```

### Componentes Principais

1. **AWS Lambda Function** (`data-atual-function`)
   - Runtime: Python 3.9
   - Timeout: 30 segundos
   - Função: Retorna data atual formatada

2. **API Gateway** (`data-atual-api`)
   - Endpoint: `GET /data`
   - Integração: AWS_PROXY com Lambda
   - Stage: `prod`

3. **IAM Role** (`lambda-data-atual-role`)
   - Permissões básicas de execução Lambda
   - Política: `AWSLambdaBasicExecutionRole`

## 🔧 Pré-requisitos

### Ferramentas Necessárias

```bash
# Terraform
terraform --version  # >= 1.0

# AWS CLI
aws --version

# LocalStack
docker --version
pip install localstack
```

### Configuração do LocalStack

```bash
# Iniciar LocalStack
localstack start

# Ou usando Docker
docker run --rm -it -p 4566:4566 -p 4510-4559:4510-4559 localstack/localstack
```

## 🚀 Como Executar

### Passo 1: Preparar o Ambiente

```bash
# Navegar para o diretório do projeto
cd get_datetime

# Verificar se LocalStack está rodando
curl http://localhost:4566/_localstack/health
```

### Passo 2: Inicializar o Terraform

```bash
# Inicializar o Terraform
terraform init

# Validar a configuração
terraform validate

# Ver o plano de execução
terraform plan
```

### Passo 3: Aplicar a Infraestrutura

```bash
# Aplicar as mudanças
terraform apply

# Ou aplicar automaticamente
terraform apply -auto-approve
```

### Passo 4: Obter a URL da API

```bash
# Visualizar os outputs
terraform output

# Exemplo de saída:
# api_gateway_url = "https://abc123.execute-api.us-east-1.amazonaws.com/prod/data"
# lambda_function_name = "data-atual-function"
# api_gateway_id = "abc123"
```

## 🧪 Testando a API

### Teste 1: Chamada Direta via Lambda

```bash
# Testar a função Lambda diretamente
aws --endpoint-url=http://localhost:4566 --region us-east-1 \
    lambda invoke \
    --function-name data-atual-function \
    response.json

# Visualizar resposta
cat response.json
```

### Teste 2: Chamada via API Gateway

```bash
# Usando curl (substitua a URL pelo output do terraform)
curl -X GET "http://localhost:4566/restapis/[API_ID]/prod/_user_request_/data"

# Exemplo de resposta esperada
{
  "message": "Data atual do sistema",
  "data": "12/07/2025 14:30:25",
  "timestamp": "2025-07-12T14:30:25.123456"
}
```

### Teste 3: Usando Postman/Insomnia

1. **Método**: GET
2. **URL**: `http://localhost:4566/restapis/[API_ID]/prod/_user_request_/data`
3. **Headers**: `Content-Type: application/json`

## 📁 Estrutura de Arquivos

```
get_datetime/
├── main.tf                 # Configuração principal do Terraform
├── terraform.tfstate       # Estado atual do Terraform
├── terraform.tfstate.backup # Backup do estado
├── lambda_function.zip     # Código da Lambda (gerado automaticamente)
├── .terraform.lock.hcl     # Lock file do Terraform
├── .terraform/             # Diretório de cache do Terraform
└── README.md              # Este arquivo
```

## 🔍 Detalhes Técnicos

### Código da Função Lambda

```python
import json
import datetime

def lambda_handler(event, context):
    """
    Função Lambda que retorna a data atual do sistema
    """
    try:
        # Obtém a data atual
        data_atual = datetime.datetime.now()
        
        # Formata a data em formato brasileiro
        data_formatada = data_atual.strftime("%d/%m/%Y %H:%M:%S")
        
        # Retorna a resposta em formato JSON
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': 'Data atual do sistema',
                'data': data_formatada,
                'timestamp': data_atual.isoformat()
            }, ensure_ascii=False)
        }
    except Exception as e:
        # Tratamento de erro
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Erro interno do servidor',
                'message': str(e)
            }, ensure_ascii=False)
        }
```

### Configurações do LocalStack

```hcl
# Provider AWS configurado para LocalStack
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  
  endpoints {
    lambda     = "http://localhost:4566"
    apigateway = "http://localhost:4566"
    iam        = "http://localhost:4566"
    sts        = "http://localhost:4566"
  }
}
```

## 🔧 Comandos Úteis

### Verificar Status

```bash
# Status do LocalStack
curl http://localhost:4566/_localstack/health

# Listar funções Lambda
aws --endpoint-url=http://localhost:4566 --region us-east-1 lambda list-functions

# Listar APIs Gateway
aws --endpoint-url=http://localhost:4566 --region us-east-1 apigateway get-rest-apis
```

### Logs e Debug

```bash
# Invocar Lambda com logs
aws --endpoint-url=http://localhost:4566 --region us-east-1 \
    lambda invoke \
    --function-name data-atual-function \
    --log-type Tail \
    response.json

# Decodificar logs (se necessário)
echo "[LOG_BASE64]" | base64 -d
```

### Monitoramento

```bash
# Verificar recursos no Terraform
terraform show

# Listar state
terraform state list

# Mostrar recurso específico
terraform state show aws_lambda_function.data_atual_lambda
```

## 🧹 Limpeza

### Destruir Recursos

```bash
# Destruir toda a infraestrutura
terraform destroy

# Ou destruir automaticamente
terraform destroy -auto-approve
```

### Limpar Arquivos

```bash
# Remover arquivos gerados
rm -f lambda_function.zip
rm -f response.json
rm -f terraform.tfstate*
rm -rf .terraform/
```

## ⚠️ Troubleshooting

### Problemas Comuns

#### 1. LocalStack não está rodando
```bash
# Erro: connection refused
# Solução: Verificar se LocalStack está ativo
curl http://localhost:4566/_localstack/health
```

#### 2. Terraform não encontra resources
```bash
# Erro: no resources found
# Solução: Verificar endpoints no provider
terraform validate
```

#### 3. API Gateway retorna erro 502
```bash
# Erro: Bad Gateway
# Solução: Verificar permissões da Lambda
aws --endpoint-url=http://localhost:4566 --region us-east-1 \
    lambda get-policy --function-name data-atual-function
```

#### 4. Lambda não executa
```bash
# Erro: function not found
# Solução: Verificar se função foi criada
aws --endpoint-url=http://localhost:4566 --region us-east-1 \
    lambda get-function --function-name data-atual-function
```

## 📚 Próximos Passos

### Melhorias Possíveis

1. **Adicionar CORS**: Configurar headers CORS no API Gateway
2. **Validação de Input**: Adicionar validação de parâmetros de entrada
3. **Diferentes Formatos**: Permitir diferentes formatos de data
4. **Timezone**: Adicionar suporte a fusos horários
5. **Logs Estruturados**: Implementar logging estruturado
6. **Métricas**: Adicionar CloudWatch metrics
7. **Autenticação**: Implementar autenticação API Key

### Exemplos de Uso

```bash
# Adicionar parâmetros de query (futuro)
curl "http://localhost:4566/restapis/[API_ID]/prod/_user_request_/data?format=iso"

# Suporte a timezone (futuro)
curl "http://localhost:4566/restapis/[API_ID]/prod/_user_request_/data?tz=America/Sao_Paulo"
```

## 📄 Licença

Este projeto é para fins educacionais e demonstrativos.

## 🤝 Contribuição

Sinta-se à vontade para contribuir com melhorias e correções!

---

**Autor**: Projeto de estudo Terraform + AWS + LocalStack  
**Data**: Dezembro 2024  
**Versão**: 1.0.0 