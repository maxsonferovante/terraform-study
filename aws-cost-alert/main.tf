# Configuração do provider AWS para alertas de custo
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Provider AWS - configuração para AWS real (não LocalStack)
provider "aws" {
  region = var.aws_region
  
  # Para usar suas credenciais AWS reais configuradas no CLI
  # aws configure ou variáveis de ambiente
}

# Variáveis de configuração
variable "aws_region" {
  description = "Região AWS onde os recursos serão criados"
  type        = string
  default     = "us-east-1"
}

variable "phone_number" {
  description = "Número de telefone para receber alertas (formato: +5511999999999)"
  type        = string
  # Você deve definir este valor no terraform.tfvars
}

variable "budget_limit" {
  description = "Limite de custo em USD para disparar o alerta"
  type        = number
  default     = 1.0
}

variable "alert_threshold" {
  description = "Percentual do orçamento que dispara o alerta (ex: 80 = 80%)"
  type        = number
  default     = 80
}

variable "email_notification" {
  description = "Email para receber notificações (opcional)"
  type        = string
  default     = ""
}

# Tópico SNS para notificações de custo
resource "aws_sns_topic" "cost_alert_topic" {
  name         = "aws-cost-alert-topic"
  display_name = "Alertas de Custo AWS"
  
  # Configurações do tópico
  delivery_policy = jsonencode({
    "http" = {
      "defaultHealthyRetryPolicy" = {
        "minDelayTarget"     = 20,
        "maxDelayTarget"     = 20,
        "numRetries"         = 3,
        "numMaxDelayRetries" = 0,
        "numMinDelayRetries" = 0,
        "numNoDelayRetries"  = 0,
        "backoffFunction"    = "linear"
      }
    }
  })
  
  tags = {
    Name        = "cost-alert-topic"
    Environment = "production"
    Purpose     = "cost-monitoring"
  }
}

# Assinatura SNS para SMS (seu número)
resource "aws_sns_topic_subscription" "cost_alert_sms" {
  topic_arn = aws_sns_topic.cost_alert_topic.arn
  protocol  = "sms"
  endpoint  = var.phone_number
  
  # Configurações da assinatura
  depends_on = [aws_sns_topic.cost_alert_topic]
}

# Assinatura SNS para Email (opcional)
resource "aws_sns_topic_subscription" "cost_alert_email" {
  count = var.email_notification != "" ? 1 : 0
  
  topic_arn = aws_sns_topic.cost_alert_topic.arn
  protocol  = "email"
  endpoint  = var.email_notification
  
  depends_on = [aws_sns_topic.cost_alert_topic]
}

# Budget para monitorar custos
resource "aws_budgets_budget" "cost_budget" {
  name         = "monthly-cost-budget"
  budget_type  = "COST"
  limit_amount = var.budget_limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  
  # Configuração do período de custo
  cost_filter {
    name   = "Region"
    values = [var.aws_region]
  }
  
  # Notificação quando atingir o threshold
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = var.alert_threshold
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = var.email_notification != "" ? [var.email_notification] : []
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alert_topic.arn]
  }
  
  # Notificação de previsão quando atingir o threshold
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = var.alert_threshold
    threshold_type            = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.email_notification != "" ? [var.email_notification] : []
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alert_topic.arn]
  }
  
  # Notificação quando atingir 100% do orçamento
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.email_notification != "" ? [var.email_notification] : []
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alert_topic.arn]
  }
  
  depends_on = [aws_sns_topic.cost_alert_topic]
}

# Política IAM para permitir que o Budget publique no SNS
resource "aws_sns_topic_policy" "cost_alert_policy" {
  arn = aws_sns_topic.cost_alert_topic.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowBudgetServiceToPublish"
        Effect = "Allow"
        Principal = {
          Service = "budgets.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.cost_alert_topic.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# Obter informações da conta atual
data "aws_caller_identity" "current" {}

# Outputs para mostrar informações importantes
output "sns_topic_arn" {
  description = "ARN do tópico SNS criado"
  value       = aws_sns_topic.cost_alert_topic.arn
}

output "budget_name" {
  description = "Nome do budget criado"
  value       = aws_budgets_budget.cost_budget.name
}

output "account_id" {
  description = "ID da conta AWS"
  value       = data.aws_caller_identity.current.account_id
}

output "phone_subscription_arn" {
  description = "ARN da assinatura SMS"
  value       = aws_sns_topic_subscription.cost_alert_sms.arn
}

output "budget_limit" {
  description = "Limite do orçamento configurado"
  value       = "${var.budget_limit} USD"
}

output "alert_threshold" {
  description = "Percentual configurado para disparar alertas"
  value       = "${var.alert_threshold}%"
} 