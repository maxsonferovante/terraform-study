# Configuração do provider AWS para sistema de permutações
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Provider AWS - configuração para LocalStack
provider "aws" {
  region                      = "us-east-1"
  
  # Credenciais fake para LocalStack
  access_key                  = "test"
  secret_key                  = "test"
  
  # Configurações específicas do LocalStack
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  
  # Forçar uso de path-style URLs para S3 (necessário para LocalStack)
  s3_use_path_style           = true
  
  # Endpoints customizados do LocalStack
  endpoints {
    lambda     = "http://localhost:4566"
    apigateway = "http://localhost:4566"
    iam        = "http://localhost:4566"
    sts        = "http://localhost:4566"
    sqs        = "http://localhost:4566"
    s3         = "http://localhost:4566"
  }

  # Alias para diferenciação
  alias = "permutacoes"
}

# Bucket S3 para armazenar permutações
resource "aws_s3_bucket" "permutacoes_bucket" {
  provider = aws.permutacoes
  bucket   = "permutacoes-palavras-bucket"
  
  # Configuração para LocalStack
  force_destroy = true
}

# Configuração de versionamento do bucket
resource "aws_s3_bucket_versioning" "permutacoes_versioning" {
  provider = aws.permutacoes
  bucket   = aws_s3_bucket.permutacoes_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Fila SQS para palavras válidas
resource "aws_sqs_queue" "palavras_validas_queue" {
  provider = aws.permutacoes
  name     = "palavras-validas-queue"
  
  # Configurações da fila
  delay_seconds             = 0
  max_message_size         = 2048
  message_retention_seconds = 1209600  # 14 dias
  receive_wait_time_seconds = 10       # Long polling
  
  # Configuração para LocalStack
  tags = {
    Name = "palavras-validas-queue"
    Environment = "development"
  }
}

# Arquivo ZIP com código da Lambda Validadora
data "archive_file" "lambda_validadora_zip" {
  type        = "zip"
  output_path = "lambda_validadora.zip"
  source {
    content = <<EOF
import json
import boto3
import logging
from datetime import datetime
from botocore.exceptions import ClientError

# Configuração de logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Clientes AWS - configurados para LocalStack
# Para Lambda rodando no LocalStack, não precisa especificar endpoint
sqs_client = boto3.client(
    'sqs',
    region_name='us-east-1'
)
s3_client = boto3.client(
    's3',
    region_name='us-east-1'
)

# Configurações
SQS_QUEUE_URL = 'http://localhost:4566/000000000000/palavras-validas-queue'
S3_BUCKET_NAME = 'permutacoes-palavras-bucket'

def lambda_handler(event, context):
    """
    Lambda Validadora: Recebe palavra, valida e envia para SQS ou consulta S3
    """
    try:
        # Determina se é POST ou GET
        http_method = event.get('httpMethod', '')
        
        if http_method == 'POST':
            return processar_post(event)
        elif http_method == 'GET':
            return processar_get(event)
        else:
            return criar_resposta(400, {'error': 'Método HTTP não suportado'})
            
    except Exception as e:
        logger.error(f'Erro na Lambda Validadora: {str(e)}')
        return criar_resposta(500, {'error': 'Erro interno do servidor'})

def processar_post(event):
    """
    Processa requisição POST - recebe palavra e valida
    """
    try:
        # Extrai palavra do corpo da requisição
        body = json.loads(event.get('body', '{}'))
        palavra = body.get('palavra', '').strip().lower()
        
        if not palavra:
            return criar_resposta(400, {'error': 'Palavra não fornecida'})
        
        # Valida se tem exatamente 4 letras
        if len(palavra) != 4 or not palavra.isalpha():
            return criar_resposta(400, {
                'error': 'Palavra deve ter exatamente 4 letras',
                'palavra_recebida': palavra,
                'tamanho': len(palavra)
            })
        
        # Envia palavra para SQS
        enviar_para_sqs(palavra)
        
        logger.info(f'Palavra válida enviada para SQS: {palavra}')
        
        return criar_resposta(200, {
            'message': 'Palavra válida recebida e enviada para processamento',
            'palavra': palavra,
            'status': 'processando'
        })
        
    except json.JSONDecodeError:
        return criar_resposta(400, {'error': 'JSON inválido'})
    except Exception as e:
        logger.error(f'Erro ao processar POST: {str(e)}')
        return criar_resposta(500, {'error': 'Erro ao processar palavra'})

def processar_get(event):
    """
    Processa requisição GET - consulta permutações no S3
    """
    try:
        # Extrai palavra do path parameter
        palavra = event.get('pathParameters', {}).get('palavra', '').strip().lower()
        
        if not palavra:
            return criar_resposta(400, {'error': 'Palavra não fornecida no path'})
        
        # Consulta permutações no S3
        permutacoes = consultar_s3(palavra)
        
        if permutacoes:
            return criar_resposta(200, {
                'palavra': palavra,
                'permutacoes': permutacoes,
                'total': len(permutacoes)
            })
        else:
            return criar_resposta(404, {
                'error': 'Permutações não encontradas',
                'palavra': palavra,
                'message': 'Palavra ainda não foi processada ou não existe'
            })
            
    except Exception as e:
        logger.error(f'Erro ao processar GET: {str(e)}')
        return criar_resposta(500, {'error': 'Erro ao consultar permutações'})

def enviar_para_sqs(palavra):
    """
    Envia palavra válida para a fila SQS
    """
    try:
        message_body = json.dumps({
            'palavra': palavra,
            'timestamp': str(datetime.now())
        })
        
        response = sqs_client.send_message(
            QueueUrl=SQS_QUEUE_URL,
            MessageBody=message_body
        )
        
        logger.info(f'Mensagem enviada para SQS: {response.get("MessageId")}')
        
    except ClientError as e:
        logger.error(f'Erro ao enviar para SQS: {str(e)}')
        raise

def consultar_s3(palavra):
    """
    Consulta permutações da palavra no S3
    """
    try:
        s3_key = f'permutacoes/{palavra}.json'
        
        response = s3_client.get_object(
            Bucket=S3_BUCKET_NAME,
            Key=s3_key
        )
        
        content = response['Body'].read().decode('utf-8')
        data = json.loads(content)
        
        return data.get('permutacoes', [])
        
    except ClientError as e:
        if e.response['Error']['Code'] == 'NoSuchKey':
            logger.info(f'Permutações não encontradas para palavra: {palavra}')
            return None
        else:
            logger.error(f'Erro ao consultar S3: {str(e)}')
            raise
    except Exception as e:
        logger.error(f'Erro ao processar resposta do S3: {str(e)}')
        raise

def criar_resposta(status_code, body):
    """
    Cria resposta HTTP padronizada
    """
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type'
        },
        'body': json.dumps(body, ensure_ascii=False)
    }
EOF
    filename = "lambda_validadora.py"
  }
}

