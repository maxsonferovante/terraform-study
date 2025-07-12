# Sistema de Alertas de Custo AWS

Este projeto Terraform configura um sistema completo de alertas de custo na AWS que envia notificações via SMS e email quando os gastos atingem um limite específico.

## Funcionalidades

- **Monitor de Custo**: Monitora gastos mensais da conta AWS
- **Alertas SMS**: Envia mensagens para seu celular via AWS SNS
- **Alertas Email**: Envia notificações por email (opcional)
- **Múltiplos Thresholds**: Alertas em diferentes percentuais do orçamento
- **Previsão de Gastos**: Alertas baseados em previsões de custo

## Pré-requisitos

1. **AWS CLI configurado** com credenciais válidas
2. **Terraform** instalado (versão 1.0+)
3. **Conta AWS** com permissões para:
   - SNS (Simple Notification Service)
   - Budgets
   - IAM (Identity and Access Management)

## Configuração

### Etapa 1: Configurar Credenciais AWS

```bash
# Configure suas credenciais AWS
aws configure

# Ou configure via variáveis de ambiente
export AWS_ACCESS_KEY_ID="sua-access-key"
export AWS_SECRET_ACCESS_KEY="sua-secret-key"
export AWS_DEFAULT_REGION="us-east-1"
```

### Etapa 2: Configurar Variáveis

```bash
# Copie o arquivo de exemplo
cp terraform.tfvars.example terraform.tfvars

# Edite o arquivo com suas configurações
nano terraform.tfvars
```

### Etapa 3: Executar o Terraform

```bash
# Inicializar o Terraform
terraform init

# Validar a configuração
terraform plan

# Aplicar as mudanças
terraform apply
```

## Configurações Disponíveis

### Variáveis Principais

| Variável | Descrição | Exemplo | Obrigatório |
|----------|-----------|---------|-------------|
| `phone_number` | Número de telefone para SMS | `"+5511999999999"` | Sim |
| `budget_limit` | Limite de custo em USD | `50.0` | Sim |
| `alert_threshold` | Percentual para alerta | `80` | Sim |
| `aws_region` | Região AWS | `"us-east-1"` | Sim |
| `email_notification` | Email para notificações | `"email@exemplo.com"` | Não |

### Exemplo de Configuração

```hcl
# terraform.tfvars
aws_region = "us-east-1"
phone_number = "+5511987654321"
budget_limit = 100.0
alert_threshold = 75
email_notification = "admin@empresa.com"
```

## Tipos de Notificação

### 1. **Alertas de Custo Real**
- Disparados quando o gasto atual atinge o threshold
- Baseados em custos já incorridos

### 2. **Alertas de Previsão**
- Disparados quando a previsão de gasto mensal atinge o threshold
- Baseados em tendências de consumo

### 3. **Alerta de Limite Total**
- Disparado quando atinge 100% do orçamento
- Alerta crítico de estouro de orçamento

## Monitoramento

Após a implementação, você pode monitorar via:

1. **AWS Console**: Budgets → Seus orçamentos
2. **AWS CloudWatch**: Métricas de custo
3. **Relatórios de Custo**: Cost Explorer

## Comandos Úteis

```bash
# Ver outputs do Terraform
terraform output

# Destruir recursos (cuidado!)
terraform destroy

# Verificar estado atual
terraform show

# Atualizar apenas um recurso
terraform apply -target=aws_budgets_budget.cost_budget
```

## Outputs Importantes

Após a execução, o Terraform mostrará:

- **ARN do tópico SNS**: Para referência
- **Nome do budget**: Para encontrar no console
- **ID da conta AWS**: Para confirmação
- **Limite configurado**: Valor em USD
- **Threshold configurado**: Percentual de alerta

## Importantes Considerações

### Custos
- **SNS SMS**: Aproximadamente $0.75 por 100 mensagens
- **AWS Budgets**: Primeiros 2 budgets gratuitos, depois $0.02/dia cada

### Limitações
- Alertas são enviados no máximo 1 vez por dia
- Demora de até 24h para detecção de custos
- SMS funciona apenas em regiões suportadas

### Segurança
- Nunca commite o arquivo `terraform.tfvars`
- Use IAM roles com permissões mínimas
- Monitore regularmente os alertas

## Solução de Problemas

### Erro: "Invalid phone number format"
```bash
# Certifique-se de usar o formato internacional
phone_number = "+5511999999999"  # Correto
phone_number = "11999999999"     # Incorreto
```

### Erro: "Insufficient permissions"
```bash
# Verifique se suas credenciais AWS têm as permissões necessárias
aws sts get-caller-identity
```

### SMS não chegando
1. Verifique se o número está no formato correto
2. Confirme se sua região AWS suporta SMS
3. Verifique se não há bloqueios de spam

## Atualizações

Para atualizar configurações:

```bash
# Modificar terraform.tfvars
nano terraform.tfvars

# Aplicar mudanças
terraform apply
```

## Suporte

- **AWS Documentation**: [AWS Budgets](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/budgets-managing-costs.html)
- **Terraform AWS Provider**: [Budgets Resources](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/budgets_budget)

---

**Dica**: Configure alertas conservadores inicialmente (ex: 50% do orçamento) para entender o padrão de gasto antes de ajustar os thresholds. 