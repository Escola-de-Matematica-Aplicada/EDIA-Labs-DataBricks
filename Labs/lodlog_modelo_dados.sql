-- ================================================================
-- LODLog Transportes e Distribuição S.A.
-- Modelo de Dados Completo — LAB 2 (Scaffold / Gabarito)
-- Databricks SQL · Delta Lake · Community Edition compatible
-- ================================================================
-- COMO USAR:
--   1. Abra um notebook SQL no Databricks (Language: SQL)
--   2. Cole este script inteiro em uma célula  OU
--      divida cada bloco em células separadas (recomendado)
--   3. Execute de cima para baixo
--
-- Diferenças vs PostgreSQL:
--   · SCHEMA → DATABASE  (Databricks Community usa Hive Metastore)
--   · SERIAL/BIGSERIAL → BIGINT  (IDs explícitos nos INSERTs)
--   · REFERENCES → comentários informativos (Delta não força FKs)
--   · CREATE INDEX → OPTIMIZE ... ZORDER BY
--   · VARCHAR/CHAR → STRING
--   · x::INT → CAST(x AS INT)
--   · CHECK constraints → REMOVED (not supported in this Databricks version)
--   · NOT NULL é ENFORCED pelo Delta Lake
-- ================================================================


-- ================================================================
-- CÉLULA 1 — Criar databases (equivalente a schemas)
-- ================================================================

CREATE DATABASE IF NOT EXISTS lodlog_op
  COMMENT 'LODLog — modelo operacional (ER 3FN)';

CREATE DATABASE IF NOT EXISTS lodlog_dw
  COMMENT 'LODLog — modelo analítico (Star Schema DW/ML)';


-- ================================================================
-- CÉLULA 2 — SCHEMA OPERACIONAL (lodlog_op)
-- Domínio CLIENTE
-- ================================================================

CREATE TABLE IF NOT EXISTS lodlog_op.cliente (
  cliente_id    BIGINT    NOT NULL,  -- PK (gerado na aplicação)
  cnpj          STRING    NOT NULL,  -- UNIQUE: não duplicar CNPJ
  razao_social  STRING    NOT NULL,
  nome_fantasia STRING,
  segmento      STRING    NOT NULL,  -- Valores: 'Varejista','Industrial','Atacadista','Outro'
  email         STRING,
  telefone      STRING,
  data_cadastro DATE      NOT NULL,
  ativo         BOOLEAN   NOT NULL
)
USING DELTA
COMMENT 'Cadastro de clientes ativos da LODLog';

-- Separar endereço evita dependência transitiva (3FN):
-- bairro/municipio/uf dependem do CEP, não do cliente_id
CREATE TABLE IF NOT EXISTS lodlog_op.endereco_cliente (
  endereco_id BIGINT  NOT NULL,
  cliente_id  BIGINT  NOT NULL,  -- FK → lodlog_op.cliente.cliente_id
  logradouro  STRING  NOT NULL,
  numero      STRING,
  complemento STRING,
  bairro      STRING  NOT NULL,
  municipio   STRING  NOT NULL,
  uf          STRING  NOT NULL,
  cep         STRING  NOT NULL,
  latitude    DECIMAL(9,6),
  longitude   DECIMAL(9,6),
  tipo        STRING  NOT NULL  -- Valores: 'Entrega','Cobrança','Principal'
)
USING DELTA;

CREATE TABLE IF NOT EXISTS lodlog_op.contrato (
  contrato_id          BIGINT      NOT NULL,
  cliente_id           BIGINT      NOT NULL,  -- FK → cliente
  numero_contrato      STRING      NOT NULL,
  data_inicio          DATE        NOT NULL,
  data_fim             DATE,
  sla_pontualidade_pct DECIMAL(5,2) NOT NULL,  -- 0-100
  multa_atraso_pct     DECIMAL(5,2) NOT NULL,  -- >= 0
  status               STRING      NOT NULL    -- Valores: 'Ativo','Encerrado','Suspenso'
)
USING DELTA;


-- ================================================================
-- CÉLULA 3 — Domínio FROTA
-- ================================================================

