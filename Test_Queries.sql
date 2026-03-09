/* ============================================================
   ORACLE JAVA BOT - QUERIES DE VERIFICACIÓN
   ============================================================ */


/* ============================================================
   1. USUARIOS Y ROLES
   Verifica: roles correctos (solo MANAGER/DEVELOPER),
             teams correctos (solo Backend/Frontend),
             credenciales 1:1 con cada usuario.
   ============================================================ */

-- 1a. Todos los usuarios con su rol y equipo
SELECT
    u.USER_ID,
    u.FULL_NAME,
    u.EMAIL,
    u.TELEGRAM_ID,
    r.ROLE_NAME,
    t.NAME      AS TEAM,
    u.STATUS
FROM USERS u
JOIN ROLES r ON r.ROLE_ID = u.ROLE_ID
LEFT JOIN TEAMS t ON t.TEAM_ID = u.TEAM_ID
ORDER BY r.ROLE_NAME, u.FULL_NAME;

-- 1b. Verificar que cada usuario tiene exactamente 1 credencial
SELECT
    u.USER_ID,
    u.FULL_NAME,
    uc.USERNAME,
    uc.FAILED_ATTEMPTS,
    uc.ACCOUNT_LOCKED,
    uc.LAST_LOGIN
FROM USERS u
JOIN USER_CREDENTIALS uc ON uc.USER_ID = u.USER_ID
ORDER BY u.USER_ID;

-- 1c. Verificar que no existen roles eliminados en el sistema
SELECT ROLE_NAME FROM ROLES
ORDER BY ROLE_ID;
-- Resultado esperado: solo MANAGER y DEVELOPER


/* ============================================================
   2. PROYECTOS Y MIEMBROS
   Verifica: manager válido por proyecto,
             miembros con roles correctos,
             usuarios en múltiples proyectos.
   ============================================================ */

-- 2a. Proyectos con su manager
SELECT
    p.PROJECT_ID,
    p.NAME        AS PROYECTO,
    p.STATUS,
    u.FULL_NAME   AS MANAGER,
    r.ROLE_NAME
FROM PROJECTS p
JOIN USERS u ON u.USER_ID = p.MANAGER_ID
JOIN ROLES r ON r.ROLE_ID = u.ROLE_ID
ORDER BY p.PROJECT_ID;

-- 2b. Miembros por proyecto con su rol
SELECT
    p.NAME          AS PROYECTO,
    u.FULL_NAME,
    pm.ROLE_IN_PROJECT,
    t.NAME          AS EQUIPO,
    pm.JOINED_AT
FROM PROJECT_MEMBERS pm
JOIN PROJECTS p ON p.PROJECT_ID = pm.PROJECT_ID
JOIN USERS    u ON u.USER_ID    = pm.USER_ID
JOIN TEAMS    t ON t.TEAM_ID    = u.TEAM_ID
ORDER BY p.PROJECT_ID, pm.ROLE_IN_PROJECT;

-- 2c. Usuarios que participan en más de un proyecto
SELECT
    u.FULL_NAME,
    COUNT(DISTINCT pm.PROJECT_ID) AS NUM_PROYECTOS,
    LISTAGG(p.NAME, ', ')
        WITHIN GROUP (ORDER BY p.NAME) AS PROYECTOS
FROM PROJECT_MEMBERS pm
JOIN USERS    u ON u.USER_ID    = pm.USER_ID
JOIN PROJECTS p ON p.PROJECT_ID = pm.PROJECT_ID
GROUP BY u.USER_ID, u.FULL_NAME
HAVING COUNT(DISTINCT pm.PROJECT_ID) > 1
ORDER BY NUM_PROYECTOS DESC;


/* ============================================================
   3. SPRINTS POR PROYECTO
   Verifica: SPRINT_NUMBER correcto y único por proyecto,
             solo 1 sprint activo por proyecto (IS_ACTIVE='Y'),
             fechas coherentes.
   ============================================================ */

