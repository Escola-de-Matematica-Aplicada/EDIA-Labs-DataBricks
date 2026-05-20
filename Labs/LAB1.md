# LAB 1 — Mapeamento do Ecossistema de Dados e Fundamentos

> **Disciplina:** Engenharia de Dados para Inteligencia Artificial e Analytics  
> **Aula:** 1 — Fundamentos  
> **Duracao do lab:** ~1h30 (dentro dos 3h20 da aula)  
> **Entrega:** Documento de respostas + diagrama inicial do grupo  

---

## Objetivos de Aprendizagem

Ao final deste lab, o aluno sera capaz de:

1. Mapear o ecossistema de dados de uma organizacao real ou ficticia
2. Distinguir sistemas transacionais de sistemas analiticos
3. Classificar dados segundo os 5 Vs do Big Data
4. Identificar oportunidades de uso de IA a partir de dados existentes
5. Posicionar servicos de nuvem nos modelos IaaS, PaaS e SaaS

---

## Parte 0 — Formacao dos Grupos (10 min)

- Formar grupos de 5 a 6 integrantes
- Escolher um "Data Product Owner" do grupo (quem representara o grupo nas discussoes)
- Acessar o ECLASS e confirmar formacao

---

## Parte 1 — Linha do Tempo da Engenharia de Dados (20 min)

### Atividade 1.1: Cartao-Resposta Historico (individual, 10 min)

Para cada marco historico abaixo, responda em uma frase: **"Por que isso mudou a forma como organizamos dados?"**

| Marco | Sua Resposta |
|-------|-------------|
| Cartoes perfurados (Hollerith, 1911) | |
| Fitas magneticas (1951) | |
| Discos rigidos e acesso randomico (anos 70) | |
| Modelo relacional de Codd (1970) | |
| Primeiro SGBD comercial (Oracle, 1977) | |
| Data Warehouse (Inmon/Kimball, anos 90) | |
| Google File System / Big Data (1998/1997) | |
| Hypervisor e computacao em nuvem (2000+) | |
| Transformers / IA Generativa (2017/2022) | |

### Atividade 1.2: Discussao em Grupo (10 min)

Discuta no grupo: **"Qual desses marcos foi mais importante para a Inteligencia Artificial aplicada a negocios? Por que?"**

Registre a conclusao do grupo em 3 a 5 linhas.

---

## Parte 2 — Transacional vs Analitico (20 min)

### Atividade 2.1: Classifique os Sistemas (individual + grupo, 10 min)

Classifique cada sistema da LODLog como **Transacional (T)** ou **Analitico (A)**. Justifique em uma frase.

| Sistema | T ou A? | Justificativa |
|---------|---------|--------------|
| ERP que registra o pagamento de um pedido | | |
| Dashboard de SLA de entregas do mes | | |
| WMS que baixa o estoque no momento da expedicao | | |
| Modelo de ML que prediz atraso de entrega | | |
| TMS que aloca um veiculo a um pedido | | |
| Relatorio de ranking de CDs por eficiencia | | |
| API de IoT que recebe evento do sensor da frota | | |
| Planilha Excel usada pelo supervisor para escalar motoristas | | |

### Atividade 2.2: Mapeamento LODLog (grupo, 10 min)

No cenario da LODLog, liste:

1. **3 sistemas transacionais** que a empresa provavelmente ja possui
2. **2 sistemas analiticos** que ela deveria ter
3. **1 sistema que comeca como transacional e vira analitico** (ex: dados de IoT)

---

## Parte 3 — Os 5 Vs na LODLog (25 min)

### Atividade 3.1: Preencha a Matriz dos 5 Vs (grupo, 15 min)

Para cada fonte de dados da LODLog, discuta e preencha:

| Fonte | Valor (insights possiveis) | Veracidade (desafios) | Variedade (formato/fontes) | Velocidade | Volume/dia |
|-------|---------------------------|----------------------|---------------------------|-----------|-----------|
| Sensores IoT da frota | | | | | |
| Pedidos do TMS | | | | | |
| Estoque do WMS | | | | | |
| APIs externas (clima, trafego) | | | | | |
| Planilhas Excel do supervisor | | | | | |

### Atividade 3.2: Priorizacao (grupo, 10 min)

Dado o problema de negocio da LODLog (*"estamos perdendo dinheiro, mas nao sabemos onde"*), ordene as fontes acima por **prioridade de ingestao** (1 = mais urgente). Justifique a escolha do top 3.

---

## Parte 4 — Nuvem e Modelos de Servico (20 min)

### Atividade 4.1: Classifique os Servicos (individual, 10 min)

Classifique cada servico/tecnologia como **IaaS**, **PaaS**, **SaaS** ou **On-Premise**:

| Servico/Tecnologia | IaaS / PaaS / SaaS / On-Prem? |
|-------------------|------------------------------|
| Servidor fisico no datacenter da empresa | |
| Amazon EC2 (maquina virtual) | |
| Amazon RDS (banco gerenciado) | |
| Power BI Online | |
| Databricks Community Edition | |
| PostgreSQL instalado em um EC2 | |
| Snowflake | |
| Excel instalado no computador do usuario | |

### Atividade 4.2: Mapeamento para o Pipeline LODLog (grupo, 10 min)

Desenhe (no papel ou no quadro) onde cada modelo de servico se encaixa no pipeline da LODLog:

- **Ingestao:** qual camada (I/P/S) e exemplo de servico?
- **Processamento/Transformacao:** qual camada (I/P/S) e exemplo de servico?
- **Consumo/Visualizacao:** qual camada (I/P/S) e exemplo de servico?

**Regra:** o grupo deve usar pelo menos **um servico de cada modelo** (IaaS, PaaS, SaaS) e justificar por que escolheu cada um.

---

## Parte 5 — Entrega do Grupo (15 min)

### Produto do LAB 1

Crie um documento simples (Word, Google Docs ou markdown) contendo:

1. **Respostas da Parte 1** (marco historico escolhido pelo grupo + justificativa)
2. **Classificacao T/A da Parte 2**
3. **Matriz dos 5 Vs preenchida** (Parte 3)
4. **Diagrama simplificado** da arquitetura LODLog com IaaS/PaaS/SaaS (Parte 4)
5. **Primeira versao do problema de negocio** que o grupo vai atacar no projeto (uma frase)

### Rubrica de Avaliacao do LAB 1 (nao avaliativo — diagnostico)

| Criterio | Excelente | Satisfatorio | Precisa Melhorar |
|----------|-----------|--------------|------------------|
| Diferenciacao T vs A | Todos corretos com justificativas claras | 6-7 corretos | < 6 corretos |
| Matriz 5 Vs | Todos os Vs analisados com profundidade | Alguns Vs genericos | Vs mal compreendidos |
| Arquitetura I/P/S | Coerente, justificada, usa os 3 modelos | Usa os 3 modelos sem justificar | Confiunde I/P/S |
| Problema de negocio | Clara, mensuravel, ligada aos dados | Clara mas pouco mensuravel | Vaga ou sem ligacao com dados |

---

## Material de Apoio

- Slide 20 da Aula 1: "Informacao transacional vs informacao analitica"
- Slide 25: "Big Data: os 5 Vs"
- Slide 35: "Modelo de servico em nuvem (IaaS/PaaS/SaaS)"
- Documento base: `Projeto-Eng-Dados-IA-para-Negocio.md` (cenário LODLog)

---

> **Dica do Professor:** Nao se preocupe em "acertar" a arquitetura agora. O objetivo do LAB 1 e **diagnosticar** o que o grupo ja sabe e **alinhá-lo** com os conceitos da aula. A arquitetura evoluira nos proximos labs.