CREATE TABLE IF NOT EXISTS lodlog_op.veiculo (
  veiculo_id     BIGINT      NOT NULL,
  placa          STRING      NOT NULL,  -- UNIQUE
  modelo         STRING      NOT NULL,
  fabricante     STRING,
  ano_fabricacao SMALLINT    NOT NULL,  -- >= 1990
  tipo           STRING      NOT NULL,  -- Valores: 'Leve','Médio','Pesado'
  capacidade_kg  DECIMAL(10,2) NOT NULL,  -- > 0
  hodometro_km   DECIMAL(10,0) NOT NULL,  -- >= 0
  data_aquisicao DATE,
  status         STRING      NOT NULL  -- Valores: 'Disponível','Em Rota','Manutenção','Inativo'
)
USING DELTA;

CREATE TABLE IF NOT EXISTS lodlog_op.motorista (
  motorista_id     BIGINT   NOT NULL,
  cpf              STRING   NOT NULL,  -- UNIQUE
  nome_completo    STRING   NOT NULL,
  cnh              STRING   NOT NULL,  -- UNIQUE
  categoria_cnh    STRING   NOT NULL,  -- Valores: 'A','B','C','D','E','AB','AC','AD','AE'
  validade_cnh     DATE     NOT NULL,
  data_admissao    DATE     NOT NULL,
  score_seguranca  DECIMAL(5,2),  -- NULL ou 0-100
  status           STRING   NOT NULL  -- Valores: 'Ativo','Afastado','Desligado'
)
USING DELTA;

CREATE TABLE IF NOT EXISTS lodlog_op.manutencao (
  manutencao_id   BIGINT        NOT NULL,
  veiculo_id      BIGINT        NOT NULL,  -- FK → veiculo
  tipo            STRING        NOT NULL,  -- Valores: 'Preventiva','Corretiva','Preditiva'
  data_abertura   TIMESTAMP     NOT NULL,
  data_conclusao  TIMESTAMP,
  km_no_momento   DECIMAL(10,0) NOT NULL,  -- >= 0
  custo_total     DECIMAL(12,2),  -- NULL ou >= 0
  descricao       STRING,
  status          STRING        NOT NULL  -- Valores: 'Aberta','Em Execução','Concluída'
)
USING DELTA;

-- Alta frequência: ~864k eventos/dia — particionada por data para eficiência
CREATE TABLE IF NOT EXISTS lodlog_op.telemetria (
  telemetria_id         BIGINT        NOT NULL,
  veiculo_id            BIGINT        NOT NULL,  -- FK → veiculo
  timestamp_evento      TIMESTAMP     NOT NULL,
  data_evento           DATE          NOT NULL,  -- Coluna de partição (DATE extraído de timestamp_evento)
  latitude              DECIMAL(9,6)  NOT NULL,
  longitude             DECIMAL(9,6)  NOT NULL,
  velocidade_kmh        DECIMAL(6,2)  NOT NULL,  -- 0-200
  rpm_motor             INT,  -- NULL ou 0-8000
  temperatura_motor_c   DECIMAL(6,2),  -- NULL ou -50 a 200
  nivel_combustivel_pct DECIMAL(5,2),  -- NULL ou 0-100
  peso_carga_kg         DECIMAL(10,2),  -- NULL ou >= 0
  hodometro_km          DECIMAL(10,0)
)
USING DELTA
CLUSTER BY (data_evento, veiculo_id)
COMMENT 'Eventos IoT da frota (~864k/dia). Particionar por data é obrigatório em produção.';


-- ================================================================
-- CÉLULA 4 — Domínio ESTOQUE
-- ================================================================

CREATE TABLE IF NOT EXISTS lodlog_op.centro_distribuicao (
  cd_id         BIGINT        NOT NULL,
  codigo        STRING        NOT NULL,  -- UNIQUE: ex. 'CD-CAMPINAS'
  nome          STRING        NOT NULL,
  municipio     STRING        NOT NULL,
  uf            STRING        NOT NULL,
  cep           STRING        NOT NULL,
  latitude      DECIMAL(9,6)  NOT NULL,
  longitude     DECIMAL(9,6)  NOT NULL,
  capacidade_m3 DECIMAL(10,2) NOT NULL,  -- > 0
  ativo         BOOLEAN       NOT NULL
)
USING DELTA;

