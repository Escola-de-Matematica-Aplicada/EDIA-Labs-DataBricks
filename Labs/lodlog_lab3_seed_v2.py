# Databricks notebook source
# /// script
# [tool.databricks.environment]
# environment_version = "2"
# ///
# MAGIC %sql
# MAGIC /*
# MAGIC # Importar este arquivo no Databricks como notebook Python e executar UMA VEZ antes do LAB 2.
# MAGIC # File: lodlog_lab3_seed_v2.py
# MAGIC # Uso: Escolher "Serverless" --> "Run all"
# MAGIC #
# MAGIC # ════════════════════════════════════════════════════════════════
# MAGIC # O QUE MUDA NA v2 (junho/2026) — em relação ao seed original
# MAGIC # ════════════════════════════════════════════════════════════════
# MAGIC # 1) A tabela lodlog_op.entrega é gerada com COLUNAS REDUNDANTES
# MAGIC #    (cliente_*, veiculo_*, motorista_*, cd_origem_*) — proposital
# MAGIC #    para que ela fique em 2FN (tem dependências transitivas).
# MAGIC #    Os alunos devem normalizar até 3FN no LAB 2 Atividade 2.2.
# MAGIC #
# MAGIC # 2) Nova coluna kpi_cat_atraso na entrega (operacional) —
# MAGIC #    derivada de minutos_atraso, com 5 valores categóricos.
# MAGIC #
# MAGIC # 3) Nova mini-dimensão lodlog_dw.dim_cat_atraso (Kimball) —
# MAGIC #    SCD Tipo 1, com 5 registros. SKEY replicado na fato_entregas.
# MAGIC #
# MAGIC # 4) A fato_entregas ganhou duas colunas novas:
# MAGIC #       - sk_cat_atraso (FK → dim_cat_atraso)
# MAGIC #       - kpi_cat_atraso (atributo replicado, mesmo valor da op)
# MAGIC */

# COMMAND ----------

# MAGIC %md
# MAGIC # LODLog — Geração de Dados Sintéticos & ETL · LAB 2 (v2)
# MAGIC
# MAGIC Execute este notebook **uma única vez** antes do LAB 2.
# MAGIC
# MAGIC **Tabelas populadas:**
# MAGIC
# MAGIC ### lodlog_op (Operacional):
# MAGIC | Tabela | Linhas | Descrição |
# MAGIC |--------|--------|-----------|
# MAGIC | `cliente` | 200 | Clientes LODLog |
# MAGIC | `endereco_cliente` | 200 | Endereços dos clientes |
# MAGIC | `contrato` | 200 | Contratos ativos |
# MAGIC | `veiculo` | 50 | Frota de veículos |
# MAGIC | `motorista` | 100 | Motoristas |
# MAGIC | `manutencao` | ~220 | Histórico de manutenção |
# MAGIC | `telemetria` | ~50K | Eventos IoT (simplificado) |
# MAGIC | `centro_distribuicao` | 5 | Centros de distribuição |
# MAGIC | `produto` | 50 | Catálogo de produtos |
# MAGIC | `estoque` | 250 | Posições de estoque |
# MAGIC | `movimentacao_estoque` | ~10K | Movimentações |
# MAGIC | `pedido` | ~50K | Pedidos de entrega |
# MAGIC | `item_pedido` | ~150K | Itens dos pedidos |
# MAGIC | `entrega` | ~50K | **Entregas em 2FN (proposital)** com kpi_cat_atraso |
# MAGIC
# MAGIC ### lodlog_dw (Data Warehouse - Star Schema):
# MAGIC | Tabela | Linhas | Descrição |
# MAGIC |--------|--------|-----------|
# MAGIC | `dim_tempo` | 944 | Calendário 2024–2026 |
# MAGIC | `dim_cliente` | 200 | Clientes (SCD Tipo 2) |
# MAGIC | `dim_veiculo` | 50 | Veículos (SCD Tipo 2) |
# MAGIC | `dim_motorista` | 100 | Motoristas (SCD Tipo 2) |
# MAGIC | `dim_centro_distribuicao` | 5 | Centros (SCD Tipo 1) |
# MAGIC | `dim_cat_atraso` | 5 | **⭐ NOVA v2** — minidimensão do KPI |
# MAGIC | `fato_entregas` | ~50.000 | Entregas (com sk_cat_atraso + kpi) |
# MAGIC
# MAGIC > **Spoiler para o professor:** as anomalias da Parte 4 estão documentadas ao final do notebook.

# COMMAND ----------

import random
import numpy as np
import pandas as pd
from datetime import date, timedelta, datetime

SEED = 42
random.seed(SEED)
np.random.seed(SEED)
rng = np.random.default_rng(SEED)

print("Gerando dados LODLog para o LAB 3...")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Parte 1: Dados Mestre (Dimensionais Operacionais)

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# CENTRO_DISTRIBUICAO — 5 centros
# ─────────────────────────────────────────────────────────────

_centros_codigos = ["CD-CAMPINAS", "CD-SAO-PAULO", "CD-BELO-HORIZONTE",
                    "CD-CURITIBA", "CD-PORTO-ALEGRE"]
_centros_nomes = ["CD Campinas", "CD São Paulo Norte", "CD Belo Horizonte",
                  "CD Curitiba", "CD Porto Alegre"]
_cidades_centros = ["Campinas", "São Paulo", "Belo Horizonte", "Curitiba", "Porto Alegre"]
_ufs = ["SP", "SP", "MG", "PR", "RS"]
_regioes = ["Sudeste", "Sudeste", "Sudeste", "Sul", "Sul"]
_capacidades = [15000.00, 8000.00, 6000.00, 5500.00, 4000.00]
_lats = [-22.9068, -23.4500, -19.9167, -25.4290, -30.0346]
_lons = [-47.0626, -46.6233, -43.9345, -49.2710, -51.2177]
_ceps = ["13010000", "02000000", "30130000", "80010000", "90010000"]

centros_op = []
for i in range(5):
    centros_op.append({
        "cd_id": i+1,
        "codigo": _centros_codigos[i],
        "nome": _centros_nomes[i],
        "municipio": _cidades_centros[i],
        "uf": _ufs[i],
        "cep": _ceps[i],
        "latitude": _lats[i],
        "longitude": _lons[i],
        "capacidade_m3": _capacidades[i],
        "ativo": True,
    })

df_centro_distribuicao_op = pd.DataFrame(centros_op)

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# CLIENTE — 200 clientes
# ─────────────────────────────────────────────────────────────

_bases = ["Supermercados Beta", "Atacadão Sul", "Distribuidora Norte",
          "Logex Comércio", "GrupoAlpha Varejo", "Fast Shop", "Mag Retail",
          "Americanas Filial", "BIG Hipermercado", "Cencosud Brasil",
          "Leroy Merlin", "C&A Modas", "Renner", "Shopee BR", "Amazon BR",
          "Raia Drogasil", "Nissei", "GNDI Saúde", "Carrefour", "Assaí"]

_cidades = [("São Paulo", "SP")] * 6 + [("Campinas", "SP")] * 3 + \
           [("Santos", "SP")] * 2 + [("Rio de Janeiro", "RJ")] * 4 + \
           [("Belo Horizonte", "MG")] * 2 + [("Curitiba", "PR")] * 2 + \
           [("Porto Alegre", "RS"), ("Goiânia", "GO"), ("Salvador", "BA"),
            ("Fortaleza", "CE"), ("Brasília", "DF")]

_segmentos = ["Varejo", "Atacado", "Indústria", "E-commerce", "Alimentício"]
_dominios_email = ["gmail.com", "yahoo.com.br", "outlook.com", "empresas.com.br"]

