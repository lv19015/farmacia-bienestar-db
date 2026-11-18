-- Cada consulta cumple con un requerimiento de negocio segun el enunciado del proyecto.

-- Busqueda de productos por nombre o principio activo
SELECT id_producto, nombre, principio_activo, marca,
       presentacion, precio_venta
FROM producto
WHERE nombre ILIKE '%para%'
   OR principio_activo ILIKE '%para%';

-- Productos que requieren receta
SELECT id_producto, nombre, principio_activo,
       marca, precio_venta
FROM producto
WHERE requiere_receta = TRUE;

-- Productos con descuento propio y su precio final
SELECT nombre, precio_venta, descuento,
       ROUND(precio_venta * descuento / 100, 2) AS ahorro,
       ROUND(precio_venta * (1 - descuento / 100), 2) AS precio_final
FROM producto
WHERE descuento > 0
ORDER BY descuento DESC;

-- Stock total por producto
SELECT
    p.id_producto,
    p.nombre,
    SUM(l.stock_actual) AS stock_total
FROM producto p
LEFT JOIN lote l ON p.id_producto = l.id_producto
GROUP BY p.id_producto, p.nombre
ORDER BY p.nombre;

-- Lotes por vencer en los proximos 90 dias
SELECT
    p.nombre,
    l.numero_lote,
    l.fecha_caducidad,
    l.stock_actual,
    l.fecha_caducidad - CURRENT_DATE AS dias_restantes
FROM lote l
JOIN producto p ON l.id_producto = p.id_producto
WHERE l.stock_actual > 0
  AND l.fecha_caducidad BETWEEN CURRENT_DATE
                            AND CURRENT_DATE + 90
ORDER BY l.fecha_caducidad;

-- Lotes vencidos que aun tienen existencias
SELECT
    p.nombre,
    l.numero_lote,
    l.fecha_caducidad,
    l.stock_actual
FROM lote l
JOIN producto p ON l.id_producto = p.id_producto
WHERE l.fecha_caducidad < CURRENT_DATE
  AND l.stock_actual > 0
ORDER BY l.fecha_caducidad;

-- Compras y monto comprado por proveedor
SELECT
    pr.nombre AS proveedor,
    COUNT(c.id_compra) AS total_compras,
    SUM(c.total) AS monto_comprado
FROM proveedor pr
LEFT JOIN compra c ON pr.id_proveedor = c.id_proveedor
GROUP BY pr.id_proveedor, pr.nombre
ORDER BY monto_comprado DESC NULLS LAST;

-- Detalle de una compra
SELECT
    c.id_compra,
    pr.nombre AS proveedor,
    p.nombre AS producto,
    dc.cantidad_solicitada,
    dc.precio_unitario,
    dc.cantidad_solicitada * dc.precio_unitario AS subtotal
FROM detalle_compra dc
JOIN compra c ON dc.id_compra = c.id_compra
JOIN proveedor pr ON c.id_proveedor = pr.id_proveedor
JOIN producto p ON dc.id_producto = p.id_producto
WHERE c.id_compra = 1;

-- Reporte de ventas por mes
SELECT
    TO_CHAR(fecha_hora, 'YYYY-MM') AS mes,
    COUNT(*) AS cantidad_ventas,
    SUM(subtotal) AS subtotal,
    SUM(descuento) AS descuentos,
    SUM(total) AS ingresos
FROM venta
GROUP BY TO_CHAR(fecha_hora, 'YYYY-MM')
ORDER BY mes;

-- Ventas por dia
SELECT
    fecha_hora::DATE AS fecha,
    COUNT(*) AS numero_ventas,
    SUM(total) AS ingresos_diarios
FROM venta
GROUP BY fecha_hora::DATE
ORDER BY fecha DESC;

-- Clientes por nivel de fidelizacion
SELECT
    nivel_fidelizacion,
    COUNT(*) AS cantidad_clientes
FROM cliente
GROUP BY nivel_fidelizacion
ORDER BY cantidad_clientes DESC;

-- Pacientes cronicos
SELECT
    c.nombre,
    c.telefono,
    p.fecha_nacimiento,
    p.condicion_cronica,
    p.observaciones
FROM paciente p
JOIN cliente c ON p.id_cliente = c.id_cliente
WHERE p.categoria = 'CRONICO'
ORDER BY c.nombre;

-- Historico de medicamentos dispensados por paciente
SELECT
    c.nombre AS paciente,
    v.fecha_hora::DATE AS fecha,
    p.nombre AS medicamento,
    dv.cantidad,
    r.id_receta,
    r.medico_emisor,
    r.diagnostico
FROM paciente pa
JOIN cliente c ON c.id_cliente = pa.id_cliente
JOIN receta r ON r.id_paciente = pa.id_paciente
JOIN venta v ON v.id_receta = r.id_receta
JOIN detalle_venta dv ON dv.id_venta = v.id_venta
JOIN lote l ON l.id_lote = dv.id_lote
JOIN producto p ON p.id_producto = l.id_producto
ORDER BY c.nombre, v.fecha_hora;

-- Recetas pendientes de validacion
SELECT r.id_receta, c.nombre AS paciente, r.fecha_emision,
       r.medico_emisor, r.clinica, r.estado
FROM receta r
JOIN paciente pa ON pa.id_paciente = r.id_paciente
JOIN cliente c ON c.id_cliente = pa.id_cliente
WHERE r.estado = 'PENDIENTE'
ORDER BY r.fecha_emision;

-- Historial de compras por cliente
SELECT
    c.nombre,
    c.nivel_fidelizacion,
    COUNT(v.id_venta) AS compras,
    COALESCE(SUM(v.total), 0) AS total_gastado,
    c.puntos_acumulados
FROM cliente c
LEFT JOIN venta v ON v.id_cliente = c.id_cliente
GROUP BY c.id_cliente, c.nombre, c.nivel_fidelizacion, c.puntos_acumulados
ORDER BY total_gastado DESC;

-- Movimientos de puntos de un cliente (acumulaciones y canjes)
SELECT c.nombre, h.fecha_movimiento, h.tipo_movimiento,
       h.puntos, h.equivalente_dinero
FROM historial_puntos h
JOIN cliente c ON c.id_cliente = h.id_cliente
WHERE c.id_cliente = 4
ORDER BY h.fecha_movimiento;

-- Promociones aplicadas por venta
SELECT v.id_venta, v.fecha_hora::DATE AS fecha,
       pr.nombre AS promocion, pr.porcentaje, vp.monto_descuento
FROM venta_promocion vp
JOIN venta v ON v.id_venta = vp.id_venta
JOIN promocion pr ON pr.id_promocion = vp.id_promocion
ORDER BY v.id_venta;

-- Promociones vigentes hoy
SELECT nombre, porcentaje, fecha_inicio, fecha_fin, monto_maximo_aplicable
FROM promocion
WHERE CURRENT_DATE BETWEEN fecha_inicio AND fecha_fin
ORDER BY fecha_fin;

-- Facturas electronicas por estado de envio
SELECT f.estado_envio, COUNT(*) AS facturas, SUM(v.total) AS monto
FROM factura_dte f
JOIN venta v ON v.id_venta = f.id_venta
GROUP BY f.estado_envio
ORDER BY facturas DESC;

-- Movimientos registrados en la bitacora por tabla y operacion
SELECT tabla_afectada, operacion, COUNT(*) AS movimientos
FROM bitacora
GROUP BY tabla_afectada, operacion
ORDER BY tabla_afectada, operacion;