CREATE TABLE IF NOT EXISTS lodlog_op.produto (
  produto_id         BIGINT        NOT NULL,
  sku                STRING        NOT NULL,  -- UNIQUE
  nome               STRING        NOT NULL,
  categoria          STRING        NOT NULL,
  peso_unitario_kg   DECIMAL(10,3) NOT NULL,  -- > 0
  volume_unitario_m3 DECIMAL(10,4),  -- NULL ou > 0
  ativo              BOOLEAN       NOT NULL
)
USING DELTA;

-- Posição atual do estoque por combinação (cd_id, produto_id)
CREATE TABLE IF NOT EXISTS lodlog_op.estoque (
  estoque_id            BIGINT NOT NULL,
  cd_id                 BIGINT NOT NULL,  -- FK → centro_distribuicao
  produto_id            BIGINT NOT NULL,  -- FK → produto
  quantidade_disponivel INT    NOT NULL,  -- >= 0
  quantidade_reservada  INT    NOT NULL,  -- >= 0
  posicao_galpao        STRING,
  ultima_atualizacao    TIMESTAMP NOT NULL
)
USING DELTA;

-- Log de cada movimentação — estoque atual é derivado desse histórico
CREATE TABLE IF NOT EXISTS lodlog_op.movimentacao_estoque (
  movimentacao_id BIGINT    NOT NULL,
  estoque_id      BIGINT    NOT NULL,  -- FK → estoque
  tipo_mov        STRING    NOT NULL,  -- Valores: 'Entrada','Saída','Reserva','Liberação','Ajuste'
  quantidade      INT       NOT NULL,
  timestamp_mov   TIMESTAMP NOT NULL,
  referencia      STRING,              -- pedido_id, NF, etc.
  observacao      STRING
)
USING DELTA;


-- ================================================================
-- CÉLULA 5 — Domínio OPERAÇÃO (Pedido / Entrega)
-- ================================================================

CREATE TABLE IF NOT EXISTS lodlog_op.pedido (
  pedido_id           BIGINT    NOT NULL,
  numero_pedido       STRING    NOT NULL,  -- UNIQUE
  cliente_id          BIGINT    NOT NULL,  -- FK → cliente
  contrato_id         BIGINT,             -- FK → contrato (opcional)
  cd_origem_id        BIGINT    NOT NULL,  -- FK → centro_distribuicao
  endereco_destino_id BIGINT    NOT NULL,  -- FK → endereco_cliente
  data_pedido         TIMESTAMP NOT NULL,
  prazo_entrega       TIMESTAMP NOT NULL,  -- > data_pedido
  prioridade          STRING    NOT NULL,  -- Valores: 'Baixa','Normal','Alta','Urgente'
  status_pedido       STRING    NOT NULL  -- Valores: 'Aberto','Em Separação','Despachado','Entregue','Cancelado'
)
USING DELTA;

-- Tabela de associação Pedido ↔ Produto (N:M) com atributos próprios
CREATE TABLE IF NOT EXISTS lodlog_op.item_pedido (
  item_id       BIGINT        NOT NULL,
  pedido_id     BIGINT        NOT NULL,  -- FK → pedido
  produto_id    BIGINT        NOT NULL,  -- FK → produto
  quantidade    INT           NOT NULL,  -- > 0
  peso_total_kg DECIMAL(10,2) NOT NULL  -- > 0
)
USING DELTA;

