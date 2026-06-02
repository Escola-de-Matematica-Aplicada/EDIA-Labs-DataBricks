
-- ================================================================
-- SCHEMA ANALÍTICO (lodlog_dw) — Star Schema
-- Granularidade da fato: 1 linha por entrega realizada
-- ================================================================

-- DIM_TEMPO — Dimensão temporal para análises
CREATE TABLE lodlog_dw.dim_tempo (
  sk_tempo         INTEGER       PRIMARY KEY,
  data_completa    DATE          NOT NULL UNIQUE,
  dia              SMALLINT      NOT NULL,
  mes              SMALLINT      NOT NULL CHECK (mes >= 1 AND mes <= 12),
  ano              SMALLINT      NOT NULL,
  trimestre        SMALLINT      NOT NULL CHECK (trimestre >= 1 AND trimestre <= 4),
  semana_do_ano    SMALLINT      NOT NULL CHECK (semana_do_ano >= 1 AND semana_do_ano <= 53),
  dia_da_semana    SMALLINT      NOT NULL CHECK (dia_da_semana >= 1 AND dia_da_semana <= 7),
  nome_dia_semana  VARCHAR(20)   NOT NULL,
  nome_mes         VARCHAR(20)   NOT NULL,
  flag_feriado     BOOLEAN       NOT NULL DEFAULT false,
  flag_fim_semana  BOOLEAN       NOT NULL DEFAULT false,
  descricao_feriado VARCHAR(255)
);

COMMENT ON TABLE lodlog_dw.dim_tempo IS
  'Dimensão tempo — carga via script ETL (1 linha/dia)';

CREATE INDEX idx_dim_tempo_data ON lodlog_dw.dim_tempo(data_completa);


-- DIM_CLIENTE — SCD Tipo 2 (rastreia histórico de mudanças)
CREATE TABLE lodlog_dw.dim_cliente (
  sk_cliente                BIGSERIAL     PRIMARY KEY,
  cliente_id                BIGINT        NOT NULL,
  cnpj                      VARCHAR(14)   NOT NULL,
  razao_social              VARCHAR(255)  NOT NULL,
  segmento                  VARCHAR(50)   NOT NULL,
  municipio                 VARCHAR(100)  NOT NULL,
  uf                        CHAR(2)       NOT NULL,
  regiao                    VARCHAR(50)   NOT NULL
    CHECK (regiao IN ('Norte','Nordeste','Centro-Oeste','Sudeste','Sul')),
  tempo_relacionamento_meses INTEGER       NOT NULL DEFAULT 0,
  sla_contratual_pct        DECIMAL(5,2),
  data_inicio_vigencia      DATE          NOT NULL DEFAULT CURRENT_DATE,
  data_fim_vigencia         DATE,
  flag_registro_atual       BOOLEAN       NOT NULL DEFAULT true
);

COMMENT ON TABLE lodlog_dw.dim_cliente IS
  'Dimensão cliente com histórico de mudanças (SCD Tipo 2)';

CREATE INDEX idx_dim_cliente_natural_key ON lodlog_dw.dim_cliente(cliente_id, data_fim_vigencia);
CREATE INDEX idx_dim_cliente_flag_atual ON lodlog_dw.dim_cliente(flag_registro_atual);


-- DIM_VEICULO — SCD Tipo 2 (hodômetro e status mudam)
CREATE TABLE lodlog_dw.dim_veiculo (
  sk_veiculo            BIGSERIAL     PRIMARY KEY,
  veiculo_id            BIGINT        NOT NULL,
  placa                 VARCHAR(8)    NOT NULL,
  modelo                VARCHAR(100)  NOT NULL,
  fabricante            VARCHAR(100),
  ano_fabricacao        SMALLINT      NOT NULL,
  tipo                  VARCHAR(20)   NOT NULL,
  capacidade_kg         DECIMAL(10,2) NOT NULL,
  faixa_capacidade      VARCHAR(50)   NOT NULL
    CHECK (faixa_capacidade IN ('Até 1t','1-5t','5-15t','Acima 15t')),
  data_inicio_vigencia  DATE          NOT NULL DEFAULT CURRENT_DATE,
  data_fim_vigencia     DATE,
  flag_registro_atual   BOOLEAN       NOT NULL DEFAULT true
);

COMMENT ON TABLE lodlog_dw.dim_veiculo IS
  'Dimensão veículo com histórico (SCD Tipo 2) - hodômetro evolui';

