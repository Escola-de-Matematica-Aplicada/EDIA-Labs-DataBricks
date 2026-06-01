# LAB 2 — Modelagem de Dados para IA e Analytics

> **Disciplina:** Engenharia de Dados para Inteligencia Artificial e Analytics  
> **Aula:** 2 — Modelagem: Estruturas de dados para suporte a IA e analytics  
> **Duracao do lab:** ~1h30  
> **Entrega:** Diagrama ER + Star Schema + DDL SQL + justificativas de modelagem  

---

## Objetivos de Aprendizagem

Ao final deste lab, o aluno sera capaz de:

1. Projetar um modelo entidade-relacionamento para um cenario de negocio
2. Aplicar normalizacao ate a 3FN em contexto transacional
3. Projetar um Star Schema para analytics e ML
4. Justificar o uso de surrogate keys vs natural keys
5. Identificar quando desnormalizar para ganho de performance

---

## Parte 0 — Contexto (5 min)

Na Aula 1, o grupo mapeou o ecossistema de dados da LODLog. Agora e hora de **estruturar** esses dados.

> **Problema do dia:** A LODLog tem dados espalhados em ERP, WMS, TMS e sensores IoT. Cada sistema usa suas proprias chaves e formatos. Nao ha uma visao unificada do cliente, do veiculo ou do produto. Relatorios demoram porque precisam fazer JOINs complexos entre sistemas.

**Missao do LAB 2:** Criar uma camada de modelagem que unifique os dados para analytics e para alimentar modelos de IA.

---

## Parte 1 — Modelo Entidade-Relacionamento (35 min)

### Atividade 1.1: Identifique as Entidades (grupo, 10 min)

A partir do cenario LODLog, liste pelo menos **8 entidades** com seus atributos principais. Exemplo:

- VEICULO (veiculo_id, placa, modelo, ano_fabricacao, capacidade_kg, ...)
- MOTORISTA (motorista_id, nome, cnh, data_admissao, ...)

Liste as suas 8 entidades abaixo:

1.
2.
3.
4.
5.
6.
7.
8.

### Atividade 1.2: Relacionamentos e Cardinalidade (grupo, 15 min)

Para cada par de entidades abaixo, defina:
- O tipo de relacionamento (1:1, 1:N, N:M)
- O nome do relacionamento
- Um atributo do relacionamento (se houver)

| Entidade A | Entidade B | Cardinalidade | Nome do Relacionamento | Atributo (se houver) |
|-----------|-----------|---------------|----------------------|---------------------|
| VEICULO | MOTORISTA | | | |
| PEDIDO | CLIENTE | | | |
| PEDIDO | VEICULO | | | |
| PRODUTO | CENTRO_DISTRIBUICAO | | | |
| MOTORISTA | MANUTENCAO | | | |

### Atividade 1.3: Diagrama ER (grupo, 10 min)

Desenhe o Diagrama Entidade-Relacionamento da LODLog. Pode ser no papel, no Miro, no draw.io ou em qualquer ferramenta.

Requisitos minimos:
- 8 entidades
- 5 relacionamentos com cardinalidade
- Atributos principais em cada entidade
- Chaves primarias identificadas

---

## Parte 2 — Normalizacao (20 min)

### Atividade 2.1: Identifique as Anomalias (individual, 10 min)

Considere a tabela nao normalizada abaixo, extraida de um relatorio de entregas da LODLog:

```
ENTREGA(entrega_id, data_entrega, cliente_nome, cliente_cnpj, cliente_endereco,
        veiculo_placa, veiculo_modelo, motorista_nome, motorista_cnh,
        cd_origem_nome, cd_destino_nome, produto_sku, produto_nome,
        quantidade, peso_kg, valor_frete)
```

Responda:

1. **Anomalia de insercao:** O que acontece se quisermos cadastrar um novo cliente que ainda nao fez nenhuma entrega?
2. **Anomalia de atualizacao:** Se o motorista "Joao Silva" mudar de CNH, quantos registros precisaremos atualizar?
3. **Anomalia de exclusao:** Se apagarmos a unica entrega de um produto, perdemos tambem as informacoes desse produto?

### Atividade 2.2: Normalize ate a 3FN (grupo, 10 min)

Decomponha a tabela ENTREGA acima ate a **Terceira Forma Normal (3FN)**.

- Liste as novas tabelas
- Indique a chave primaria de cada uma
- Indique as chaves estrangeiras
- Justifique por que esta na 3FN

---

## Parte 3 — Star Schema para Analytics (30 min)

### Atividade 3.1: Diferenca ER vs Star Schema (individual, 5 min)

Complete a tabela comparativa:

| Caracteristica | Modelo ER (Transacional) | Star Schema (Analitico) |
|----------------|-------------------------|------------------------|
| Objetivo principal | | |
| Numero de tabelas | | |
| Tipo de JOIN | | |
| Granularidade | | |
| Uso de surrogate keys | | |
| Otimizado para | | |

### Atividade 3.2: Projete o Star Schema da LODLog (grupo, 20 min)

A partir do ER criado na Parte 1, projete um **Star Schema** para responder as seguintes perguntas de negocio:

1. Qual a taxa de pontualidade por centro de distribuicao e por mes?
2. Qual o custo medio de frete por regiao e por tipo de veiculo?
3. Quantos pedidos foram entregues com atraso por cliente no ultimo trimestre?
4. Qual a correlacao entre temperatura do motor e atraso de entrega?

**Requisitos:**
- Defina a **tabela fato** (qual evento voce esta medindo?)
- Defina pelo menos **4 dimensoes**
- Para cada dimensao, liste os atributos mais importantes
- Indique a **granularidade** da fato (ex: uma linha por entrega? por pedido? por dia?)

### Atividade 3.3: Surrogate Keys (individual, 5 min)

Para cada tabela do seu Star Schema, responda:

| Tabela | Usa surrogate key? | Por que? |
|--------|-------------------|----------|
| Fato | | |
| Dimensao Tempo | | |
| Dimensao Cliente | | |
| Dimensao Veiculo | | |
| Dimensao Localidade | | |

---

## Parte 4 — SQL DDL (20 min)

### Atividade 4.1: Crie as Tabelas (individual, 15 min)

Escreva o comando `CREATE TABLE` para:

1. A tabela fato do seu Star Schema
2. Duas dimensoes a sua escolha

Requisitos:
- Tipos de dados adequados (INT, VARCHAR, DECIMAL, DATE, TIMESTAMP, BOOLEAN)
- Chaves primarias definidas
- Chaves estrangeiras com `REFERENCES`
- Pelo menos uma constraint `CHECK` (ex: `CHECK (peso_kg > 0)`)
- Pelo menos uma coluna com `NOT NULL`

### Atividade 4.2: Justifique suas Escolhas (grupo, 5 min)

Explique em 2-3 linhas:

1. Por que voce escolheu essa granularidade para a tabela fato?
2. Por que incluiu (ou nao) a coluna `indicador_atraso` na fato?
3. Qual dimensao voce acha que vai crescer mais? Como lidaria com isso?

---

## Parte 5 — Entrega do Grupo (10 min)

### Produto do LAB 2

Entregue um unico documento contendo:

1. **Diagrama ER** da LODLog (imagem ou link)
2. **Decomposicao 3FN** da tabela ENTREGA
3. **Star Schema** proposto (diagrama + descricao das tabelas)
4. **DDL SQL** da fato + 2 dimensoes
5. **Respostas** das Atividades 3.3 e 4.2

### Rubrica de Avaliaao do LAB 2 (compoe 10% da nota do projeto em grupo)

| Criterio | Peso | Excelente | Satisfatorio | Insatisfatorio |
|----------|------|-----------|--------------|----------------|
| Diagrama ER | 15% | 8+ entidades, cardinalidades corretas, atributos completos | 6-7 entidades, algumas cardinalidades erradas | < 6 entidades ou muitos erros |
| Normalizacao | 20% | Decomposicao correta ate 3FN, PKs/FKs claras | Decomposicao ate 2FN ou PKs confusas | Nao normalizou ou PKs ausentes |
| Star Schema | 25% | Fato bem definida, 4+ dimensoes, granularidade clara | Fato ok, 3 dimensoes, granularidade confusa | Fato inadequada ou < 3 dimensoes |
| DDL SQL | 25% | Sintaxe correta, tipos adequados, constraints presentes | Sintaxe ok, 1-2 erros de tipo ou constraint | Erros graves de sintaxe ou sem constraints |
| Justificativas | 15% | Respostas claras, demonstram compreensao | Respostas aceitaveis, compreensao parcial | Respostas vagas ou incorretas |

---

## Material de Apoio

- Aula 2 — Slides de Modelagem ER e Dimensional
- Documento base: `Projeto-Eng-Dados-IA-para-Negocio.md` (Secao 3: Modelagem de Dados para IA)
- Livro: Jukic et al. — Database Systems (Cap. 5 e 10)

---

> **Dica do Professor:** O Star Schema nao e "melhor" que o ER — sao modelos para propositos diferentes. O ER serve para operar (transacoes); o Star Schema serve para analisar (agregacoes). Um pipeline de dados bem projetado comeca no ER dos sistemas transacionais e termina no Star Schema do DW.