CREATE TABLE IF NOT EXISTS lodlog_op.entrega (
  entrega_id            BIGINT        NOT NULL,
  pedido_id             BIGINT        NOT NULL,  -- FK → pedido
  veiculo_id            BIGINT        NOT NULL,  -- FK → veiculo
  motorista_id          BIGINT        NOT NULL,  -- FK → motorista
  data_saida            TIMESTAMP     NOT NULL,
  data_entrega_prevista TIMESTAMP     NOT NULL,
  data_entrega_real     TIMESTAMP,
  distancia_km          DECIMAL(10,2) NOT NULL,  -- > 0
  custo_combustivel     DECIMAL(12,2),  -- NULL ou >= 0
  custo_pedagio         DECIMAL(12,2),  -- NULL ou >= 0
  valor_frete           DECIMAL(12,2) NOT NULL,  -- > 0
  multa_atraso          DECIMAL(12,2),  -- NULL ou >= 0
  status_entrega        STRING        NOT NULL  -- Valores: 'Pendente','Em Rota','Entregue','Ocorrência','Devolvido'
)
USING DELTA;


-- ================================================================
-- CÉLULA 6 — SCHEMA ANALÍTICO (lodlog_dw) — Star Schema
-- Granularidade da fato: 1 linha por entrega realizada
-- ================================================================

-- DIM_TEMPO — SK no formato YYYYMMDD (INT), sem IDENTITY
-- Motivo: o valor da SK é também o identificador de negócio (a data)
CREATE TABLE IF NOT EXISTS lodlog_dw.dim_tempo (
  sk_tempo         INT     NOT NULL,  -- PK: ex. 20250714 (YYYYMMDD)
  data_completa    DATE    NOT NULL,
  dia              SMALLINT NOT NULL,  -- 1-31
  mes              SMALLINT NOT NULL,  -- 1-12
  ano              SMALLINT NOT NULL,
  trimestre        SMALLINT NOT NULL,  -- 1-4
  semana_do_ano    SMALLINT NOT NULL,  -- 1-53
  dia_da_semana    SMALLINT NOT NULL,  -- 1=Seg ... 7=Dom
  nome_dia_semana  STRING  NOT NULL,
  nome_mes         STRING  NOT NULL,
  flag_feriado     BOOLEAN NOT NULL,
  flag_fim_semana  BOOLEAN NOT NULL,
  descricao_feriado STRING
)
USING DELTA
COMMENT 'Dimensão tempo — carga feita via script Python (1 linha/dia)';

-- DIM_CLIENTE — SCD Tipo 2 (histórico de mudanças de segmento/SLA)
CREATE TABLE IF NOT EXISTS lodlog_dw.dim_cliente (
  sk_cliente                 BIGINT  NOT NULL,  -- PK surrogate
  cliente_id                 BIGINT  NOT NULL,  -- chave natural (OLTP)
  cnpj                       STRING  NOT NULL,
  razao_social               STRING  NOT NULL,
  segmento                   STRING  NOT NULL,
  municipio                  STRING  NOT NULL,
  uf                         STRING  NOT NULL,
  regiao                     STRING  NOT NULL,  -- Valores: 'Norte','Nordeste','Centro-Oeste','Sudeste','Sul'
  tempo_relacionamento_meses INT     NOT NULL,  -- >= 0
  sla_contratual_pct         DECIMAL(5,2),
  -- campos SCD Tipo 2: rastreiam versões históricas do registro
  data_inicio_vigencia       DATE    NOT NULL,
  data_fim_vigencia          DATE,                -- NULL = registro atual
  flag_registro_atual        BOOLEAN NOT NULL
)
USING DELTA;

-- DIM_VEICULO — SCD Tipo 2 (hodômetro e status mudam)
CREATE TABLE IF NOT EXISTS lodlog_dw.dim_veiculo (
  sk_veiculo           BIGINT      NOT NULL,
  veiculo_id           BIGINT      NOT NULL,
  placa                STRING      NOT NULL,
  modelo               STRING      NOT NULL,
  fabricante           STRING,
  ano_fabricacao       SMALLINT    NOT NULL,
  tipo                 STRING      NOT NULL,
  capacidade_kg        DECIMAL(10,2) NOT NULL,
  faixa_capacidade     STRING      NOT NULL,  -- Valores: 'Até 1t','1-5t','5-15t','Acima 15t'
  data_inicio_vigencia DATE        NOT NULL,
  data_fim_vigencia    DATE,
  flag_registro_atual  BOOLEAN     NOT NULL
)
USING DELTA;

