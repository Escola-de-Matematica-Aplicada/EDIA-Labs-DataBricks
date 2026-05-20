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
--   · CHECK constraints são ENFORCED pelo Delta Lake
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
  segmento      STRING    NOT NULL,
  email         STRING,
  telefone      STRING,
  data_cadastro DATE      NOT NULL,
  ativo         BOOLEAN   NOT NULL,
  CONSTRAINT chk_cliente_segmento
    CHECK (segmento IN ('Varejista','Industrial','Atacadista','Outro'))
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
  tipo        STRING  NOT NULL,
  CONSTRAINT chk_endereco_tipo CHECK (tipo IN ('Entrega','Cobrança','Principal'))
)
USING DELTA;

CREATE TABLE IF NOT EXISTS lodlog_op.contrato (
  contrato_id          BIGINT      NOT NULL,
  cliente_id           BIGINT      NOT NULL,  -- FK → cliente
  numero_contrato      STRING      NOT NULL,
  data_inicio          DATE        NOT NULL,
  data_fim             DATE,
  sla_pontualidade_pct DECIMAL(5,2) NOT NULL,
  multa_atraso_pct     DECIMAL(5,2) NOT NULL,
  status               STRING      NOT NULL,
  CONSTRAINT chk_contrato_sla    CHECK (sla_pontualidade_pct BETWEEN 0 AND 100),
  CONSTRAINT chk_contrato_multa  CHECK (multa_atraso_pct >= 0),
  CONSTRAINT chk_contrato_status CHECK (status IN ('Ativo','Encerrado','Suspenso'))
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
  ano_fabricacao SMALLINT    NOT NULL,
  tipo           STRING      NOT NULL,
  capacidade_kg  DECIMAL(10,2) NOT NULL,
  hodometro_km   DECIMAL(10,0) NOT NULL,
  data_aquisicao DATE,
  status         STRING      NOT NULL,
  CONSTRAINT chk_veiculo_ano        CHECK (ano_fabricacao >= 1990),
  CONSTRAINT chk_veiculo_tipo       CHECK (tipo IN ('Leve','Médio','Pesado')),
  CONSTRAINT chk_veiculo_capacidade CHECK (capacidade_kg > 0),
  CONSTRAINT chk_veiculo_hodometro  CHECK (hodometro_km >= 0),
  CONSTRAINT chk_veiculo_status     CHECK (status IN ('Disponível','Em Rota','Manutenção','Inativo'))
)
USING DELTA;

CREATE TABLE IF NOT EXISTS lodlog_op.motorista (
  motorista_id     BIGINT   NOT NULL,
  cpf              STRING   NOT NULL,  -- UNIQUE
  nome_completo    STRING   NOT NULL,
  cnh              STRING   NOT NULL,  -- UNIQUE
  categoria_cnh    STRING   NOT NULL,
  validade_cnh     DATE     NOT NULL,
  data_admissao    DATE     NOT NULL,
  score_seguranca  DECIMAL(5,2),
  status           STRING   NOT NULL,
  CONSTRAINT chk_motorista_cnh    CHECK (categoria_cnh IN ('A','B','C','D','E','AB','AC','AD','AE')),
  CONSTRAINT chk_motorista_score  CHECK (score_seguranca IS NULL OR score_seguranca BETWEEN 0 AND 100),
  CONSTRAINT chk_motorista_status CHECK (status IN ('Ativo','Afastado','Desligado'))
)
USING DELTA;

CREATE TABLE IF NOT EXISTS lodlog_op.manutencao (
  manutencao_id   BIGINT        NOT NULL,
  veiculo_id      BIGINT        NOT NULL,  -- FK → veiculo
  tipo            STRING        NOT NULL,
  data_abertura   TIMESTAMP     NOT NULL,
  data_conclusao  TIMESTAMP,
  km_no_momento   DECIMAL(10,0) NOT NULL,
  custo_total     DECIMAL(12,2),
  descricao       STRING,
  status          STRING        NOT NULL,
  CONSTRAINT chk_manut_tipo   CHECK (tipo IN ('Preventiva','Corretiva','Preditiva')),
  CONSTRAINT chk_manut_km     CHECK (km_no_momento >= 0),
  CONSTRAINT chk_manut_custo  CHECK (custo_total IS NULL OR custo_total >= 0),
  CONSTRAINT chk_manut_status CHECK (status IN ('Aberta','Em Execução','Concluída'))
)
USING DELTA;