-- 3a. Todos los sprints organizados por proyecto y número
SELECT
    p.NAME          AS PROYECTO,
    ps.SPRINT_NUMBER,
    s.NAME          AS SPRINT,
    s.START_DATE,
    s.END_DATE,
    s.STATUS,
    ps.IS_ACTIVE
FROM PROJECT_SPRINTS ps
JOIN PROJECTS p ON p.PROJECT_ID = ps.PROJECT_ID
JOIN SPRINTS  s ON s.SPRINT_ID  = ps.SPRINT_ID
ORDER BY p.PROJECT_ID, ps.SPRINT_NUMBER;

-- 3b. Verificar que cada proyecto tiene máximo 1 sprint activo
SELECT
    p.NAME  AS PROYECTO,
    COUNT(*) AS SPRINTS_ACTIVOS
FROM PROJECT_SPRINTS ps
JOIN PROJECTS p ON p.PROJECT_ID = ps.PROJECT_ID
WHERE ps.IS_ACTIVE = 'Y'
GROUP BY p.PROJECT_ID, p.NAME
ORDER BY p.NAME;
-- Resultado esperado: todos con valor 1


/* ============================================================
   4. FLUJO DE VIDA DE TAREAS
   Verifica: distribución de tareas por stage y status,
             tareas sin sprint (backlog),
             tareas asignadas vs sin asignar.
   ============================================================ */

-- 4a. Todas las tareas con su contexto completo
SELECT
    t.TASK_ID,
    t.TITLE,
    p.NAME          AS PROYECTO,
    s.NAME          AS SPRINT,
    ps.SPRINT_NUMBER,
    t.TASK_STAGE,
    t.STATUS,
    t.PRIORITY,
    cb.FULL_NAME    AS CREADA_POR,
    ab.FULL_NAME    AS ASIGNADA_A,
    t.DUE_DATE
FROM TASKS t
LEFT JOIN PROJECTS p  ON p.PROJECT_ID = t.PROJECT_ID
LEFT JOIN SPRINTS  s  ON s.SPRINT_ID  = t.SPRINT_ID
LEFT JOIN PROJECT_SPRINTS ps ON ps.SPRINT_ID  = t.SPRINT_ID
                             AND ps.PROJECT_ID = t.PROJECT_ID
LEFT JOIN USERS cb ON cb.USER_ID = t.CREATED_BY
LEFT JOIN USERS ab ON ab.USER_ID = t.ASSIGNED_TO
WHERE t.IS_DELETED = 'N'
ORDER BY t.PROJECT_ID, ps.SPRINT_NUMBER NULLS LAST, t.TASK_ID;

-- 4b. Resumen de tareas por stage y status
SELECT
    t.TASK_STAGE,
    t.STATUS,
    COUNT(*) AS TOTAL
FROM TASKS t
WHERE t.IS_DELETED = 'N'
GROUP BY t.TASK_STAGE, t.STATUS
ORDER BY t.TASK_STAGE, t.STATUS;

-- 4c. Tareas en backlog (sin sprint asignado)
SELECT
    t.TASK_ID,
    t.TITLE,
    p.NAME      AS PROYECTO,
    t.STATUS,
    t.PRIORITY,
    cb.FULL_NAME AS CREADA_POR
FROM TASKS t
LEFT JOIN PROJECTS p  ON p.PROJECT_ID = t.PROJECT_ID
JOIN      USERS    cb ON cb.USER_ID   = t.CREATED_BY
WHERE t.SPRINT_ID  IS NULL
  AND t.IS_DELETED = 'N'
ORDER BY t.PRIORITY DESC, t.TASK_ID;


/* ============================================================
   5. HISTORIAL DE STATUS DE TAREAS
   Verifica: trazabilidad completa de cada tarea,
             tareas reabiertas (REOPENED),
             tareas sin historial (sin trazabilidad).
   ============================================================ */

