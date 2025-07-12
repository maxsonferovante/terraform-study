# Sistema de Permutações - Guia de Teste

## Visão Geral

Sistema completo de processamento de permutações de palavras usando AWS Lambda, SQS, S3 e API Gateway, executando no LocalStack.

## Funcionalidades

### 1. Validação e Processamento (POST)
- Recebe uma palavra de 4 letras
- Valida se a palavra atende os critérios
- Envia para processamento assíncrono via SQS
- Gera todas as permutações possíveis
- Salva no S3 para consulta posterior

### 2. Consulta de Permutações (GET)
- Consulta permutações já processadas
- Retorna lista completa de combinações
- Inclui total de permutações encontradas

## Testes Realizados

### Teste 1: Envio de Palavra
```bash
# Comando usado para testar
aws --endpoint-url=http://localhost:4566 --region us-east-1 lambda invoke \
  --function-name palavras-validadora \
  --payload '{"httpMethod": "POST", "body": "{\"palavra\": \"casa\"}"}' \
  response.json

# Resposta obtida
{
  "statusCode": 200,
  "message": "Palavra válida recebida e enviada para processamento",
  "palavra": "casa",
  "status": "processando"
}
```

### Teste 2: Consulta de Permutações
```bash
# Comando usado para consultar
aws --endpoint-url=http://localhost:4566 --region us-east-1 lambda invoke \
  --function-name palavras-validadora \
  --payload '{"httpMethod": "GET", "pathParameters": {"palavra": "casa"}}' \
  response_get.json

# Resposta obtida
{
  "statusCode": 200,
  "palavra": "casa",
  "permutacoes": [
    "aacs", "aasc", "acas", "acsa", "asac", "asca", 
    "caas", "casa", "csaa", "saac", "saca", "scaa"
  ],
  "total": 12
}
```

## Arquitetura do Sistema

### Componentes Principais

1. **Lambda Validadora** (`palavras-validadora`)
   - Recebe requisições POST/GET
   - Valida palavras de 4 letras
   - Envia para SQS (POST) ou consulta S3 (GET)

2. **Lambda Processadora** (`palavras-processadora`)
   - Consome mensagens do SQS
   - Gera permutações usando Python itertools
   - Salva resultados no S3

3. **Fila SQS** (`palavras-validas-queue`)
   - Armazena palavras válidas para processamento
   - Configurada com long polling (10s)

4. **Bucket S3** (`permutacoes-palavras-bucket`)
   - Armazena permutações em formato JSON
   - Estrutura: `permutacoes/{palavra}.json`

5. **API Gateway** (REST API)
   - Endpoint POST: `/palavra`
   - Endpoint GET: `/palavra/{palavra}`

### Fluxo de Dados

```
POST /palavra
    ↓
Lambda Validadora
    ↓
SQS Queue
    ↓
Lambda Processadora
    ↓
S3 Bucket
    ↑
Lambda Validadora
    ↑
GET /palavra/{palavra}
```

## Configurações Especiais para LocalStack

### 1. Provider AWS
```hcl
# Configuração essencial para S3 funcionar no LocalStack
s3_use_path_style = true
```

### 2. Clientes boto3 nas Lambdas
```python
# Dentro das funções Lambda, não especificar endpoint
# O LocalStack gerencia automaticamente
sqs_client = boto3.client('sqs', region_name='us-east-1')
s3_client = boto3.client('s3', region_name='us-east-1')
```

## Problemas Resolvidos

### 1. Erro de DNS no S3
**Problema**: `dial tcp: lookup permutacoes-palavras-bucket.localhost`
**Solução**: Adicionar `s3_use_path_style = true` no provider AWS

### 2. Erro de Conexão na Lambda
**Problema**: `Could not connect to the endpoint URL: "http://localhost:4566/"`
**Solução**: Remover endpoint_url dos clientes boto3 dentro das Lambdas

### 3. Bucket já existe
**Problema**: `BucketAlreadyExists`
**Solução**: Remover bucket existente antes de recriar

## Próximos Passos

1. **Testes com API Gateway**: Testar endpoints HTTP diretamente
2. **Validação de Entrada**: Adicionar mais validações
3. **Error Handling**: Melhorar tratamento de erros
4. **Monitoring**: Adicionar métricas e logs
5. **Performance**: Otimizar tempos de resposta

## Comandos Úteis

```bash
# Verificar saúde do LocalStack
curl -s http://localhost:4566/_localstack/health

# Listar buckets S3
aws --endpoint-url=http://localhost:4566 s3 ls

# Verificar fila SQS
aws --endpoint-url=http://localhost:4566 --region us-east-1 sqs get-queue-attributes --queue-url http://localhost:4566/000000000000/palavras-validas-queue --attribute-names All

# Aplicar mudanças no Terraform
terraform apply -auto-approve

# Destruir recursos
terraform destroy -auto-approve
```



curl -X POST http://localhost:4566/restapis/hug7i1twr1/prod/_user_request_/palavra -H "Content-Type: application/json" -d '{"palavra": "casa"}'


aws --endpoint-url=http://localhost:4566 --region us-east-1 lambda invoke --function-name palavras-validadora --payload '{"httpMethod": "POST", "body": "{\"palavra\": \"casa\"}"}' response.json


aws --endpoint-url=http://localhost:4566 --region us-east-1 lambda invoke --function-name palavras-validadora --payload '{"httpMethod": "GET", "pathParameters": {"palavra": "casa"}}' response_get.json


aws --endpoint-url=http://localhost:4566 --region us-east-1 s3 cp s3://permutacoes-palavras-bucket/permutacoes/casa.json - | head -20