-- Alta frequência: ~864k eventos/dia — particionada por data para eficiência
CREATE TABLE IF NOT EXISTS lodlog_op.telemetria (
  telemetria_id         BIGINT        NOT NULL,
  veiculo_id            BIGINT        NOT NULL,  -- FK → veiculo
  timestamp_evento      TIMESTAMP     NOT NULL,
  latitude              DECIMAL(9,6)  NOT NULL,
  longitude             DECIMAL(9,6)  NOT NULL,
  velocidade_kmh        DECIMAL(6,2)  NOT NULL,
  rpm_motor             INT,
  temperatura_motor_c   DECIMAL(6,2),
  nivel_combustivel_pct DECIMAL(5,2),
  peso_carga_kg         DECIMAL(10,2),
  hodometro_km          DECIMAL(10,0),
  CONSTRAINT chk_telem_vel   CHECK (velocidade_kmh BETWEEN 0 AND 200),
  CONSTRAINT chk_telem_rpm   CHECK (rpm_motor IS NULL OR rpm_motor BETWEEN 0 AND 8000),
  CONSTRAINT chk_telem_temp  CHECK (temperatura_motor_c IS NULL OR temperatura_motor_c BETWEEN -50 AND 200),
  CONSTRAINT chk_telem_comb  CHECK (nivel_combustivel_pct IS NULL OR nivel_combustivel_pct BETWEEN 0 AND 100),
  CONSTRAINT chk_telem_peso  CHECK (peso_carga_kg IS NULL OR peso_carga_kg >= 0)
)
USING DELTA
PARTITIONED BY (DATE(timestamp_evento))  -- partition pruning nas queries por período
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
  capacidade_m3 DECIMAL(10,2) NOT NULL,
  ativo         BOOLEAN       NOT NULL,
  CONSTRAINT chk_cd_capacidade CHECK (capacidade_m3 > 0)
)
USING DELTA;

CREATE TABLE IF NOT EXISTS lodlog_op.produto (
  produto_id         BIGINT        NOT NULL,
  sku                STRING        NOT NULL,  -- UNIQUE
  nome               STRING        NOT NULL,
  categoria          STRING        NOT NULL,
  peso_unitario_kg   DECIMAL(10,3) NOT NULL,
  volume_unitario_m3 DECIMAL(10,4),
  ativo              BOOLEAN       NOT NULL,
  CONSTRAINT chk_produto_peso   CHECK (peso_unitario_kg > 0),
  CONSTRAINT chk_produto_volume CHECK (volume_unitario_m3 IS NULL OR volume_unitario_m3 > 0)
)
USING DELTA;

-- Posição atual do estoque por combinação (cd_id, produto_id)
CREATE TABLE IF NOT EXISTS lodlog_op.estoque (
  estoque_id            BIGINT NOT NULL,
  cd_id                 BIGINT NOT NULL,  -- FK → centro_distribuicao
  produto_id            BIGINT NOT NULL,  -- FK → produto
  quantidade_disponivel INT    NOT NULL,
  quantidade_reservada  INT    NOT NULL,
  posicao_galpao        STRING,
  ultima_atualizacao    TIMESTAMP NOT NULL,
  CONSTRAINT chk_estoque_disp CHECK (quantidade_disponivel >= 0),
  CONSTRAINT chk_estoque_res  CHECK (quantidade_reservada >= 0)
)
USING DELTA;

-- Log de cada movimentação — estoque atual é derivado desse histórico
CREATE TABLE IF NOT EXISTS lodlog_op.movimentacao_estoque (
  movimentacao_id BIGINT    NOT NULL,
  estoque_id      BIGINT    NOT NULL,  -- FK → estoque
  tipo_mov        STRING    NOT NULL,
  quantidade      INT       NOT NULL,
  timestamp_mov   TIMESTAMP NOT NULL,
  referencia      STRING,              -- pedido_id, NF, etc.
  observacao      STRING,
  CONSTRAINT chk_mov_tipo CHECK (tipo_mov IN ('Entrada','Saída','Reserva','Liberação','Ajuste'))
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
  prazo_entrega       TIMESTAMP NOT NULL,
  prioridade          STRING    NOT NULL,
  status_pedido       STRING    NOT NULL,
  CONSTRAINT chk_pedido_prioridade CHECK (prioridade IN ('Baixa','Normal','Alta','Urgente')),
  CONSTRAINT chk_pedido_status     CHECK (status_pedido IN ('Aberto','Em Separação','Despachado','Entregue','Cancelado')),
  CONSTRAINT chk_pedido_prazo      CHECK (prazo_entrega > data_pedido)
)
USING DELTA;