-- 5a. Historial completo de una tarea (ej: tarea 10 - bug OAuth)
SELECT
    t.TITLE,
    tsh.OLD_STATUS,
    tsh.NEW_STATUS,
    u.FULL_NAME     AS CAMBIADO_POR,
    tsh.CHANGED_AT
FROM TASK_STATUS_HISTORY tsh
JOIN TASKS t ON t.TASK_ID  = tsh.TASK_ID
LEFT JOIN USERS u ON u.USER_ID = tsh.CHANGED_BY
WHERE tsh.TASK_ID = 10
ORDER BY tsh.CHANGED_AT;

-- 5b. Todas las tareas que pasaron por REOPENED
SELECT
    t.TASK_ID,
    t.TITLE,
    p.NAME          AS PROYECTO,
    s.NAME          AS SPRINT,
    u.FULL_NAME     AS REABIERTA_POR,
    tsh.CHANGED_AT  AS FECHA_REABIERTURA
FROM TASK_STATUS_HISTORY tsh
JOIN TASKS    t ON t.TASK_ID    = tsh.TASK_ID
LEFT JOIN PROJECTS p ON p.PROJECT_ID = t.PROJECT_ID
LEFT JOIN SPRINTS  s ON s.SPRINT_ID  = t.SPRINT_ID
LEFT JOIN USERS    u ON u.USER_ID    = tsh.CHANGED_BY
WHERE tsh.NEW_STATUS = 'REOPENED'
ORDER BY tsh.CHANGED_AT;

-- 5c. Tareas SIN ningún registro en historial (sin trazabilidad)
SELECT
    t.TASK_ID,
    t.TITLE,
    p.NAME      AS PROYECTO,
    t.TASK_STAGE,
    t.STATUS
FROM TASKS t
LEFT JOIN PROJECTS p ON p.PROJECT_ID = t.PROJECT_ID
WHERE t.IS_DELETED = 'N'
  AND NOT EXISTS (
      SELECT 1 FROM TASK_STATUS_HISTORY tsh
      WHERE tsh.TASK_ID = t.TASK_ID
  )
ORDER BY t.TASK_ID;


/* ============================================================
   6. HISTORIAL DE SPRINT (ARRASTRES)
   Verifica: tareas movidas entre sprints,
             cuántos sprints tardó cada tarea en completarse.
   ============================================================ */

-- 6a. Todas las tareas que fueron movidas de sprint
SELECT
    t.TITLE,
    p.NAME          AS PROYECTO,
    s_old.NAME      AS SPRINT_ORIGEN,
    s_new.NAME      AS SPRINT_DESTINO,
    u.FULL_NAME     AS MOVIDA_POR,
    tsph.CHANGED_AT
FROM TASK_SPRINT_HISTORY tsph
JOIN TASKS   t     ON t.TASK_ID       = tsph.TASK_ID
LEFT JOIN PROJECTS p     ON p.PROJECT_ID   = t.PROJECT_ID
LEFT JOIN SPRINTS  s_old ON s_old.SPRINT_ID = tsph.OLD_SPRINT_ID
LEFT JOIN SPRINTS  s_new ON s_new.SPRINT_ID = tsph.NEW_SPRINT_ID
LEFT JOIN USERS    u     ON u.USER_ID       = tsph.CHANGED_BY
WHERE tsph.OLD_SPRINT_ID IS NOT NULL   -- excluye primera asignación
ORDER BY tsph.CHANGED_AT;

-- 6b. Número de sprints que tardó cada tarea (carryover count)
SELECT
    t.TASK_ID,
    t.TITLE,
    p.NAME              AS PROYECTO,
    t.STATUS,
    COUNT(tsph.HISTORY_ID) - 1  AS VECES_ARRASTRADA
FROM TASKS t
LEFT JOIN PROJECTS p ON p.PROJECT_ID = t.PROJECT_ID
LEFT JOIN TASK_SPRINT_HISTORY tsph ON tsph.TASK_ID = t.TASK_ID
WHERE t.IS_DELETED = 'N'
  AND t.SPRINT_ID IS NOT NULL