clientes_op = []
for i in range(1, 201):
    cidade, uf = random.choice(_cidades)
    base = random.choice(_bases)
    
    # Gerar CNPJ fictício válido (apenas formato)
    cnpj = f"{random.randint(1,99999999):08d}0001{random.randint(1,99):02d}"
    
    # Data de cadastro: 2020-2024
    data_cadastro = date(2020, 1, 1) + timedelta(days=random.randint(0, 1825))
    
    clientes_op.append({
        "cliente_id": i,
        "cnpj": cnpj,
        "razao_social": f"{base} {i:03d} LTDA",
        "nome_fantasia": f"{base} {i:03d}",
        "segmento": random.choice(_segmentos),
        "email": f"contato_{i:03d}@{random.choice(_dominios_email)}".lower(),
        "telefone": f"({random.randint(11,99)}) {random.randint(9000,9999)}-{random.randint(1000,9999)}",
        "data_cadastro": data_cadastro.isoformat(),
        "ativo": True,
    })

df_cliente_op = pd.DataFrame(clientes_op)

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# ENDERECO_CLIENTE — 1 endereço principal por cliente
# ─────────────────────────────────────────────────────────────

_bairros_sp = ["Bela Vista", "Consolação", "Pinheiros", "Itaim Bibi", "Jardins", 
               "Vila Mariana", "Santana", "Lapa", "Barra Funda"]
_bairros_rj = ["Copacabana", "Ipanema", "Leblon", "Tijuca", "Botafogo", 
               "Centro", "Barra da Tijuca"]
_bairros_outros = ["Centro", "Industrial", "Residencial", "Comercial", "Jardim"]

enderecos_op = []
for i, cliente in df_cliente_op.iterrows():
    cidade = cliente["municipio"] if "municipio" in cliente else random.choice(_cidades)[0]
    uf = cliente["uf"] if "uf" in cliente else random.choice(_cidades)[1]
    
    # Selecionar bairro com base na cidade
    if cidade == "São Paulo":
        bairro = random.choice(_bairros_sp)
    elif cidade == "Rio de Janeiro":
        bairro = random.choice(_bairros_rj)
    else:
        bairro = random.choice(_bairros_outros)
    
    # Gerar CEP fictício
    cep_base = {"SP": "01310", "RJ": "20040", "MG": "30130", "PR": "80010", 
                "RS": "90010", "GO": "74010", "BA": "40010", "CE": "60010", "DF": "70010"}
    cep = f"{cep_base.get(uf, '01310')}{random.randint(0, 9999):04d}"
    
    # Coordenadas aproximadas
    lat_lon_map = {
        ("São Paulo", "SP"): (-23.5630, -46.6544),
        ("Campinas", "SP"): (-22.9068, -47.0626),
        ("Rio de Janeiro", "RJ"): (-22.9068, -43.1729),
        ("Belo Horizonte", "MG"): (-19.9167, -43.9345),
        ("Curitiba", "PR"): (-25.4290, -49.2710),
        ("Porto Alegre", "RS"): (-30.0346, -51.2177),
        ("Goiânia", "GO"): (-16.6869, -49.2648),
        ("Salvador", "BA"): (-12.9714, -38.5014),
        ("Fortaleza", "CE"): (-3.7172, -38.5434),
        ("Brasília", "DF"): (-15.8267, -47.9218),
    }
    lat, lon = lat_lon_map.get((cidade, uf), (-23.5630, -46.6544))
    
    enderecos_op.append({
        "endereco_id": i + 1,
        "cliente_id": cliente["cliente_id"],
        "logradouro": f"Rua {random.choice(['Principal', 'Comercial', 'Industrial', 'das Flores', 'Augusta'])}",
        "numero": str(random.randint(100, 5000)),
        "complemento": random.choice([None, f"Bloco {random.choice('ABCDE')}", "Sala 1", ""]),
        "bairro": bairro,
        "municipio": cidade,
        "uf": uf,
        "cep": cep,
        "latitude": round(lat + random.uniform(-0.01, 0.01), 6),
        "longitude": round(lon + random.uniform(-0.01, 0.01), 6),
        "tipo": "Principal",
    })

df_endereco_cliente_op = pd.DataFrame(enderecos_op)

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# CONTRATO — 1 contrato por cliente
# ─────────────────────────────────────────────────────────────

contratos_op = []
for i, cliente in df_cliente_op.iterrows():
    data_inicio = date.fromisoformat(cliente["data_cadastro"]) + timedelta(days=random.randint(30, 180))
    data_fim = data_inicio + timedelta(days=random.randint(365, 1095))  # 1-3 anos
    
    contratos_op.append({
        "contrato_id": i + 1,
        "cliente_id": cliente["cliente_id"],
        "numero_contrato": f"CTR-{cliente['cliente_id']:05d}-{random.randint(1, 999):03d}",
        "data_inicio": data_inicio.isoformat(),
        "data_fim": data_fim.isoformat(),
        "sla_pontualidade_pct": round(random.uniform(85.0, 99.5), 2),
        "multa_atraso_pct": round(random.uniform(0.5, 5.0), 2),
        "status": "Ativo",
    })

df_contrato_op = pd.DataFrame(contratos_op)

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# VEICULO — 50 veículos
# ─────────────────────────────────────────────────────────────

_modelos = ["VW Delivery 9.170", "Mercedes-Benz Atego 2430",
            "Iveco Daily 35S14", "Ford Cargo 1723", "Scania R450",
            "MAN TGX 28.440", "Volvo FH 460", "Renault Master 2.3"]
_fabricantes = ["Volkswagen", "Mercedes-Benz", "Iveco", "Ford", 
               "Scania", "MAN", "Volvo", "Renault"]
_letras = "ABCDEFGHJKLMNPQRSTUVWXYZ"

veiculos_op = []
for i in range(1, 51):
    fabricante_idx = random.randint(0, len(_fabricantes) - 1)
    veiculos_op.append({
        "veiculo_id": i,
        "placa": (f"{''.join(random.choices(_letras, k=3))}"
                  f"{random.randint(0,9)}{random.choice(_letras)}{random.randint(10,99)}"),
        "modelo": _modelos[fabricante_idx],
        "fabricante": _fabricantes[fabricante_idx],
        "ano_fabricacao": random.randint(2015, 2023),
        "tipo": random.choice(["Leve", "Médio", "Pesado"]),
        "capacidade_kg": random.choice([3500, 5000, 8000, 15000, 25000]),
        "hodometro_km": random.randint(10000, 200000),
        "data_aquisicao": (date(2020, 1, 1) + timedelta(days=random.randint(0, 1460))).isoformat(),
        "status": random.choice(["Disponível", "Em Rota", "Manutenção"]),
    })

df_veiculo_op = pd.DataFrame(veiculos_op)

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# MOTORISTA — 100 motoristas
# ─────────────────────────────────────────────────────────────

_primeiros_nomes = ["João", "Maria", "Carlos", "Ana", "Pedro", "Julia", "Rafael", "Fernanda",
                    "Daniel", "Marcia", "Bruno", "Renata", "Eder", "Simone", "Marcelo", "Paula",
                    "Diego", "Barbara", "Rodrigo", "Patrícia", "Anderson", "Priscila", "Luiz",
                    "Vanessa", "Fabio", "Rita", "José", "Teresa", "Antonio", "Cida"]
_sobrenomes = ["Silva", "Santos", "Oliveira", "Souza", "Rodrigues", "Ferreira", "Pereira",
               "Lima", "Gomes", "Ribeiro", "Martins", "Almeida", "Barbosa", "Araujo", "Dias",
               "Nunes", "Moraes", "Costa", "Leite", "Teixeira", "Queiroz", "Nascimento"]

_categorias_cnh = ["A", "B", "C", "D", "E", "AB", "AC", "AD", "AE"]