-- Tabela de associação Pedido ↔ Produto (N:M) com atributos próprios
CREATE TABLE IF NOT EXISTS lodlog_op.item_pedido (
  item_id       BIGINT        NOT NULL,
  pedido_id     BIGINT        NOT NULL,  -- FK → pedido
  produto_id    BIGINT        NOT NULL,  -- FK → produto
  quantidade    INT           NOT NULL,
  peso_total_kg DECIMAL(10,2) NOT NULL,
  CONSTRAINT chk_item_qtd  CHECK (quantidade > 0),
  CONSTRAINT chk_item_peso CHECK (peso_total_kg > 0)
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
  distancia_km          DECIMAL(10,2) NOT NULL,
  custo_combustivel     DECIMAL(12,2),
  custo_pedagio         DECIMAL(12,2),
  valor_frete           DECIMAL(12,2) NOT NULL,
  multa_atraso          DECIMAL(12,2),
  status_entrega        STRING        NOT NULL,
  CONSTRAINT chk_entrega_dist    CHECK (distancia_km > 0),
  CONSTRAINT chk_entrega_frete   CHECK (valor_frete > 0),
  CONSTRAINT chk_entrega_comb    CHECK (custo_combustivel IS NULL OR custo_combustivel >= 0),
  CONSTRAINT chk_entrega_pedagio CHECK (custo_pedagio IS NULL OR custo_pedagio >= 0),
  CONSTRAINT chk_entrega_multa   CHECK (multa_atraso IS NULL OR multa_atraso >= 0),
  CONSTRAINT chk_entrega_status  CHECK (status_entrega IN ('Pendente','Em Rota','Entregue','Ocorrência','Devolvido'))
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
  dia              SMALLINT NOT NULL,
  mes              SMALLINT NOT NULL,
  ano              SMALLINT NOT NULL,
  trimestre        SMALLINT NOT NULL,
  semana_do_ano    SMALLINT NOT NULL,
  dia_da_semana    SMALLINT NOT NULL,  -- 1=Seg ... 7=Dom
  nome_dia_semana  STRING  NOT NULL,
  nome_mes         STRING  NOT NULL,
  flag_feriado     BOOLEAN NOT NULL,
  flag_fim_semana  BOOLEAN NOT NULL,
  descricao_feriado STRING,
  CONSTRAINT chk_tempo_dia      CHECK (dia BETWEEN 1 AND 31),
  CONSTRAINT chk_tempo_mes      CHECK (mes BETWEEN 1 AND 12),
  CONSTRAINT chk_tempo_trim     CHECK (trimestre BETWEEN 1 AND 4),
  CONSTRAINT chk_tempo_semana   CHECK (semana_do_ano BETWEEN 1 AND 53),
  CONSTRAINT chk_tempo_diasem   CHECK (dia_da_semana BETWEEN 1 AND 7)
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
  regiao                     STRING  NOT NULL,
  tempo_relacionamento_meses INT     NOT NULL,
  sla_contratual_pct         DECIMAL(5,2),
  -- campos SCD Tipo 2: rastreiam versões históricas do registro
  data_inicio_vigencia       DATE    NOT NULL,
  data_fim_vigencia          DATE,                -- NULL = registro atual
  flag_registro_atual        BOOLEAN NOT NULL,
  CONSTRAINT chk_cli_regiao CHECK (regiao IN ('Norte','Nordeste','Centro-Oeste','Sudeste','Sul')),
  CONSTRAINT chk_cli_tempo  CHECK (tempo_relacionamento_meses >= 0)
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
  faixa_capacidade     STRING      NOT NULL,
  data_inicio_vigencia DATE        NOT NULL,
  data_fim_vigencia    DATE,
  flag_registro_atual  BOOLEAN     NOT NULL,
  CONSTRAINT chk_veic_faixa CHECK (faixa_capacidade IN ('Até 1t','1-5t','5-15t','Acima 15t'))
)
USING DELTA;

