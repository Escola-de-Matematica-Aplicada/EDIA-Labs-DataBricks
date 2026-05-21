# Databricks notebook source
# Importar este arquivo no Databricks como notebook Python e executar UMA VEZ antes do LAB 3.
# File: lodlog_lab3_seed.py
# Uso: Workspace > Import > selecione este arquivo (.py) > Run All

# COMMAND ----------

# MAGIC %md
# MAGIC # LODLog — Geração de Dados Sintéticos · LAB 3
# MAGIC
# MAGIC Execute este notebook **uma única vez** antes do LAB 3.
# MAGIC
# MAGIC **Tabelas criadas no banco `lodlog`:**
# MAGIC
# MAGIC | Tabela | Linhas | Descrição |
# MAGIC |--------|--------|-----------|
# MAGIC | `dim_cliente` | 200 | Clientes LODLog |
# MAGIC | `dim_veiculo` | 50 | Frota de veículos |
# MAGIC | `dim_veiculo_manutencao` | ~220 | Histórico de manutenção |
# MAGIC | `dim_tempo` | 944 | Calendário 2024–2026 |
# MAGIC | `dim_clima` | 944 | Clima diário (ind_chuva) |
# MAGIC | `fato_entregas` | ~50.000 | Entregas com anomalias propositais |
# MAGIC
# MAGIC > **Spoiler para o professor:** as anomalias da Parte 4 estão documentadas ao final do notebook.

# COMMAND ----------

import random
import numpy as np
import pandas as pd
from datetime import date, timedelta

SEED = 42
random.seed(SEED)
np.random.seed(SEED)
rng = np.random.default_rng(SEED)

print("Gerando dados LODLog para o LAB 3...")

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# DIM_CLIENTE — 200 clientes  (sk_cliente 1–200)
# Anomalia 4 usa sk_cliente 201–300 (FK quebrada)
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

clientes = [{
    "sk_cliente": i,
    "cliente_id": f"CLI-{i:05d}",
    "nome_cliente": f"{random.choice(_bases)} {i:03d}",
    "segmento": random.choice(_segmentos),
    "cidade": random.choice(_cidades)[0],
    "estado": random.choice(_cidades)[1],
} for i in range(1, 201)]

df_dim_cliente = pd.DataFrame(clientes)

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# DIM_VEICULO — 50 veículos  +  DIM_VEICULO_MANUTENCAO
# ─────────────────────────────────────────────────────────────

_modelos = ["VW Delivery 9.170", "Mercedes-Benz Atego 2430",
            "Iveco Daily 35S14", "Ford Cargo 1723", "Scania R450",
            "MAN TGX 28.440", "Volvo FH 460", "Renault Master 2.3"]
_letras = "ABCDEFGHJKLMNPQRSTUVWXYZ"

veiculos = [{
    "veiculo_id": i,
    "modelo": random.choice(_modelos),
    "placa": (f"{''.join(random.choices(_letras, k=3))}"
              f"{random.randint(0,9)}{random.choice(_letras)}{random.randint(10,99)}"),
    "ano_fabricacao": random.randint(2015, 2023),
    "capacidade_kg": random.choice([3500, 5000, 8000, 15000, 25000]),
} for i in range(1, 51)]

df_dim_veiculo = pd.DataFrame(veiculos)

# Manutenção: 2–7 registros por veículo entre 2023-01-01 e 2026-05-01
_dt0 = date(2023, 1, 1)
_dt1 = date(2026, 5, 1)
_span = (_dt1 - _dt0).days
manut = []
for vid in range(1, 51):
    for dt in sorted(random.choices(
            [_dt0 + timedelta(days=d) for d in range(_span)],
            k=random.randint(2, 7))):
        manut.append({
            "veiculo_id": vid,
            "data_manutencao": dt.isoformat(),
            "tipo_manutencao": random.choice(
                ["Preventiva", "Corretiva", "Revisão geral", "Troca de óleo"]),
        })

