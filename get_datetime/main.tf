# Configuração do provider AWS
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
  
  # Endpoints customizados do LocalStack
  endpoints {
    lambda     = "http://localhost:4566"
    apigateway = "http://localhost:4566"
    iam        = "http://localhost:4566"
    sts        = "http://localhost:4566"
  }
}

# Arquivo ZIP com o código Python da Lambda
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "lambda_function.zip"
  source {
    content = <<EOF
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
EOF
    filename = "lambda_function.py"
  }
}

# Role IAM para a função Lambda
resource "aws_iam_role" "lambda_role" {
  name = "lambda-data-atual-role"

  # Política de confiança que permite à Lambda assumir esta role
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

# Anexa a política básica de execução à role da Lambda
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Função Lambda que retorna a data atual
resource "aws_lambda_function" "data_atual_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "data-atual-function"
  role            = aws_iam_role.lambda_role.arn
  handler         = "lambda_function.lambda_handler"
  runtime         = "python3.9"
  timeout         = 30
  
  # Hash do arquivo ZIP para detectar mudanças
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  # Descrição da função
  description = "Função Lambda que retorna a data atual do sistema"
}

# API Gateway REST API
resource "aws_api_gateway_rest_api" "data_atual_api" {
  name        = "data-atual-api"
  description = "API Gateway para função Lambda que retorna data atual"
  
  # Configuração do endpoint
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Recurso do API Gateway (endpoint /data)
resource "aws_api_gateway_resource" "data_resource" {
  rest_api_id = aws_api_gateway_rest_api.data_atual_api.id
  parent_id   = aws_api_gateway_rest_api.data_atual_api.root_resource_id
  path_part   = "data"
}

# Método GET para o recurso
resource "aws_api_gateway_method" "data_get_method" {
  rest_api_id   = aws_api_gateway_rest_api.data_atual_api.id
  resource_id   = aws_api_gateway_resource.data_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# Integração entre API Gateway e Lambda
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.data_atual_api.id
  resource_id = aws_api_gateway_resource.data_resource.id
  http_method = aws_api_gateway_method.data_get_method.http_method

  integration_http_method = "POST"
  type                   = "AWS_PROXY"
  uri                    = aws_lambda_function.data_atual_lambda.invoke_arn
}

# Deployment do API Gateway
resource "aws_api_gateway_deployment" "data_atual_deployment" {
  depends_on = [
    aws_api_gateway_method.data_get_method,
    aws_api_gateway_integration.lambda_integration
  ]

  rest_api_id = aws_api_gateway_rest_api.data_atual_api.id
  
  # Força a recriação quando há mudanças
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.data_resource.id,
      aws_api_gateway_method.data_get_method.id,
      aws_api_gateway_integration.lambda_integration.id,
    ]))
  }
  
  # Ciclo de vida para evitar conflitos
  lifecycle {
    create_before_destroy = true
  }
}

# Stage do API Gateway (substitui o stage_name deprecado)
resource "aws_api_gateway_stage" "data_atual_stage" {
  deployment_id = aws_api_gateway_deployment.data_atual_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.data_atual_api.id
  stage_name    = "prod"
  
  # Configurações do stage
  description = "Stage de produção para API de data atual"
  
  # Tags para organização
  tags = {
    Name        = "data-atual-prod-stage"
    Environment = "production"
  }
}

# Permissão para o API Gateway invocar a Lambda
resource "aws_lambda_permission" "allow_api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_atual_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  
  # ARN do API Gateway (específico para o stage prod)
  source_arn = "${aws_api_gateway_rest_api.data_atual_api.execution_arn}/${aws_api_gateway_stage.data_atual_stage.stage_name}/*/*"
}

# Outputs para mostrar informações importantes
output "api_gateway_url" {
  description = "URL da API Gateway para acessar a função"
  value       = "${aws_api_gateway_stage.data_atual_stage.invoke_url}/data"
}

output "lambda_function_name" {
  description = "Nome da função Lambda criada"
  value       = aws_lambda_function.data_atual_lambda.function_name
}

output "api_gateway_id" {
  description = "ID do API Gateway criado"
  value       = aws_api_gateway_rest_api.data_atual_api.id
}