motoristas_op = []
for i in range(1, 101):
    nome_completo = f"{random.choice(_primeiros_nomes)} {random.choice(_sobrenomes)}"
    cpf = f"{random.randint(100000000, 999999999):09d}{random.randint(0, 99):02d}"
    cnh = f"CNH{random.randint(1000000, 9999999):07d}"
    categoria = random.choice(_categorias_cnh)
    
    # Tempo de empresa em meses
    data_admissao = date(2015, 1, 1) + timedelta(days=random.randint(0, 3285))  # até 2024
    tempo_empresa_meses = (date(2024, 6, 1) - data_admissao).days // 30
    
    # Validade CNH: 5 anos a partir da admissão
    validade_cnh = data_admissao + timedelta(days=1825)
    
    # Faixa de experiência
    if tempo_empresa_meses < 24:
        faixa = "Júnior"
    elif tempo_empresa_meses < 96:
        faixa = "Pleno"
    else:
        faixa = "Sênior"
    
    # Score de segurança
    if faixa == "Sênior":
        score = round(random.uniform(60, 100), 2)
    elif faixa == "Pleno":
        score = round(random.uniform(40, 85), 2)
    else:
        score = round(random.uniform(30, 70), 2)
    
    motoristas_op.append({
        "motorista_id": i,
        "cpf": cpf,
        "nome_completo": nome_completo,
        "cnh": cnh,
        "categoria_cnh": categoria,
        "validade_cnh": validade_cnh.isoformat(),
        "data_admissao": data_admissao.isoformat(),
        "score_seguranca": score,
        "status": "Ativo",
    })

df_motorista_op = pd.DataFrame(motoristas_op)

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# MANUTENCAO — ~220 registros
# ─────────────────────────────────────────────────────────────

_dt0 = date(2023, 1, 1)
_dt1 = date(2026, 5, 1)
_span = (_dt1 - _dt0).days

manutencoes_op = []
manut_id = 1
for vid in range(1, 51):
    for dt in sorted(random.choices(
            [_dt0 + timedelta(days=d) for d in range(_span)],
            k=random.randint(2, 7))):
        data_abertura = datetime(dt.year, dt.month, dt.day, 
                                  random.randint(0, 23), random.randint(0, 59), 0)
        data_conclusao = data_abertura + timedelta(hours=random.randint(2, 72))
        
        manutencoes_op.append({
            "manutencao_id": manut_id,
            "veiculo_id": vid,
            "tipo": random.choice(["Preventiva", "Corretiva", "Revisão geral", "Troca de óleo"]),
            "data_abertura": data_abertura.isoformat(),
            "data_conclusao": data_conclusao.isoformat(),
            "km_no_momento": random.randint(10000, 250000),
            "custo_total": round(random.uniform(200, 15000), 2),
            "descricao": f"Manutenção {random.choice(['rotineira', 'urgente', 'programada'])} no veículo {vid}",
            "status": "Concluída",
        })
        manut_id += 1

df_manutencao_op = pd.DataFrame(manutencoes_op)

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# PRODUTO — 50 produtos
# ─────────────────────────────────────────────────────────────

_categorias_produto = ["Eletrônicos", "Alimentos", "Farmacêutico", "Industrial", 
                       "Limpeza", "Bebidas", "Automotivo", "Construção"]

produtos_op = []
for i in range(1, 51):
    categoria = random.choice(_categorias_produto)
    
    # Gerar SKU
    cat_prefix = {"Eletrônicos": "ELE", "Alimentos": "ALI", "Farmacêutico": "FAR", 
                  "Industrial": "IND", "Limpeza": "LIM", "Bebidas": "BEB",
                  "Automotivo": "AUT", "Construção": "CON"}
    sku = f"{cat_prefix[categoria]}-{i:04d}"
    
    # Peso e volume baseados na categoria
    if categoria == "Eletrônicos":
        peso = round(random.uniform(0.5, 20.0), 3)
        volume = round(random.uniform(0.001, 0.5), 4)
    elif categoria == "Alimentos":
        peso = round(random.uniform(0.5, 10.0), 3)
        volume = round(random.uniform(0.001, 0.1), 4)
    elif categoria == "Farmacêutico":
        peso = round(random.uniform(0.01, 2.0), 3)
        volume = round(random.uniform(0.0001, 0.01), 4)
    elif categoria == "Industrial":
        peso = round(random.uniform(5.0, 100.0), 3)
        volume = round(random.uniform(0.01, 0.5), 4)
    else:
        peso = round(random.uniform(1.0, 15.0), 3)
        volume = round(random.uniform(0.01, 0.2), 4)
    
    produtos_op.append({
        "produto_id": i,
        "sku": sku,
        "nome": f"Produto {categoria} {i:03d}",
        "categoria": categoria,
        "peso_unitario_kg": peso,
        "volume_unitario_m3": volume,
        "ativo": True,
    })

df_produto_op = pd.DataFrame(produtos_op)

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# ESTOQUE & MOVIMENTACAO_ESTOQUE
# ─────────────────────────────────────────────────────────────

# Estoque: 5 produtos por CD
estoques_op = []
estoque_id = 1
for cd in range(1, 6):
    for prod in range(1, 51):
        estoques_op.append({
            "estoque_id": estoque_id,
            "cd_id": cd,
            "produto_id": prod,
            "quantidade_disponivel": random.randint(0, 1000),
            "quantidade_reservada": random.randint(0, 200),
            "posicao_galpao": f"{random.choice(['A', 'B', 'C', 'D'])}-{random.randint(1, 20):02d}-{random.randint(1, 10)}",
            "ultima_atualizacao": (date(2024, 1, 1) + timedelta(days=random.randint(0, 547))).isoformat() + " 10:00:00",
        })
        estoque_id += 1

df_estoque_op = pd.DataFrame(estoques_op)

# Movimentações: ~200 por estoque
movimentacoes_op = []
for estoque in df_estoque_op.itertuples():
    estoque_row = estoque._asdict()
    n_movs = random.randint(100, 250)
    
    for m in range(n_movs):
        dt_mov = date(2024, 1, 1) + timedelta(days=random.randint(0, 547))
        hora = random.randint(0, 23)
        minuto = random.randint(0, 59)
        
        tipo_mov = random.choice(["Entrada", "Saída", "Reserva", "Liberação", "Ajuste"])
        
        if tipo_mov == "Entrada":
            qtd = random.randint(1, 50)
        elif tipo_mov == "Saída":
            qtd = -random.randint(1, 50)
        elif tipo_mov == "Reserva":
            qtd = -random.randint(1, 20)
        elif tipo_mov == "Liberação":
            qtd = random.randint(1, 20)
        else:  # Ajuste
            qtd = random.choice([-1, 1]) * random.randint(1, 5)
        
        movimentacoes_op.append({
            "movimentacao_id": len(movimentacoes_op) + 1,
            "estoque_id": estoque_row["estoque_id"],
            "tipo_mov": tipo_mov,
            "quantidade": qtd,
            "timestamp_mov": f"{dt_mov.isoformat()} {hora:02d}:{minuto:02d}:00",
            "referencia": f"REF-{random.randint(10000, 99999)}",
            "observacao": random.choice([None, "Movimentação automática", "Ajuste de inventário"]),
        })

df_movimentacao_estoque_op = pd.DataFrame(movimentacoes_op)

# COMMAND ----------

# MAGIC %md
# MAGIC ## Parte 2: Dados Transacionais (Pedidos e Entregas)

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# TEMPO — 2024-01-01 a 2026-09-30
# ─────────────────────────────────────────────────────────────

_feriados = {
    "2024-01-01","2024-02-12","2024-02-13","2024-03-29","2024-04-21",
    "2024-05-01","2024-05-30","2024-09-07","2024-10-12","2024-11-02",
    "2024-11-15","2024-11-20","2024-12-25",
    "2025-01-01","2025-03-03","2025-03-04","2025-04-18","2025-04-21",
    "2025-05-01","2025-06-19","2025-09-07","2025-10-12","2025-11-02",
    "2025-11-15","2025-11-20","2025-12-25",
    "2026-01-01","2026-02-16","2026-02-17","2026-04-03","2026-04-21",
    "2026-05-01","2026-06-04","2026-09-07",
}
_mes_nomes = ["", "Jan", "Fev", "Mar", "Abr", "Mai", "Jun",
              "Jul", "Ago", "Set", "Out", "Nov", "Dez"]
