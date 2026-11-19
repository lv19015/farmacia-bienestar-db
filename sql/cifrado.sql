---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- Cifrado de datos clinicos con pgcrypto
-- EJECUTAR DESPUES DE seguridad.sql, conectado como postgres.
--
-- Que protege: receta.diagnostico y paciente.observaciones (texto libre con
-- informacion de salud). Se guardan CIFRADAS dentro de la base (cifrado a
-- nivel de columna, PGP simetrico). Si alguien copia los archivos de datos,
-- un backup o un volcado (pg_dump), solo ve texto ilegible.
--
-- Como funciona (transparente para la aplicacion):
--   - Un trigger BEFORE INSERT/UPDATE cifra el valor antes de guardarlo.
--   - La clave NO esta en la base: cada sesion la entrega con
--         SET app.clave_cifrado = '...';
--     Sin clave, el trigger rechaza guardar datos clinicos (falla cerrado).
--   - Para leer descifrado se usan las vistas v_receta_clinica y
--     v_paciente_clinico (solo farmaceutico y administrador).
--
-- IMPORTANTE (informe): en este proyecto la clave se escribe en el script solo
-- como demostracion. En produccion debe venir de la aplicacion o de un
-- gestor de secretos, y guardarse aparte de la base y de los backups. Si se
-- pierde la clave, los datos cifrados NO se pueden recuperar.
--
-- Efecto en consultas.sql: dos consultas leen estas columnas directamente
-- (historico de medicamentos -> r.diagnostico y pacientes cronicos ->
-- p.observaciones). Ahora mostrarian texto cifrado; para verlas legibles se
-- cambian por las vistas (ver seccion 5).
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---

CREATE EXTENSION IF NOT EXISTS pgcrypto;

---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 1. FUNCIONES DE CIFRADO Y DESCIFRADO
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
CREATE OR REPLACE FUNCTION fn_cifrar_texto(p_texto TEXT)
RETURNS TEXT AS $$
DECLARE
    v_clave TEXT := current_setting('app.clave_cifrado', true);
BEGIN
    IF p_texto IS NULL THEN
        RETURN NULL;
    END IF;
    -- Si ya viene cifrado (por ejemplo en un UPDATE de otra columna) no se cifra otra vez
    IF p_texto LIKE '-----BEGIN PGP MESSAGE-----%' THEN
        RETURN p_texto;
    END IF;
    IF v_clave IS NULL OR v_clave = '' THEN
        RAISE EXCEPTION 'No se puede guardar informacion clinica: la sesion no tiene clave de cifrado (SET app.clave_cifrado)'
              USING ERRCODE = '28000';
    END IF;
    RETURN armor(pgp_sym_encrypt(p_texto, v_clave));
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_descifrar_texto(p_texto TEXT)
RETURNS TEXT AS $$
DECLARE
    v_clave TEXT := current_setting('app.clave_cifrado', true);
BEGIN
    IF p_texto IS NULL OR p_texto NOT LIKE '-----BEGIN PGP MESSAGE-----%' THEN
        RETURN p_texto;                       -- nulo o dato anterior al cifrado
    END IF;
    IF v_clave IS NULL OR v_clave = '' THEN
        RETURN '[CIFRADO - sin clave]';
    END IF;
    RETURN pgp_sym_decrypt(dearmor(p_texto), v_clave);
EXCEPTION
    WHEN OTHERS THEN
        RETURN '[CIFRADO - clave incorrecta]';
END;
$$ LANGUAGE plpgsql;

---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 2. TRIGGER QUE CIFRA AL GUARDAR
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
CREATE OR REPLACE FUNCTION fn_cifrar_columnas_clinicas()
RETURNS trigger AS $$
BEGIN
    IF TG_TABLE_NAME = 'receta' THEN
        NEW.diagnostico := fn_cifrar_texto(NEW.diagnostico);
    ELSIF TG_TABLE_NAME = 'paciente' THEN
        NEW.observaciones := fn_cifrar_texto(NEW.observaciones);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_receta_cifrar   ON receta;
DROP TRIGGER IF EXISTS trg_paciente_cifrar ON paciente;
CREATE TRIGGER trg_receta_cifrar
    BEFORE INSERT OR UPDATE ON receta
    FOR EACH ROW EXECUTE FUNCTION fn_cifrar_columnas_clinicas();