GROUP BY t.TASK_ID, t.TITLE, p.NAME, t.STATUS
ORDER BY VECES_ARRASTRADA DESC;


/* ============================================================
   7. KPI POR SPRINT
   Verifica: tareas completadas, cumplimiento y disponibilidad
             con su número de sprint relativo al proyecto.
   ============================================================ */

-- 7a. KPIs de tipo SPRINT agrupados con número relativo
SELECT
    p.NAME              AS PROYECTO,
    ps.SPRINT_NUMBER,
    s.NAME              AS SPRINT,
    kt.NAME             AS KPI,
    kt.UNIT,
    kv.VALUE,
    kv.RECORDED_AT
FROM KPI_VALUES kv
JOIN KPI_TYPES     kt ON kt.KPI_TYPE_ID = kv.KPI_TYPE_ID
JOIN SPRINTS        s ON s.SPRINT_ID    = kv.SPRINT_ID
JOIN PROJECT_SPRINTS ps ON ps.SPRINT_ID = kv.SPRINT_ID
JOIN PROJECTS       p  ON p.PROJECT_ID  = ps.PROJECT_ID
WHERE kv.SCOPE_TYPE = 'SPRINT'
ORDER BY p.PROJECT_ID, ps.SPRINT_NUMBER, kt.NAME;

-- 7b. Comparar cumplimiento sprint a sprint por proyecto
SELECT
    p.NAME          AS PROYECTO,
    ps.SPRINT_NUMBER,
    s.NAME          AS SPRINT,
    kv.VALUE        AS CUMPLIMIENTO_PCT
FROM KPI_VALUES kv
JOIN KPI_TYPES     kt ON kt.KPI_TYPE_ID = kv.KPI_TYPE_ID
JOIN SPRINTS        s ON s.SPRINT_ID    = kv.SPRINT_ID
JOIN PROJECT_SPRINTS ps ON ps.SPRINT_ID = kv.SPRINT_ID
JOIN PROJECTS       p  ON p.PROJECT_ID  = ps.PROJECT_ID
WHERE kt.NAME       = 'CUMPLIMIENTO_SPRINT'
  AND kv.SCOPE_TYPE = 'SPRINT'
ORDER BY p.PROJECT_ID, ps.SPRINT_NUMBER;


/* ============================================================
   8. KPI POR PROYECTO
   Verifica: MTTR, tasa de despliegues, trazabilidad
             y actualización diaria por proyecto.
   ============================================================ */

-- 8a. Todos los KPIs de scope PROJECT con valor más reciente
SELECT
    p.NAME      AS PROYECTO,
    kt.NAME     AS KPI,
    kt.CATEGORY,
    kt.UNIT,
    kv.VALUE,
    kv.RECORDED_AT
FROM KPI_VALUES kv
JOIN KPI_TYPES kt ON kt.KPI_TYPE_ID = kv.KPI_TYPE_ID
JOIN PROJECTS  p  ON p.PROJECT_ID   = kv.PROJECT_ID
WHERE kv.SCOPE_TYPE  = 'PROJECT'
  AND kv.RECORDED_AT = (
      SELECT MAX(kv2.RECORDED_AT)
      FROM KPI_VALUES kv2
      WHERE kv2.KPI_TYPE_ID = kv.KPI_TYPE_ID
        AND kv2.PROJECT_ID  = kv.PROJECT_ID
  )
ORDER BY p.NAME, kt.CATEGORY, kt.NAME;

-- 8b. Evolución de CPU en el tiempo (múltiples snapshots)
SELECT
    p.NAME          AS PROYECTO,
    kt.NAME         AS KPI,
    kv.VALUE        AS PORCENTAJE,
    kv.RECORDED_AT
