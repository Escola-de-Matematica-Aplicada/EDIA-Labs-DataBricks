-- ================================================================
-- LODLog — Modelo Relacional em PostgreSQL
-- Conversão de Databricks/Delta Lake para PostgreSQL
-- ================================================================
-- Autor: Converted from Databricks schema
-- Data: 2025
-- Descrição: Sistema de gestão de logística com schema operacional (OLTP)
--            e analítico (DW/Star Schema) para ML
-- ================================================================

-- ================================================================
-- DROP (descomente se precisar limpar ambiente existente)
-- ================================================================
-- DROP SCHEMA IF EXISTS lodlog_dw CASCADE;
-- DROP SCHEMA IF EXISTS lodlog_op CASCADE;


-- ================================================================
-- CRIAÇÃO DOS SCHEMAS
-- ================================================================

CREATE SCHEMA IF NOT EXISTS lodlog_op
  AUTHORIZATION postgres;

COMMENT ON SCHEMA lodlog_op IS
  'LODLog — modelo operacional (ER 3FN / OLTP)';


CREATE SCHEMA IF NOT EXISTS lodlog_dw
  AUTHORIZATION postgres;

COMMENT ON SCHEMA lodlog_dw IS
  'LODLog — modelo analítico (Star Schema DW/ML)';


-- ================================================================
-- SCHEMA OPERACIONAL (lodlog_op)
-- Domínio CLIENTE
-- ================================================================