-- DIM_MOTORISTA — SCD Tipo 2 (score e experiência evoluem)
CREATE TABLE IF NOT EXISTS lodlog_dw.dim_motorista (
  sk_motorista         BIGINT   NOT NULL,
  motorista_id         BIGINT   NOT NULL,
  nome_completo        STRING   NOT NULL,
  categoria_cnh        STRING   NOT NULL,
  tempo_empresa_meses  INT      NOT NULL,
  faixa_experiencia    STRING   NOT NULL,
  score_seguranca      DECIMAL(5,2),
  data_inicio_vigencia DATE     NOT NULL,
  data_fim_vigencia    DATE,
  flag_registro_atual  BOOLEAN  NOT NULL,
  CONSTRAINT chk_mot_faixa CHECK (faixa_experiencia IN ('Júnior','Pleno','Sênior')),
  CONSTRAINT chk_mot_tempo  CHECK (tempo_empresa_meses >= 0),
  CONSTRAINT chk_mot_score  CHECK (score_seguranca IS NULL OR score_seguranca BETWEEN 0 AND 100)
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
  regiao        STRING        NOT NULL,
  capacidade_m3 DECIMAL(10,2) NOT NULL,
  latitude      DECIMAL(9,6),
  longitude     DECIMAL(9,6),
  CONSTRAINT chk_cd_regiao CHECK (regiao IN ('Norte','Nordeste','Centro-Oeste','Sudeste','Sul'))
)
USING DELTA;

-- FATO_ENTREGAS — tabela central do Star Schema
-- 1 linha por entrega realizada
-- indicador_atraso = variável-alvo (target) do modelo de classificação
CREATE TABLE IF NOT EXISTS lodlog_dw.fato_entregas (
  sk_entrega           BIGINT  NOT NULL,  -- PK surrogate

  -- Surrogate keys das dimensões
  sk_data_saida        INT     NOT NULL,  -- FK → dim_tempo
  sk_data_entrega      INT,               -- FK → dim_tempo (NULL se ainda em rota)
  sk_cliente           BIGINT  NOT NULL,  -- FK → dim_cliente
  sk_cd_origem         BIGINT  NOT NULL,  -- FK → dim_centro_distribuicao
  sk_cd_destino_regiao BIGINT,            -- FK → dim_centro_distribuicao (CD mais próximo do destino)
  sk_veiculo           BIGINT  NOT NULL,  -- FK → dim_veiculo
  sk_motorista         BIGINT  NOT NULL,  -- FK → dim_motorista

  -- Chaves naturais degeneradas (sem dimensão própria, para rastreabilidade)
  entrega_id           BIGINT  NOT NULL,
  pedido_id            BIGINT  NOT NULL,

  -- Métricas aditivas (somáveis em qualquer combinação de dimensões)
  quantidade_volumes   INT           NOT NULL,
  peso_total_kg        DECIMAL(10,2) NOT NULL,
  distancia_km         DECIMAL(10,2) NOT NULL,
  tempo_estimado_min   INT           NOT NULL,
  tempo_real_min       INT,
  custo_combustivel    DECIMAL(12,2) NOT NULL,
  custo_pedagio        DECIMAL(12,2) NOT NULL,
  valor_frete          DECIMAL(12,2) NOT NULL,
  multa_atraso         DECIMAL(12,2) NOT NULL,

  -- Métricas derivadas
  minutos_atraso       INT     NOT NULL,  -- 0 = no prazo | >0 = quantos min atrasou
  indicador_atraso     SMALLINT NOT NULL, -- 0 = pontual | 1 = atrasado  ← TARGET ML

  CONSTRAINT chk_fato_volumes  CHECK (quantidade_volumes >= 0),
  CONSTRAINT chk_fato_peso     CHECK (peso_total_kg > 0),
  CONSTRAINT chk_fato_dist     CHECK (distancia_km > 0),
  CONSTRAINT chk_fato_testamp  CHECK (tempo_estimado_min > 0),
  CONSTRAINT chk_fato_frete    CHECK (valor_frete > 0),
  CONSTRAINT chk_fato_atraso   CHECK (indicador_atraso IN (0, 1))
)
USING DELTA
COMMENT 'Fato entregas — granularidade: 1 linha por entrega. indicador_atraso é o target do modelo de predição.';


-- ================================================================
-- CÉLULA 7 — Dados de exemplo (seed)
-- Necessário para queries do LAB 3 funcionarem
-- ================================================================