FROM KPI_VALUES kv
JOIN KPI_TYPES kt ON kt.KPI_TYPE_ID = kv.KPI_TYPE_ID
JOIN PROJECTS  p  ON p.PROJECT_ID   = kv.PROJECT_ID
WHERE kt.NAME IN ('USO_CPU', 'USO_MEMORIA')
ORDER BY kt.NAME, kv.RECORDED_AT;


/* ============================================================
   9. KPI GLOBAL
   Verifica: interacciones del bot día a día.
   ============================================================ */

SELECT
    kt.NAME         AS KPI,
    kv.VALUE        AS TOTAL_INTERACCIONES,
    kv.RECORDED_AT  AS DIA
FROM KPI_VALUES kv
JOIN KPI_TYPES kt ON kt.KPI_TYPE_ID = kv.KPI_TYPE_ID
WHERE kv.SCOPE_TYPE = 'GLOBAL'
ORDER BY kv.RECORDED_AT;


/* ============================================================
   10. CONTRIBUCIÓN DE USUARIO CON CONTEXTO DE SPRINT
   Verifica: que USER_ID + SPRINT_ID en KPI_VALUES funciona
             correctamente para medir contribución individual.
   ============================================================ */

-- 10a. Simular contribución individual (usando tareas reales del schema)
--      Este SELECT muestra lo que el KPI mediría si ya estuviera insertado
SELECT
    u.FULL_NAME,
    p.NAME          AS PROYECTO,
    s.NAME          AS SPRINT,
    ps.SPRINT_NUMBER,
    COUNT(*)        AS TAREAS_COMPLETADAS
FROM TASKS t
JOIN USERS    u  ON u.USER_ID    = t.ASSIGNED_TO
JOIN PROJECTS p  ON p.PROJECT_ID = t.PROJECT_ID
JOIN SPRINTS  s  ON s.SPRINT_ID  = t.SPRINT_ID
JOIN PROJECT_SPRINTS ps ON ps.SPRINT_ID  = t.SPRINT_ID
                        AND ps.PROJECT_ID = t.PROJECT_ID
WHERE t.STATUS     = 'DONE'
  AND t.IS_DELETED = 'N'
GROUP BY u.USER_ID, u.FULL_NAME, p.PROJECT_ID, p.NAME,
         s.SPRINT_ID, s.NAME, ps.SPRINT_NUMBER
ORDER BY p.NAME, ps.SPRINT_NUMBER, TAREAS_COMPLETADAS DESC;

-- 10b. Ranking de contribución total por usuario (todos los sprints)
SELECT
    u.FULL_NAME,
    COUNT(*) AS TOTAL_TAREAS_COMPLETADAS,
    ROUND(COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER (), 2) AS PORCENTAJE_CONTRIBUCION
FROM TASKS t
JOIN USERS u ON u.USER_ID = t.ASSIGNED_TO
WHERE t.STATUS     = 'DONE'
  AND t.IS_DELETED = 'N'
GROUP BY u.USER_ID, u.FULL_NAME
ORDER BY TOTAL_TAREAS_COMPLETADAS DESC;


/* ============================================================
   11. DESPLIEGUES Y TASA DE ÉXITO
   Verifica: pipeline completo por versión,
             fallos con tiempo de recuperación,
             tasa de éxito por proyecto.
   ============================================================ */

-- 11a. Pipeline de despliegues por versión y proyecto
SELECT
    p.NAME          AS PROYECTO,
    d.VERSION,
    d.ENVIRONMENT,
    d.STATUS,
    d.DEPLOYED_AT,
    d.RECOVERY_TIME_MIN
FROM DEPLOYMENTS d
JOIN PROJECTS p ON p.PROJECT_ID = d.PROJECT_ID
ORDER BY p.NAME, d.VERSION, d.DEPLOYED_AT;