df_dim_manutencao = pd.DataFrame(manut)

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# DIM_TEMPO — 2024-01-01 a 2026-09-30  (944 dias)
# DIM_CLIMA  — ind_chuva + temperatura por dia
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
_mes_nomes = ["","Jan","Fev","Mar","Abr","Mai","Jun",
              "Jul","Ago","Set","Out","Nov","Dez"]
_dia_nomes = ["Seg","Ter","Qua","Qui","Sex","Sab","Dom"]

tempo_rows, clima_rows = [], []
dt = date(2024, 1, 1)
sk = 1
while dt <= date(2026, 9, 30):
    ds = dt.isoformat()
    tempo_rows.append({
        "sk_data": sk, "data": ds,
        "dia_semana": dt.weekday(),
        "nome_dia": _dia_nomes[dt.weekday()],
        "mes": dt.month, "nome_mes": _mes_nomes[dt.month],
        "ano": dt.year, "trimestre": (dt.month - 1) // 3 + 1,
        "eh_feriado": 1 if ds in _feriados else 0,
        "eh_fim_de_semana": 1 if dt.weekday() >= 5 else 0,
    })
    # clima: 20% de dias com chuva; temperatura sazonal
    mes_fator = abs(dt.month - 6) / 6  # mais quente no verão BR (dez-jan)
    temp_base = 25 + 10 * (1 - mes_fator)
    clima_rows.append({
        "sk_data": sk,
        "ind_chuva": int(random.random() < 0.20),
        "temperatura_max_c": round(temp_base + random.uniform(-3, 6), 1),
        "temperatura_min_c": round(temp_base - random.uniform(5, 12), 1),
    })
    dt += timedelta(days=1)
    sk += 1

df_dim_tempo = pd.DataFrame(tempo_rows)
df_dim_clima = pd.DataFrame(clima_rows)

# Lookup: sk_data por data (string)
_sk_por_data = dict(zip(df_dim_tempo["data"], df_dim_tempo["sk_data"]))
# Dias úteis para geração de entregas
_dias_uteis_sk = df_dim_tempo[
    (df_dim_tempo["eh_fim_de_semana"] == 0) &
    (df_dim_tempo["eh_feriado"] == 0)
]["sk_data"].values

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# FATO_ENTREGAS — 49.770 linhas limpas
# ─────────────────────────────────────────────────────────────

N = 49_770
_cds = ["CD-SP-01","CD-SP-02","CD-SP-03","CD-SP-04","CD-SP-05",
        "CD-RJ-01","CD-RJ-02","CD-RJ-03","CD-MG-01","CD-PR-01"]
_cd_pesos = [0.18, 0.15, 0.12, 0.10, 0.08, 0.10, 0.07, 0.06, 0.08, 0.06]

sk_datas   = rng.choice(_dias_uteis_sk, size=N, replace=True)
sk_clientes = rng.integers(1, 201, size=N)
veic_ids   = rng.integers(1, 51, size=N)
motor_ids  = rng.integers(1, 101, size=N)
cds        = rng.choice(_cds, size=N, p=_cd_pesos)

# Distância: log-normal centrada em ~130 km (ln(130) ≈ 4.87)
distancias = np.clip(np.round(np.exp(rng.normal(4.87, 0.65, N)), 1), 15.0, 1500.0)

# Peso: normal com média 2.500 kg
pesos = np.clip(np.round(rng.normal(2500, 1100, N)), 50, 25000).astype(float)

# Hora de saída: 06:00–17:59
hh = rng.integers(6, 18, N)
mm = rng.integers(0, 60, N)

# Atraso: 40% adiantado, 42% pontual, 14% atrasado leve, 4% muito atrasado
_tipo = rng.choice(["adi","ok","lat","mla"], N, p=[0.40, 0.42, 0.14, 0.04])
atraso = np.zeros(N, dtype=int)
atraso[_tipo == "adi"] = -rng.integers(5,  61, (_tipo=="adi").sum())
atraso[_tipo == "lat"] =  rng.integers(1, 121, (_tipo=="lat").sum())
atraso[_tipo == "mla"] =  rng.integers(121, 481, (_tipo=="mla").sum())

