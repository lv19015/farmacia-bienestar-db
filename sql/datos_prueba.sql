-- =====================================================================
-- Farmacia Comunitaria "Bienestar" - Datos de prueba (10 registros por tabla)
-- Ejecutar DESPUES de estructura_db.sql y indices_bitacora.sql.
-- Al ejecutarse despues del script 02, los triggers de auditoria llenan la
-- tabla bitacora automaticamente con estas inserciones.
-- =====================================================================

INSERT INTO proveedor
(nombre, tipo, contacto, plazo_entrega_dias, condiciones_pago)
VALUES
('Laboratorios Suizos', 'LABORATORIO', '2222-1001', 5, 'Credito 30 dias'),
('Laboratorios Vijosa', 'LABORATORIO', '2222-1002', 7, 'Contado'),
('Laboratorios Lopez', 'LABORATORIO', '2222-1003', 4, 'Credito 15 dias'),
('Distribuidora Farmaceutica SA', 'DISTRIBUIDORA', '2222-1004', 3, 'Credito 30 dias'),
('Distribuidora Medica Centro', 'DISTRIBUIDORA', '2222-1005', 2, 'Contado'),
('Laboratorios Bayer', 'LABORATORIO', '2222-1006', 8, 'Credito 30 dias'),
('Laboratorios MK', 'LABORATORIO', '2222-1007', 6, 'Credito 15 dias'),
('Distribuidora Salud Total', 'DISTRIBUIDORA', '2222-1008', 3, 'Contado'),
('Laboratorios Pfizer', 'LABORATORIO', '2222-1009', 10, 'Credito 30 dias'),
('Distribuidora Farma Plus', 'DISTRIBUIDORA', '2222-1010', 4, 'Credito 15 dias');

INSERT INTO producto
(nombre, principio_activo, marca, presentacion,
 requiere_receta, condiciones_almacenamiento, precio_venta, descuento)
VALUES
('Paracetamol 500mg', 'Paracetamol', 'MK', 'Tabletas x 20', FALSE, 'Temperatura ambiente', 3.50, 0),
('Ibuprofeno 400mg', 'Ibuprofeno', 'Vijosa', 'Tabletas x 10', FALSE, 'Temperatura ambiente', 4.75, 5),
('Amoxicilina 500mg', 'Amoxicilina', 'Suizos', 'Capsulas x 20', TRUE, 'Lugar fresco y seco', 8.50, 0),
('Loratadina 10mg', 'Loratadina', 'MK', 'Tabletas x 10', FALSE, 'Temperatura ambiente', 3.25, 10),
('Omeprazol 20mg', 'Omeprazol', 'Lopez', 'Capsulas x 14', FALSE, 'Lugar fresco y seco', 5.00, 0),
('Losartan 50mg', 'Losartan', 'Bayer', 'Tabletas x 30', TRUE, 'Temperatura ambiente', 12.00, 5),
('Metformina 850mg', 'Metformina', 'MK', 'Tabletas x 30', TRUE, 'Temperatura ambiente', 9.50, 0),
('Vitamina C 500mg', 'Acido ascorbico', 'Vijosa', 'Tabletas x 30', FALSE, 'Lugar fresco y seco', 6.00, 10),
('Diclofenaco 50mg', 'Diclofenaco', 'Suizos', 'Tabletas x 20', FALSE, 'Temperatura ambiente', 5.50, 0),
('Cetirizina 10mg', 'Cetirizina', 'Pfizer', 'Tabletas x 10', FALSE, 'Temperatura ambiente', 4.00, 0);

INSERT INTO cliente
(nombre, dui, telefono, correo, nivel_fidelizacion, puntos_acumulados)
VALUES
('Carlos Martinez', '01234567-8', '7000-1001', 'carlos@gmail.com', 'ORO', 150),
('Maria Lopez', '01234568-9', '7000-1002', 'maria@gmail.com', 'PLATA', 80),
('Jose Hernandez', '01234569-0', '7000-1003', 'jose@gmail.com', 'BASICO', 40),
('Ana Garcia', '01234570-1', '7000-1004', 'ana@gmail.com', 'DIAMANTE', 500),
('Pedro Ramirez', '01234571-2', '7000-1005', 'pedro@gmail.com', 'ORO', 200),
('Sofia Flores', '01234572-3', '7000-1006', 'sofia@gmail.com', 'PLATA', 90),
('Luis Rodriguez', '01234573-4', '7000-1007', 'luis@gmail.com', 'BASICO', 60),
('Daniela Perez', '01234574-5', '7000-1008', 'daniela@gmail.com', 'ORO', 180),
('Miguel Torres', '01234575-6', '7000-1009', 'miguel@gmail.com', 'PLATA', 75),
('Gabriela Cruz', '01234576-7', '7000-1010', 'gabriela@gmail.com', 'DIAMANTE', 600);

