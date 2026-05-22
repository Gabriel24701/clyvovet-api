# ClyvoVet - Infraestrutura e CI/CD

## 📌 Sobre o Projeto
O ecossistema ClyvoVet foi projetado para suportar o monitoramento de saúde de pets via dispositivos IoT. Este repositório contém a infraestrutura e a esteira de Continuous Deployment (CD) para a nossa API backend.

## 🏗️ Arquitetura de Nuvem
Nossa infraestrutura foi construída sob o conceito de recursos efêmeros e orquestração de contêineres.
* **Provedor Cloud:** Microsoft Azure
* **Registro de Imagens:** Azure Container Registry (ACR) privado.
* **Servidor:** Azure Virtual Machine (Linux/Ubuntu)
* **Banco de Dados:** Oracle Database Free (conteinerizado).
* **Automação:** GitHub Actions com acesso seguro via SSH.

*(Insira aqui a imagem do seu diagrama desenhado no Draw.io)*

## 🚀 Fluxo de Deploy Contínuo (CI/CD)
O deploy ocorre de forma 100% automatizada. Ao realizar um push na branch `develop`:
1. O GitHub Actions realiza o checkout do código.
2. É feito o build da imagem Docker da API em formato multi-stage.
3. A imagem é enviada (push) para o ACR utilizando credenciais secretas do repositório.
4. A pipeline acessa a VM na Azure via SSH, realiza a autenticação no ACR, faz o pull da nova imagem e recria o contêiner utilizando o `docker-compose.yml`, sem tempo de inatividade no banco de dados.

## 🛠️ Como Provisionar a Infraestrutura do Zero
Para replicar o ambiente, não é necessária intervenção manual no servidor. Basta executar o script de automação localmente:

1. Dê permissão de execução: `chmod +x deploy-interativo.sh`
2. Execute o script: `./deploy-interativo.sh`
3. O script criará o Resource Group, a VM, instalará o Docker, criará o arquivo `.env` com senhas seguras e iniciará a stack base.