---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- Seguridad: roles, usuarios, permisos y auditoria endurecida
-- EJECUTAR DESPUES DE mantenimiento.sql (el particionamiento vuelve a crear
-- la tabla bitacora, por eso los permisos sobre ella se dan al final).
-- Ejecutar conectado como postgres (superusuario) a la base farmacia_bienestar.
--
-- Que hace:
--   1. Crea roles de grupo (sin login) segun la funcion de cada persona
--   2. Crea usuarios con contrasena, limite de conexiones y tiempos maximos
--   3. Cierra los permisos por defecto (PUBLIC) y da solo lo necesario
--   4. Endurece la funcion de auditoria (SECURITY DEFINER y datos clinicos
--      protegidos) y cierra la bitacora: solo lectura para auditor/admin
--   5. Comprobaciones para tomar capturas como evidencia
--
-- Principio aplicado: MINIMO PRIVILEGIO. Ningun rol de la aplicacion es
-- superusuario, nadie puede borrar ni modificar la bitacora y los datos
-- clinicos solo los ve quien los necesita para su trabajo.
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---


---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 1. ROLES DE GRUPO (NOLOGIN)
-- Los permisos se dan a estos roles y las personas entran con un usuario que
-- pertenece a uno de ellos. Si alguien cambia de puesto solo se cambia su rol.
--   rol_admin_farmacia : administra los datos del negocio (no es superusuario)
--   rol_farmaceutico   : dispensa, valida recetas, atiende pacientes
--   rol_cajero         : registra ventas; NO ve datos clinicos ni el DUI
--   rol_compras        : proveedores, compras y recepcion de lotes
--   rol_auditor        : solo lectura, incluida la bitacora
--   rol_respaldo       : solo lectura de toda la base para pg_dump
--   rol_monitoreo      : consulta metricas y ejecuta las alertas
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
DO $$
DECLARE
    r TEXT;
BEGIN
    FOREACH r IN ARRAY ARRAY['rol_admin_farmacia', 'rol_farmaceutico', 'rol_cajero',
                             'rol_compras', 'rol_auditor', 'rol_respaldo',
                             'rol_monitoreo']
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('CREATE ROLE %I NOLOGIN', r);
        END IF;
    END LOOP;
END $$;

-- Rol predefinido de PostgreSQL (14 o superior) para ver estadisticas y estado
GRANT pg_monitor TO rol_monitoreo;

-- OJO: para el rol de respaldo NO se usa pg_read_all_data. En las pruebas ese
-- rol alcanzo a leer los hashes de contrasena de todos los usuarios (pg_authid),
-- mucho mas de lo que necesita un backup. Su lectura se da tabla por tabla en
-- la seccion 4.6. (Si una version anterior de este script ya se ejecuto:)
REVOKE pg_read_all_data FROM rol_respaldo;


---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 2. USUARIOS
-- CONTRASENA DE DEMOSTRACION: cambiarla despues con
--   ALTER ROLE usr_cajero1 PASSWORD 'nueva';
-- Las contrasenas se guardan con scram-sha-256 (el valor por defecto desde
-- PostgreSQL 14). Se comprueba mas abajo.
-- Cada usuario tiene: limite de conexiones simultaneas, tiempo maximo por
-- consulta y tiempo maximo con una transaccion abierta sin actividad.
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
DO $$
DECLARE
    v_clave TEXT := 'Cambiar_Clave_2026!';
    u       RECORD;
BEGIN
    FOR u IN
        SELECT * FROM (VALUES
          -- usuario            rol                  conexiones  statement_timeout
          ('usr_admin',         'rol_admin_farmacia', 3,          '0'),
          ('usr_farmaceutico1', 'rol_farmaceutico',   5,          '30s'),
          ('usr_cajero1',       'rol_cajero',         5,          '30s'),
          ('usr_compras1',      'rol_compras',        3,          '30s'),
          ('usr_auditor1',      'rol_auditor',        2,          '120s'),
          ('usr_respaldo',      'rol_respaldo',       2,          '0'),
          ('usr_monitor',       'rol_monitoreo',      2,          '30s')
        ) AS x(usuario, rol, conexiones, tiempo)
    LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = u.usuario) THEN
            EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', u.usuario, v_clave);
        END IF;
        EXECUTE format('ALTER ROLE %I NOSUPERUSER NOCREATEDB NOCREATEROLE CONNECTION LIMIT %s',
                       u.usuario, u.conexiones);
        EXECUTE format('GRANT %I TO %I', u.rol, u.usuario);
        -- Los parametros por rol se aplican al usuario que inicia sesion
        EXECUTE format('ALTER ROLE %I SET statement_timeout = %L', u.usuario, u.tiempo);
        EXECUTE format('ALTER ROLE %I SET idle_in_transaction_session_timeout = %L',
                       u.usuario, '5min');
    END LOOP;