INSERT INTO paciente
(id_cliente, fecha_nacimiento, categoria, condicion_cronica, observaciones)
VALUES
(1, '1985-04-12', 'GENERAL', NULL, 'Paciente regular'),
(2, '1990-07-20', 'CRONICO', 'Hipertension', 'Control periodico'),
(3, '1978-02-15', 'GENERAL', NULL, 'Sin observaciones'),
(4, '1965-11-10', 'CRONICO', 'Diabetes tipo 2', 'Seguimiento mensual'),
(5, '1982-09-05', 'GENERAL', NULL, 'Paciente regular'),
(6, '1995-01-25', 'GENERAL', NULL, 'Sin observaciones'),
(7, '1970-06-18', 'CRONICO', 'Hipertension', 'Control de presion'),
(8, '1988-12-30', 'GENERAL', NULL, 'Paciente regular'),
(9, '1975-03-22', 'CRONICO', 'Diabetes tipo 2', 'Seguimiento medico'),
(10, '1992-08-14', 'GENERAL', NULL, 'Sin observaciones');

INSERT INTO compra
(id_proveedor, fecha_compra, total, estado)
VALUES
(1, '2026-01-05', 250.00, 'RECIBIDA'),
(2, '2026-01-08', 350.00, 'RECIBIDA'),
(3, '2026-01-10', 600.00, 'RECIBIDA'),
(4, '2026-01-12', 200.00, 'RECIBIDA'),
(5, '2026-01-15', 350.00, 'RECIBIDA'),
(6, '2026-01-18', 900.00, 'RECIBIDA'),
(7, '2026-01-20', 700.00, 'RECIBIDA'),
(8, '2026-01-22', 450.00, 'RECIBIDA'),
(9, '2026-01-25', 400.00, 'RECIBIDA'),
(10, '2026-01-28', 300.00, 'RECIBIDA');

INSERT INTO detalle_compra
(id_compra, id_producto, cantidad_solicitada, precio_unitario)
VALUES
(1, 1, 100, 2.50),
(2, 2, 100, 3.50),
(3, 3, 100, 6.00),
(4, 4, 100, 2.00),
(5, 5, 100, 3.50),
(6, 6, 100, 9.00),
(7, 7, 100, 7.00),
(8, 8, 100, 4.50),
(9, 9, 100, 4.00),
(10, 10, 100, 3.00);

INSERT INTO lote
(id_producto, id_compra, numero_lote, fecha_fabricacion,
 fecha_caducidad, cantidad_recibida, stock_actual)
VALUES
(1, 1, 'PAR-2026-001', '2025-10-01', '2028-10-01', 60, 58),
(2, 2, 'IBU-2026-001', '2025-11-01', '2028-11-01', 80, 75),
(3, 3, 'AMO-2026-001', '2025-09-01', '2027-09-01', 100, 97),
(4, 4, 'LOR-2026-001', '2025-12-01', '2028-12-01', 100, 98),
(5, 5, 'OME-2026-001', '2025-08-01', '2028-08-01', 100, 97),
(6, 6, 'LOS-2026-001', '2025-07-01', '2028-07-01', 100, 97),
(7, 7, 'MET-2026-001', '2025-06-01', '2028-06-01', 100, 97),
(8, 8, 'VIT-2026-001', '2025-12-01', '2028-12-01', 100, 98),
(9, 9, 'DIC-2026-001', '2025-10-01', '2028-10-01', 100, 98),
(10, 10, 'CET-2026-001', '2025-11-01', '2028-11-01', 100, 98),
(1, 1, 'PAR-2026-002', '2025-06-01', '2027-01-15', 40, 40),
(2, 2, 'IBU-2025-009', '2024-11-01', '2026-10-31', 20, 20);

-- Las recetas 2, 3, 4, 7 y 9 ya fueron dispensadas (estan ligadas a una venta).
-- Las recetas 6 y 10 siguen PENDIENTES y por eso no tienen venta.
INSERT INTO receta
(id_paciente, fecha_emision, vigencia, medico_emisor,
 especialidad, clinica, estado, diagnostico)