-- dim_tempo: primeiros dias de julho/2025
INSERT INTO lodlog_dw.dim_tempo VALUES
(20250701,'2025-07-01', 1,7,2025,3,27,2,'Terça-feira', 'Julho',false,false,NULL),
(20250702,'2025-07-02', 2,7,2025,3,27,3,'Quarta-feira','Julho',false,false,NULL),
(20250703,'2025-07-03', 3,7,2025,3,27,4,'Quinta-feira','Julho',false,false,NULL),
(20250704,'2025-07-04', 4,7,2025,3,27,5,'Sexta-feira', 'Julho',false,false,NULL),
(20250705,'2025-07-05', 5,7,2025,3,27,6,'Sábado',      'Julho',false,true, NULL),
(20250706,'2025-07-06', 6,7,2025,3,27,7,'Domingo',     'Julho',false,true, NULL),
(20250707,'2025-07-07', 7,7,2025,3,28,1,'Segunda-feira','Julho',false,false,NULL),
(20250714,'2025-07-14',14,7,2025,3,29,1,'Segunda-feira','Julho',false,false,NULL),
(20250715,'2025-07-15',15,7,2025,3,29,2,'Terça-feira', 'Julho',false,false,NULL),
(20250716,'2025-07-16',16,7,2025,3,29,3,'Quarta-feira','Julho',false,false,NULL);

-- lodlog_op: centros de distribuição
INSERT INTO lodlog_op.centro_distribuicao VALUES
(1,'CD-CAMPINAS',    'CD Campinas',        'Campinas',       'SP','13010000',-22.9068,-47.0626,15000.00,true),
(2,'CD-SAO-PAULO',   'CD São Paulo Norte', 'São Paulo',      'SP','02000000',-23.4500,-46.6233, 8000.00,true),
(3,'CD-BELO-HORIZONTE','CD Belo Horizonte','Belo Horizonte', 'MG','30130000',-19.9167,-43.9345, 6000.00,true),
(4,'CD-CURITIBA',    'CD Curitiba',        'Curitiba',       'PR','80010000',-25.4290,-49.2710, 5500.00,true),
(5,'CD-PORTO-ALEGRE','CD Porto Alegre',    'Porto Alegre',   'RS','90010000',-30.0346,-51.2177, 4000.00,true);

-- lodlog_op: clientes
INSERT INTO lodlog_op.cliente VALUES
(1,'12345678000191','Rede Varejo Brasil S.A.',  'Varejo Brasil','Varejista', 'compras@varejo.com.br',  NULL,'2020-01-15',true),
(2,'98765432000100','Indústria Metal Sul Ltda.', 'Metal Sul',   'Industrial','logistica@metalsul.com.br',NULL,'2022-03-01',true),
(3,'11223344000155','Atacado Centro-Oeste S.A.','Atacadão CO',  'Atacadista','pedidos@atacadao.com.br', NULL,'2024-06-10',true);

-- lodlog_op: endereços
INSERT INTO lodlog_op.endereco_cliente VALUES
(1,1,'Av. Paulista','1000',NULL,'Bela Vista','São Paulo',     'SP','01310100',-23.5630,-46.6544,'Entrega'),
(2,2,'Rod. BR-116', 'km 5',NULL,'Industrial','Belo Horizonte','MG','30640060',-19.8800,-43.9600,'Entrega'),
(3,3,'Av. Goiás',   '500', NULL,'Centro',    'Goiânia',       'GO','74010050',-16.6869,-49.2648,'Entrega');

-- lodlog_op: contratos
INSERT INTO lodlog_op.contrato VALUES
(1,1,'CTR-2025-001','2025-01-01',NULL,95.00,2.50,'Ativo'),
(2,2,'CTR-2025-002','2025-03-01',NULL,92.00,1.80,'Ativo'),
(3,3,'CTR-2025-003','2025-06-01',NULL,90.00,1.50,'Ativo');

-- lodlog_op: veículos
INSERT INTO lodlog_op.veiculo VALUES
(1,'ABC1D23','Actros 2651',  'Mercedes-Benz',2022,'Pesado',23000, 87400,'2022-03-15','Disponível'),
(2,'DEF4E56','Cargo 2429',   'Ford',         2021,'Pesado',18000,120000,'2021-07-01','Em Rota'),
(3,'GHI7F89','Sprinter 416', 'Mercedes-Benz',2023,'Leve',   3500, 34000,'2023-01-20','Disponível'),
(4,'JKL2G34','Daily 70-170', 'Iveco',        2020,'Médio',  7000, 98000,'2020-09-10','Manutenção'),
(5,'MNO5H67','VOLARE W9',    'Volkswagen',   2022,'Médio',  6500, 54000,'2022-05-05','Em Rota');