-- 11b. Tasa de éxito calculada en tiempo real por proyecto
SELECT
    p.NAME                                      AS PROYECTO,
    COUNT(*)                                    AS TOTAL_DEPLOYS,
    COUNT(CASE WHEN d.STATUS = 'SUCCESS' THEN 1 END) AS EXITOSOS,
    COUNT(CASE WHEN d.STATUS = 'FAILED'  THEN 1 END) AS FALLIDOS,
    ROUND(
        COUNT(CASE WHEN d.STATUS = 'SUCCESS' THEN 1 END) * 100.0
        / NULLIF(COUNT(*), 0)
    , 2)                                        AS TASA_EXITO_PCT
FROM DEPLOYMENTS d
JOIN PROJECTS p ON p.PROJECT_ID = d.PROJECT_ID
GROUP BY p.PROJECT_ID, p.NAME
ORDER BY p.NAME;

-- 11c. Despliegues a PRODUCTION únicamente
SELECT
    p.NAME          AS PROYECTO,
    d.VERSION,
    d.STATUS,
    d.DEPLOYED_AT
FROM DEPLOYMENTS d
JOIN PROJECTS p ON p.PROJECT_ID = d.PROJECT_ID
WHERE d.ENVIRONMENT = 'PRODUCTION'
ORDER BY d.DEPLOYED_AT;


/* ============================================================
   12. INCIDENTES Y MTTR
   Verifica: incidentes por severidad,
             tiempo de resolución real,
             incidentes aún abiertos.
   ============================================================ */

-- 12a. Todos los incidentes con tiempo de resolución
SELECT
    p.NAME          AS PROYECTO,
    i.TYPE,
    i.SEVERITY,
    i.OCCURRED_AT,
    i.RESOLVED_AT,
    ROUND(
        (CAST(NVL(i.RESOLVED_AT, CURRENT_TIMESTAMP) AS DATE)
         - CAST(i.OCCURRED_AT AS DATE)) * 1440
    , 0)            AS MINUTOS_RESOLUCION,
    CASE WHEN i.RESOLVED_AT IS NULL THEN 'ABIERTO' ELSE 'RESUELTO' END AS ESTADO
FROM INCIDENTS i
JOIN PROJECTS p ON p.PROJECT_ID = i.PROJECT_ID
WHERE i.IS_DELETED = 'N'
ORDER BY i.SEVERITY DESC, i.OCCURRED_AT;

-- 12b. MTTR calculado en tiempo real por proyecto
SELECT
    p.NAME  AS PROYECTO,
    COUNT(*) AS TOTAL_INCIDENTES,
    ROUND(AVG(
        (CAST(i.RESOLVED_AT AS DATE) - CAST(i.OCCURRED_AT AS DATE)) * 1440
    ), 2)   AS MTTR_MINUTOS
FROM INCIDENTS i
JOIN PROJECTS p ON p.PROJECT_ID = i.PROJECT_ID
WHERE i.RESOLVED_AT IS NOT NULL
  AND i.IS_DELETED  = 'N'
GROUP BY p.PROJECT_ID, p.NAME
ORDER BY MTTR_MINUTOS DESC;

-- 12c. Incidentes de seguridad
SELECT
    p.NAME          AS PROYECTO,
    i.TYPE,
    i.SEVERITY,
    i.DESCRIPTION,
    i.OCCURRED_AT,
    i.RESOLVED_AT
FROM INCIDENTS i
JOIN PROJECTS p ON p.PROJECT_ID = i.PROJECT_ID
WHERE i.TYPE       = 'SECURITY'
  AND i.IS_DELETED = 'N'
ORDER BY i.OCCURRED_AT;


/* ============================================================
   13. INTERACCIONES DEL BOT
   Verifica: mensajes por usuario,
             interacciones anónimas,
             volumen por día.
   ============================================================ */

-- 13a. Todas las interacciones con usuario o anónimo
SELECT
    bi.INTERACTION_ID,
    NVL(u.FULL_NAME, 'Anónimo') AS USUARIO,
    bi.MESSAGE,
    bi.RESPONSE,
    bi.CREATED_AT
FROM BOT_INTERACTIONS bi
LEFT JOIN USERS u ON u.USER_ID = bi.USER_ID
ORDER BY bi.CREATED_AT;