VALUES
(1, '2026-02-01', '2026-12-31', 'Dr. Roberto Perez', 'Medicina general', 'Clinica Central', 'VALIDADA', 'Dolor general'),
(2, '2026-02-02', '2026-12-31', 'Dra. Ana Morales', 'Cardiologia', 'Clinica Salud', 'DISPENSADA', 'Hipertension'),
(3, '2026-02-03', '2026-12-31', 'Dr. Carlos Ruiz', 'Medicina general', 'Clinica San Jose', 'DISPENSADA', 'Infeccion bacteriana'),
(4, '2026-02-04', '2026-12-31', 'Dra. Maria Torres', 'Endocrinologia', 'Hospital Central', 'DISPENSADA', 'Diabetes tipo 2'),
(5, '2026-02-05', '2026-12-31', 'Dr. Luis Gomez', 'Medicina general', 'Clinica Familiar', 'VALIDADA', 'Dolor muscular'),
(6, '2026-02-06', '2026-12-31', 'Dra. Sofia Diaz', 'Medicina general', 'Clinica Norte', 'PENDIENTE', 'Alergia'),
(7, '2026-02-07', '2026-12-31', 'Dr. Pedro Castro', 'Cardiologia', 'Clinica Salud', 'DISPENSADA', 'Hipertension'),
(8, '2026-02-08', '2026-12-31', 'Dra. Elena Flores', 'Medicina general', 'Clinica Central', 'VALIDADA', 'Dolor general'),
(9, '2026-02-09', '2026-12-31', 'Dr. Miguel Santos', 'Endocrinologia', 'Hospital Central', 'DISPENSADA', 'Diabetes tipo 2'),
(10, '2026-02-10', '2026-12-31', 'Dra. Gabriela Cruz', 'Medicina general', 'Clinica Familiar', 'PENDIENTE', 'Alergia');

INSERT INTO promocion
(nombre, porcentaje, fecha_inicio, fecha_fin, monto_maximo_aplicable)
VALUES
('Descuento bienvenida', 10, '2026-01-01', '2026-12-31', 10.00),
('Semana de salud', 15, '2026-02-01', '2026-12-31', 15.00),
('Promocion vitaminas', 20, '2026-03-01', '2026-12-31', 20.00),
('Descuento adultos mayores', 10, '2026-01-01', '2026-12-31', 12.00),
('Promocion analgesicos', 5, '2026-04-01', '2026-12-31', 8.00),
('Mes de la diabetes', 15, '2026-05-01', '2026-12-31', 20.00),
('Promocion familiar', 10, '2026-06-01', '2026-12-31', 15.00),
('Descuento especial', 25, '2026-07-01', '2026-12-31', 25.00),
('Oferta de temporada', 12, '2026-08-01', '2026-12-31', 18.00),
('Promocion fin de año', 20, '2026-11-01', '2026-12-31', 30.00);

-- Reglas de los datos de prueba:
--   subtotal  = suma de detalle_venta
--   descuento = descuento de la promocion + canje de puntos (puntos_canjeados x 0.01)
--   total     = subtotal - descuento
--   id_receta solo en ventas con medicamentos que requieren receta
INSERT INTO venta
(id_cliente, id_receta, fecha_hora, subtotal, descuento,
 total, puntos_canjeados)
VALUES
(1, NULL, '2026-02-15 09:00:00-06', 7.00, 0.70, 6.30, 0),
(2, 2, '2026-02-16 10:00:00-06', 24.00, 3.60, 20.40, 0),
(3, 3, '2026-03-17 11:00:00-06', 25.50, 5.10, 20.40, 0),
(4, 4, '2026-03-18 12:00:00-06', 19.00, 2.90, 16.10, 100),
(5, NULL, '2026-04-19 13:00:00-06', 11.00, 0.55, 10.45, 0),
(6, NULL, '2026-05-20 14:00:00-06', 8.00, 1.20, 6.80, 0),
(7, 7, '2026-06-21 15:00:00-06', 35.75, 3.58, 32.17, 0),
(8, NULL, '2026-07-22 16:00:00-06', 12.00, 3.00, 9.00, 0),
(9, 9, '2026-08-23 17:00:00-06', 24.50, 2.94, 21.56, 0),
(10, NULL, '2026-11-10 18:00:00-06', 6.50, 1.30, 5.20, 0);

INSERT INTO detalle_venta
(id_venta, id_lote, cantidad, precio_unitario)
VALUES
(1, 1, 2, 3.50),
(2, 6, 2, 12.00),
(3, 3, 3, 8.50),
(4, 7, 2, 9.50),
(5, 9, 2, 5.50),
(6, 10, 2, 4.00),
(7, 2, 5, 4.75),
(7, 6, 1, 12.00),
(8, 8, 2, 6.00),
(9, 5, 3, 5.00),
(9, 7, 1, 9.50),
(10, 4, 2, 3.25);

INSERT INTO venta_promocion
(id_venta, id_promocion, monto_descuento)
VALUES
(1, 1, 0.70),
(2, 2, 3.60),
(3, 3, 5.10),
(4, 4, 1.90),
(5, 5, 0.55),
(6, 6, 1.20),
(7, 7, 3.58),
(8, 8, 3.00),
(9, 9, 2.94),
(10, 10, 1.30);

