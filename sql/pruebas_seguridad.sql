---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- Pruebas de seguridad (evidencia)
-- EJECUTAR DESPUES DE seguridad.sql, conectado como postgres.
--
-- Cada prueba se ejecuta "como" un usuario (SET ROLE) e intenta una accion.
-- Despues de cada prueba se deshace todo, asi que no cambia ningun dato.
-- Resultado esperado:
--   DENEGADO  = PostgreSQL rechazo la accion (permission denied)
--   PERMITIDO = la accion es valida para ese rol
-- La columna "ok" dice si el resultado coincide con lo esperado.
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---

DROP TABLE IF EXISTS resultado_pruebas_seguridad;
CREATE TEMP TABLE resultado_pruebas_seguridad (
    nro        SERIAL,
    usuario    TEXT,
    prueba     TEXT,
    esperado   TEXT,
    resultado  TEXT,
    ok         TEXT
);

DO $$
DECLARE
    t   RECORD;
    res TEXT;
BEGIN
    FOR t IN
        SELECT * FROM (VALUES
          -- usuario, descripcion, sentencia, esperado
          ('usr_cajero1',       'Ver nombre y puntos de clientes',
           'SELECT nombre, puntos_acumulados FROM cliente',                                  'PERMITIDO'),
          ('usr_cajero1',       'Ver el DUI de los clientes',
           'SELECT dui FROM cliente',                                                         'DENEGADO'),
          ('usr_cajero1',       'Ver pacientes (datos clinicos)',
           'SELECT * FROM paciente',                                                          'DENEGADO'),
          ('usr_cajero1',       'Ver recetas',
           'SELECT * FROM receta',                                                            'DENEGADO'),
          ('usr_cajero1',       'Registrar una venta',
           'INSERT INTO venta (subtotal, total) VALUES (5.00, 5.00)',                         'PERMITIDO'),
          ('usr_cajero1',       'Borrar una venta',
           'DELETE FROM venta WHERE id_venta = 1',                                            'DENEGADO'),
          ('usr_cajero1',       'Cambiar el precio de un producto',
           'UPDATE producto SET precio_venta = 0.01',                                         'DENEGADO'),
          ('usr_cajero1',       'Leer la bitacora',
           'SELECT * FROM bitacora',                                                          'DENEGADO'),

          ('usr_farmaceutico1', 'Ver diagnostico de recetas',
           'SELECT diagnostico FROM receta',                                                  'PERMITIDO'),
          ('usr_farmaceutico1', 'Validar una receta (cambiar estado)',
           'UPDATE receta SET estado = ''VALIDADA'' WHERE id_receta = 6',                     'PERMITIDO'),
          ('usr_farmaceutico1', 'Alterar el diagnostico de una receta',
           'UPDATE receta SET diagnostico = ''otro'' WHERE id_receta = 6',                    'DENEGADO'),
          ('usr_farmaceutico1', 'Borrar una receta',
           'DELETE FROM receta WHERE id_receta = 6',                                          'DENEGADO'),
          ('usr_farmaceutico1', 'Ver proveedores y compras',
           'SELECT * FROM proveedor',                                                         'DENEGADO'),

          ('usr_compras1',      'Registrar una compra',
           'INSERT INTO compra (id_proveedor) VALUES (1)',                                    'PERMITIDO'),
          ('usr_compras1',      'Ver pacientes',
           'SELECT * FROM paciente',                                                          'DENEGADO'),
          ('usr_compras1',      'Ver ventas',
           'SELECT * FROM venta',                                                             'DENEGADO'),
          ('usr_compras1',      'Cambiar precios de productos',
           'UPDATE producto SET precio_venta = 0.01',                                         'DENEGADO'),

          ('usr_auditor1',      'Leer la bitacora',
           'SELECT count(*) FROM bitacora',                                                   'PERMITIDO'),
          ('usr_auditor1',      'Modificar la bitacora',
           'UPDATE bitacora SET usuario = ''nadie''',                                         'DENEGADO'),
          ('usr_auditor1',      'Borrar de la bitacora',
           'DELETE FROM bitacora',                                                            'DENEGADO'),
          ('usr_auditor1',      'Registrar una venta',
           'INSERT INTO venta (subtotal, total) VALUES (1, 1)',                               'DENEGADO'),
          ('usr_auditor1',      'Ver el DUI de los clientes',
           'SELECT dui FROM cliente',                                                         'DENEGADO'),

          ('usr_admin',         'Ver el DUI de los clientes',
           'SELECT dui FROM cliente',                                                         'PERMITIDO'),
          ('usr_admin',         'Borrar de la bitacora',
           'DELETE FROM bitacora',                                                            'DENEGADO'),
          ('usr_admin',         'Eliminar una tabla (DROP)',
           'DROP TABLE venta CASCADE',                                                        'DENEGADO'),
          ('usr_admin',         'Crear un usuario nuevo',
           'CREATE ROLE intruso LOGIN',                                                       'DENEGADO'),

          ('usr_respaldo',      'Leer todas las tablas (para pg_dump)',
           'SELECT count(*) FROM paciente',                                                   'PERMITIDO'),
          ('usr_respaldo',      'Escribir datos',
           'INSERT INTO venta (subtotal, total) VALUES (1, 1)',                               'DENEGADO'),
          ('usr_respaldo',      'Leer contrasenas de los usuarios (pg_authid)',
           'SELECT rolname, rolpassword FROM pg_authid',                                      'DENEGADO'),

          ('usr_monitor',       'Ejecutar las alertas',
           'SELECT * FROM fn_verificar_alertas()',                                            'PERMITIDO'),
          ('usr_monitor',       'Leer las ventas',
           'SELECT * FROM venta',                                                             'DENEGADO')
        ) AS x(usuario, prueba, sentencia, esperado)
    LOOP
        BEGIN
            EXECUTE format('SET LOCAL ROLE %I', t.usuario);
            EXECUTE t.sentencia;
            -- Se llego hasta aqui: la accion estaba permitida. Se fuerza un error
            -- para deshacer la prueba y no dejar cambios en los datos.
            RAISE EXCEPTION 'deshacer prueba' USING ERRCODE = 'RB001';
        EXCEPTION
            WHEN SQLSTATE 'RB001'        THEN res := 'PERMITIDO';
            WHEN insufficient_privilege  THEN res := 'DENEGADO';
            WHEN OTHERS                  THEN res := 'ERROR: ' || SQLERRM;
        END;
        INSERT INTO resultado_pruebas_seguridad (usuario, prueba, esperado, resultado, ok)
        VALUES (t.usuario, t.prueba, t.esperado, res,
                CASE WHEN res = t.esperado THEN 'OK' ELSE 'REVISAR' END);
    END LOOP;
END $$;

SELECT nro, usuario, prueba, esperado, resultado, ok
  FROM resultado_pruebas_seguridad
 ORDER BY nro;

-- Resumen
SELECT count(*)                                  AS pruebas,
       count(*) FILTER (WHERE ok = 'OK')         AS correctas,
       count(*) FILTER (WHERE ok <> 'OK')        AS por_revisar
  FROM resultado_pruebas_seguridad;