# Arquivo ZIP com código da Lambda Processadora
data "archive_file" "lambda_processadora_zip" {
  type        = "zip"
  output_path = "lambda_processadora.zip"
  source {
    content = <<EOF
import json
import boto3
import logging
from itertools import permutations
from datetime import datetime
from botocore.exceptions import ClientError

# Configuração de logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Clientes AWS - configurados para LocalStack
# Para Lambda rodando no LocalStack, não precisa especificar endpoint
s3_client = boto3.client(
    's3',
    region_name='us-east-1'
)

# Configurações
S3_BUCKET_NAME = 'permutacoes-palavras-bucket'

def lambda_handler(event, context):
    """
    Lambda Processadora: Consome SQS, gera permutações e salva no S3
    """
    try:
        # Processa todas as mensagens do SQS
        for record in event['Records']:
            processar_mensagem(record)
        
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Mensagens processadas com sucesso'})
        }
        
    except Exception as e:
        logger.error(f'Erro na Lambda Processadora: {str(e)}')
        raise

def processar_mensagem(record):
    """
    Processa uma mensagem individual do SQS
    """
    try:
        # Extrai dados da mensagem
        message_body = json.loads(record['body'])
        palavra = message_body.get('palavra', '').strip().lower()
        
        if not palavra:
            logger.warning('Mensagem SQS sem palavra válida')
            return
        
        logger.info(f'Processando palavra: {palavra}')
        
        # Gera todas as permutações da palavra
        lista_permutacoes = gerar_permutacoes(palavra)
        
        # Salva permutações no S3
        salvar_no_s3(palavra, lista_permutacoes)
        
        logger.info(f'Permutações geradas e salvas para palavra: {palavra}')
        
    except json.JSONDecodeError:
        logger.error('Erro ao decodificar JSON da mensagem SQS')
    except Exception as e:
        logger.error(f'Erro ao processar mensagem: {str(e)}')
        raise

def gerar_permutacoes(palavra):
    """
    Gera todas as permutações possíveis da palavra
    """
    try:
        # Converte palavra em lista de caracteres
        caracteres = list(palavra)
        
        # Gera todas as permutações
        perms = list(permutations(caracteres))
        
        # Converte permutações em strings e remove duplicatas
        lista_permutacoes = list(set([''.join(p) for p in perms]))
        
        # Ordena alfabeticamente
        lista_permutacoes.sort()
        
        logger.info(f'Geradas {len(lista_permutacoes)} permutações para palavra: {palavra}')
        
        return lista_permutacoes
        
    except Exception as e:
        logger.error(f'Erro ao gerar permutações: {str(e)}')
        raise

def salvar_no_s3(palavra, permutacoes):
    """
    Salva permutações no S3 em formato JSON
    """
    try:
        # Prepara dados para salvar
        data = {
            'palavra_original': palavra,
            'total_permutacoes': len(permutacoes),
            'permutacoes': permutacoes,
            'processado_em': datetime.now().isoformat(),
            'metadata': {
                'tamanho_palavra': len(palavra),
                'caracteres_unicos': len(set(palavra)),
                'primeira_permutacao': permutacoes[0] if permutacoes else None,
                'ultima_permutacao': permutacoes[-1] if permutacoes else None
            }
        }
        
        # Define chave do objeto S3
        s3_key = f'permutacoes/{palavra}.json'
        
        # Salva no S3
        s3_client.put_object(
            Bucket=S3_BUCKET_NAME,
            Key=s3_key,
            Body=json.dumps(data, ensure_ascii=False, indent=2),
            ContentType='application/json'
        )
        
        logger.info(f'Permutações salvas no S3: {s3_key}')
        
    except ClientError as e:
        logger.error(f'Erro ao salvar no S3: {str(e)}')
        raise
    except Exception as e:
        logger.error(f'Erro ao preparar dados para S3: {str(e)}')
        raise
EOF
    filename = "lambda_processadora.py"
  }
}

