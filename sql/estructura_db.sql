-- =====================================================================
-- Farmacia Comunitaria "Bienestar" - Estructura de la base de datos
-- Todas las tablas incluyen fecha_creacion y fecha_actualizacion para
-- poder auditar cada tabla y se mantendran automaticamente con un trigger.
-- =====================================================================
-- Crear la base de datos antes de ejecutar este script:
-- CREATE DATABASE farmacia_bienestar;
-- =====================================================================

-- ---------------------------------------------------------------------
-- Funcion de auditoria: actualiza fecha_actualizacion en cada UPDATE
-- de cada registro en cada tabla 
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_set_fecha_actualizacion()
RETURNS trigger AS $$
BEGIN
    NEW.fecha_actualizacion := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- PROVEEDOR
-- Laboratorios y distribuidoras que surten a la farmacia. Guarda el plazo
-- de entrega (en dias) y las condiciones de pago acordadas, datos que sirven
-- para planificar reposiciones de productos y pagos.
-- ---------------------------------------------------------------------
CREATE TABLE proveedor (
    id_proveedor        INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre              VARCHAR(150) NOT NULL,
    tipo                VARCHAR(20)  NOT NULL
                        CHECK (tipo IN ('LABORATORIO', 'DISTRIBUIDORA')),
    contacto            VARCHAR(150),
    plazo_entrega_dias  SMALLINT     NOT NULL DEFAULT 0
                        CHECK (plazo_entrega_dias >= 0),
    condiciones_pago    VARCHAR(150), -- de contado o a credito, etc
    fecha_creacion      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    fecha_actualizacion TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- PRODUCTO
-- Catalogo de medicamentos y productos que vende la farmacia. La marca
-- permite diferenciar productos con el mismo principio activo. Aqui se
-- registran tambien las condiciones especiales de almacenamiento.
-- descuento: porcentaje de 0 a 100 que se aplicari al precio del producto.
-- ---------------------------------------------------------------------
CREATE TABLE producto (
    id_producto                INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre                     VARCHAR(150)  NOT NULL,
    principio_activo           VARCHAR(150),
    marca                      VARCHAR(100),
    presentacion               VARCHAR(100),
    requiere_receta            BOOLEAN       NOT NULL DEFAULT FALSE,
    condiciones_almacenamiento TEXT,
    precio_venta               NUMERIC(10,2) NOT NULL CHECK (precio_venta >= 0),
    descuento                  NUMERIC(5,2)  NOT NULL DEFAULT 0
                               CHECK (descuento >= 0 AND descuento <= 100),
    fecha_creacion             TIMESTAMPTZ   NOT NULL DEFAULT now(),
    fecha_actualizacion        TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- COMPRA
-- Compra realizaada a un proveedor. Los productos pedidos se detallan
-- en detalle_compra y los lotes que realmente llegan se registran en lote.
-- ---------------------------------------------------------------------
CREATE TABLE compra (
    id_compra           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_proveedor        INTEGER       NOT NULL
                        REFERENCES proveedor (id_proveedor),
    fecha_compra        DATE          NOT NULL DEFAULT CURRENT_DATE,
    total               NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total >= 0),
    estado              VARCHAR(20)   NOT NULL DEFAULT 'PENDIENTE'
                        CHECK (estado IN ('PENDIENTE', 'RECIBIDA', 'CANCELADA')),
    fecha_creacion      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    fecha_actualizacion TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- DETALLE_COMPRA (relacion M:N) tabla intermedia
-- Productos solicitados en cada compra, con la cantidad pedida y el precio
-- unitario acordado en esa compra. Permite detallar compras PENDIENTES antes
-- de que llegue a la farmacia y que no se cambie equivocadamente el stock.
-- ---------------------------------------------------------------------
CREATE TABLE detalle_compra (
    id_compra           INTEGER       NOT NULL
                        REFERENCES compra (id_compra) ON DELETE CASCADE,
    id_producto         INTEGER       NOT NULL
                        REFERENCES producto (id_producto),
    cantidad_solicitada INTEGER       NOT NULL CHECK (cantidad_solicitada > 0),
    precio_unitario     NUMERIC(10,2) NOT NULL CHECK (precio_unitario >= 0),
    fecha_creacion      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    fecha_actualizacion TIMESTAMPTZ   NOT NULL DEFAULT now(),
    PRIMARY KEY (id_compra, id_producto)
);

-- ---------------------------------------------------------------------
-- LOTE: control de inventario y caducidad. Cada lote pertenece a un
-- producto, ingresado mediante una compra y lleva su propia fecha de caducidad
-- y existencias. Las ventas descuentan stock de un lote especifico.
-- El lote se genera una vez que la compra se recibio en farmacia 
-- ya que el estado de la compra puede ser cancelada y asi se evita generar
-- lotes con datos vacios porque nunca se recibio la compra de producto
-- ---------------------------------------------------------------------
CREATE TABLE lote (
    id_lote             INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_producto         INTEGER      NOT NULL REFERENCES producto (id_producto),
    id_compra           INTEGER      NOT NULL REFERENCES compra (id_compra),
    numero_lote         VARCHAR(50)  NOT NULL,
    fecha_fabricacion   DATE,
    fecha_caducidad     DATE         NOT NULL,
    cantidad_recibida   INTEGER      NOT NULL CHECK (cantidad_recibida > 0),
    stock_actual        INTEGER      NOT NULL CHECK (stock_actual >= 0),
    fecha_creacion      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    fecha_actualizacion TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_lote_producto_numero UNIQUE (id_producto, numero_lote),
    CONSTRAINT ck_lote_fechas
        CHECK (fecha_fabricacion IS NULL OR fecha_caducidad > fecha_fabricacion),
    CONSTRAINT ck_lote_stock CHECK (stock_actual <= cantidad_recibida)
);

-- ---------------------------------------------------------------------
-- CLIENTE
-- Persona registrada en el programa de fidelizacion. Acumula puntos y tiene
-- un nivel (BASICO, PLATA, ORO, DIAMANTE).
-- ---------------------------------------------------------------------
CREATE TABLE cliente (
    id_cliente          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre              VARCHAR(150) NOT NULL,
    dui                 VARCHAR(10)  UNIQUE,
    telefono            VARCHAR(20),
    correo              VARCHAR(120),
    nivel_fidelizacion  VARCHAR(20)  NOT NULL DEFAULT 'BASICO'
                        CHECK (nivel_fidelizacion IN ('BASICO', 'PLATA',
                                                      'ORO', 'DIAMANTE')),
    puntos_acumulados   INTEGER      NOT NULL DEFAULT 0
                        CHECK (puntos_acumulados >= 0),
    fecha_creacion      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    fecha_actualizacion TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- PACIENTE
-- Perfil clinico de un cliente. La categoria permite
-- identificar pacientes cronicos para su seguimiento; si es CRONICO debe
-- indicarse la condicion cronica.
-- ---------------------------------------------------------------------
CREATE TABLE paciente (
    id_paciente         INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_cliente          INTEGER      NOT NULL UNIQUE
                        REFERENCES cliente (id_cliente),
    fecha_nacimiento    DATE,
    categoria           VARCHAR(20)  NOT NULL DEFAULT 'GENERAL'
                        CHECK (categoria IN ('GENERAL', 'CRONICO')),
    condicion_cronica   VARCHAR(150),
    observaciones       TEXT,
    fecha_registro      DATE         NOT NULL DEFAULT CURRENT_DATE,
    fecha_creacion      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    fecha_actualizacion TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT ck_paciente_cronico
        CHECK (categoria <> 'CRONICO' OR condicion_cronica IS NOT NULL)
);

-- ---------------------------------------------------------------------
-- RECETA
-- Receta medica de un paciente. Los datos del medico se guardan en la propia
-- receta. El estado controla su validacion y dispensacion
-- vigencia es la fecha hasta la cual la receta es valida.
-- ---------------------------------------------------------------------
CREATE TABLE receta (
    id_receta           INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_paciente         INTEGER      NOT NULL REFERENCES paciente (id_paciente),
    fecha_emision       DATE         NOT NULL,
    vigencia            DATE         NOT NULL,
    medico_emisor       VARCHAR(150) NOT NULL,
    especialidad        VARCHAR(100),
    clinica             VARCHAR(150),
    estado              VARCHAR(20)  NOT NULL DEFAULT 'PENDIENTE'
                        CHECK (estado IN ('PENDIENTE', 'VALIDADA', 'DISPENSADA',
                                          'RECHAZADA', 'VENCIDA')),
    diagnostico         TEXT,
    fecha_creacion      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    fecha_actualizacion TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT ck_receta_vigencia CHECK (vigencia >= fecha_emision)
);

-- ---------------------------------------------------------------------
-- PROMOCION
-- Campaña promocional temporal con porcentaje de descuento, fechas de
-- vigencia y un monto maximo aplicable en el monto de la venta. 
-- Se aplica a las ventas mediante la tabla intermedia venta_promocion.
-- ---------------------------------------------------------------------
CREATE TABLE promocion (
    id_promocion          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre                VARCHAR(150)  NOT NULL,
    porcentaje            NUMERIC(5,2)  NOT NULL
                          CHECK (porcentaje > 0 AND porcentaje <= 100),
    fecha_inicio          DATE          NOT NULL,
    fecha_fin             DATE          NOT NULL,
    monto_maximo_aplicable NUMERIC(10,2) CHECK (monto_maximo_aplicable >= 0),
    fecha_creacion        TIMESTAMPTZ   NOT NULL DEFAULT now(),
    fecha_actualizacion   TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT ck_promocion_fechas CHECK (fecha_fin >= fecha_inicio)
);

-- ---------------------------------------------------------------------
-- VENTA
-- Cliente y receta son opcionales (ventas a clientes sin registro o sin receta)
-- De aqui sale el reporte mensual de ventas, agrupando por fecha_hora.
-- ---------------------------------------------------------------------
CREATE TABLE venta (
    id_venta            INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_cliente          INTEGER       REFERENCES cliente (id_cliente),
    id_receta           INTEGER       REFERENCES receta (id_receta),
    fecha_hora          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    subtotal            NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
    descuento           NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (descuento >= 0),
    total               NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (total >= 0),
    puntos_canjeados    INTEGER       NOT NULL DEFAULT 0
                        CHECK (puntos_canjeados >= 0),
    fecha_creacion      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    fecha_actualizacion TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- DETALLE_VENTA (relacion VENTA - LOTE, M:N)
-- que lote se vendio, cuantas unidades y a que precio.
-- Al ligarse al lote queda la trazabilidad de caducidad y el historico de
-- medicamentos dispensados por paciente.
-- ---------------------------------------------------------------------
CREATE TABLE detalle_venta (
    id_venta            INTEGER       NOT NULL
                        REFERENCES venta (id_venta) ON DELETE CASCADE,
    id_lote             INTEGER       NOT NULL REFERENCES lote (id_lote),
    cantidad            INTEGER       NOT NULL CHECK (cantidad > 0),
    precio_unitario     NUMERIC(10,2) NOT NULL CHECK (precio_unitario >= 0),
    fecha_creacion      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    fecha_actualizacion TIMESTAMPTZ   NOT NULL DEFAULT now(),
    PRIMARY KEY (id_venta, id_lote)
);

-- ---------------------------------------------------------------------
-- VENTA_PROMOCION (relacion M:N)
-- Promociones aplicadas a una venta y el monto descontado por cada una.
-- ---------------------------------------------------------------------
CREATE TABLE venta_promocion (
    id_venta            INTEGER       NOT NULL
                        REFERENCES venta (id_venta) ON DELETE CASCADE,
    id_promocion        INTEGER       NOT NULL
                        REFERENCES promocion (id_promocion),
    monto_descuento     NUMERIC(10,2) NOT NULL CHECK (monto_descuento >= 0),
    fecha_creacion      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    fecha_actualizacion TIMESTAMPTZ   NOT NULL DEFAULT now(),
    PRIMARY KEY (id_venta, id_promocion)
);

-- ---------------------------------------------------------------------
-- HISTORIAL_PUNTOS
-- Bitacora de movimientos de puntos del cliente: acumulaciones por compras y
-- canjes por descuentos, con su equivalente en dinero.
-- ---------------------------------------------------------------------
CREATE TABLE historial_puntos (
    id_historial_puntos INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_cliente          INTEGER       NOT NULL REFERENCES cliente (id_cliente),
    fecha_movimiento    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    tipo_movimiento     VARCHAR(15)   NOT NULL
                        CHECK (tipo_movimiento IN ('ACUMULACION', 'CANJE')),
    puntos              INTEGER       NOT NULL CHECK (puntos > 0),
    equivalente_dinero  NUMERIC(10,2) NOT NULL DEFAULT 0
                        CHECK (equivalente_dinero >= 0),
    fecha_creacion      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    fecha_actualizacion TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- FACTURA_DTE
-- Documento tributario electronico de una venta (relacion 1:1). Guarda los
-- identificadores y el estado de envio para interoperar con el sistema tributario
-- ---------------------------------------------------------------------
CREATE TABLE factura_dte (
    id_factura          INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_venta            INTEGER      NOT NULL UNIQUE REFERENCES venta (id_venta),
    codigo_generacion   UUID         UNIQUE,
    numero_control      VARCHAR(31)  UNIQUE,
    sello_recepcion     VARCHAR(100),
    fecha_emision       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    estado_envio        VARCHAR(20)  NOT NULL DEFAULT 'PENDIENTE'
                        CHECK (estado_envio IN ('PENDIENTE', 'ENVIADO', 'ACEPTADO',
                                                'RECHAZADO', 'ANULADO')),
    json_dte            JSONB,
    fecha_creacion      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    fecha_actualizacion TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- INDICES (llaves foraneas y consultas frecuentes)
-- ---------------------------------------------------------------------
CREATE INDEX idx_compra_proveedor        ON compra (id_proveedor);
CREATE INDEX idx_lote_producto           ON lote (id_producto);
CREATE INDEX idx_lote_compra             ON lote (id_compra);
CREATE INDEX idx_lote_caducidad          ON lote (fecha_caducidad) WHERE stock_actual > 0;
CREATE INDEX idx_receta_paciente         ON receta (id_paciente);
CREATE INDEX idx_venta_cliente           ON venta (id_cliente);
CREATE INDEX idx_venta_receta            ON venta (id_receta);
CREATE INDEX idx_venta_fecha             ON venta (fecha_hora);
CREATE INDEX idx_detalle_venta_lote      ON detalle_venta (id_lote);
CREATE INDEX idx_venta_promocion_promo   ON venta_promocion (id_promocion);
CREATE INDEX idx_historial_puntos_cliente ON historial_puntos (id_cliente, fecha_movimiento);
CREATE INDEX idx_promocion_vigencia      ON promocion (fecha_inicio, fecha_fin);
CREATE INDEX idx_detalle_compra_producto ON detalle_compra (id_producto);

-- ---------------------------------------------------------------------
-- TRIGGERS de auditoria: se crean para toda tabla con fecha_actualizacion
-- ---------------------------------------------------------------------
DO $$
DECLARE
    t TEXT;
BEGIN
    FOR t IN
        SELECT table_name
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND column_name = 'fecha_actualizacion'
    LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_%s_fecha_actualizacion
             BEFORE UPDATE ON %I
             FOR EACH ROW EXECUTE FUNCTION fn_set_fecha_actualizacion()',
            t, t);
    END LOOP;
END $$;