-- DIM_MOTORISTA — SCD Tipo 2 (score e experiência evoluem)
CREATE TABLE IF NOT EXISTS lodlog_dw.dim_motorista (
  sk_motorista         BIGINT   NOT NULL,
  motorista_id         BIGINT   NOT NULL,
  nome_completo        STRING   NOT NULL,
  categoria_cnh        STRING   NOT NULL,
  tempo_empresa_meses  INT      NOT NULL,  -- >= 0
  faixa_experiencia    STRING   NOT NULL,  -- Valores: 'Júnior','Pleno','Sênior'
  score_seguranca      DECIMAL(5,2),  -- NULL ou 0-100
  data_inicio_vigencia DATE     NOT NULL,
  data_fim_vigencia    DATE,
  flag_registro_atual  BOOLEAN  NOT NULL
)
USING DELTA;

-- DIM_CENTRO_DISTRIBUICAO — SCD Tipo 1 (atualiza no lugar, sem histórico)
CREATE TABLE IF NOT EXISTS lodlog_dw.dim_centro_distribuicao (
  sk_cd         BIGINT        NOT NULL,
  cd_id         BIGINT        NOT NULL,  -- chave natural (OLTP)
  codigo        STRING        NOT NULL,
  nome          STRING        NOT NULL,
  municipio     STRING        NOT NULL,
  uf            STRING        NOT NULL,
  regiao        STRING        NOT NULL,  -- Valores: 'Norte','Nordeste','Centro-Oeste','Sudeste','Sul'
  capacidade_m3 DECIMAL(10,2) NOT NULL,
  latitude      DECIMAL(9,6),
  longitude     DECIMAL(9,6)
)
USING DELTA;

-- FATO_ENTREGAS — tabela central do Star Schema
-- 1 linha por entrega realizada
-- indicador_atraso = variável-alvo (target) do modelo de classificação
CREATE TABLE IF NOT EXISTS lodlog_dw.fato_entregas (
  sk_entrega           BIGINT  NOT NULL,  -- PK surrogate
  -- Surrogate keys das dimensões
  sk_data              INT     NOT NULL,  -- FK → dim_tempo
  sk_cliente           BIGINT  NOT NULL,  -- FK → dim_cliente
  sk_cd_origem         BIGINT  NOT NULL,  -- FK → dim_centro_distribuicao
  sk_veiculo           BIGINT  NOT NULL,  -- FK → dim_veiculo
  sk_motorista         BIGINT  NOT NULL,  -- FK → dim_motorista
  -- Chaves naturais degeneradas (sem dimensão própria, para rastreabilidade)
  entrega_id           BIGINT  NOT NULL,
  pedido_id            BIGINT  NOT NULL,
  -- Atributos de data/hora
  data_entrega         DATE,               -- data da entrega (conveniência)
  hora_saida           TIMESTAMP,          -- timestamp completo de saída
-- Métricas aditivas (somáveis em qualquer combinação de dimensões)
  quantidade_volumes   INT           NOT NULL,  -- >= 0
  peso_total_kg        DECIMAL(10,2) NOT NULL,  -- > 0
  distancia_km         DECIMAL(10,2) NOT NULL,  -- > 0
  tempo_estimado_min   INT           NOT NULL,  -- > 0
  tempo_real_min       INT,
  custo_combustivel    DECIMAL(12,2) NOT NULL,
  custo_pedagio        DECIMAL(12,2) NOT NULL,
  valor_frete          DECIMAL(12,2) NOT NULL,  -- > 0
  multa_atraso         DECIMAL(12,2) NOT NULL,
-- Métricas derivadas
  minutos_atraso       INT     NOT NULL,  -- 0 = no prazo | >0 = quantos min atrasou
  indicador_atraso     SMALLINT NOT NULL,  -- 0 = pontual | 1 = atrasado  ← TARGET ML (valores: 0 ou 1)
  temperatura_media_motor DECIMAL(6,2)  -- temperatura média do motor (°C)
)
USING DELTA
COMMENT 'Fato entregas — granularidade: 1 linha por entrega. indicador_atraso é o target do modelo de predição.';
