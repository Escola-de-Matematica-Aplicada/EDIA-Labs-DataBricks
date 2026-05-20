# LAB 3 — SQL Avancado e Preparacao de Dados para Modelos de IA

> **Disciplina:** Engenharia de Dados para Inteligencia Artificial e Analytics  
> **Aula:** 3 — Implementacao: SQL avancado e preparacao de dados para modelos de IA  
> **Duracao do lab:** ~1h30  
> **Ambiente:** Databricks Community Edition  
> **Entrega:** Notebook `.py` ou `.ipynb` com queries comentadas  

---

## Objetivos de Aprendizagem

Ao final deste lab, o aluno sera capaz de:

1. Escrever consultas SQL avancadas (JOINs, CTEs, window functions, agregacoes)
2. Preparar um dataset estruturado para treinamento de modelos de ML
3. Identificar e tratar problemas de qualidade nos dados via SQL
4. Criar metricas de negocio diretamente no banco de dados
5. Documentar um pipeline de feature engineering em SQL

---

## Parte 0 — Setup do Ambiente (10 min)

### Databricks Community Edition (unico ambiente do LAB)

1. Acesse [community.cloud.databricks.com](https://community.cloud.databricks.com) e faca login.
2. Crie um cluster (Single Node, DBR 14.x ou superior) — botao **"Create compute"**.
3. Importe o notebook de seed: **Workspace > Import > URL ou arquivo** → selecione `lodlog_lab3_seed.py`.
4. Execute o notebook de seed do inicio ao fim (**Run All**) — leva ~2 minutos.
5. Crie um novo notebook para o seu trabalho e execute na primeira celula:

```sql
-- Cole em uma celula %sql ou Python equivalente
USE lodlog;
SHOW TABLES;
```

**Como executar SQL no Databricks:**
- Crie uma celula com `%sql` no inicio para escrever SQL diretamente.
- Ou use `spark.sql("SELECT ...")` em Python para capturar o resultado em DataFrame.
- Use `display(spark.sql("SELECT ..."))` para visualizar com graficos.

**Como visualizar resultados:**
- Apos executar uma celula `%sql`, clique no icone **"+"** abaixo da tabela de resultado.
- Escolha o tipo de grafico (Barras, Linha, Dispersao, Pizza, Histograma).
- Configure os eixos X/Y com arrastar e soltar.

> **Banco de dados:** `lodlog` | **Tabelas:** `dim_cliente`, `dim_veiculo`, `dim_veiculo_manutencao`, `dim_tempo`, `dim_clima`, `fato_entregas` (~50.000 linhas)

---

## Parte 1 — Analise Exploratoria com SQL (25 min)

### Atividade 1.1: Conhecendo os Dados (individual, 10 min)

Execute e interprete as queries abaixo. Para cada uma, escreva em uma frase o que ela revela sobre a LODLog.

```sql
-- Query 1: Volume de entregas por mes
SELECT DATE_TRUNC('month', data_entrega) AS mes,
       COUNT(*) AS total_entregas,
       SUM(CASE WHEN atraso_min > 0 THEN 1 ELSE 0 END) AS entregas_atrasadas
FROM fato_entregas
GROUP BY 1
ORDER BY 1;
```

Interpretacao:

```sql
-- Query 2: Ranking de CDs por eficiencia
SELECT cd_origem,
       ROUND(AVG(atraso_min), 2) AS atraso_medio_min,
       ROUND(SUM(custo_combustivel), 2) AS custo_total_combustivel,
       COUNT(DISTINCT veiculo_id) AS frota_alocada
FROM fato_entregas
WHERE data_entrega >= CURRENT_DATE - INTERVAL '90 days'
GROUP BY cd_origem
ORDER BY atraso_medio_min ASC;
```

Interpretacao:

```sql
-- Query 3: Correlacao simples entre distancia e custo
SELECT corr(distancia_km, custo_total) AS correlacao_distancia_custo
FROM fato_entregas
WHERE data_entrega >= CURRENT_DATE - INTERVAL '30 days';
```

Interpretacao:

### Atividade 1.2: Sua Primeira Query Analitica (individual, 15 min)

Escreva uma query que responda: **"Qual o percentual de entregas no prazo por cliente, nos ultimos 90 dias, para clientes com mais de 10 entregas?"**

Requisitos:
- Use `JOIN` com a dimensao cliente
- Use `HAVING` para filtrar clientes com > 10 entregas
- Calcule o percentual com `ROUND(..., 2)`
- Ordene do pior para o melhor percentual

```sql
-- Escreva sua query aqui

```

---

## Parte 2 — Window Functions e Series Temporais (25 min)

### Atividade 2.1: Media Movel de Atrasos (individual, 10 min)

Escreva uma query que calcule a **media movel de 7 dias** de atraso por centro de distribuicao.

Dica: use `AVG(atraso_min) OVER (PARTITION BY cd_origem ORDER BY data_entrega ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)`

```sql
-- Escreva sua query aqui

```

### Atividade 2.2: Ranking e Percentil (individual, 10 min)

Escreva uma query que classifique cada motorista em percentis de performance baseados no custo por km nos ultimos 30 dias.

```sql
-- Escreva sua query aqui

```

### Atividade 2.3: Discussao em Grupo (5 min)

Por que window functions sao mais eficientes que subqueries correlacionadas para calculos como media movel e ranking?

---

## Parte 3 — Feature Engineering em SQL (30 min)

### Atividade 3.1: Crie a View `vw_features_ml` (grupo, 20 min)

Crie uma view (ou CTE) que produza o dataset de features para o **Modelo de Predicao de Atraso**. Cada linha deve representar uma entrega com as seguintes features:

| Feature | Como calcular em SQL |
|---------|---------------------|
| distancia_km | Ja existe na fato |
| peso_carga_kg | Ja existe na fato |
| hora_saida | EXTRACT(HOUR FROM hora_saida) |
| dia_semana | EXTRACT(DOW FROM data_entrega) |
| eh_feriado | JOIN com dim_tempo |
| temperatura_media_motor | Media dos sensores IoT na data |
| ind_chuva | JOIN com dados de clima (se disponivel) |
| historico_atrasos_7d | Media de atraso do mesmo cliente nos ultimos 7 dias (window function) |
| dias_ultima_manutencao | Diferenca entre data_entrega e ultima manutencao do veiculo |
| target (indicador_atraso) | 1 se atraso_min > 0, senao 0 |

```sql
CREATE VIEW vw_features_ml AS
WITH historico_cliente AS (
    -- Calcule aqui o historico de atrasos do cliente
),
manutencao_veiculo AS (
    -- Calcule aqui os dias desde a ultima manutencao
)
SELECT
    fe.sk_entrega,
    fe.distancia_km,
    fe.peso_carga_kg,
    -- ... complete as features
FROM fato_entregas fe
JOIN dim_cliente dc ON fe.sk_cliente = dc.sk_cliente
-- ... complete os JOINs
;
```

### Atividade 3.2: Valide a Feature Store (individual, 10 min)

Execute queries de validacao:

1. **Completude:** `SELECT COUNT(*) FROM vw_features_ml WHERE temperatura_media_motor IS NULL;`
2. **Range:** `SELECT MIN(distancia_km), MAX(distancia_km) FROM vw_features_ml;`
3. **Distribuicao do target:** `SELECT indicador_atraso, COUNT(*) FROM vw_features_ml GROUP BY 1;`
4. **Correlacao preliminar:** `SELECT corr(distancia_km, indicador_atraso) FROM vw_features_ml;`

Registre os resultados. Ha algum problema evidente?

---

## Parte 4 — Qualidade de Dados via SQL (15 min)

### Atividade 4.1: Detecte Problemas (individual, 10 min)

Escreva queries que detectem:

1. **Registros duplicados** na tabela fato (mesmo pedido_id + data_entrega)
2. **Valores negativos** em campos que deveriam ser positivos (peso, distancia, custo)
3. **Outliers** em atraso_min (ex: atrasos > 1000 minutos)
4. **Inconsistencia** entre dimensoes: clientes na fato que nao existem em dim_cliente

```sql
-- Query 1: Duplicatas

-- Query 2: Valores negativos

-- Query 3: Outliers

-- Query 4: Inconsistencia de FK

```

### Atividade 4.2: Plano de Correcao (grupo, 5 min)

Para cada problema detectado acima, discuta:
- Qual a causa provavel?
- Como corrigir no pipeline (ETL)?
- Como prevenir que volte a acontecer?

---

## Parte 5 — Entrega do Grupo (5 min)

### Produto do LAB 3

Exporte o notebook Databricks e entregue **um arquivo `.ipynb` ou `.py`** comentado contendo:

1. Query analitica da Parte 1.2
2. Window functions da Parte 2
3. Criacao da view `vw_features_ml` (Parte 3)
4. Queries de qualidade da Parte 4
5. Um comentario no topo indicando: **"Este dataset alimenta o Modelo X de IA, com as features Y"**

> **Como exportar no Databricks:** File > Export > Source File (.py) ou Jupyter Notebook (.ipynb)

### Rubrica de Avaliacao do LAB 3 (compoe 15% da nota do projeto individual)

| Criterio | Peso | Excelente | Satisfatorio | Insatisfatorio |
|----------|------|-----------|--------------|----------------|
| Query analitica | 15% | Sintaxe correta, logica clara, resultado coerente | 1 erro menor de sintaxe ou logica | Erro grave ou nao executa |
| Window functions | 20% | Uso correto de PARTITION BY e ORDER BY | Uso parcial ou ordenacao errada | Nao usou window function |
| Feature engineering | 30% | 8+ features criadas, todas justificadas | 5-7 features, algumas genericas | < 5 features ou sem justificativa |
| Qualidade de dados | 20% | 4 queries de qualidade funcionando | 2-3 queries funcionando | < 2 queries |
| Documentacao | 15% | SQL comentado, explicacao clara do modelo de IA | SQL com comentarios basicos | SQL sem comentarios |

---

## Material de Apoio

- Aula 3 — Slides de SQL Avancado e Preparacao de Dados
- Documento base: `Projeto-Eng-Dados-IA-para-Negocio.md` (Secoes 3 e 7)
- Notebook de seed: `lodlog_lab3_seed.py` (execute antes do lab)
- Cheat sheet de Window Functions (Spark SQL): <https://spark.apache.org/docs/latest/sql-ref-functions-builtin.html>
- Visualizacoes no Databricks: <https://docs.databricks.com/en/visualizations/index.html>

---

> **Dica do Professor:** SQL nao e apenas uma linguagem de consulta — e a principal ferramenta de feature engineering em pipelines de dados tradicionais. Muitos modelos de ML em producao sao alimentados por views SQL materializadas diariamente. Domine o SQL antes de partir para PySpark ou Pandas.