CREATE TABLE lodlog_op.cliente (
  cliente_id    BIGSERIAL     PRIMARY KEY,
  cnpj          VARCHAR(14)   NOT NULL UNIQUE,
  razao_social  VARCHAR(255)  NOT NULL,
  nome_fantasia VARCHAR(255),
  segmento      VARCHAR(50)   NOT NULL
    CHECK (segmento IN ('Varejista','Industrial','Atacadista','Outro')),
  email         VARCHAR(255),
  telefone      VARCHAR(20),
  data_cadastro DATE          NOT NULL,
  ativo         BOOLEAN       NOT NULL DEFAULT true,
  created_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE lodlog_op.cliente IS
  'Cadastro de clientes ativos da LODLog';

COMMENT ON COLUMN lodlog_op.cliente.cliente_id IS
  'Identificador único do cliente (gerado sequencialmente)';

COMMENT ON COLUMN lodlog_op.cliente.cnpj IS
  'CNPJ único do cliente';


-- Tabela de endereços (separada para evitar dependência transitiva / 3FN)
-- bairro/municipio/uf dependem do CEP, não do cliente_id
CREATE TABLE lodlog_op.endereco_cliente (
  endereco_id   BIGSERIAL     PRIMARY KEY,
  cliente_id    BIGINT        NOT NULL REFERENCES lodlog_op.cliente(cliente_id),
  logradouro    VARCHAR(255)  NOT NULL,
  numero        VARCHAR(20),
  complemento   VARCHAR(255),
  bairro        VARCHAR(100)  NOT NULL,
  municipio     VARCHAR(100)  NOT NULL,
  uf            CHAR(2)       NOT NULL,
  cep           VARCHAR(8)    NOT NULL,
  latitude      DECIMAL(9,6),
  longitude     DECIMAL(9,6),
  tipo          VARCHAR(20)   NOT NULL
    CHECK (tipo IN ('Entrega','Cobrança','Principal')),
  ativo         BOOLEAN       NOT NULL DEFAULT true,
  created_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE lodlog_op.endereco_cliente IS
  'Endereços de clientes - separado para normalização 3FN';

CREATE INDEX idx_endereco_cliente_id ON lodlog_op.endereco_cliente(cliente_id);
CREATE INDEX idx_endereco_cep ON lodlog_op.endereco_cliente(cep);


CREATE TABLE lodlog_op.contrato (
  contrato_id          BIGSERIAL     PRIMARY KEY,
  cliente_id           BIGINT        NOT NULL REFERENCES lodlog_op.cliente(cliente_id),
  numero_contrato      VARCHAR(50)   NOT NULL UNIQUE,
  data_inicio          DATE          NOT NULL,
  data_fim             DATE,
  sla_pontualidade_pct DECIMAL(5,2)  NOT NULL
    CHECK (sla_pontualidade_pct >= 0 AND sla_pontualidade_pct <= 100),
  multa_atraso_pct     DECIMAL(5,2)  NOT NULL
    CHECK (multa_atraso_pct >= 0),
  status               VARCHAR(20)   NOT NULL
    CHECK (status IN ('Ativo','Encerrado','Suspenso')),
  created_at           TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at           TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE lodlog_op.contrato IS
  'Contratos de serviço com clientes';

CREATE INDEX idx_contrato_cliente_id ON lodlog_op.contrato(cliente_id);


-- ================================================================
-- Domínio FROTA
-- ================================================================

CREATE TABLE lodlog_op.veiculo (
  veiculo_id     BIGSERIAL     PRIMARY KEY,
  placa          VARCHAR(8)    NOT NULL UNIQUE,
  modelo         VARCHAR(100)  NOT NULL,
  fabricante     VARCHAR(100),
  ano_fabricacao SMALLINT      NOT NULL
    CHECK (ano_fabricacao >= 1990),
  tipo           VARCHAR(20)   NOT NULL
    CHECK (tipo IN ('Leve','Médio','Pesado')),
  capacidade_kg  DECIMAL(10,2) NOT NULL
    CHECK (capacidade_kg > 0),
  hodometro_km   DECIMAL(10,0) NOT NULL
    CHECK (hodometro_km >= 0),
  data_aquisicao DATE,
  status         VARCHAR(20)   NOT NULL DEFAULT 'Disponível'
    CHECK (status IN ('Disponível','Em Rota','Manutenção','Inativo')),
  created_at     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at     TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE lodlog_op.veiculo IS
  'Frota de veículos da operação logística';

CREATE INDEX idx_veiculo_placa ON lodlog_op.veiculo(placa);
CREATE INDEX idx_veiculo_status ON lodlog_op.veiculo(status);


CREATE TABLE lodlog_op.motorista (
  motorista_id    BIGSERIAL     PRIMARY KEY,
  cpf             VARCHAR(11)   NOT NULL UNIQUE,
  nome_completo   VARCHAR(255)  NOT NULL,
  cnh             VARCHAR(12)   NOT NULL UNIQUE,
  categoria_cnh   VARCHAR(3)    NOT NULL
    CHECK (categoria_cnh IN ('A','B','C','D','E','AB','AC','AD','AE')),
  validade_cnh    DATE          NOT NULL,
  data_admissao   DATE          NOT NULL,
  score_seguranca DECIMAL(5,2)
    CHECK (score_seguranca IS NULL OR (score_seguranca >= 0 AND score_seguranca <= 100)),
  status          VARCHAR(20)   NOT NULL DEFAULT 'Ativo'
    CHECK (status IN ('Ativo','Afastado','Desligado')),
  created_at      TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE lodlog_op.motorista IS
  'Cadastro de motoristas da frota';

CREATE INDEX idx_motorista_cpf ON lodlog_op.motorista(cpf);
CREATE INDEX idx_motorista_status ON lodlog_op.motorista(status);


CREATE TABLE lodlog_op.manutencao (
  manutencao_id   BIGSERIAL      PRIMARY KEY,
  veiculo_id      BIGINT         NOT NULL REFERENCES lodlog_op.veiculo(veiculo_id),
  tipo            VARCHAR(20)    NOT NULL
    CHECK (tipo IN ('Preventiva','Corretiva','Preditiva')),
  data_abertura   TIMESTAMP      NOT NULL,
  data_conclusao  TIMESTAMP,
  km_no_momento   DECIMAL(10,0)  NOT NULL
    CHECK (km_no_momento >= 0),
  custo_total     DECIMAL(12,2)
    CHECK (custo_total IS NULL OR custo_total >= 0),
  descricao       TEXT,
  status          VARCHAR(20)    NOT NULL
    CHECK (status IN ('Aberta','Em Execução','Concluída')),
  created_at      TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE lodlog_op.manutencao IS
  'Registro de manutenção de veículos';

CREATE INDEX idx_manutencao_veiculo_id ON lodlog_op.manutencao(veiculo_id);
CREATE INDEX idx_manutencao_status ON lodlog_op.manutencao(status);
CREATE INDEX idx_manutencao_data_abertura ON lodlog_op.manutencao(data_abertura);


-- Alta frequência: ~864k eventos/dia
-- Criada como tabela normal; considere particionamento por data em produção
-- PARTITION BY RANGE (data_evento) em PostgreSQL 10+
CREATE TABLE lodlog_op.telemetria (
  telemetria_id         BIGSERIAL     PRIMARY KEY,
  veiculo_id            BIGINT        NOT NULL REFERENCES lodlog_op.veiculo(veiculo_id),
  timestamp_evento      TIMESTAMP     NOT NULL,
  data_evento           DATE          NOT NULL,
  latitude              DECIMAL(9,6)  NOT NULL,
  longitude             DECIMAL(9,6)  NOT NULL,
  velocidade_kmh        DECIMAL(6,2)  NOT NULL
    CHECK (velocidade_kmh >= 0 AND velocidade_kmh <= 200),
  rpm_motor             INTEGER
    CHECK (rpm_motor IS NULL OR (rpm_motor >= 0 AND rpm_motor <= 8000)),
  temperatura_motor_c   DECIMAL(6,2)
    CHECK (temperatura_motor_c IS NULL OR (temperatura_motor_c >= -50 AND temperatura_motor_c <= 200)),
  nivel_combustivel_pct DECIMAL(5,2)
    CHECK (nivel_combustivel_pct IS NULL OR (nivel_combustivel_pct >= 0 AND nivel_combustivel_pct <= 100)),
  peso_carga_kg         DECIMAL(10,2)
    CHECK (peso_carga_kg IS NULL OR peso_carga_kg >= 0),
  hodometro_km          DECIMAL(10,0)
);

COMMENT ON TABLE lodlog_op.telemetria IS
  'Eventos IoT da frota (~864k/dia). RECOMENDAÇÃO: Particionar por data em produção.';

-- Índices críticos para telemetria (alta frequência)
CREATE INDEX idx_telemetria_veiculo_id ON lodlog_op.telemetria(veiculo_id);
CREATE INDEX idx_telemetria_data_evento ON lodlog_op.telemetria(data_evento);
CREATE INDEX idx_telemetria_timestamp ON lodlog_op.telemetria(timestamp_evento);
CREATE INDEX idx_telemetria_localizacao ON lodlog_op.telemetria(latitude, longitude);


-- ================================================================
-- Domínio ESTOQUE
-- ================================================================

CREATE TABLE lodlog_op.centro_distribuicao (
  cd_id         BIGSERIAL      PRIMARY KEY,
  codigo        VARCHAR(20)    NOT NULL UNIQUE,
  nome          VARCHAR(255)   NOT NULL,
  municipio     VARCHAR(100)   NOT NULL,
  uf            CHAR(2)        NOT NULL,
  cep           VARCHAR(8)     NOT NULL,
  latitude      DECIMAL(9,6)   NOT NULL,
  longitude     DECIMAL(9,6)   NOT NULL,
  capacidade_m3 DECIMAL(10,2)  NOT NULL
    CHECK (capacidade_m3 > 0),
  ativo         BOOLEAN        NOT NULL DEFAULT true,
  created_at    TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE lodlog_op.centro_distribuicao IS
  'Centros de distribuição da rede logística';

CREATE INDEX idx_cd_municipio_uf ON lodlog_op.centro_distribuicao(municipio, uf);


CREATE TABLE lodlog_op.produto (
  produto_id         BIGSERIAL      PRIMARY KEY,
  sku                VARCHAR(50)    NOT NULL UNIQUE,
  nome               VARCHAR(255)   NOT NULL,
  categoria          VARCHAR(100)   NOT NULL,
  peso_unitario_kg   DECIMAL(10,3)  NOT NULL
    CHECK (peso_unitario_kg > 0),
  volume_unitario_m3 DECIMAL(10,4)
    CHECK (volume_unitario_m3 IS NULL OR volume_unitario_m3 > 0),
  ativo              BOOLEAN        NOT NULL DEFAULT true,
  created_at         TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         TIMESTAMP      NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE lodlog_op.produto IS
  'Catálogo de produtos';

CREATE INDEX idx_produto_categoria ON lodlog_op.produto(categoria);


-- Posição atual do estoque (state table)
CREATE TABLE lodlog_op.estoque (
  estoque_id            BIGSERIAL     PRIMARY KEY,
  cd_id                 BIGINT        NOT NULL REFERENCES lodlog_op.centro_distribuicao(cd_id),
  produto_id            BIGINT        NOT NULL REFERENCES lodlog_op.produto(produto_id),
  quantidade_disponivel INTEGER       NOT NULL
    CHECK (quantidade_disponivel >= 0),
  quantidade_reservada  INTEGER       NOT NULL
    CHECK (quantidade_reservada >= 0),
  posicao_galpao        VARCHAR(50),
  ultima_atualizacao    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(cd_id, produto_id)
);

COMMENT ON TABLE lodlog_op.estoque IS
  'Posição atual de estoque por CD e produto (derivado do histórico)';

CREATE INDEX idx_estoque_cd_id ON lodlog_op.estoque(cd_id);
CREATE INDEX idx_estoque_produto_id ON lodlog_op.estoque(produto_id);


-- Log de movimentações — histórico completo para auditoria
CREATE TABLE lodlog_op.movimentacao_estoque (
  movimentacao_id BIGSERIAL     PRIMARY KEY,
  estoque_id      BIGINT        NOT NULL REFERENCES lodlog_op.estoque(estoque_id),
  tipo_mov        VARCHAR(20)   NOT NULL
    CHECK (tipo_mov IN ('Entrada','Saída','Reserva','Liberação','Ajuste')),
  quantidade      INTEGER       NOT NULL,
  timestamp_mov   TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  referencia      VARCHAR(50),
  observacao      TEXT
);

COMMENT ON TABLE lodlog_op.movimentacao_estoque IS
  'Histórico de movimentações de estoque - auditoria e rastreabilidade';

CREATE INDEX idx_movimentacao_estoque_id ON lodlog_op.movimentacao_estoque(estoque_id);
CREATE INDEX idx_movimentacao_timestamp ON lodlog_op.movimentacao_estoque(timestamp_mov);
CREATE INDEX idx_movimentacao_tipo ON lodlog_op.movimentacao_estoque(tipo_mov);


-- ================================================================
-- Domínio OPERAÇÃO (Pedido / Entrega)
-- ================================================================

CREATE TABLE lodlog_op.pedido (
  pedido_id           BIGSERIAL     PRIMARY KEY,
  numero_pedido       VARCHAR(50)   NOT NULL UNIQUE,
  cliente_id          BIGINT        NOT NULL REFERENCES lodlog_op.cliente(cliente_id),
  contrato_id         BIGINT        REFERENCES lodlog_op.contrato(contrato_id),
  cd_origem_id        BIGINT        NOT NULL REFERENCES lodlog_op.centro_distribuicao(cd_id),
  endereco_destino_id BIGINT        NOT NULL REFERENCES lodlog_op.endereco_cliente(endereco_id),
  data_pedido         TIMESTAMP     NOT NULL,
  prazo_entrega       TIMESTAMP     NOT NULL,
  prioridade          VARCHAR(20)   NOT NULL
    CHECK (prioridade IN ('Baixa','Normal','Alta','Urgente')),
  status_pedido       VARCHAR(20)   NOT NULL DEFAULT 'Aberto'
    CHECK (status_pedido IN ('Aberto','Em Separação','Despachado','Entregue','Cancelado')),
  created_at          TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE lodlog_op.pedido IS
  'Pedidos de clientes para entrega';

COMMENT ON COLUMN lodlog_op.pedido.prazo_entrega IS
  'Prazo de entrega prometido ao cliente (deve ser > data_pedido)';

CREATE INDEX idx_pedido_cliente_id ON lodlog_op.pedido(cliente_id);
CREATE INDEX idx_pedido_status_pedido ON lodlog_op.pedido(status_pedido);
CREATE INDEX idx_pedido_data_pedido ON lodlog_op.pedido(data_pedido);
CREATE INDEX idx_pedido_prazo_entrega ON lodlog_op.pedido(prazo_entrega);


-- Tabela de associação Pedido ↔ Produto (N:M)
CREATE TABLE lodlog_op.item_pedido (
  item_id       BIGSERIAL     PRIMARY KEY,
  pedido_id     BIGINT        NOT NULL REFERENCES lodlog_op.pedido(pedido_id),
  produto_id    BIGINT        NOT NULL REFERENCES lodlog_op.produto(produto_id),
  quantidade    INTEGER       NOT NULL
    CHECK (quantidade > 0),
  peso_total_kg DECIMAL(10,2) NOT NULL
    CHECK (peso_total_kg > 0),
  created_at    TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(pedido_id, produto_id)
);

COMMENT ON TABLE lodlog_op.item_pedido IS
  'Itens/produtos de um pedido (relacionamento N:M)';

CREATE INDEX idx_item_pedido_pedido_id ON lodlog_op.item_pedido(pedido_id);
CREATE INDEX idx_item_pedido_produto_id ON lodlog_op.item_pedido(produto_id);


CREATE TABLE lodlog_op.entrega (
  entrega_id            BIGSERIAL     PRIMARY KEY,
  pedido_id             BIGINT        NOT NULL REFERENCES lodlog_op.pedido(pedido_id),
  veiculo_id            BIGINT        NOT NULL REFERENCES lodlog_op.veiculo(veiculo_id),
  motorista_id          BIGINT        NOT NULL REFERENCES lodlog_op.motorista(motorista_id),
  data_saida            TIMESTAMP     NOT NULL,
  data_entrega_prevista TIMESTAMP     NOT NULL,
  data_entrega_real     TIMESTAMP,
  distancia_km          DECIMAL(10,2) NOT NULL
    CHECK (distancia_km > 0),
  custo_combustivel     DECIMAL(12,2)
    CHECK (custo_combustivel IS NULL OR custo_combustivel >= 0),
  custo_pedagio         DECIMAL(12,2)
    CHECK (custo_pedagio IS NULL OR custo_pedagio >= 0),
  valor_frete           DECIMAL(12,2) NOT NULL
    CHECK (valor_frete > 0),
  multa_atraso          DECIMAL(12,2)
    CHECK (multa_atraso IS NULL OR multa_atraso >= 0),
  status_entrega        VARCHAR(20)   NOT NULL DEFAULT 'Pendente'
    CHECK (status_entrega IN ('Pendente','Em Rota','Entregue','Ocorrência','Devolvido')),
  created_at            TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at            TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE lodlog_op.entrega IS
  'Registro de entregas realizadas ou em andamento';

CREATE INDEX idx_entrega_pedido_id ON lodlog_op.entrega(pedido_id);
CREATE INDEX idx_entrega_veiculo_id ON lodlog_op.entrega(veiculo_id);
CREATE INDEX idx_entrega_motorista_id ON lodlog_op.entrega(motorista_id);
CREATE INDEX idx_entrega_status_entrega ON lodlog_op.entrega(status_entrega);
CREATE INDEX idx_entrega_data_saida ON lodlog_op.entrega(data_saida);