-- 13b. Conteo de interacciones por usuario
SELECT
    NVL(u.FULL_NAME, 'Anónimo') AS USUARIO,
    COUNT(*) AS TOTAL_INTERACCIONES
FROM BOT_INTERACTIONS bi
LEFT JOIN USERS u ON u.USER_ID = bi.USER_ID
GROUP BY bi.USER_ID, u.FULL_NAME
ORDER BY TOTAL_INTERACCIONES DESC;

-- 13c. Volumen de interacciones por día
SELECT
    TRUNC(bi.CREATED_AT, 'DD') AS DIA,
    COUNT(*)                   AS TOTAL_MENSAJES
FROM BOT_INTERACTIONS bi
GROUP BY TRUNC(bi.CREATED_AT, 'DD')
ORDER BY DIA;


/* ============================================================
   14. ANÁLISIS LLM
   Verifica: anomalías detectadas por scope,
             recomendaciones por proyecto/usuario/sprint.
   ============================================================ */

-- 14a. Todos los análisis con su contexto
SELECT
    la.ANALYSIS_ID,
    la.SCOPE_TYPE,
    CASE la.SCOPE_TYPE
        WHEN 'USER'    THEN u.FULL_NAME
        WHEN 'PROJECT' THEN p.NAME
        WHEN 'SPRINT'  THEN s.NAME
        ELSE                'Global'
    END                     AS ENTIDAD,
    la.ANOMALY_DETECTED,
    la.ANOMALY_TYPE,
    la.CONFIDENCE_SCORE,
    la.RECOMMENDATION,
    la.ANALYSIS_DATE
FROM LLM_ANALYSIS la
LEFT JOIN USERS    u ON u.USER_ID    = la.USER_ID
LEFT JOIN PROJECTS p ON p.PROJECT_ID = la.PROJECT_ID
LEFT JOIN SPRINTS  s ON s.SPRINT_ID  = la.SPRINT_ID
ORDER BY la.ANOMALY_DETECTED DESC, la.CONFIDENCE_SCORE DESC;

-- 14b. Solo anomalías detectadas
SELECT
    la.SCOPE_TYPE,
    la.ANOMALY_TYPE,
    la.CONFIDENCE_SCORE,
    la.RECOMMENDATION
FROM LLM_ANALYSIS la
WHERE la.ANOMALY_DETECTED = 'Y'
ORDER BY la.CONFIDENCE_SCORE DESC;


/* ============================================================
   15. AUDIT LOG
   Verifica: acciones por usuario,
             entidades más modificadas,
             intentos de acceso externos (USER_ID NULL).
   ============================================================ */

-- 15a. Log completo con usuario o externo
SELECT
    al.AUDIT_ID,
    NVL(u.FULL_NAME, 'EXTERNO / SISTEMA') AS USUARIO,
    al.ACTION_TYPE,
    al.ENTITY_NAME,
    al.ENTITY_ID,
    al.IP_ADDRESS,
    al.ACTION_DATE
FROM AUDIT_LOG al
LEFT JOIN USERS u ON u.USER_ID = al.USER_ID
ORDER BY al.ACTION_DATE;

-- 15b. Acciones agrupadas por usuario
SELECT
    NVL(u.FULL_NAME, 'EXTERNO') AS USUARIO,
    al.ACTION_TYPE,
    COUNT(*) AS TOTAL
FROM AUDIT_LOG al
LEFT JOIN USERS u ON u.USER_ID = al.USER_ID
GROUP BY al.USER_ID, u.FULL_NAME, al.ACTION_TYPE
ORDER BY TOTAL DESC;

-- 15c. Intentos de acceso externos (sin usuario autenticado)
SELECT
    al.ACTION_TYPE,
    al.ENTITY_NAME,
    al.IP_ADDRESS,
    al.ACTION_DATE
FROM AUDIT_LOG al
WHERE al.USER_ID IS NULL
ORDER BY al.ACTION_DATE;