_dia_nomes = ["Seg", "Ter", "Qua", "Qui", "Sex", "Sab", "Dom"]

tempo_dw_rows = []
dt = date(2024, 1, 1)
sk = 1
while dt <= date(2026, 9, 30):
    ds = dt.isoformat()
    semana_do_ano = dt.isocalendar()[1]
    tempo_dw_rows.append({
        "sk_tempo": int(dt.strftime("%Y%m%d")),
        "data_completa": ds,
        "dia": dt.day,
        "mes": dt.month,
        "ano": dt.year,
        "trimestre": (dt.month - 1) // 3 + 1,
        "semana_do_ano": semana_do_ano,
        "dia_da_semana": dt.weekday() + 1,  # 1=Seg ... 7=Dom
        "nome_dia_semana": _dia_nomes[dt.weekday()],
        "nome_mes": _mes_nomes[dt.month],
        "flag_feriado": 1 if ds in _feriados else 0,
        "flag_fim_semana": 1 if dt.weekday() >= 5 else 0,
        "descricao_feriado": None,
    })
    dt += timedelta(days=1)
    sk += 1

df_dim_tempo_dw = pd.DataFrame(tempo_dw_rows)

# Lookup: data por sk_tempo
_data_por_sk_tempo = dict(zip(df_dim_tempo_dw["sk_tempo"], df_dim_tempo_dw["data_completa"]))
_dias_uteis_sk = df_dim_tempo_dw[
    (df_dim_tempo_dw["flag_fim_semana"] == 0) &
    (df_dim_tempo_dw["flag_feriado"] == 0)
]["sk_tempo"].values

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# PEDIDO, ITEM_PEDIDO, ENTREGA — ~50.000 entregas
# ─────────────────────────────────────────────────────────────

N_ENTREGAS = 49_770
_cd_pesos = [0.20, 0.25, 0.15, 0.25, 0.15]  # pesos para 5 CDs

# Gerar datas e IDs
sk_datas = rng.choice(_dias_uteis_sk, size=N_ENTREGAS, replace=True)
sk_clientes = rng.integers(1, 201, size=N_ENTREGAS)
sk_veiculos = rng.integers(1, 51, size=N_ENTREGAS)
sk_motoristas = rng.integers(1, 101, size=N_ENTREGAS)
sk_cd_origens = rng.choice([1, 2, 3, 4, 5], size=N_ENTREGAS, p=_cd_pesos)

# Distância: log-normal centrada em ~130 km (ln(130) ≈ 4.87)
distancias = np.clip(np.round(np.exp(rng.normal(4.87, 0.65, N_ENTREGAS)), 1), 15.0, 1500.0)

# Peso: normal com média 2.500 kg
pesos = np.clip(np.round(rng.normal(2500, 1100, N_ENTREGAS)), 50, 25000).astype(float)

# Quantidade de volumes: média de 10 volumes por entrega
quantidade_volumes = np.clip(np.round(rng.normal(10, 5, N_ENTREGAS)), 1, 50).astype(int)

# Hora de saída: 06:00–17:59
hh = rng.integers(6, 18, N_ENTREGAS)
mm = rng.integers(0, 60, N_ENTREGAS)

# Atraso: 40% adiantado, 42% pontual, 14% atrasado leve, 4% muito atrasado
_tipo = rng.choice(["adi", "ok", "lat", "mla"], N_ENTREGAS, p=[0.40, 0.42, 0.14, 0.04])
atraso = np.zeros(N_ENTREGAS, dtype=int)
atraso[_tipo == "adi"] = -rng.integers(5, 61, (_tipo == "adi").sum())
atraso[_tipo == "lat"] = rng.integers(1, 121, (_tipo == "lat").sum())
atraso[_tipo == "mla"] = rng.integers(121, 481, (_tipo == "mla").sum())

# Tempo estimado: baseado em velocidade média de 50 km/h
tempo_estimado_min = np.round(distancias * 1.2, 0).astype(int)
# Tempo real: baseado no tempo estimado com ruído
ruido_tempo = rng.normal(0, 15, N_ENTREGAS)
tempo_real_min = tempo_estimado_min + ruido_tempo.astype(int)
tempo_real_min = np.clip(tempo_real_min, 1, None)

# Valor frete: baseado em distância e peso, com ruído
valor_frete = np.round(distancias * 2.5 + pesos * 0.5 + rng.uniform(-100, 500, N_ENTREGAS), 2)

# Custos
custo_comb = np.clip(np.round(distancias * 0.75 * rng.normal(1.0, 0.12, N_ENTREGAS), 2), 15.0, 3500.0)
custo_pedagio = np.round(distancias * rng.uniform(0.30, 0.70, N_ENTREGAS), 2)
custo_total = np.round(custo_comb * rng.uniform(1.20, 1.50, N_ENTREGAS) + custo_pedagio + valor_frete, 2)

# Multa atraso: 10% do valor frete para entregas atrasadas
multa_atraso = np.zeros(N_ENTREGAS)
multa_atraso[atraso > 0] = np.round(valor_frete[atraso > 0] * 0.10, 2)

# Temperatura do motor
temp_motor = np.clip(np.round(rng.normal(96, 8, N_ENTREGAS), 1), 70.0, 115.0)

# Indicador atraso
indicador_atraso = (atraso > 0).astype(int)

# Datas e horas
datas_str = [_data_por_sk_tempo[s] for s in sk_datas]
datas_dt = [datetime.strptime(d, "%Y-%m-%d") for d in datas_str]
horas_str = [f"{d.year:04d}-{d.month:02d}-{d.day:02d} {h:02d}:{m:02d}:00"
             for d, h, m in zip(datas_dt, hh, mm)]

# Criar pedidos e entregas
pedidos_op = []
entregas_op = []
item_pedido_op = []

pedido_id = 1
entrega_id = 1
item_id = 1