END $$;


---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 3. CERRAR LO QUE VIENE ABIERTO POR DEFECTO
-- Por defecto cualquier rol puede conectarse a la base y varias funciones
-- pueden ser ejecutadas por PUBLIC. Se cierra todo y se abre solo lo necesario.
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
DO $$
BEGIN
    EXECUTE format('REVOKE ALL ON DATABASE %I FROM PUBLIC', current_database());
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO rol_admin_farmacia, rol_farmaceutico,
                    rol_cajero, rol_compras, rol_auditor, rol_respaldo, rol_monitoreo',
                   current_database());
END $$;

REVOKE ALL    ON SCHEMA public FROM PUBLIC;
GRANT  USAGE  ON SCHEMA public TO rol_admin_farmacia, rol_farmaceutico, rol_cajero,
                                  rol_compras, rol_auditor, rol_respaldo, rol_monitoreo;

REVOKE ALL ON ALL TABLES    IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;

-- Funciones de mantenimiento de la bitacora: solo las ejecuta quien administra
REVOKE ALL ON FUNCTION fn_crear_particiones_bitacora(INTEGER)  FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_archivar_particiones_bitacora(INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_mantenimiento_mensual(INTEGER, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_auditoria_generica() FROM PUBLIC;

-- Lo que se cree en el futuro tampoco queda abierto
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES    FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM PUBLIC;


---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 4. PERMISOS POR ROL
-- S = SELECT, I = INSERT, U = UPDATE, D = DELETE. Nadie, salvo el
-- administrador, tiene DELETE. Con columnas entre parentesis el permiso es
-- solo sobre esas columnas.
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---

-- 4.1 ADMINISTRADOR: S, I, U, D en las tablas del negocio.
GRANT SELECT, INSERT, UPDATE, DELETE ON
    proveedor, producto, compra, detalle_compra, lote, cliente, paciente,
    receta, promocion, venta, detalle_venta, venta_promocion,
    historial_puntos, factura_dte
TO rol_admin_farmacia;

-- 4.2 FARMACEUTICO: dispensa y atiende pacientes. Ve datos clinicos.
GRANT SELECT ON
    producto, lote, cliente, paciente, receta, promocion, venta,
    detalle_venta, venta_promocion, historial_puntos, factura_dte
TO rol_farmaceutico;
GRANT INSERT ON venta, detalle_venta, venta_promocion, historial_puntos,
                factura_dte, cliente, paciente
TO rol_farmaceutico;
GRANT UPDATE (subtotal, descuento, total, id_receta) ON venta TO rol_farmaceutico;
GRANT UPDATE (estado)                                ON receta TO rol_farmaceutico;   -- validar / dispensar
GRANT UPDATE (stock_actual)                          ON lote TO rol_farmaceutico;      -- descontar stock
GRANT UPDATE (telefono, correo, nivel_fidelizacion, puntos_acumulados)
                                                     ON cliente TO rol_farmaceutico;
GRANT UPDATE (categoria, condicion_cronica, observaciones)
                                                     ON paciente TO rol_farmaceutico;
GRANT UPDATE (estado_envio, sello_recepcion, json_dte)
                                                     ON factura_dte TO rol_farmaceutico;

-- 4.3 CAJERO: registra ventas y puntos. NO ve paciente, receta, DUI ni correo.
GRANT SELECT ON producto, promocion, venta, detalle_venta, venta_promocion,
                historial_puntos, factura_dte
TO rol_cajero;
GRANT SELECT (id_lote, id_producto, numero_lote, fecha_caducidad, stock_actual)
                                              ON lote    TO rol_cajero;
GRANT SELECT (id_cliente, nombre, nivel_fidelizacion, puntos_acumulados)
                                              ON cliente TO rol_cajero;
GRANT INSERT ON venta, detalle_venta, venta_promocion, historial_puntos,
                factura_dte, cliente
TO rol_cajero;
GRANT UPDATE (subtotal, descuento, total)     ON venta   TO rol_cajero;
GRANT UPDATE (stock_actual)                   ON lote    TO rol_cajero;
GRANT UPDATE (nivel_fidelizacion, puntos_acumulados)
                                              ON cliente TO rol_cajero;
GRANT UPDATE (estado_envio, sello_recepcion, json_dte)
                                              ON factura_dte TO rol_cajero;

-- 4.4 COMPRAS: proveedores, compras y recepcion de lotes. Sin clientes ni pacientes.
GRANT SELECT, INSERT, UPDATE ON proveedor, compra, detalle_compra TO rol_compras;
GRANT SELECT, INSERT, UPDATE ON lote TO rol_compras;
GRANT SELECT ON producto TO rol_compras;

-- 4.5 AUDITOR: solo lectura. Sin acceso a datos clinicos ni al DUI.
GRANT SELECT ON proveedor, producto, compra, detalle_compra, lote, promocion,
                venta, detalle_venta, venta_promocion, historial_puntos,
                factura_dte
TO rol_auditor;
GRANT SELECT (id_cliente, nombre, nivel_fidelizacion, puntos_acumulados,
              fecha_creacion, fecha_actualizacion)
                                              ON cliente TO rol_auditor;

-- 4.6 RESPALDO: solo lectura de las tablas y secuencias del esquema public
--     (lo que necesita pg_dump). Las particiones futuras de bitacora las crea
--     postgres, por eso se define tambien el permiso por defecto.
GRANT SELECT ON ALL TABLES    IN SCHEMA public TO rol_respaldo;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO rol_respaldo;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    GRANT SELECT ON TABLES    TO rol_respaldo;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
    GRANT SELECT ON SEQUENCES TO rol_respaldo;

-- 4.7 MONITOREO: sus permisos vienen de pg_monitor (seccion 1) y de
--     monitoreo_alertas.sql (ejecutar fn_verificar_alertas y leer las alertas).


---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 5. AUDITORIA ENDURECIDA
-- 5.1 Problema: la funcion fn_auditoria_generica() escribe en bitacora con los
--     permisos de quien hizo el cambio. Si se cierra la bitacora, los cajeros
--     y farmaceuticos no podrian vender. Si se les diera INSERT en bitacora
--     podrian escribir registros falsos.
--     Solucion: la funcion se ejecuta como su propietario (SECURITY DEFINER) y
--     registra al usuario REAL con session_user (current_user seria el dueno).
-- 5.2 Los datos clinicos (diagnostico, observaciones, condicion cronica) NO se
--     copian a la bitacora: se guarda '[PROTEGIDO]'. Asi la bitacora, que la ve
--     el auditor, no se convierte en una segunda copia de datos sensibles.
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
CREATE OR REPLACE FUNCTION fn_proteger_json(p_datos JSONB)
RETURNS JSONB AS $$
DECLARE
    v_clave TEXT;
BEGIN
    IF p_datos IS NULL THEN
        RETURN NULL;
    END IF;
    FOREACH v_clave IN ARRAY ARRAY['diagnostico', 'observaciones', 'condicion_cronica']
    LOOP
        IF p_datos ? v_clave AND p_datos -> v_clave <> 'null'::jsonb THEN
            p_datos := jsonb_set(p_datos, ARRAY[v_clave], '"[PROTEGIDO]"'::jsonb);
        END IF;
    END LOOP;
    RETURN p_datos;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION fn_auditoria_generica()
RETURNS trigger
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    INSERT INTO bitacora (
        tabla_afectada, operacion, usuario, nro_transaccion,
        datos_anteriores, datos_nuevos, fecha_hora
    ) VALUES (
        TG_TABLE_NAME,
        TG_OP,
        session_user,
        pg_current_xact_id()::text,
        CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN fn_proteger_json(to_jsonb(OLD)) END,
        CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN fn_proteger_json(to_jsonb(NEW)) END,
        clock_timestamp()
    );
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

REVOKE ALL ON FUNCTION fn_proteger_json(JSONB)  FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_auditoria_generica() FROM PUBLIC;

-- 5.3 Limpieza unica: los registros que ya estaban en la bitacora (cargados
--     con datos_prueba.sql) tienen los datos clinicos sin proteger.
UPDATE bitacora
   SET datos_anteriores = fn_proteger_json(datos_anteriores),
       datos_nuevos     = fn_proteger_json(datos_nuevos)
 WHERE tabla_afectada IN ('paciente', 'receta');

-- 5.4 Cerrar la bitacora. Se hace aqui porque particionamiento.sql la volvio a
--     crear. Los permisos de la tabla padre aplican al consultar por ella.
REVOKE ALL ON bitacora FROM PUBLIC;
GRANT SELECT ON bitacora TO rol_auditor, rol_admin_farmacia;
-- Ademas de auditor y administrador, solo el rol de respaldo la lee (para el
-- backup, ver 4.6). Nadie (salvo el propietario) puede hacer UPDATE, DELETE o
-- TRUNCATE sobre ella.


---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 6. COMPROBACIONES
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---

-- 6.1 Roles, si pueden iniciar sesion, limite de conexiones y a que grupo pertenecen
SELECT r.rolname                                   AS rol,
       r.rolcanlogin                               AS puede_iniciar_sesion,
       r.rolsuper                                  AS superusuario,
       r.rolconnlimit                              AS limite_conexiones,
       COALESCE(string_agg(g.rolname, ', '), '-')  AS pertenece_a
  FROM pg_roles r
  LEFT JOIN pg_auth_members m ON m.member = r.oid
  LEFT JOIN pg_roles g        ON g.oid = m.roleid AND g.rolname LIKE 'rol\_%'
 WHERE r.rolname LIKE 'rol\_%' OR r.rolname LIKE 'usr\_%'
 GROUP BY r.rolname, r.rolcanlogin, r.rolsuper, r.rolconnlimit
 ORDER BY r.rolcanlogin, r.rolname;

-- 6.2 Parametros de cada usuario (tiempos maximos)
SELECT r.rolname AS usuario, c.setconfig AS parametros
  FROM pg_db_role_setting c
  JOIN pg_roles r ON r.oid = c.setrole
 WHERE r.rolname LIKE 'usr\_%'
 ORDER BY r.rolname;

-- 6.3 Las contrasenas estan guardadas con scram-sha-256 (no en texto ni md5)
SELECT rolname AS usuario,
       CASE WHEN rolpassword LIKE 'SCRAM-SHA-256$%' THEN 'scram-sha-256'
            WHEN rolpassword LIKE 'md5%'            THEN 'md5 (debil)'
            ELSE 'sin contrasena' END AS algoritmo
  FROM pg_authid
 WHERE rolname LIKE 'usr\_%'
 ORDER BY rolname;

-- 6.4 Matriz de permisos por tabla. Letra mayuscula = permiso sobre toda la
--     tabla; minuscula = solo sobre algunas columnas; '-' = sin permiso.
WITH roles AS (
    SELECT unnest(ARRAY['rol_admin_farmacia', 'rol_farmaceutico', 'rol_cajero',
                        'rol_compras', 'rol_auditor', 'rol_respaldo']) AS rol
), tablas AS (
    SELECT c.oid, c.relname
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p') AND NOT c.relispartition
)
SELECT t.relname AS tabla,
       max(CASE WHEN r.rol = 'rol_admin_farmacia' THEN p.permisos END) AS admin,
       max(CASE WHEN r.rol = 'rol_farmaceutico'   THEN p.permisos END) AS farmaceutico,
       max(CASE WHEN r.rol = 'rol_cajero'         THEN p.permisos END) AS cajero,
       max(CASE WHEN r.rol = 'rol_compras'        THEN p.permisos END) AS compras,
       max(CASE WHEN r.rol = 'rol_auditor'        THEN p.permisos END) AS auditor,
       max(CASE WHEN r.rol = 'rol_respaldo'       THEN p.permisos END) AS respaldo
  FROM tablas t
 CROSS JOIN roles r
 CROSS JOIN LATERAL (
    SELECT concat(
        CASE WHEN has_table_privilege(r.rol, t.oid, 'SELECT') THEN 'S'
             WHEN has_any_column_privilege(r.rol, t.oid, 'SELECT') THEN 's' ELSE '-' END,
        CASE WHEN has_table_privilege(r.rol, t.oid, 'INSERT') THEN 'I'
             WHEN has_any_column_privilege(r.rol, t.oid, 'INSERT') THEN 'i' ELSE '-' END,
        CASE WHEN has_table_privilege(r.rol, t.oid, 'UPDATE') THEN 'U'
             WHEN has_any_column_privilege(r.rol, t.oid, 'UPDATE') THEN 'u' ELSE '-' END,
        CASE WHEN has_table_privilege(r.rol, t.oid, 'DELETE') THEN 'D' ELSE '-' END
    ) AS permisos
 ) p
 GROUP BY t.relname
 ORDER BY t.relname;

-- 6.5 Ningun usuario de la aplicacion es superusuario
SELECT rolname AS superusuarios FROM pg_roles WHERE rolsuper;