# Custo combustível ≈ R$0.75/km + ruído ±12 %
custo_comb = np.clip(np.round(distancias * 0.75 * rng.normal(1.0, 0.12, N), 2),
                     15.0, 3500.0)
# Custo total = combustível × fator (1.2–1.5) + pedágio/fixo
custo_total = np.round(custo_comb * rng.uniform(1.20, 1.50, N)
                       + rng.uniform(45, 220, N), 2)

# Temperatura do motor: normal 88–105 °C
temp_motor = np.clip(np.round(rng.normal(96, 8, N), 1), 70.0, 115.0)

# Datas e horas
_data_por_sk = dict(zip(df_dim_tempo["sk_data"], df_dim_tempo["data"]))
datas_str = [_data_por_sk[s] for s in sk_datas]
horas_str = [f"{_data_por_sk[s]} {h:02d}:{m:02d}:00"
             for s, h, m in zip(sk_datas, hh, mm)]

df_fato_clean = pd.DataFrame({
    "sk_entrega":          range(1, N + 1),
    "pedido_id":           [f"PED-{datas_str[i][:4]}-{i+1:06d}" for i in range(N)],
    "sk_cliente":          sk_clientes,
    "veiculo_id":          veic_ids,
    "motorista_id":        motor_ids,
    "cd_origem":           cds,
    "sk_data":             sk_datas,
    "data_entrega":        datas_str,
    "hora_saida":          horas_str,
    "distancia_km":        distancias,
    "peso_carga_kg":       pesos,
    "atraso_min":          atraso,
    "custo_combustivel":   custo_comb,
    "custo_total":         custo_total,
    "temperatura_media_motor": temp_motor,
})

print(f"Dados limpos: {len(df_fato_clean):,} linhas | "
      f"Taxa de atraso: {(atraso > 0).mean():.1%}")

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# ANOMALIAS PROPOSITAIS — para a Parte 4 do LAB 3
# Os alunos devem detectá-las com SQL; não há marcação nas linhas.
# ─────────────────────────────────────────────────────────────

anomalias = []
sk_next = N + 1
_sample = lambda n: df_fato_clean.sample(n, random_state=SEED).copy()

# --- Anomalia 1 · Duplicatas (100 linhas) ---
# Mesmo pedido_id + data_entrega, sk_entrega diferente.
# Simula reenvio de mensagem em sistema de integração (retry sem idempotência).
for _, row in _sample(100).iterrows():
    row = row.copy()
    row["sk_entrega"] = sk_next
    row["custo_total"] = round(float(row["custo_total"]) * random.uniform(0.98, 1.02), 2)
    anomalias.append(row.to_dict())
    sk_next += 1

# --- Anomalia 2 · Valores negativos (50 linhas) ---
# Simula bug de integração que inverte sinal ao converter unidades.
for _, row in _sample(50).iterrows():
    row = row.copy()
    row["sk_entrega"] = sk_next
    row["pedido_id"]  = f"PED-NEG-{sk_next:06d}"
    campo = random.choice(["distancia_km", "peso_carga_kg", "custo_combustivel"])
    row[campo] = -abs(float(row[campo]))
    anomalias.append(row.to_dict())
    sk_next += 1

# --- Anomalia 3 · Outliers em atraso_min (30 linhas) ---
# Mistura: atrasos absurdos (>1.000 min) e adiantamentos impossíveis (<-480 min).
for _, row in _sample(30).iterrows():
    row = row.copy()
    row["sk_entrega"] = sk_next
    row["pedido_id"]  = f"PED-OUT-{sk_next:06d}"
    row["atraso_min"] = random.choice([
        random.randint(1_001, 5_760),   # até 4 dias de atraso
        random.randint(-1_440, -481),   # adiantamento impossível
    ])
    anomalias.append(row.to_dict())
    sk_next += 1

