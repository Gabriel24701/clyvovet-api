# ClyvoVet - Backend API & Infraestrutura DevOps

## 📌 Sobre o Projeto
O ecossistema ClyvoVet foi projetado para suportar o monitoramento de saúde de pets via dispositivos IoT. Este repositório entrega uma API robusta desenvolvida em **C# (.NET 8)**, integrada a um banco de dados **Oracle** e automatizada através de uma esteira de **Continuous Deployment (CI/CD)**.

---

## 🛠️ Tecnologias e Funcionalidades (C# & EF Core)
O backend foi estruturado seguindo boas práticas de desenvolvimento para garantir integridade e alta performance:

* **Configuração do DbContext:** Implementação centralizada do `AppDbContext`, gerenciando o ciclo de vida das conexões e contextos do banco de dados.
* **Mapeamento das Entidades:** Modelagem orientada a objetos das entidades (como `Pet` e `User`), utilizando *Data Annotations* para garantir o mapeamento consistente com o esquema relacional.
* **Conexão com Oracle:** Integração nativa utilizando `Oracle.EntityFrameworkCore`, garantindo persistência robusta dos dados de telemetria IoT.
* **Uso de Migrations:** Utilização de *Code-First Migrations* para controle de versão do esquema do banco, com aplicação automatizada (`context.Database.Migrate()`) durante a inicialização da API, garantindo que o banco esteja sempre sincronizado.
* **Estrutura Coerente:** Modelagem normalizada com integridade referencial, garantindo o correto relacionamento entre tutores e seus respectivos pets.

---

## 🏗️ Arquitetura de Nuvem
Nossa infraestrutura foi construída sob o conceito de recursos efêmeros e orquestração de contêineres:

* **Provedor Cloud:** Microsoft Azure
* **Backend:** C# .NET 8 (API RESTful)
* **Banco de Dados:** Oracle Database Free (conteinerizado)
* **Registro de Imagens:** Azure Container Registry (ACR) privado
* **Servidor:** Azure Virtual Machine (Linux/Ubuntu)
* **Automação:** GitHub Actions com acesso seguro via SSH

*(Insira aqui a imagem do seu diagrama de arquitetura)*

---

## 🚀 Fluxo de Deploy Contínuo (CI/CD)
O deploy é 100% automatizado, garantindo que o ciclo de vida da aplicação C# acompanhe a evolução da infraestrutura:

1. **CI:** O GitHub Actions valida o build da aplicação C#.
2. **Build:** Criação da imagem Docker *multi-stage* otimizada para .NET 8.
3. **CD:** Push da imagem para o ACR utilizando segredos de segurança.
4. **Deploy:** A pipeline acessa a VM via SSH, faz o pull da nova imagem, executa as *migrations* do EF Core automaticamente e reinicia o contêiner sem *downtime*.

---

## 🛠️ Como Provisionar a Infraestrutura do Zero
Para replicar o ambiente, não é necessária intervenção manual no servidor. Basta executar o script de automação:

1. Configure as variáveis de ambiente no arquivo `.env` (credenciais do Oracle e Azure).
2. Dê permissão de execução: `chmod +x deploy-interativo.sh`
3. Execute o script: `./deploy-interativo.sh`
4. O script criará o Resource Group, a VM, instalará o Docker e iniciará a stack. O EF Core cuidará da criação das tabelas no Oracle automaticamente na primeira execução.