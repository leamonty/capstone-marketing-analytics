-- ============================================================================
-- PROYECTO CAPSTONE: EFECTIVIDAD DE CAMPAÑAS DE MARKETING Y COMPORTAMIENTO
--                    DE COMPRA DE CLIENTES
-- Archivo: estructura.sql
-- Fuente de datos: "Customer Personality Analysis" (Kaggle, imakash3011)
--   https://www.kaggle.com/datasets/imakash3011/customer-personality-analysis
-- ============================================================================
-- DECISIONES DE MODELADO (por qué el esquema quedó así):
--
-- El dataset original viene como UN SOLO archivo plano de 29 columnas por
-- cliente (demografía + gasto por categoría + compras por canal + respuesta
-- a 6 campañas, todo mezclado en la misma fila). Se decidió NORMALIZAR esa
-- estructura ancha en 4 tablas relacionadas, en vez de dejarla como una
-- tabla única, para poder:
--   a) aplicar GROUP BY por categoría/canal/campaña sin tener que escribir
--      una suma manual por cada una de las 15 columnas repetidas, y
--   b) reflejar que "gasto por categoría", "compras por canal" y "respuesta
--      a campañas" son, conceptualmente, hechos repetibles por cliente
--      (un cliente tiene VARIOS gastos, uno por categoría), no atributos
--      fijos de la persona.
--
-- Se descartaron del modelo las columnas Z_CostContact y Z_Revenue del
-- dataset original: tienen el mismo valor en las 2.240 filas (3 y 11
-- respectivamente), por lo que no aportan ninguna capacidad analítica.
-- ============================================================================

-- Antes de correr este archivo, crear la base desde pgAdmin (Create > Database)
-- o ejecutando una sola vez, conectado a otra base administrativa:
--   CREATE DATABASE capstone_marketing WITH ENCODING 'UTF8' TEMPLATE template0;
-- Después, abrir un Query Tool NUEVO conectado a capstone_marketing y recién
-- ahí ejecutar todo lo que sigue.

DROP TABLE IF EXISTS respuesta_campanas;
DROP TABLE IF EXISTS compras_por_canal;
DROP TABLE IF EXISTS gasto_por_categoria;
DROP TABLE IF EXISTS clientes;

-- ------------------------------------------------------------
-- CLIENTES
-- Un renglón por cliente, con su demografía y comportamiento general.
-- ------------------------------------------------------------
CREATE TABLE clientes (
    cliente_id                 INTEGER PRIMARY KEY,
    year_birth                 SMALLINT NOT NULL
        CHECK (year_birth >= 1900 AND year_birth <= 2010),
    educacion                  VARCHAR(20) NOT NULL,
    estado_civil                VARCHAR(20) NOT NULL,
    -- Ingreso anual: se completan los nulos con la mediana en la carga
    -- (ver README), por eso acá NOT NULL una vez cargados los datos.
    ingreso_anual               NUMERIC(10,2) NOT NULL,
    hijos_pequenos               SMALLINT NOT NULL DEFAULT 0,
    hijos_adolescentes           SMALLINT NOT NULL DEFAULT 0,
    fecha_alta                  DATE NOT NULL,
    dias_desde_ultima_compra     SMALLINT NOT NULL,
    visitas_web_mes              SMALLINT NOT NULL,
    reclamo                     BOOLEAN NOT NULL DEFAULT FALSE
);

-- ------------------------------------------------------------
-- GASTO POR CATEGORIA
-- Normaliza las 6 columnas Mnt* del dataset original (Wines, Fruits,
-- MeatProducts, FishProducts, SweetProducts, GoldProds) en filas.
-- ------------------------------------------------------------
CREATE TABLE gasto_por_categoria (
    id              SERIAL PRIMARY KEY,
    cliente_id      INTEGER NOT NULL REFERENCES clientes(cliente_id),
    categoria       VARCHAR(20) NOT NULL
        CHECK (categoria IN ('Vinos','Frutas','Carnes','Pescado','Dulces','Oro')),
    monto_gastado   NUMERIC(10,2) NOT NULL CHECK (monto_gastado >= 0)
);

-- ------------------------------------------------------------
-- COMPRAS POR CANAL
-- Normaliza las 4 columnas Num*Purchases (Deals, Web, Catalog, Store).
-- ------------------------------------------------------------
CREATE TABLE compras_por_canal (
    id                  SERIAL PRIMARY KEY,
    cliente_id          INTEGER NOT NULL REFERENCES clientes(cliente_id),
    canal               VARCHAR(20) NOT NULL
        CHECK (canal IN ('ConDescuento','Web','Catalogo','Tienda')),
    cantidad_compras    SMALLINT NOT NULL CHECK (cantidad_compras >= 0)
);

-- ------------------------------------------------------------
-- RESPUESTA A CAMPANAS
-- Normaliza AcceptedCmp1..5 + Response (la ultima campaña) en filas.
-- ------------------------------------------------------------
CREATE TABLE respuesta_campanas (
    id          SERIAL PRIMARY KEY,
    cliente_id  INTEGER NOT NULL REFERENCES clientes(cliente_id),
    campana     VARCHAR(20) NOT NULL
        CHECK (campana IN ('Campana1','Campana2','Campana3','Campana4','Campana5','UltimaCampana')),
    acepto      BOOLEAN NOT NULL
);

-- ------------------------------------------------------------
-- INDICES para las columnas mas usadas en JOIN y filtros
-- ------------------------------------------------------------
CREATE INDEX idx_gasto_cliente   ON gasto_por_categoria(cliente_id);
CREATE INDEX idx_gasto_categoria ON gasto_por_categoria(categoria);
CREATE INDEX idx_canal_cliente   ON compras_por_canal(cliente_id);
CREATE INDEX idx_campana_cliente ON respuesta_campanas(cliente_id);
CREATE INDEX idx_campana_nombre  ON respuesta_campanas(campana);

-- ------------------------------------------------------------
-- Los datos se cargan DESPUES de correr este script, importando los 4
-- archivos CSV ya limpios (clientes.csv, gasto_por_categoria.csv,
-- compras_por_canal.csv, respuesta_campanas.csv) con la herramienta
-- Import/Export Data de pgAdmin, tabla por tabla. Ver los pasos en el chat.
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- CONTROL DE CARGA (correr esto recien despues de importar los 4 CSV)
-- El resultado esperado es: clientes 2236, gasto_por_categoria 13416,
-- compras_por_canal 8944, respuesta_campanas 13416.
-- ------------------------------------------------------------
SELECT 'clientes' AS tabla, COUNT(*) AS filas FROM clientes
UNION ALL SELECT 'gasto_por_categoria', COUNT(*) FROM gasto_por_categoria
UNION ALL SELECT 'compras_por_canal', COUNT(*) FROM compras_por_canal
UNION ALL SELECT 'respuesta_campanas', COUNT(*) FROM respuesta_campanas;