# Role IAM para Lambda Validadora
resource "aws_iam_role" "lambda_validadora_role" {
  provider = aws.permutacoes
  name     = "lambda-validadora-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Role IAM para Lambda Processadora
resource "aws_iam_role" "lambda_processadora_role" {
  provider = aws.permutacoes
  name     = "lambda-processadora-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Políticas básicas para as Lambdas
resource "aws_iam_role_policy_attachment" "lambda_validadora_basic" {
  provider   = aws.permutacoes
  role       = aws_iam_role.lambda_validadora_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_processadora_basic" {
  provider   = aws.permutacoes
  role       = aws_iam_role.lambda_processadora_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Política personalizada para Lambda Validadora (SQS + S3)
resource "aws_iam_role_policy" "lambda_validadora_policy" {
  provider = aws.permutacoes
  name     = "lambda-validadora-policy"
  role     = aws_iam_role.lambda_validadora_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.palavras_validas_queue.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.permutacoes_bucket.arn}/*"
      }
    ]
  })
}

# Política personalizada para Lambda Processadora (SQS + S3)
resource "aws_iam_role_policy" "lambda_processadora_policy" {
  provider = aws.permutacoes
  name     = "lambda-processadora-policy"
  role     = aws_iam_role.lambda_processadora_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.palavras_validas_queue.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.permutacoes_bucket.arn}/*"
      }
    ]
  })
}

# Função Lambda Validadora
resource "aws_lambda_function" "lambda_validadora" {
  provider         = aws.permutacoes
  filename         = data.archive_file.lambda_validadora_zip.output_path
  function_name    = "palavras-validadora"
  role            = aws_iam_role.lambda_validadora_role.arn
  handler         = "lambda_validadora.lambda_handler"
  runtime         = "python3.9"
  timeout         = 30
  
  source_code_hash = data.archive_file.lambda_validadora_zip.output_base64sha256
  description      = "Lambda que valida palavras e consulta permutações"
}

# Função Lambda Processadora
resource "aws_lambda_function" "lambda_processadora" {
  provider         = aws.permutacoes
  filename         = data.archive_file.lambda_processadora_zip.output_path
  function_name    = "palavras-processadora"
  role            = aws_iam_role.lambda_processadora_role.arn
  handler         = "lambda_processadora.lambda_handler"
  runtime         = "python3.9"
  timeout         = 60
  
  source_code_hash = data.archive_file.lambda_processadora_zip.output_base64sha256
  description      = "Lambda que processa permutações e salva no S3"
}

# Trigger SQS para Lambda Processadora
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  provider         = aws.permutacoes
  event_source_arn = aws_sqs_queue.palavras_validas_queue.arn
  function_name    = aws_lambda_function.lambda_processadora.arn
  batch_size       = 10
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "permutacoes_api" {
  provider    = aws.permutacoes
  name        = "permutacoes-api"
  description = "API para processamento de permutações de palavras"
  
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Recurso /palavra
resource "aws_api_gateway_resource" "palavra_resource" {
  provider    = aws.permutacoes
  rest_api_id = aws_api_gateway_rest_api.permutacoes_api.id
  parent_id   = aws_api_gateway_rest_api.permutacoes_api.root_resource_id
  path_part   = "palavra"
}

# Recurso /palavra/{palavra}
resource "aws_api_gateway_resource" "palavra_param_resource" {
  provider    = aws.permutacoes
  rest_api_id = aws_api_gateway_rest_api.permutacoes_api.id
  parent_id   = aws_api_gateway_resource.palavra_resource.id
  path_part   = "{palavra}"
}

# Método POST /palavra
resource "aws_api_gateway_method" "post_palavra" {
  provider      = aws.permutacoes
  rest_api_id   = aws_api_gateway_rest_api.permutacoes_api.id
  resource_id   = aws_api_gateway_resource.palavra_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

# Método GET /palavra/{palavra}
resource "aws_api_gateway_method" "get_palavra" {
  provider      = aws.permutacoes
  rest_api_id   = aws_api_gateway_rest_api.permutacoes_api.id
  resource_id   = aws_api_gateway_resource.palavra_param_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# Integração POST com Lambda Validadora
resource "aws_api_gateway_integration" "post_integration" {
  provider                = aws.permutacoes
  rest_api_id             = aws_api_gateway_rest_api.permutacoes_api.id
  resource_id             = aws_api_gateway_resource.palavra_resource.id
  http_method             = aws_api_gateway_method.post_palavra.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_validadora.invoke_arn
}

# Integração GET com Lambda Validadora
resource "aws_api_gateway_integration" "get_integration" {
  provider                = aws.permutacoes
  rest_api_id             = aws_api_gateway_rest_api.permutacoes_api.id
  resource_id             = aws_api_gateway_resource.palavra_param_resource.id
  http_method             = aws_api_gateway_method.get_palavra.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.lambda_validadora.invoke_arn
}

# Deployment da API
resource "aws_api_gateway_deployment" "permutacoes_deployment" {
  provider = aws.permutacoes
  depends_on = [
    aws_api_gateway_method.post_palavra,
    aws_api_gateway_method.get_palavra,
    aws_api_gateway_integration.post_integration,
    aws_api_gateway_integration.get_integration
  ]

  rest_api_id = aws_api_gateway_rest_api.permutacoes_api.id
  
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.palavra_resource.id,
      aws_api_gateway_resource.palavra_param_resource.id,
      aws_api_gateway_method.post_palavra.id,
      aws_api_gateway_method.get_palavra.id,
      aws_api_gateway_integration.post_integration.id,
      aws_api_gateway_integration.get_integration.id,
    ]))
  }
  
  lifecycle {
    create_before_destroy = true
  }
}

# Stage da API
resource "aws_api_gateway_stage" "permutacoes_stage" {
  provider      = aws.permutacoes
  deployment_id = aws_api_gateway_deployment.permutacoes_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.permutacoes_api.id
  stage_name    = "prod"
  
  description = "Stage de produção para API de permutações"
  
  tags = {
    Name        = "permutacoes-prod-stage"
    Environment = "production"
  }
}

# Permissões para API Gateway invocar Lambda Validadora
resource "aws_lambda_permission" "api_gateway_lambda_validadora" {
  provider      = aws.permutacoes
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_validadora.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.permutacoes_api.execution_arn}/${aws_api_gateway_stage.permutacoes_stage.stage_name}/*/*"
}

# Outputs
output "permutacoes_api_url_post" {
  description = "URL para enviar palavras (POST)"
  value       = "${aws_api_gateway_stage.permutacoes_stage.invoke_url}/palavra"
}

output "permutacoes_api_url_get" {
  description = "URL para consultar permutações (GET)"
  value       = "${aws_api_gateway_stage.permutacoes_stage.invoke_url}/palavra/{palavra}"
}

output "sqs_queue_url" {
  description = "URL da fila SQS"
  value       = aws_sqs_queue.palavras_validas_queue.url
}

output "s3_bucket_name" {
  description = "Nome do bucket S3"
  value       = aws_s3_bucket.permutacoes_bucket.bucket
} 