for i in range(N_ENTREGAS):
    # Dados da entrega
    sk_data = sk_datas[i]
    sk_cliente = sk_clientes[i]
    sk_cd = sk_cd_origens[i]
    sk_veiculo = sk_veiculos[i]
    sk_motorista = sk_motoristas[i]
    
    data_entrega_str = datas_str[i]
    hora_saida_str = horas_str[i]
    
    # Gerar data_pedido: 1-3 dias antes da entrega
    data_pedido_dt = datas_dt[i] - timedelta(days=random.randint(1, 3))
    prazo_entrega_dt = datas_dt[i] + timedelta(hours=random.randint(12, 48))
    
    # Data real de entrega = hora_saida + tempo_real_min
    data_saida_dt = datetime.strptime(hora_saida_str, "%Y-%m-%d %H:%M:%S")
    data_entrega_real_dt = data_saida_dt + timedelta(minutes=int(tempo_real_min[i]))
    
    # Status: Entregue (com alguams exceções para variação)
    if atraso[i] > 300:  # Muito atrasado
        status_pedido = "Entregue"
        status_entrega = "Ocorrência"
    elif atraso[i] > 0:
        status_pedido = "Entregue"
        status_entrega = "Entregue"
    elif atraso[i] < 0:
        status_pedido = "Entregue"
        status_entrega = "Entregue"
    else:
        status_pedido = "Entregue"
        status_entrega = "Entregue"
    
    # Prioridade
    if distancias[i] > 1000:
        prioridade = "Alta"
    elif distancias[i] > 500:
        prioridade = "Normal"
    else:
        prioridade = random.choice(["Normal", "Baixa"])
    
    # Pedido
    pedidos_op.append({
        "pedido_id": pedido_id,
        "numero_pedido": f"PED-{datas_str[i][:4]}-{pedido_id:06d}",
        "cliente_id": sk_cliente,
        "contrato_id": random.choice([None, sk_cliente]),  # Nem todos tem contrato
        "cd_origem_id": sk_cd,
        "endereco_destino_id": sk_cliente,  # Simplificação: usando cliente_id como endereco_id
        "data_pedido": f"{data_pedido_dt.strftime('%Y-%m-%d')} {random.randint(8, 17):02d}:00:00",
        "prazo_entrega": f"{prazo_entrega_dt.strftime('%Y-%m-%d %H:%M:%S')}",
        "prioridade": prioridade,
        "status_pedido": status_pedido,
    })
    
    # Entrega
    # v2: calcular KPI categoria_atraso (derivado de minutos_atraso)
    _min_atraso = int(atraso[i])
    if _min_atraso < 0:
        _kpi_cat = "Adiantado"
    elif _min_atraso == 0:
        _kpi_cat = "No Prazo"
    elif _min_atraso <= 60:
        _kpi_cat = "Atraso Leve"
    elif _min_atraso <= 240:
        _kpi_cat = "Atraso Moderado"
    else:
        _kpi_cat = "Atraso Crítico"

    # v2: buscar dados redundantes (proposital, 2FN) das entidades relacionadas
    _cli = df_cliente_op.iloc[sk_cliente - 1]
    _vei = df_veiculo_op.iloc[sk_veiculo - 1]
    _mot = df_motorista_op.iloc[sk_motorista - 1]
    _cd  = df_centro_distribuicao_op.iloc[sk_cd - 1]

    entregas_op.append({
        "entrega_id": entrega_id,
        "pedido_id": pedido_id,
        "veiculo_id": sk_veiculo,
        "motorista_id": sk_motorista,

        # ▓ v2: dados redundantes do cliente (dependência transitiva)
        "cliente_id":            int(sk_cliente),
        "cliente_cnpj":          _cli["cnpj"],
        "cliente_razao_social":  _cli["razao_social"],
        "cliente_segmento":      _cli["segmento"],

        # ▓ v2: dados redundantes do veículo
        "veiculo_placa":         _vei["placa"],
        "veiculo_modelo":        _vei["modelo"],
        "veiculo_fabricante":    _vei["fabricante"],
        "veiculo_capacidade_kg": float(_vei["capacidade_kg"]),

        # ▓ v2: dados redundantes do motorista
        "motorista_nome":        _mot["nome_completo"],
        "motorista_cnh":         _mot["cnh"],
        "motorista_categoria":   _mot["categoria_cnh"],

        # ▓ v2: dados redundantes do CD origem
        "cd_origem_id":          int(sk_cd),
        "cd_origem_codigo":      _cd["codigo"],
        "cd_origem_nome":        _cd["nome"],
        "cd_origem_uf":          _cd["uf"],

        "data_saida": hora_saida_str,
        "data_entrega_prevista": f"{prazo_entrega_dt.strftime('%Y-%m-%d %H:%M:%S')}",
        "data_entrega_real": data_entrega_real_dt.strftime("%Y-%m-%d %H:%M:%S"),
        "distancia_km": round(float(distancias[i]), 2),
        "custo_combustivel": round(float(custo_comb[i]), 2),
        "custo_pedagio": round(float(custo_pedagio[i]), 2),
        "valor_frete": round(float(valor_frete[i]), 2),
        "multa_atraso": round(float(multa_atraso[i]), 2),
        "status_entrega": status_entrega,

        # ⭐ v2: KPI categoria_atraso
        "kpi_cat_atraso": _kpi_cat,
    })
    
    # Itens do pedido: 1-5 itens por pedido
    n_itens = random.randint(1, 5)
    peso_total_item = pesos[i]
    
    for j in range(n_itens):
        produto_id = random.randint(1, 50)
        peso_item = round(peso_total_item * (0.5 + random.random()), 2)
        qtd = random.randint(1, 10)
        
        item_pedido_op.append({
            "item_id": item_id,
            "pedido_id": pedido_id,
            "produto_id": produto_id,
            "quantidade": qtd,
            "peso_total_kg": round(qtd * peso_item, 2),
        })
        
        item_id += 1
    
    pedido_id += 1
    entrega_id += 1

df_pedido_op = pd.DataFrame(pedidos_op)
df_entrega_op = pd.DataFrame(entregas_op)
df_item_pedido_op = pd.DataFrame(item_pedido_op)

print(f"Pedidos gerados: {len(df_pedido_op):,}")
print(f"Entregas geradas: {len(df_entrega_op):,}")
print(f"Itens de pedido gerados: {len(df_item_pedido_op):,}")

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# TELEMETRIA — simplificada (1 registro por entrega)
# ─────────────────────────────────────────────────────────────

telemetrias_op = []
for i, entrega in df_entrega_op.iterrows():
    data_evento_dt = datetime.strptime(entrega["data_saida"], "%Y-%m-%d %H:%M:%S")
    
    telemetrias_op.append({
        "telemetria_id": i + 1,
        "veiculo_id": entrega["veiculo_id"],
        "timestamp_evento": entrega["data_saida"],
        "data_evento": data_evento_dt.strftime("%Y-%m-%d"),
        "latitude": round(random.uniform(-30, -15), 6),
        "longitude": round(random.uniform(-55, -35), 6),
        "velocidade_kmh": round(random.uniform(0, 110), 2),
        "rpm_motor": random.randint(800, 3000),
        "temperatura_motor_c": round(random.uniform(80, 110), 2),
        "nivel_combustivel_pct": round(random.uniform(10, 100), 2),
        "peso_carga_kg": round(random.uniform(100, 25000), 2),
        "hodometro_km": random.randint(50000, 300000),
    })

df_telemetria_op = pd.DataFrame(telemetrias_op)

# COMMAND ----------

# MAGIC %md
# MAGIC ## Parte 3: SALVAR DADOS OPERACIONAIS (lodlog_op)

# COMMAND ----------

from pyspark.sql import functions as F
from pyspark.sql.types import DateType, TimestampType, IntegerType, DoubleType, DecimalType

# Criar database se não existir
spark.sql("CREATE DATABASE IF NOT EXISTS lodlog_op")
spark.sql("USE lodlog_op")

def _save_op(df_pd, nome, tipo_cast=None):
    spark.sql(f"DROP TABLE IF EXISTS lodlog_op.{nome}")
    df_sp = spark.createDataFrame(df_pd)
    if tipo_cast:
        for col, t in tipo_cast.items():
            df_sp = df_sp.withColumn(col, F.col(col).cast(t))
    (df_sp.write.format("delta")
         .mode("overwrite")
         .option("overwriteSchema", "true")
         .saveAsTable(f"lodlog_op.{nome}"))
    n = spark.table(f"lodlog_op.{nome}").count()
    print(f"  ✓ lodlog_op.{nome}: {n:,} linhas")

print("Salvando tabelas operacionais (lodlog_op)...")

# Tabelas mestre
_save_op(df_cliente_op, "cliente", {
    "data_cadastro": DateType(),
    "ativo": "boolean"
})
_save_op(df_endereco_cliente_op, "endereco_cliente", {
    "latitude": DecimalType(9, 6),
    "longitude": DecimalType(9, 6)
})
_save_op(df_contrato_op, "contrato", {
    "data_inicio": DateType(),
    "data_fim": DateType()
})
_save_op(df_centro_distribuicao_op, "centro_distribuicao", {
    "capacidade_m3": DecimalType(10, 2),
    "latitude": DecimalType(9, 6),
    "longitude": DecimalType(9, 6),
    "ativo": "boolean"
})

# Frota
_save_op(df_veiculo_op, "veiculo", {
    "capacidade_kg": DecimalType(10, 2),
    "hodometro_km": DecimalType(10, 0),
    "data_aquisicao": DateType()
})
_save_op(df_motorista_op, "motorista", {
    "score_seguranca": DecimalType(5, 2),
    "data_admissao": DateType(),
    "validade_cnh": DateType()
})
_save_op(df_manutencao_op, "manutencao", {
    "data_abertura": TimestampType(),
    "data_conclusao": TimestampType(),
    "km_no_momento": DecimalType(10, 0),
    "custo_total": DecimalType(12, 2)
})

