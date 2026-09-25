-- ============================================================================
-- PROYECTO CAPSTONE: EFECTIVIDAD DE CAMPAÑAS DE MARKETING Y COMPORTAMIENTO
--                    DE COMPRA DE CLIENTES
-- Archivo: analisis.sql
-- Base esperada: capstone_marketing
-- ============================================================================
-- Nota sobre la limpieza: los datos se transformaron ANTES de cargarlos
-- (a partir del CSV original de Kaggle) aplicando 3 reglas documentadas en
-- el README:
--   1) se excluyeron 4 registros con datos imposibles (3 con año de
--      nacimiento < 1940, 1 con ingreso de 666.666, un outlier evidente),
--   2) los 24 nulos de ingreso se completaron con la MEDIANA (no el
--      promedio, por la asimetría que genera el outlier ya excluido),
--   3) las categorías basura de estado civil ('Absurd','YOLO','Alone') se
--      unificaron bajo 'Otro'.
-- La sección 1 de este archivo VERIFICA con SQL que esa limpieza haya
-- quedado bien aplicada. Ademas, donde corresponde, se usa COALESCE en
-- las consultas de negocio para blindar los promedios/sumas ante posibles
-- valores nulos que puedan surgir de un LEFT JOIN sin coincidencias.
-- ============================================================================

SET search_path TO public;

-- ============================================================================
-- 1. VERIFICACION DE LA LIMPIEZA APLICADA EN LA CARGA
-- ============================================================================

-- 1.1 Nulos en columnas criticas: tiene que dar 0 en todas.
-- Confirma que la imputacion de la mediana de ingreso se aplico antes de
-- cargar los datos, y que no quedo ningun campo obligatorio vacio.
SELECT
    COUNT(*) FILTER (WHERE ingreso_anual IS NULL) AS ingresos_nulos,
    COUNT(*) FILTER (WHERE fecha_alta IS NULL) AS fechas_nulas,
    COUNT(*) FILTER (WHERE year_birth IS NULL) AS nacimientos_nulos
FROM clientes;

-- 1.2 Rango de year_birth: confirma que los 3 registros con edades
-- imposibles (nacidos antes de 1940) fueron excluidos de la carga.
SELECT MIN(year_birth) AS nacimiento_mas_antiguo,
       MAX(year_birth) AS nacimiento_mas_reciente
FROM clientes;

-- 1.3 Rango de ingreso_anual: confirma que el outlier de 666.666 no entro.
SELECT MIN(ingreso_anual) AS ingreso_minimo,
       MAX(ingreso_anual) AS ingreso_maximo,
       ROUND(AVG(ingreso_anual), 2) AS ingreso_promedio
FROM clientes;

-- 1.4 Categorias validas de estado_civil: no debe aparecer ninguna de las
-- categorias basura originales (Absurd, YOLO, Alone).
SELECT estado_civil, COUNT(*) AS cantidad_clientes
FROM clientes
GROUP BY estado_civil
ORDER BY cantidad_clientes DESC;

-- 1.5 Verificacion de tipos DATE/NUMERIC (no texto) contra el catalogo.
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND ((table_name = 'clientes' AND column_name IN ('fecha_alta','ingreso_anual'))
    OR (table_name = 'gasto_por_categoria' AND column_name = 'monto_gastado')
    OR (table_name = 'compras_por_canal' AND column_name = 'cantidad_compras'))
ORDER BY table_name, column_name;

-- 1.6 Integridad de la normalizacion: cada cliente tiene que tener
-- EXACTAMENTE 6 filas en gasto_por_categoria, 4 en compras_por_canal y
-- 6 en respuesta_campanas (una por cada categoria/canal/campana). Si esta
-- consulta devuelve filas, hay clientes mal cargados.
SELECT c.cliente_id,
       COUNT(DISTINCT g.categoria) AS categorias_cargadas,
       COUNT(DISTINCT p.canal) AS canales_cargados,
       COUNT(DISTINCT r.campana) AS campanas_cargadas
FROM clientes c
LEFT JOIN gasto_por_categoria g ON g.cliente_id = c.cliente_id
LEFT JOIN compras_por_canal p ON p.cliente_id = c.cliente_id
LEFT JOIN respuesta_campanas r ON r.cliente_id = c.cliente_id
GROUP BY c.cliente_id
HAVING COUNT(DISTINCT g.categoria) <> 6
    OR COUNT(DISTINCT p.canal) <> 4
    OR COUNT(DISTINCT r.campana) <> 6;

-- ============================================================================
-- 2. PREGUNTAS DE NEGOCIO
-- ============================================================================