INSERT INTO historial_puntos
(id_cliente, fecha_movimiento, tipo_movimiento, puntos, equivalente_dinero)
VALUES
(1, '2026-01-10 10:00:00-06', 'ACUMULACION', 144, 1.44),
(2, '2026-01-10 10:00:00-06', 'ACUMULACION', 60, 0.60),
(3, '2026-01-10 10:00:00-06', 'ACUMULACION', 20, 0.20),
(4, '2026-01-10 10:00:00-06', 'ACUMULACION', 584, 5.84),
(5, '2026-01-10 10:00:00-06', 'ACUMULACION', 190, 1.90),
(6, '2026-01-10 10:00:00-06', 'ACUMULACION', 84, 0.84),
(7, '2026-01-10 10:00:00-06', 'ACUMULACION', 28, 0.28),
(8, '2026-01-10 10:00:00-06', 'ACUMULACION', 171, 1.71),
(9, '2026-01-10 10:00:00-06', 'ACUMULACION', 54, 0.54),
(10, '2026-01-10 10:00:00-06', 'ACUMULACION', 595, 5.95),
(1, '2026-02-15 09:00:00-06', 'ACUMULACION', 6, 0.06),
(2, '2026-02-16 10:00:00-06', 'ACUMULACION', 20, 0.20),
(3, '2026-03-17 11:00:00-06', 'ACUMULACION', 20, 0.20),
(4, '2026-03-18 12:00:00-06', 'ACUMULACION', 16, 0.16),
(4, '2026-03-18 12:00:00-06', 'CANJE', 100, 1.00),
(5, '2026-04-19 13:00:00-06', 'ACUMULACION', 10, 0.10),
(6, '2026-05-20 14:00:00-06', 'ACUMULACION', 6, 0.06),
(7, '2026-06-21 15:00:00-06', 'ACUMULACION', 32, 0.32),
(8, '2026-07-22 16:00:00-06', 'ACUMULACION', 9, 0.09),
(9, '2026-08-23 17:00:00-06', 'ACUMULACION', 21, 0.21),
(10, '2026-11-10 18:00:00-06', 'ACUMULACION', 5, 0.05);

INSERT INTO factura_dte
(id_venta, codigo_generacion, numero_control, sello_recepcion,
 fecha_emision, estado_envio, json_dte)
VALUES
(1, gen_random_uuid(), 'DTE-01-000001', 'SELLO001', '2026-02-15 09:00:00-06', 'ACEPTADO', '{"tipo":"FACTURA","total":6.30}'),
(2, gen_random_uuid(), 'DTE-01-000002', 'SELLO002', '2026-02-16 10:00:00-06', 'ACEPTADO', '{"tipo":"FACTURA","total":20.40}'),
(3, gen_random_uuid(), 'DTE-01-000003', 'SELLO003', '2026-03-17 11:00:00-06', 'ACEPTADO', '{"tipo":"FACTURA","total":20.40}'),
(4, gen_random_uuid(), 'DTE-01-000004', 'SELLO004', '2026-03-18 12:00:00-06', 'ACEPTADO', '{"tipo":"FACTURA","total":16.10}'),
(5, gen_random_uuid(), 'DTE-01-000005', 'SELLO005', '2026-04-19 13:00:00-06', 'ACEPTADO', '{"tipo":"FACTURA","total":10.45}'),
(6, gen_random_uuid(), 'DTE-01-000006', 'SELLO006', '2026-05-20 14:00:00-06', 'ACEPTADO', '{"tipo":"FACTURA","total":6.80}'),
(7, gen_random_uuid(), 'DTE-01-000007', 'SELLO007', '2026-06-21 15:00:00-06', 'ACEPTADO', '{"tipo":"FACTURA","total":32.17}'),
(8, gen_random_uuid(), 'DTE-01-000008', 'SELLO008', '2026-07-22 16:00:00-06', 'ACEPTADO', '{"tipo":"FACTURA","total":9.00}'),
(9, gen_random_uuid(), 'DTE-01-000009', NULL, '2026-08-23 17:00:00-06', 'RECHAZADO', '{"tipo":"FACTURA","total":21.56}'),
(10, gen_random_uuid(), 'DTE-01-000010', NULL, '2026-11-10 18:00:00-06', 'PENDIENTE', '{"tipo":"FACTURA","total":5.20}');

-- ---------------------------------------------------------------------
-- MANTENIMIENTO
-- Ejecutar SOLO esta linea, despues de cargar los datos de prueba

-- REINDEX TABLE CONCURRENTLY producto;
-- ---------------------------------------------------------------------