CREATE INDEX idx_dim_veiculo_natural_key ON lodlog_dw.dim_veiculo(veiculo_id, data_fim_vigencia);
CREATE INDEX idx_dim_veiculo_flag_atual ON lodlog_dw.dim_veiculo(flag_registro_atual);


-- DIM_MOTORISTA — SCD Tipo 2 (score e experiência evoluem)
CREATE TABLE lodlog_dw.dim_motorista (
  sk_motorista          BIGSERIAL     PRIMARY KEY,
  motorista_id          BIGINT        NOT NULL,
  nome_completo         VARCHAR(255)  NOT NULL,
  categoria_cnh         VARCHAR(3)    NOT NULL,
  tempo_empresa_meses   INTEGER       NOT NULL DEFAULT 0,
  faixa_experiencia     VARCHAR(50)   NOT NULL
    CHECK (faixa_experiencia IN ('Júnior','Pleno','Sênior')),
  score_seguranca       DECIMAL(5,2),
  data_inicio_vigencia  DATE          NOT NULL DEFAULT CURRENT_DATE,
  data_fim_vigencia     DATE,
  flag_registro_atual   BOOLEAN       NOT NULL DEFAULT true
);

COMMENT ON TABLE lodlog_dw.dim_motorista IS
  'Dimensão motorista com histórico (SCD Tipo 2) - score evolui';

CREATE INDEX idx_dim_motorista_natural_key ON lodlog_dw.dim_motorista(motorista_id, data_fim_vigencia);
CREATE INDEX idx_dim_motorista_flag_atual ON lodlog_dw.dim_motorista(flag_registro_atual);


-- DIM_CENTRO_DISTRIBUICAO — SCD Tipo 1 (atualiza no lugar)
CREATE TABLE lodlog_dw.dim_centro_distribuicao (
  sk_cd         BIGSERIAL      PRIMARY KEY,
  cd_id         BIGINT         NOT NULL UNIQUE,
  codigo        VARCHAR(20)    NOT NULL,
  nome          VARCHAR(255)   NOT NULL,
  municipio     VARCHAR(100)   NOT NULL,
  uf            CHAR(2)        NOT NULL,
  regiao        VARCHAR(50)    NOT NULL
    CHECK (regiao IN ('Norte','Nordeste','Centro-Oeste','Sudeste','Sul')),
  capacidade_m3 DECIMAL(10,2)  NOT NULL,
  latitude      DECIMAL(9,6),
  longitude     DECIMAL(9,6)
);

COMMENT ON TABLE lodlog_dw.dim_centro_distribuicao IS
  'Dimensão CD - atualiza no lugar (SCD Tipo 1)';

CREATE INDEX idx_dim_cd_natural_key ON lodlog_dw.dim_centro_distribuicao(cd_id);