-- PREGUNTA 1: ¿que categoria de producto genera mas ingresos y cual menos?
-- Sirve para decidir en que categorias reforzar stock/promocion y en
-- cuales el catalogo esta desaprovechado.
SELECT
    categoria,
    COUNT(DISTINCT cliente_id) AS clientes_que_compraron,
    ROUND(SUM(monto_gastado), 2) AS ingreso_total,
    ROUND(AVG(monto_gastado), 2) AS gasto_promedio_por_cliente
FROM gasto_por_categoria
GROUP BY categoria
ORDER BY ingreso_total DESC;

-- PREGUNTA 2: ¿que campana de marketing tuvo mejor tasa de aceptacion?
-- La tasa (no el total absoluto) es la metrica correcta para comparar
-- campanas, porque las 6 se ofrecieron a la misma base de 2.236 clientes.
SELECT
    campana,
    COUNT(*) FILTER (WHERE acepto) AS clientes_que_aceptaron,
    COUNT(*) AS total_clientes_contactados,
    ROUND(100.0 * COUNT(*) FILTER (WHERE acepto) / COUNT(*), 2) AS tasa_aceptacion_pct
FROM respuesta_campanas
GROUP BY campana
ORDER BY tasa_aceptacion_pct DESC;

-- PREGUNTA 3: ¿los clientes que aceptaron alguna campana gastan mas que
-- los que nunca aceptaron ninguna?
-- Responde si las campanas estan llegando a los clientes de mayor valor,
-- o si el marketing esta gastando esfuerzo en el segmento equivocado.
-- COALESCE cubre el caso de un cliente sin gasto registrado en alguna
-- categoria (para que sume 0 y no rompa el promedio con un NULL).
WITH aceptacion_por_cliente AS (
    SELECT cliente_id,
           COUNT(*) FILTER (WHERE acepto) AS campanas_aceptadas
    FROM respuesta_campanas
    GROUP BY cliente_id
),
gasto_por_cliente AS (
    SELECT cliente_id, COALESCE(SUM(monto_gastado), 0) AS gasto_total
    FROM gasto_por_categoria
    GROUP BY cliente_id
)
SELECT
    CASE
        WHEN a.campanas_aceptadas = 0 THEN 'Nunca acepto una campana'
        ELSE 'Acepto al menos una campana'
    END AS segmento,
    COUNT(*) AS cantidad_clientes,
    ROUND(AVG(g.gasto_total), 2) AS gasto_promedio,
    ROUND(SUM(g.gasto_total), 2) AS gasto_total_segmento
FROM aceptacion_por_cliente a
JOIN gasto_por_cliente g ON g.cliente_id = a.cliente_id
GROUP BY segmento
ORDER BY gasto_promedio DESC;

-- PREGUNTA 4: top 5 clientes por gasto total (funcion de ventana).
-- Identifica a los clientes de mayor valor para acciones de fidelizacion
-- puntuales (no un segmento entero, sino personas concretas).
WITH gasto_total_cliente AS (
    SELECT cliente_id, SUM(monto_gastado) AS gasto_total
    FROM gasto_por_categoria
    GROUP BY cliente_id
),
ranking AS (
    SELECT cliente_id, gasto_total,
           RANK() OVER (ORDER BY gasto_total DESC) AS posicion
    FROM gasto_total_cliente
)
SELECT
    r.posicion,
    r.cliente_id,
    c.educacion,
    c.estado_civil,
    c.ingreso_anual,
    r.gasto_total
FROM ranking r
JOIN clientes c ON c.cliente_id = r.cliente_id
WHERE r.posicion <= 5
ORDER BY r.posicion;

-- PREGUNTA 5: ¿que canal de compra predomina segun el nivel de ingreso?
-- Los cortes de "ingreso bajo/medio/alto" se definieron con los cuartiles
-- 25 y 75 del propio dataset (35.000 y 68.000 aprox.), no con un numero
-- arbitrario. Sirve para decidir en que canal invertir segun a quien se
-- le quiera vender.
WITH clientes_segmentados AS (
    SELECT
        cliente_id,
        CASE
            WHEN ingreso_anual < 35000 THEN 'Ingreso bajo'
            WHEN ingreso_anual < 68000 THEN 'Ingreso medio'
            ELSE 'Ingreso alto'
        END AS segmento_ingreso
    FROM clientes
)
SELECT
    cs.segmento_ingreso,
    cpc.canal,
    SUM(cpc.cantidad_compras) AS total_compras,
    ROUND(AVG(cpc.cantidad_compras), 2) AS promedio_por_cliente
FROM clientes_segmentados cs
JOIN compras_por_canal cpc ON cpc.cliente_id = cs.cliente_id
GROUP BY cs.segmento_ingreso, cpc.canal
ORDER BY cs.segmento_ingreso, total_compras DESC;