-- lodlog_op: motoristas
INSERT INTO lodlog_op.motorista VALUES
(1,'11122233344','João da Silva Santos',   'CNH00001','E', '2027-06-30','2018-03-15',92.50,'Ativo'),
(2,'22233344455','Maria Oliveira Costa',   'CNH00002','E', '2026-11-30','2020-07-01',88.00,'Ativo'),
(3,'33344455566','Carlos Eduardo Pereira', 'CNH00003','D', '2025-09-30','2022-01-10',79.50,'Ativo'),
(4,'44455566677','Ana Paula Rodrigues',    'CNH00004','C', '2028-03-15','2023-05-20',95.00,'Ativo'),
(5,'55566677788','Roberto Nascimento Jr.', 'CNH00005','E', '2026-07-31','2015-11-08',85.75,'Ativo');

-- lodlog_op: produtos
INSERT INTO lodlog_op.produto VALUES
(1,'ELE-TV-55P', 'Smart TV 55 pol.',      'Eletrônicos',  14.000,0.1200,true),
(2,'ALI-AZT-5K', 'Açúcar Refinado 5kg',  'Alimentos',     5.000,0.0060,true),
(3,'FAR-MED-001','Medicamento Genérico A','Farmacêutico',  0.250,0.0002,true),
(4,'IND-ACO-12M','Barra de Aço 12m',      'Industrial',   85.000,0.0100,true);

-- lodlog_op: estoque no CD Campinas (cd_id=1)
INSERT INTO lodlog_op.estoque VALUES
(1,1,1,142, 38,'A-12-3','2025-07-14 11:00:00'),
(2,1,2,500,100,'B-05-1','2025-07-14 11:00:00'),
(3,1,3,2000,450,'C-01-7','2025-07-14 11:00:00'),
(4,1,4, 30,  5,'D-03-2','2025-07-14 11:00:00');

-- lodlog_op: pedidos
INSERT INTO lodlog_op.pedido VALUES
(1,'PED-2025-084321',1,1,1,1,'2025-07-14 08:00:00','2025-07-15 18:00:00','Alta',   'Entregue'),
(2,'PED-2025-084322',2,2,1,2,'2025-07-14 09:30:00','2025-07-16 12:00:00','Normal', 'Entregue'),
(3,'PED-2025-084323',3,3,1,3,'2025-07-14 11:00:00','2025-07-17 18:00:00','Baixa',  'Despachado');

-- lodlog_op: itens dos pedidos
INSERT INTO lodlog_op.item_pedido VALUES
(1,1,1,10,140.00),
(2,1,2,50,250.00),
(3,2,4, 5,425.00),
(4,3,3,200, 50.00);

-- lodlog_op: entregas
INSERT INTO lodlog_op.entrega VALUES
(1,1,1,1,'2025-07-14 14:00:00','2025-07-15 17:30:00','2025-07-15 19:15:00', 98.4,185.00, 42.00,1250.00, 31.25,'Entregue'),
(2,2,2,2,'2025-07-14 15:30:00','2025-07-16 11:00:00','2025-07-16 10:45:00',490.0,620.00,130.00,3800.00,  0.00,'Entregue'),
(3,3,5,5,'2025-07-15 06:00:00','2025-07-17 16:00:00',NULL,                 900.0,950.00,200.00,5200.00,  0.00,'Em Rota');

-- lodlog_dw: dim_centro_distribuicao
INSERT INTO lodlog_dw.dim_centro_distribuicao VALUES
(1,1,'CD-CAMPINAS',    'CD Campinas',        'Campinas',       'SP','Sudeste',15000.00,-22.9068,-47.0626),
(2,2,'CD-SAO-PAULO',   'CD São Paulo Norte', 'São Paulo',      'SP','Sudeste', 8000.00,-23.4500,-46.6233),
(3,3,'CD-BELO-HORIZONTE','CD Belo Horizonte','Belo Horizonte', 'MG','Sudeste', 6000.00,-19.9167,-43.9345),
(4,4,'CD-CURITIBA',    'CD Curitiba',        'Curitiba',       'PR','Sul',     5500.00,-25.4290,-49.2710),
(5,5,'CD-PORTO-ALEGRE','CD Porto Alegre',    'Porto Alegre',   'RS','Sul',     4000.00,-30.0346,-51.2177);