-- FATO_ENTREGAS — Tabela de fatos central do Star Schema
-- Granularidade: 1 linha por entrega realizada
-- indicador_atraso = variável-alvo (target) para modelo ML
CREATE TABLE lodlog_dw.fato_entregas (
  sk_entrega              BIGSERIAL     PRIMARY KEY,

  -- Surrogate keys das dimensões
  sk_data                 INTEGER       NOT NULL REFERENCES lodlog_dw.dim_tempo(sk_tempo),
  sk_cliente              BIGINT        NOT NULL REFERENCES lodlog_dw.dim_cliente(sk_cliente),
  sk_cd_origem            BIGINT        NOT NULL REFERENCES lodlog_dw.dim_centro_distribuicao(sk_cd),
  sk_veiculo              BIGINT        NOT NULL REFERENCES lodlog_dw.dim_veiculo(sk_veiculo),
  sk_motorista            BIGINT        NOT NULL REFERENCES lodlog_dw.dim_motorista(sk_motorista),

  -- Chaves naturais degeneradas (rastreabilidade, sem dimensão própria)
  entrega_id              BIGINT        NOT NULL,
  pedido_id               BIGINT        NOT NULL,

  -- Atributos de data/hora
  data_entrega            DATE,
  hora_saida              TIMESTAMP,

  -- Métricas aditivas (somáveis em qualquer combinação de dimensões)
  quantidade_volumes      INTEGER       NOT NULL DEFAULT 0
    CHECK (quantidade_volumes >= 0),
  peso_total_kg           DECIMAL(10,2) NOT NULL
    CHECK (peso_total_kg > 0),
  distancia_km            DECIMAL(10,2) NOT NULL
    CHECK (distancia_km > 0),
  tempo_estimado_min      INTEGER       NOT NULL
    CHECK (tempo_estimado_min > 0),
  tempo_real_min          INTEGER,
  custo_combustivel       DECIMAL(12,2) NOT NULL DEFAULT 0
    CHECK (custo_combustivel >= 0),
  custo_pedagio           DECIMAL(12,2) NOT NULL DEFAULT 0
    CHECK (custo_pedagio >= 0),
  valor_frete             DECIMAL(12,2) NOT NULL
    CHECK (valor_frete > 0),
  multa_atraso            DECIMAL(12,2) NOT NULL DEFAULT 0
    CHECK (multa_atraso >= 0),

  -- Métricas derivadas
  minutos_atraso          INTEGER       NOT NULL DEFAULT 0
    CHECK (minutos_atraso >= 0),
  indicador_atraso        SMALLINT      NOT NULL DEFAULT 0
    CHECK (indicador_atraso IN (0, 1)),
  temperatura_media_motor DECIMAL(6,2),

  created_at              TIMESTAMP     NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE lodlog_dw.fato_entregas IS
  'Fato entregas - granularidade: 1 linha/entrega. '
  'indicador_atraso é o target do modelo de ML (0=pontual, 1=atrasado)';

COMMENT ON COLUMN lodlog_dw.fato_entregas.indicador_atraso IS
  'Target para modelo ML: 0 = entrega pontual | 1 = entrega atrasada';

-- Índices na tabela de fatos para performance de queries analíticas
CREATE INDEX idx_fato_entregas_data ON lodlog_dw.fato_entregas(sk_data);
CREATE INDEX idx_fato_entregas_cliente ON lodlog_dw.fato_entregas(sk_cliente);
CREATE INDEX idx_fato_entregas_veiculo ON lodlog_dw.fato_entregas(sk_veiculo);
CREATE INDEX idx_fato_entregas_motorista ON lodlog_dw.fato_entregas(sk_motorista);
CREATE INDEX idx_fato_entregas_cd ON lodlog_dw.fato_entregas(sk_cd_origem);
CREATE INDEX idx_fato_entregas_indicador_atraso ON lodlog_dw.fato_entregas(indicador_atraso);


-- ================================================================
-- VIEWS ÚTEIS PARA VALIDAÇÃO E CONSULTAS COMUNS
-- ================================================================

-- View: Clientes ativos
CREATE VIEW lodlog_op.v_clientes_ativos AS
SELECT cliente_id, cnpj, razao_social, nome_fantasia, segmento
FROM lodlog_op.cliente
WHERE ativo = true
ORDER BY razao_social;

COMMENT ON VIEW lodlog_op.v_clientes_ativos IS
  'Lista de clientes ativos da empresa';


-- View: Veículos disponíveis
CREATE VIEW lodlog_op.v_veiculos_disponiveis AS
SELECT veiculo_id, placa, modelo, tipo, capacidade_kg, status
FROM lodlog_op.veiculo
WHERE status = 'Disponível' AND ativo IS NOT FALSE
ORDER BY capacidade_kg;

COMMENT ON VIEW lodlog_op.v_veiculos_disponiveis IS
  'Frota de veículos atualmente disponíveis para rota';


-- View: Entregas atrasadas (analítica)
CREATE VIEW lodlog_op.v_entregas_atrasadas AS
SELECT
  e.entrega_id,
  p.numero_pedido,
  c.razao_social,
  e.data_entrega_prevista,
  e.data_entrega_real,
  EXTRACT(EPOCH FROM (e.data_entrega_real - e.data_entrega_prevista)) / 60 AS minutos_atraso,
  e.multa_atraso,
  e.status_entrega
FROM lodlog_op.entrega e
JOIN lodlog_op.pedido p ON e.pedido_id = p.pedido_id
JOIN lodlog_op.cliente c ON p.cliente_id = c.cliente_id
WHERE e.data_entrega_real > e.data_entrega_prevista
ORDER BY minutos_atraso DESC;

COMMENT ON VIEW lodlog_op.v_entregas_atrasadas IS
  'Análise de entregas atrasadas com cálculo de atraso em minutos';


-- ================================================================
-- FIM DO SCRIPT
-- ================================================================
-- Próximos passos:
-- 1. Executar script de carga dim_tempo (um script Python ou SQL separado)
-- 2. Implementar triggers para auditoria (optional)
-- 3. Configurar backup e replicação
-- 4. Implementar políticas de row-level security (RLS) se necessário
-- 5. Criar tabelas de staging para ETL
-- ================================================================