# Estoque
_save_op(df_produto_op, "produto", {
    "peso_unitario_kg": DecimalType(10, 3),
    "volume_unitario_m3": DecimalType(10, 4),
    "ativo": "boolean"
})
_save_op(df_estoque_op, "estoque", {
    "ultima_atualizacao": TimestampType()
})
_save_op(df_movimentacao_estoque_op, "movimentacao_estoque", {
    "timestamp_mov": TimestampType()
})

# Operação
_save_op(df_pedido_op, "pedido", {
    "data_pedido": TimestampType(),
    "prazo_entrega": TimestampType()
})
_save_op(df_entrega_op, "entrega", {
    "data_saida": TimestampType(),
    "data_entrega_prevista": TimestampType(),
    "data_entrega_real": TimestampType(),
    "distancia_km": DecimalType(10, 2),
    "custo_combustivel": DecimalType(12, 2),
    "custo_pedagio": DecimalType(12, 2),
    "valor_frete": DecimalType(12, 2),
    "multa_atraso": DecimalType(12, 2),
    # v2: colunas redundantes (2FN) + KPI
    "veiculo_capacidade_kg": DecimalType(10, 2)
})
_save_op(df_item_pedido_op, "item_pedido", {
    "peso_total_kg": DecimalType(10, 2)
})

# Telemetria
_save_op(df_telemetria_op, "telemetria", {
    "timestamp_evento": TimestampType(),
    "data_evento": DateType(),
    "latitude": DecimalType(9, 6),
    "longitude": DecimalType(9, 6),
    "velocidade_kmh": DecimalType(6, 2),
    "temperatura_motor_c": DecimalType(6, 2),
    "nivel_combustivel_pct": DecimalType(5, 2),
    "peso_carga_kg": DecimalType(10, 2),
    "hodometro_km": DecimalType(10, 0)
})

print("\nTabelas operacionais salvo com sucesso!")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Parte 4: ETL para lodlog_dw (Star Schema)

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# DIM_CATEGORIA_ATRASO — NOVA v2 (minidimensão Kimball, SCD Tipo 1)
# ─────────────────────────────────────────────────────────────

print("\nProcessando ETL para lodlog_dw...")

# Criar database se não existir
spark.sql("CREATE DATABASE IF NOT EXISTS lodlog_dw")
spark.sql("USE lodlog_dw")

dim_cat_atraso_dw = [
    {
        "sk_cat_atraso": 1,
        "categoria":            "Adiantado",
        "descricao":            "Entrega concluída antes do prazo previsto",
        "limite_inferior_min":  -99999,
        "limite_superior_min":  -1,
        "sla_violado":          False,
        "ordem":                1,
    },
    {
        "sk_cat_atraso": 2,
        "categoria":            "No Prazo",
        "descricao":            "Entrega concluída exatamente no prazo previsto",
        "limite_inferior_min":  0,
        "limite_superior_min":  0,
        "sla_violado":          False,
        "ordem":                2,
    },
    {
        "sk_cat_atraso": 3,
        "categoria":            "Atraso Leve",
        "descricao":            "Atraso de até 60 minutos — dentro de margem tolerável",
        "limite_inferior_min":  1,
        "limite_superior_min":  60,
        "sla_violado":          True,
        "ordem":                3,
    },
    {
        "sk_cat_atraso": 4,
        "categoria":            "Atraso Moderado",
        "descricao":            "Atraso entre 61 e 240 minutos — impacta SLA contratual",
        "limite_inferior_min":  61,
        "limite_superior_min":  240,
        "sla_violado":          True,
        "ordem":                4,
    },
    {
        "sk_cat_atraso": 5,
        "categoria":            "Atraso Crítico",
        "descricao":            "Atraso acima de 240 minutos — pode gerar multa e perda de cliente",
        "limite_inferior_min":  241,
        "limite_superior_min":  None,
        "sla_violado":          True,
        "ordem":                5,
    },
]
df_dim_cat_atraso_dw = pd.DataFrame(dim_cat_atraso_dw)

def _save_dw(df_pd, nome, tipo_cast=None):
    spark.sql(f"DROP TABLE IF EXISTS lodlog_dw.{nome}")
    df_sp = spark.createDataFrame(df_pd)
    if tipo_cast:
        for col, t in tipo_cast.items():
            df_sp = df_sp.withColumn(col, F.col(col).cast(t))
    (df_sp.write.format("delta")
         .mode("overwrite")
         .option("overwriteSchema", "true")
         .saveAsTable(f"lodlog_dw.{nome}"))
    n = spark.table(f"lodlog_dw.{nome}").count()
    print(f"  ✓ lodlog_dw.{nome}: {n:,} linhas")

# Salvar dim_cat_atraso (v2)
_save_dw(df_dim_cat_atraso_dw, "dim_cat_atraso", {
    "sk_cat_atraso": IntegerType(),
    "limite_inferior_min": IntegerType(),
    "limite_superior_min": IntegerType(),
    "sla_violado": "boolean",
    "ordem": IntegerType(),
})

# Salvar dim_tempo
_save_dw(df_dim_tempo_dw, "dim_tempo", {
    "sk_tempo": IntegerType(),
    "data_completa": DateType(),
    "flag_feriado": "boolean",
    "flag_fim_semana": "boolean"
})

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# DIM_CENTRO_DISTRIBUICAO — SCD Tipo 1 (atualização no lugar)
# ─────────────────────────────────────────────────────────────

# Mapear região com base no UF
regiao_map = {
    "SP": "Sudeste", "MG": "Sudeste", "RJ": "Sudeste", "ES": "Sudeste",
    "PR": "Sul", "RS": "Sul", "SC": "Sul",
    "GO": "Centro-Oeste", "DF": "Centro-Oeste", "MT": "Centro-Oeste", "MS": "Centro-Oeste",
    "BA": "Nordeste", "PE": "Nordeste", "CE": "Nordeste", "RN": "Nordeste",
    "MA": "Nordeste", "PI": "Nordeste", "SE": "Nordeste", "AL": "Nordeste", "PB": "Nordeste",
    "PA": "Norte", "AM": "Norte", "AC": "Norte", "RO": "Norte", "RR": "Norte", "AP": "Norte", "TO": "Norte"
}

dim_cd_dw = []
for i, cd in df_centro_distribuicao_op.iterrows():
    dim_cd_dw.append({
        "sk_cd": cd["cd_id"],
        "cd_id": cd["cd_id"],
        "codigo": cd["codigo"],
        "nome": cd["nome"],
        "municipio": cd["municipio"],
        "uf": cd["uf"],
        "regiao": regiao_map.get(cd["uf"], "Sudeste"),
        "capacidade_m3": cd["capacidade_m3"],
        "latitude": cd["latitude"],
        "longitude": cd["longitude"],
    })

df_dim_cd_dw = pd.DataFrame(dim_cd_dw)

_save_dw(df_dim_cd_dw, "dim_centro_distribuicao", {
    "capacidade_m3": DecimalType(10, 2),
    "latitude": DecimalType(9, 6),
    "longitude": DecimalType(9, 6)
})

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# DIM_CLIENTE — SCD Tipo 2
# ─────────────────────────────────────────────────────────────

# Mapear região com base no UF do endereço
dim_cliente_dw = []
for i, cliente in df_cliente_op.iterrows():
    # Buscar endereço
    endereco = df_endereco_cliente_op[df_endereco_cliente_op["cliente_id"] == cliente["cliente_id"]].iloc[0]
    uf = endereco["uf"]
    municipio = endereco["municipio"]
    
    # Tempo de relacionamento em meses
    data_cadastro = date.fromisoformat(cliente["data_cadastro"])
    tempo_meses = (date(2024, 6, 1) - data_cadastro).days // 30
    
    # Buscar contrato para SLA
    contrato = df_contrato_op[df_contrato_op["cliente_id"] == cliente["cliente_id"]].iloc[0]
    sla = contrato["sla_pontualidade_pct"]
    
    dim_cliente_dw.append({
        "sk_cliente": cliente["cliente_id"],
        "cliente_id": cliente["cliente_id"],
        "cnpj": cliente["cnpj"],
        "razao_social": cliente["razao_social"],
        "segmento": cliente["segmento"],
        "municipio": municipio,
        "uf": uf,
        "regiao": regiao_map.get(uf, "Sudeste"),
        "tempo_relacionamento_meses": tempo_meses,
        "sla_contratual_pct": sla,
        "data_inicio_vigencia": cliente["data_cadastro"],
        "data_fim_vigencia": None,
        "flag_registro_atual": True,
    })