-- lodlog_dw: dim_cliente (SCD Tipo 2 — 1 versão inicial por cliente)
INSERT INTO lodlog_dw.dim_cliente VALUES
(1,1,'12345678000191','Rede Varejo Brasil S.A.',   'Varejista', 'São Paulo',     'SP','Sudeste',      54,95.00,'2025-01-01',NULL,true),
(2,2,'98765432000100','Indústria Metal Sul Ltda.',  'Industrial','Belo Horizonte','MG','Sudeste',      28,92.00,'2025-01-01',NULL,true),
(3,3,'11223344000155','Atacado Centro-Oeste S.A.', 'Atacadista','Goiânia',       'GO','Centro-Oeste', 12,90.00,'2025-01-01',NULL,true);

-- lodlog_dw: dim_veiculo
INSERT INTO lodlog_dw.dim_veiculo VALUES
(1,1,'ABC1D23','Actros 2651',  'Mercedes-Benz',2022,'Pesado',23000,'Acima 15t','2025-01-01',NULL,true),
(2,2,'DEF4E56','Cargo 2429',   'Ford',         2021,'Pesado',18000,'Acima 15t','2025-01-01',NULL,true),
(3,3,'GHI7F89','Sprinter 416', 'Mercedes-Benz',2023,'Leve',   3500,'1-5t',     '2025-01-01',NULL,true),
(4,4,'JKL2G34','Daily 70-170', 'Iveco',        2020,'Médio',  7000,'5-15t',    '2025-01-01',NULL,true),
(5,5,'MNO5H67','VOLARE W9',    'Volkswagen',   2022,'Médio',  6500,'5-15t',    '2025-01-01',NULL,true);

-- lodlog_dw: dim_motorista
INSERT INTO lodlog_dw.dim_motorista VALUES
(1,1,'João da Silva Santos',   'E', 88,'Sênior',92.50,'2025-01-01',NULL,true),
(2,2,'Maria Oliveira Costa',   'E', 60,'Sênior',88.00,'2025-01-01',NULL,true),
(3,3,'Carlos Eduardo Pereira', 'D', 41,'Pleno', 79.50,'2025-01-01',NULL,true),
(4,4,'Ana Paula Rodrigues',    'C', 25,'Júnior',95.00,'2025-01-01',NULL,true),
(5,5,'Roberto Nascimento Jr.', 'E',126,'Sênior',85.75,'2025-01-01',NULL,true);

-- lodlog_dw: fato_entregas (2 linhas concluídas; entrega 3 ainda em rota)
INSERT INTO lodlog_dw.fato_entregas VALUES
-- entrega 1: atrasada 105 min (multa aplicada)
(1, 20250714,20250715, 1,1,2, 1,1, 1,1,  34, 390.00,  98.4, 450,555, 185.00, 42.00,1250.00, 31.25, 105,1),
-- entrega 2: 15 min adiantada (indicador_atraso=0)
(2, 20250714,20250716, 2,1,3, 2,2, 2,2,  12, 425.00, 490.0, 780,765, 620.00,130.00,3800.00,  0.00,   0,0);


-- ================================================================
-- CÉLULA 8 — OPTIMIZE (rodar após carga de dados)
-- Equivalente ao CREATE INDEX do PostgreSQL no Delta Lake
-- ZORDER coloca dados relacionados fisicamente próximos no Parquet
-- ================================================================

-- OLTP: buscas por status e data de entrega
OPTIMIZE lodlog_op.entrega      ZORDER BY (status_entrega, data_saida);
OPTIMIZE lodlog_op.pedido       ZORDER BY (cliente_id, status_pedido);
OPTIMIZE lodlog_op.telemetria   ZORDER BY (veiculo_id, timestamp_evento);

-- DW: queries de agregação por tempo, CD e cliente
OPTIMIZE lodlog_dw.fato_entregas ZORDER BY (sk_data_saida, sk_cd_origem, indicador_atraso);
OPTIMIZE lodlog_dw.dim_tempo     ZORDER BY (sk_tempo);


-- ================================================================
-- CÉLULA 9 — VIEWS analíticas
-- ================================================================