# --- Anomalia 4 · FK quebrada — sk_cliente inexistente (50 linhas) ---
# sk_cliente 201–300 não existem em dim_cliente.
# Simula carga de dados de sistema legado com clientes não migrados.
for _, row in _sample(50).iterrows():
    row = row.copy()
    row["sk_entrega"] = sk_next
    row["pedido_id"]  = f"PED-FKB-{sk_next:06d}"
    row["sk_cliente"] = random.randint(201, 300)
    anomalias.append(row.to_dict())
    sk_next += 1

df_anomalias = pd.DataFrame(anomalias)
df_fato_entregas = (
    pd.concat([df_fato_clean, df_anomalias], ignore_index=True)
    .sample(frac=1, random_state=SEED)        # embaralha para ocultar anomalias
    .reset_index(drop=True)
)

print(f"fato_entregas total: {len(df_fato_entregas):,} linhas "
      f"({len(df_anomalias)} anômalas)")

# COMMAND ----------

# ─────────────────────────────────────────────────────────────
# SALVAR COMO DELTA TABLES no banco 'lodlog'
# ─────────────────────────────────────────────────────────────

from pyspark.sql import functions as F
from pyspark.sql.types import DateType, TimestampType, IntegerType, DoubleType

spark.sql("CREATE DATABASE IF NOT EXISTS lodlog")
spark.sql("USE lodlog")

def _save(df_pd, nome, tipo_cast=None):
    spark.sql(f"DROP TABLE IF EXISTS lodlog.{nome}")
    df_sp = spark.createDataFrame(df_pd)
    if tipo_cast:
        for col, t in tipo_cast.items():
            df_sp = df_sp.withColumn(col, F.col(col).cast(t))
    (df_sp.write.format("delta")
         .mode("overwrite")
         .option("overwriteSchema", "true")
         .saveAsTable(f"lodlog.{nome}"))
    n = spark.table(f"lodlog.{nome}").count()
    print(f"  ✓ lodlog.{nome}: {n:,} linhas")

print("Salvando tabelas Delta…")
_save(df_dim_cliente, "dim_cliente")
_save(df_dim_veiculo, "dim_veiculo")
_save(df_dim_manutencao, "dim_veiculo_manutencao",
      {"data_manutencao": DateType()})
_save(df_dim_tempo,  "dim_tempo",  {"data": DateType()})
_save(df_dim_clima,  "dim_clima")
_save(df_fato_entregas, "fato_entregas", {
    "data_entrega": DateType(),
    "hora_saida":   TimestampType(),
    "atraso_min":   IntegerType(),
    "distancia_km": DoubleType(),
    "peso_carga_kg": DoubleType(),
    "custo_combustivel": DoubleType(),
    "custo_total":  DoubleType(),
    "temperatura_media_motor": DoubleType(),
})
print("\nSetup concluído! Execute: USE lodlog;")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Verificação das Tabelas

# COMMAND ----------

# MAGIC %sql
# MAGIC -- Confirme as tabelas e contagens
# MAGIC SHOW TABLES IN lodlog;

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT
# MAGIC   CASE
# MAGIC     WHEN atraso_min < -60  THEN '① Muito adiantado'
# MAGIC     WHEN atraso_min <   0  THEN '② Adiantado'
# MAGIC     WHEN atraso_min =   0  THEN '③ Pontual'
# MAGIC     WHEN atraso_min <= 120 THEN '④ Atrasado (1–120 min)'
# MAGIC     WHEN atraso_min <= 480 THEN '⑤ Muito atrasado (121–480 min)'
# MAGIC     ELSE                        '⑥ OUTLIER (>480 ou <-480)'
# MAGIC   END AS categoria,
# MAGIC   COUNT(*) AS total,
# MAGIC   ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS pct
# MAGIC FROM lodlog.fato_entregas
# MAGIC GROUP BY 1 ORDER BY 1;