df_dim_cliente_dw = pd.DataFrame(dim_cliente_dw)

_save_dw(df_dim_cliente_dw, "dim_cliente", {
    "sk_cliente": "long",
    "cliente_id": "long",
    "sla_contratual_pct": DecimalType(5, 2),
    "data_inicio_vigencia": DateType(),
    "data_fim_vigencia": DateType(),
    "flag_registro_atual": "boolean"
})

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# DIM_VEICULO — SCD Tipo 2
# ─────────────────────────────────────────────────────────────

def get_faixa_capacidade(capacidade):
    if capacidade <= 1000:
        return "Até 1t"
    elif capacidade <= 5000:
        return "1-5t"
    elif capacidade <= 15000:
        return "5-15t"
    else:
        return "Acima 15t"

dim_veiculo_dw = []
for i, veiculo in df_veiculo_op.iterrows():
    dim_veiculo_dw.append({
        "sk_veiculo": veiculo["veiculo_id"],
        "veiculo_id": veiculo["veiculo_id"],
        "placa": veiculo["placa"],
        "modelo": veiculo["modelo"],
        "fabricante": veiculo["fabricante"],
        "ano_fabricacao": veiculo["ano_fabricacao"],
        "tipo": veiculo["tipo"],
        "capacidade_kg": veiculo["capacidade_kg"],
        "faixa_capacidade": get_faixa_capacidade(veiculo["capacidade_kg"]),
        "data_inicio_vigencia": veiculo["data_aquisicao"],
        "data_fim_vigencia": None,
        "flag_registro_atual": True,
    })

df_dim_veiculo_dw = pd.DataFrame(dim_veiculo_dw)

_save_dw(df_dim_veiculo_dw, "dim_veiculo", {
    "sk_veiculo": "long",
    "veiculo_id": "long",
    "capacidade_kg": DecimalType(10, 2),
    "data_inicio_vigencia": DateType(),
    "data_fim_vigencia": DateType(),
    "flag_registro_atual": "boolean"
})

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# DIM_MOTORISTA — SCD Tipo 2
# ─────────────────────────────────────────────────────────────

dim_motorista_dw = []
for i, motorista in df_motorista_op.iterrows():
    # Tempo de empresa em meses
    data_admissao = date.fromisoformat(motorista["data_admissao"])
    tempo_meses = (date(2024, 6, 1) - data_admissao).days // 30
    
    # Faixa de experiência
    if tempo_meses < 24:
        faixa = "Júnior"
    elif tempo_meses < 96:
        faixa = "Pleno"
    else:
        faixa = "Sênior"
    
    dim_motorista_dw.append({
        "sk_motorista": motorista["motorista_id"],
        "motorista_id": motorista["motorista_id"],
        "nome_completo": motorista["nome_completo"],
        "categoria_cnh": motorista["categoria_cnh"],
        "tempo_empresa_meses": tempo_meses,
        "faixa_experiencia": faixa,
        "score_seguranca": motorista["score_seguranca"],
        "data_inicio_vigencia": motorista["data_admissao"],
        "data_fim_vigencia": None,
        "flag_registro_atual": True,
    })

df_dim_motorista_dw = pd.DataFrame(dim_motorista_dw)

_save_dw(df_dim_motorista_dw, "dim_motorista", {
    "sk_motorista": "long",
    "motorista_id": "long",
    "tempo_empresa_meses": IntegerType(),
    "score_seguranca": DecimalType(5, 2),
    "data_inicio_vigencia": DateType(),
    "data_fim_vigencia": DateType(),
    "flag_registro_atual": "boolean"
})

# COMMAND ----------

# MAGIC %md
# MAGIC ## Parte 5: FATO_ENTREGAS com Anomalias

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# Criar DataFrame base do fato_entregas a partir das entregas operacionais
# ─────────────────────────────────────────────────────────────

# Mapear entregas para dimensoes
fato_data = []
for i, entrega in df_entrega_op.iterrows():
    # Buscar pedido correspondente
    pedido = df_pedido_op[df_pedido_op["pedido_id"] == entrega["pedido_id"]].iloc[0]
    
    # Data de entrega (do pedido ou da entrega real)
    if pd.notna(entrega["data_entrega_real"]):
        data_entrega = entrega["data_entrega_real"][:10]  # Apenas a data
        sk_data = int(datetime.strptime(data_entrega, "%Y-%m-%d").strftime("%Y%m%d"))
    else:
        data_entrega = entrega["data_entrega_prevista"][:10]
        sk_data = int(datetime.strptime(data_entrega, "%Y-%m-%d").strftime("%Y%m%d"))
    
    # Tempo real em minutos (calculado a partir das datas)
    if pd.notna(entrega["data_entrega_real"]):
        data_saida = datetime.strptime(entrega["data_saida"], "%Y-%m-%d %H:%M:%S")
        data_entrega_real = datetime.strptime(entrega["data_entrega_real"], "%Y-%m-%d %H:%M:%S")
        minutos_atraso = int((data_entrega_real - data_saida).total_seconds() / 60) - int(entrega["tempo_estimado_min"] if "tempo_estimado_min" in entrega else 0)
    else:
        minutos_atraso = 0
    
    # Se minutos_atraso for negativo, é adiantado
    indicador_atraso = 1 if minutos_atraso > 0 else 0

    # Buscar peso total do pedido
    itens = df_item_pedido_op[df_item_pedido_op["pedido_id"] == entrega["pedido_id"]]
    peso_total = itens["peso_total_kg"].sum()

    # v2: mapear kpi_cat_atraso a partir do minutos_atraso calculado
    if minutos_atraso < 0:
        _kpi_fato = "Adiantado"
        _sk_cat_atraso = 1
    elif minutos_atraso == 0:
        _kpi_fato = "No Prazo"
        _sk_cat_atraso = 2
    elif minutos_atraso <= 60:
        _kpi_fato = "Atraso Leve"
        _sk_cat_atraso = 3
    elif minutos_atraso <= 240:
        _kpi_fato = "Atraso Moderado"
        _sk_cat_atraso = 4
    else:
        _kpi_fato = "Atraso Crítico"
        _sk_cat_atraso = 5
    
    fato_data.append({
        "sk_entrega": i + 1,
        "sk_data": sk_data,
        "sk_cliente": pedido["cliente_id"],
        "sk_cd_origem": pedido["cd_origem_id"],
        "sk_veiculo": entrega["veiculo_id"],
        "sk_motorista": entrega["motorista_id"],
        "entrega_id": entrega["entrega_id"],
        "pedido_id": entrega["pedido_id"],
        "data_entrega": data_entrega,
        "hora_saida": entrega["data_saida"],
        "quantidade_volumes": int(len(itens)),
        "peso_total_kg": round(float(peso_total), 2),
        "distancia_km": float(entrega["distancia_km"]),
        "tempo_estimado_min": int(float(entrega["distancia_km"]) * 1.2),
        "tempo_real_min": int(minutos_atraso + int(float(entrega["distancia_km"]) * 1.2)) if minutos_atraso >= 0 else int(float(entrega["distancia_km"]) * 1.2) + minutos_atraso,
        "custo_combustivel": float(entrega["custo_combustivel"]),
        "custo_pedagio": float(entrega["custo_pedagio"]),
        "valor_frete": float(entrega["valor_frete"]),
        "multa_atraso": float(entrega["multa_atraso"]),
        "minutos_atraso": minutos_atraso,
        "indicador_atraso": indicador_atraso,
        "temperatura_media_motor": round(random.uniform(85, 105), 2),
        # v2: minidimensão categoria_atraso + atributo replicado
        "sk_cat_atraso": _sk_cat_atraso,
        "kpi_cat_atraso": _kpi_fato,
    })