-- KPI de pontualidade por CD e mês
CREATE OR REPLACE VIEW lodlog_dw.v_kpi_entrega_cd_mes AS
SELECT
  t.ano,
  t.mes,
  t.nome_mes,
  cd.nome                                              AS cd_origem,
  cd.regiao,
  COUNT(*)                                             AS total_entregas,
  SUM(f.indicador_atraso)                              AS total_atrasos,
  ROUND(100.0 * SUM(f.indicador_atraso) / COUNT(*), 2) AS pct_atraso,
  ROUND(AVG(f.distancia_km), 1)                        AS distancia_media_km,
  ROUND(AVG(f.valor_frete), 2)                         AS ticket_medio_frete,
  SUM(f.multa_atraso)                                  AS total_multas
FROM lodlog_dw.fato_entregas                    f
JOIN lodlog_dw.dim_tempo                        t  ON f.sk_data_saida = t.sk_tempo
JOIN lodlog_dw.dim_centro_distribuicao          cd ON f.sk_cd_origem  = cd.sk_cd
GROUP BY t.ano, t.mes, t.nome_mes, cd.nome, cd.regiao;

-- Feature store para modelo de predição de atraso (LAB 3 / ML)
CREATE OR REPLACE VIEW lodlog_dw.v_features_ml AS
SELECT
  f.sk_entrega,
  f.indicador_atraso,                        -- TARGET (variável-alvo)
  f.distancia_km,
  f.peso_total_kg,
  f.tempo_estimado_min,
  t.dia_da_semana,
  CAST(t.flag_feriado    AS INT) AS flag_feriado,     -- Spark: CAST em vez de ::INT
  CAST(t.flag_fim_semana AS INT) AS flag_fim_semana,
  v.tipo                         AS tipo_veiculo,
  v.faixa_capacidade,
  m.faixa_experiencia            AS experiencia_motorista,
  m.score_seguranca,
  cl.segmento                    AS segmento_cliente,
  cl.regiao                      AS regiao_cliente,
  cd.regiao                      AS regiao_cd_origem
FROM lodlog_dw.fato_entregas                    f
JOIN lodlog_dw.dim_tempo                        t  ON f.sk_data_saida = t.sk_tempo
JOIN lodlog_dw.dim_veiculo                      v  ON f.sk_veiculo    = v.sk_veiculo    AND v.flag_registro_atual = true
JOIN lodlog_dw.dim_motorista                    m  ON f.sk_motorista  = m.sk_motorista  AND m.flag_registro_atual = true
JOIN lodlog_dw.dim_cliente                      cl ON f.sk_cliente    = cl.sk_cliente   AND cl.flag_registro_atual = true
JOIN lodlog_dw.dim_centro_distribuicao          cd ON f.sk_cd_origem  = cd.sk_cd;


-- ================================================================
-- CÉLULA 10 — Queries de validação (rodar para checar o modelo)
-- ================================================================

-- Verifica totais de cada tabela OLTP
SELECT 'cliente'              AS tabela, COUNT(*) AS linhas FROM lodlog_op.cliente              UNION ALL
SELECT 'veiculo',                        COUNT(*)           FROM lodlog_op.veiculo               UNION ALL
SELECT 'motorista',                      COUNT(*)           FROM lodlog_op.motorista             UNION ALL
SELECT 'centro_distribuicao',            COUNT(*)           FROM lodlog_op.centro_distribuicao   UNION ALL
SELECT 'produto',                        COUNT(*)           FROM lodlog_op.produto               UNION ALL
SELECT 'pedido',                         COUNT(*)           FROM lodlog_op.pedido                UNION ALL
SELECT 'entrega',                        COUNT(*)           FROM lodlog_op.entrega;

-- Verifica totais do DW
SELECT 'dim_tempo'               AS tabela, COUNT(*) AS linhas FROM lodlog_dw.dim_tempo               UNION ALL
SELECT 'dim_cliente',                        COUNT(*)           FROM lodlog_dw.dim_cliente             UNION ALL
SELECT 'dim_veiculo',                        COUNT(*)           FROM lodlog_dw.dim_veiculo             UNION ALL
SELECT 'dim_motorista',                      COUNT(*)           FROM lodlog_dw.dim_motorista           UNION ALL
SELECT 'dim_centro_distribuicao',            COUNT(*)           FROM lodlog_dw.dim_centro_distribuicao UNION ALL
SELECT 'fato_entregas',                      COUNT(*)           FROM lodlog_dw.fato_entregas;

-- KPI de entrega (responde pergunta 1 da Parte 3 do LAB 2)
SELECT * FROM lodlog_dw.v_kpi_entrega_cd_mes ORDER BY ano, mes, cd_origem;

-- ================================================================
-- FIM DO SCRIPT
-- ================================================================