CREATE TRIGGER trg_paciente_cifrar
    BEFORE INSERT OR UPDATE ON paciente
    FOR EACH ROW EXECUTE FUNCTION fn_cifrar_columnas_clinicas();

---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 3. CIFRAR LOS DATOS QUE YA EXISTEN
-- (la clave de abajo es de DEMOSTRACION; usar la misma clave siempre)
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
SELECT set_config('app.clave_cifrado', 'ClaveDemo_Farmacia_2026', false);

UPDATE receta   SET diagnostico   = diagnostico   WHERE diagnostico   IS NOT NULL;
UPDATE paciente SET observaciones = observaciones WHERE observaciones IS NOT NULL;

---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 4. VISTAS PARA LEER LOS DATOS DESCIFRADOS
-- security_invoker: la vista respeta los permisos de quien la consulta
-- (PostgreSQL 15 o superior), asi un rol sin permiso sobre receta o paciente
-- tampoco puede usarlas.
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
CREATE OR REPLACE VIEW v_receta_clinica WITH (security_invoker = true) AS
SELECT id_receta, id_paciente, fecha_emision, vigencia, medico_emisor,
       especialidad, clinica, estado,
       fn_descifrar_texto(diagnostico) AS diagnostico
  FROM receta;

CREATE OR REPLACE VIEW v_paciente_clinico WITH (security_invoker = true) AS
SELECT id_paciente, id_cliente, fecha_nacimiento, categoria, condicion_cronica,
       fn_descifrar_texto(observaciones) AS observaciones, fecha_registro
  FROM paciente;

REVOKE ALL ON v_receta_clinica, v_paciente_clinico FROM PUBLIC;
GRANT SELECT ON v_receta_clinica, v_paciente_clinico
   TO rol_farmaceutico, rol_admin_farmacia;

---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 5. COMO ADAPTAR consultas.sql
--   Historico de medicamentos: cambiar  JOIN receta r ON r.id_paciente = pa.id_paciente
--                              por      JOIN v_receta_clinica r ON r.id_paciente = pa.id_paciente
--   Pacientes cronicos:        cambiar  FROM paciente p
--                              por      FROM v_paciente_clinico p
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---


---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---
-- 6. COMPROBACIONES
---*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*--*-*-*-*-*-*-*---

-- 6.1 Asi esta guardado en la tabla (ilegible)
SELECT id_receta, left(diagnostico, 60) AS diagnostico_guardado
  FROM receta ORDER BY id_receta LIMIT 3;

-- 6.2 Con la clave, la vista lo muestra legible
SELECT id_receta, estado, diagnostico FROM v_receta_clinica ORDER BY id_receta LIMIT 3;

-- 6.3 Sin la clave (sesion nueva o clave vacia), la vista no lo revela
SELECT set_config('app.clave_cifrado', '', false);
SELECT id_receta, diagnostico FROM v_receta_clinica ORDER BY id_receta LIMIT 3;

-- 6.4 Con una clave incorrecta tampoco
SELECT set_config('app.clave_cifrado', 'clave_equivocada', false);
SELECT id_receta, diagnostico FROM v_receta_clinica ORDER BY id_receta LIMIT 3;

-- 6.5 Sin clave no se pueden guardar datos clinicos nuevos: la prueba debe dar error
SELECT set_config('app.clave_cifrado', '', false);
-- INSERT INTO receta (id_paciente, fecha_emision, vigencia, medico_emisor, diagnostico)
-- VALUES (1, CURRENT_DATE, CURRENT_DATE + 30, 'Dr. Prueba', 'texto de prueba');
-- ERROR: No se puede guardar informacion clinica: la sesion no tiene clave de cifrado

-- Dejar la sesion lista con la clave correcta
SELECT set_config('app.clave_cifrado', 'ClaveDemo_Farmacia_2026', false);

-- 6.6 La bitacora tampoco guarda el diagnostico (queda '[PROTEGIDO]')
SELECT tabla_afectada, operacion, datos_nuevos ->> 'diagnostico' AS diagnostico_en_bitacora
  FROM bitacora
 WHERE tabla_afectada = 'receta'
 ORDER BY id_bitacora DESC LIMIT 3;