df_fato_clean = pd.DataFrame(fato_data)

print(f"Fato entregas base: {len(df_fato_clean):,} linhas")

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# ANOMALIAS PROPOSITAIS — para a Parte 4 do LAB 3
# ─────────────────────────────────────────────────────────────

anomalias = []
sk_next = len(df_fato_clean) + 1
_sample = lambda n: df_fato_clean.sample(n, random_state=SEED).copy()

# --- Anomalia 1 · Duplicatas (100 linhas) ---
for _, row in _sample(100).iterrows():
    row = row.copy()
    row["sk_entrega"] = sk_next
    row["custo_combustivel"] = round(float(row["custo_combustivel"]) * random.uniform(0.98, 1.02), 2)
    anomalias.append(row.to_dict())
    sk_next += 1

# --- Anomalia 2 · Valores negativos (50 linhas) ---
for _, row in _sample(50).iterrows():
    row = row.copy()
    row["sk_entrega"] = sk_next
    row["pedido_id"] = f"PED-NEG-{sk_next:06d}"
    campo = random.choice(["distancia_km", "peso_total_kg", "custo_combustivel"])
    row[campo] = -abs(float(row[campo]))
    anomalias.append(row.to_dict())
    sk_next += 1

# --- Anomalia 3 · Outliers em minutos_atraso (30 linhas) ---
for _, row in _sample(30).iterrows():
    row = row.copy()
    row["sk_entrega"] = sk_next
    row["pedido_id"] = f"PED-OUT-{sk_next:06d}"
    row["minutos_atraso"] = random.choice([
        random.randint(1_001, 5_760),   # até 4 dias de atraso
        random.randint(-1_440, -481),   # adiantamento impossível
    ])
    anomalias.append(row.to_dict())
    sk_next += 1

# --- Anomalia 4 · FK quebrada — sk_cliente inexistente (50 linhas) ---
for _, row in _sample(50).iterrows():
    row = row.copy()
    row["sk_entrega"] = sk_next
    row["pedido_id"] = f"PED-FKB-{sk_next:06d}"
    row["sk_cliente"] = random.randint(201, 300)
    anomalias.append(row.to_dict())
    sk_next += 1

df_anomalias = pd.DataFrame(anomalias)
df_fato_entregas_dw = (
    pd.concat([df_fato_clean, df_anomalias], ignore_index=True)
    .sample(frac=1, random_state=SEED)
    .reset_index(drop=True)
)

print(f"fato_entregas total: {len(df_fato_entregas_dw):,} linhas ({len(df_anomalias)} anômalas)")

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# SALVAR FATO_ENTREGAS
# ─────────────────────────────────────────────────────────────

# Convert pedido_id to string to handle mixed integer/string values from anomalies
df_fato_entregas_dw["pedido_id"] = df_fato_entregas_dw["pedido_id"].astype(str)

_save_dw(df_fato_entregas_dw, "fato_entregas", {
    "sk_entrega": "long",
    "sk_data": IntegerType(),
    "sk_cliente": "long",
    "sk_cd_origem": "long",
    "sk_veiculo": "long",
    "sk_motorista": "long",
    "entrega_id": "long",
    "pedido_id": "string",
    "data_entrega": DateType(),
    "hora_saida": TimestampType(),
    "quantidade_volumes": IntegerType(),
    "peso_total_kg": DecimalType(10, 2),
    "distancia_km": DecimalType(10, 2),
    "tempo_estimado_min": IntegerType(),
    "tempo_real_min": IntegerType(),
    "custo_combustivel": DecimalType(12, 2),
    "custo_pedagio": DecimalType(12, 2),
    "valor_frete": DecimalType(12, 2),
    "multa_atraso": DecimalType(12, 2),
    "minutos_atraso": IntegerType(),
    "indicador_atraso": "int",
    "temperatura_media_motor": DecimalType(6, 2),
    # v2: minidimensão categoria_atraso
    "sk_cat_atraso": IntegerType(),
    "kpi_cat_atraso": "string"
})

# COMMAND ----------

# MAGIC %md
# MAGIC ## Parte 6: OPTIMIZE e Validação

# COMMAND ----------

# Otimizar tabelas com ZORDER
print("\nOtimizando tabelas...")
spark.sql("OPTIMIZE lodlog_dw.fato_entregas ZORDER BY (sk_data, sk_cd_origem, indicador_atraso, sk_cat_atraso)")
spark.sql("OPTIMIZE lodlog_dw.dim_tempo ZORDER BY (sk_tempo)")
spark.sql("OPTIMIZE lodlog_dw.dim_cat_atraso ZORDER BY (sk_cat_atraso)")
spark.sql("OPTIMIZE lodlog_op.entrega ZORDER BY (status_entrega, data_saida)")
spark.sql("OPTIMIZE lodlog_op.pedido ZORDER BY (cliente_id, status_pedido)")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Verificação Final

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Confirme as tabelas e contagens em lodlog_op
# MAGIC SELECT 'lodlog_op' AS schema, 'cliente' AS tabela, COUNT(*) AS linhas FROM lodlog_op.cliente UNION ALL
# MAGIC SELECT 'lodlog_op', 'veiculo', COUNT(*) FROM lodlog_op.veiculo UNION ALL
# MAGIC SELECT 'lodlog_op', 'motorista', COUNT(*) FROM lodlog_op.motorista UNION ALL
# MAGIC SELECT 'lodlog_op', 'centro_distribuicao', COUNT(*) FROM lodlog_op.centro_distribuicao UNION ALL
# MAGIC SELECT 'lodlog_op', 'pedido', COUNT(*) FROM lodlog_op.pedido UNION ALL
# MAGIC SELECT 'lodlog_op', 'entrega', COUNT(*) FROM lodlog_op.entrega;

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Confirme as tabelas e contagens em lodlog_dw
# MAGIC SELECT 'lodlog_dw' AS schema, 'dim_tempo' AS tabela, COUNT(*) AS linhas FROM lodlog_dw.dim_tempo UNION ALL
# MAGIC SELECT 'lodlog_dw', 'dim_cliente', COUNT(*) FROM lodlog_dw.dim_cliente UNION ALL
# MAGIC SELECT 'lodlog_dw', 'dim_veiculo', COUNT(*) FROM lodlog_dw.dim_veiculo UNION ALL
# MAGIC SELECT 'lodlog_dw', 'dim_motorista', COUNT(*) FROM lodlog_dw.dim_motorista UNION ALL
# MAGIC SELECT 'lodlog_dw', 'dim_centro_distribuicao', COUNT(*) FROM lodlog_dw.dim_centro_distribuicao UNION ALL
# MAGIC SELECT 'lodlog_dw', 'fato_entregas', COUNT(*) FROM lodlog_dw.fato_entregas;

# COMMAND ----------

# MAGIC %md
# MAGIC ### Setup Concluído!
# MAGIC
# MAGIC Execute os comandos a seguir para validar:
# MAGIC ```sql
# MAGIC USE lodlog_dw;
# MAGIC SELECT COUNT(*), COUNT(DISTINCT sk_entrega) FROM fato_entregas;
# MAGIC -- Deve retornar ~50.000 linhas e ~50.000 sk_entrega únicos (com duplicatas entre as anomalias)
# MAGIC ```
# MAGIC
# MAGIC **Anomalias propositais no fato_entregas (para Parte 4 do LAB 3):**
# MAGIC - 100 linhas duplicadas (mesmo pedido_id + data_entrega)
# MAGIC - 50 linhas com valores negativos (distancia_km, peso_total_kg ou custo_combustivel)
# MAGIC - 30 linhas com outliers em minutos_atraso (atrasos > 1000 min ou adiantamentos < -480 min)
# MAGIC - 50 linhas com FK quebrada (sk_cliente 201-300 não existem em dim_cliente)
