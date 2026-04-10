--
-- PostgreSQL database dump
--

\restrict j5LWfe8NZyhoIjrUx9mc2pi7pa2bja0peoqgmTAtpK0Z9UBugxbcQrJMKmdCzJK

-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.6

-- Started on 2026-01-21 15:55:22

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 4 (class 2615 OID 2200)
-- Name: public; Type: SCHEMA; Schema: -; Owner: pg_database_owner
--




--
-- TOC entry 257 (class 1255 OID 50304)
-- Name: cancel_transactions_on_order_delete(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.cancel_transactions_on_order_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE financial_transactions
    SET status = 'cancelled'
    WHERE related_order_id = OLD.order_id;

    RETURN OLD;
END;
$$;


ALTER FUNCTION public.cancel_transactions_on_order_delete() OWNER TO postgres;

--
-- TOC entry 256 (class 1255 OID 50302)
-- Name: cancel_transactions_on_purchase_delete(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.cancel_transactions_on_purchase_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE financial_transactions
    SET status = 'cancelled'
    WHERE related_purchase_id = OLD.purchase_id;

    RETURN OLD;
END;
$$;


ALTER FUNCTION public.cancel_transactions_on_purchase_delete() OWNER TO postgres;

--
-- TOC entry 270 (class 1255 OID 33694)
-- Name: create_expense_transaction_on_purchase(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_expense_transaction_on_purchase() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO financial_transactions (
        type, note, amount, transaction_date, employee_id, original_document_number,
        supplier_id, payer_receiver_name, payer_receiver_phone, payer_receiver_address,
        related_purchase_id, payment_method_id, status, created_at
    )
    VALUES (
        'expense',
        'Chi tiền nhập hàng ' || NEW.purchase_number,
        NEW.total_amount,
        NEW.purchase_date,
        NEW.employee_id,
        'DOC-' || NEW.purchase_number,
        NULL, -- Không có supplier_id trong purchases
        NULL, -- Không có thông tin nhà cung cấp
        NULL, -- Không có số điện thoại nhà cung cấp
        NULL, -- Không có địa chỉ nhà cung cấp
        NEW.purchase_id,
        NEW.payment_method_id,
        NEW.status,
        CURRENT_TIMESTAMP
    );

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.create_expense_transaction_on_purchase() OWNER TO postgres;

--
-- TOC entry 258 (class 1255 OID 33465)
-- Name: create_income_transaction_on_order(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.create_income_transaction_on_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO financial_transactions (
        type, note, amount, transaction_date, employee_id, original_document_number,
        customer_id, payer_receiver_name, payer_receiver_phone, payer_receiver_address,
        related_order_id, payment_method_id, status, created_at
    )
    VALUES (
        'income',
        'Thu tiền từ hóa đơn ' || NEW.order_number,
        NEW.total_amount,
        NEW.order_date,
        NEW.employee_id,
        'DOC-' || NEW.order_number,
        NEW.customer_id,
        (SELECT name FROM customers WHERE customer_id = NEW.customer_id),
        (SELECT phone FROM customers WHERE customer_id = NEW.customer_id),
        (SELECT address FROM customers WHERE customer_id = NEW.customer_id),
        NEW.order_id,
        NEW.payment_method_id,
        NEW.status,
        CURRENT_TIMESTAMP
    );

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.create_income_transaction_on_order() OWNER TO postgres;

--
-- TOC entry 254 (class 1255 OID 50298)
-- Name: sync_transaction_status_from_order(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sync_transaction_status_from_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Chỉ update nếu status thay đổi
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        UPDATE financial_transactions
        SET status = NEW.status
        WHERE related_order_id = NEW.order_id;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.sync_transaction_status_from_order() OWNER TO postgres;

--
-- TOC entry 255 (class 1255 OID 50300)
-- Name: sync_transaction_status_from_purchase(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sync_transaction_status_from_purchase() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Chỉ update nếu status thay đổi
    IF NEW.status IS DISTINCT FROM OLD.status THEN
        UPDATE financial_transactions
        SET status = NEW.status
        WHERE related_purchase_id = NEW.purchase_id;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.sync_transaction_status_from_purchase() OWNER TO postgres;

--
-- TOC entry 271 (class 1255 OID 41986)
-- Name: update_stock_on_order(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_stock_on_order() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    p RECORD;
    existing_alert RECORD;
BEGIN
    -- Cập nhật tồn kho
    UPDATE products
    SET stock = stock - NEW.quantity
    WHERE product_id = NEW.product_id;

    SELECT * INTO p FROM products WHERE product_id = NEW.product_id;

    -- Alert đang mở
    SELECT * INTO existing_alert
    FROM alerts
    WHERE related_product_id = NEW.product_id
      AND is_resolved = FALSE
    LIMIT 1;

    -- CASE 1: LOW STOCK (bán khiến stock thấp)
    IF p.stock < p.minimum_inventory THEN
    
        IF FOUND AND existing_alert.type = 'low_stock' THEN
            -- Update alert nếu đúng loại
            UPDATE alerts
            SET message = 'Sản phẩm ' || p.name ||
                          ' sắp hết hàng (còn ' || p.stock ||
                          ', dưới ngưỡng ' || p.minimum_inventory || ')',
                updated_at = CURRENT_TIMESTAMP
            WHERE alert_id = existing_alert.alert_id;

        ELSIF NOT FOUND THEN
            -- Tạo alert mới nếu chưa có alert mở
            INSERT INTO alerts (type, message, related_product_id, severity, is_resolved, created_at, updated_at)
            VALUES (
                'low_stock',
                'Sản phẩm ' || p.name ||
                ' sắp hết hàng (còn ' || p.stock ||
                ', dưới ngưỡng ' || p.minimum_inventory || ')',
                NEW.product_id,
                'medium',
                FALSE,
                CURRENT_TIMESTAMP,
                CURRENT_TIMESTAMP
            );
        END IF;

    -- CASE 2: Stock vẫn cao hơn MIN nhưng có alert 'low_stock' → resolve
    ELSIF FOUND AND existing_alert.type = 'low_stock' AND p.stock >= p.minimum_inventory THEN
        UPDATE alerts
        SET is_resolved = TRUE,
            updated_at = CURRENT_TIMESTAMP
        WHERE alert_id = existing_alert.alert_id;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_stock_on_order() OWNER TO postgres;

--
-- TOC entry 272 (class 1255 OID 50292)
-- Name: update_stock_on_purchase(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.update_stock_on_purchase() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    p RECORD;
    existing_alert RECORD;
BEGIN
    UPDATE products
    SET stock = stock + NEW.quantity
    WHERE product_id = NEW.product_id;

    SELECT * INTO p FROM products WHERE product_id = NEW.product_id;

    SELECT * INTO existing_alert
    FROM alerts
    WHERE related_product_id = NEW.product_id
      AND is_resolved = FALSE
	  AND type IN ('low_stock','over_stock')
    LIMIT 1;

    -- CASE 1: OVER STOCK
    IF p.stock > p.maximum_inventory THEN

        IF FOUND AND existing_alert.type = 'over_stock' THEN
            UPDATE alerts
            SET message = 'Sản phẩm ' || p.name ||
                          ' vượt tồn kho tối đa (còn ' || p.stock ||
                          ', trên ngưỡng ' || p.maximum_inventory || ')',
                updated_at = CURRENT_TIMESTAMP
            WHERE alert_id = existing_alert.alert_id;

        ELSIF NOT FOUND THEN
            INSERT INTO alerts (type, message, related_product_id, severity, is_resolved, created_at, updated_at)
            VALUES (
                'over_stock',
                'Sản phẩm ' || p.name ||
                ' vượt tồn kho tối đa (còn ' || p.stock ||
                ', trên ngưỡng ' || p.maximum_inventory || ')',
                NEW.product_id,
                'low',
                FALSE,
                CURRENT_TIMESTAMP,
                CURRENT_TIMESTAMP
            );
        END IF;

    -- CASE 2: Stock giảm về mức OK → resolve over_stock alert
    ELSIF FOUND AND existing_alert.type = 'over_stock' AND p.stock <= p.maximum_inventory THEN
        UPDATE alerts
        SET is_resolved = TRUE,
            updated_at = CURRENT_TIMESTAMP
        WHERE alert_id = existing_alert.alert_id;
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.update_stock_on_purchase() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 250 (class 1259 OID 33438)
-- Name: alerts; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.alerts (
    alert_id integer NOT NULL,
    type character varying(50) NOT NULL,
    message text NOT NULL,
    related_product_id integer,
    related_prediction_id integer,
    severity character varying(20) NOT NULL,
    is_resolved boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT alerts_severity_check CHECK (((severity)::text = ANY ((ARRAY['low'::character varying, 'medium'::character varying, 'high'::character varying])::text[]))),
    CONSTRAINT alerts_type_check CHECK (((type)::text = ANY ((ARRAY['low_stock'::character varying, 'over_stock'::character varying, 'promotion_expired'::character varying, 'ai_prediction'::character varying])::text[])))
);


ALTER TABLE public.alerts OWNER TO postgres;

--
-- TOC entry 249 (class 1259 OID 33437)
-- Name: alerts_alert_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.alerts_alert_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.alerts_alert_id_seq OWNER TO postgres;

--
-- TOC entry 5083 (class 0 OID 0)
-- Dependencies: 249
-- Name: alerts_alert_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.alerts_alert_id_seq OWNED BY public.alerts.alert_id;


--
-- TOC entry 220 (class 1259 OID 33086)
-- Name: categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.categories (
    category_id integer NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.categories OWNER TO postgres;

--
-- TOC entry 219 (class 1259 OID 33085)
-- Name: categories_category_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.categories_category_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.categories_category_id_seq OWNER TO postgres;

--
-- TOC entry 5084 (class 0 OID 0)
-- Dependencies: 219
-- Name: categories_category_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.categories_category_id_seq OWNED BY public.categories.category_id;


--
-- TOC entry 228 (class 1259 OID 33147)
-- Name: customers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.customers (
    customer_id integer NOT NULL,
    name character varying(255) NOT NULL,
    phone character varying(20),
    email character varying(100),
    gender character varying(10),
    birthday date,
    address text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.customers OWNER TO postgres;

--
-- TOC entry 227 (class 1259 OID 33146)
-- Name: customers_customer_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.customers_customer_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.customers_customer_id_seq OWNER TO postgres;

--
-- TOC entry 5085 (class 0 OID 0)
-- Dependencies: 227
-- Name: customers_customer_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.customers_customer_id_seq OWNED BY public.customers.customer_id;


--
-- TOC entry 230 (class 1259 OID 33158)
-- Name: employees; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.employees (
    employee_id integer NOT NULL,
    name character varying(255) NOT NULL,
    username character varying(100) NOT NULL,
    password_hash character varying(255) NOT NULL,
    role character varying(50) NOT NULL,
    avatar character varying(255),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT employees_role_check CHECK (((role)::text = ANY ((ARRAY['admin'::character varying, 'warehouse'::character varying, 'cashier'::character varying])::text[])))
);


ALTER TABLE public.employees OWNER TO postgres;

--
-- TOC entry 229 (class 1259 OID 33157)
-- Name: employees_employee_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.employees_employee_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.employees_employee_id_seq OWNER TO postgres;

--
-- TOC entry 5086 (class 0 OID 0)
-- Dependencies: 229
-- Name: employees_employee_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.employees_employee_id_seq OWNED BY public.employees.employee_id;


--
-- TOC entry 246 (class 1259 OID 33358)
-- Name: financial_transactions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.financial_transactions (
    transaction_id integer NOT NULL,
    type character varying(20) NOT NULL,
    note text,
    amount numeric(10,2) NOT NULL,
    transaction_date date NOT NULL,
    employee_id integer NOT NULL,
    customer_id integer,
    supplier_id integer,
    payer_receiver_name character varying(100),
    payer_receiver_phone character varying(20),
    payer_receiver_address text,
    related_order_id integer,
    related_purchase_id integer,
    payment_method_id integer,
    status character varying(20) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    original_document_number character varying(100),
    CONSTRAINT financial_transactions_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'completed'::character varying, 'cancelled'::character varying])::text[]))),
    CONSTRAINT financial_transactions_type_check CHECK (((type)::text = ANY ((ARRAY['income'::character varying, 'expense'::character varying])::text[])))
);


ALTER TABLE public.financial_transactions OWNER TO postgres;

--
-- TOC entry 245 (class 1259 OID 33357)
-- Name: financial_transactions_transaction_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.financial_transactions_transaction_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.financial_transactions_transaction_id_seq OWNER TO postgres;

--
-- TOC entry 5087 (class 0 OID 0)
-- Dependencies: 245
-- Name: financial_transactions_transaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.financial_transactions_transaction_id_seq OWNED BY public.financial_transactions.transaction_id;


--
-- TOC entry 240 (class 1259 OID 33267)
-- Name: order_details; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.order_details (
    order_detail_id integer NOT NULL,
    order_id integer,
    product_id integer,
    quantity integer NOT NULL,
    price numeric(10,2) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT order_details_quantity_check CHECK ((quantity >= 0))
);


ALTER TABLE public.order_details OWNER TO postgres;

--
-- TOC entry 239 (class 1259 OID 33266)
-- Name: order_details_order_detail_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.order_details_order_detail_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.order_details_order_detail_id_seq OWNER TO postgres;

--
-- TOC entry 5088 (class 0 OID 0)
-- Dependencies: 239
-- Name: order_details_order_detail_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.order_details_order_detail_id_seq OWNED BY public.order_details.order_detail_id;


--
-- TOC entry 238 (class 1259 OID 33232)
-- Name: orders; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.orders (
    order_id integer NOT NULL,
    order_number character varying(100) NOT NULL,
    customer_id integer,
    employee_id integer,
    order_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    total_amount numeric(10,2) DEFAULT 0 NOT NULL,
    payment_method_id integer,
    status character varying(50) NOT NULL,
    promotion_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT orders_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'completed'::character varying, 'cancelled'::character varying])::text[])))
);


ALTER TABLE public.orders OWNER TO postgres;

--
-- TOC entry 237 (class 1259 OID 33231)
-- Name: orders_order_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.orders_order_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.orders_order_id_seq OWNER TO postgres;

--
-- TOC entry 5089 (class 0 OID 0)
-- Dependencies: 237
-- Name: orders_order_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.orders_order_id_seq OWNED BY public.orders.order_id;


--
-- TOC entry 218 (class 1259 OID 33073)
-- Name: payment_methods; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.payment_methods (
    payment_method_id integer NOT NULL,
    code character varying(50) NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.payment_methods OWNER TO postgres;

--
-- TOC entry 217 (class 1259 OID 33072)
-- Name: payment_methods_payment_method_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.payment_methods_payment_method_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.payment_methods_payment_method_id_seq OWNER TO postgres;

--
-- TOC entry 5090 (class 0 OID 0)
-- Dependencies: 217
-- Name: payment_methods_payment_method_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.payment_methods_payment_method_id_seq OWNED BY public.payment_methods.payment_method_id;


--
-- TOC entry 252 (class 1259 OID 50192)
-- Name: payments; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.payments (
    payment_id integer NOT NULL,
    context_type character varying(20) NOT NULL,
    order_number character varying(100),
    purchase_number character varying(100),
    pay_code bigint NOT NULL,
    provider character varying(50) DEFAULT 'payos'::character varying NOT NULL,
    reference character varying(255),
    amount numeric(12,2) NOT NULL,
    status character varying(20) NOT NULL,
    checkout_url text,
    data jsonb,
    created_by integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    qr_base64 text,
    CONSTRAINT payments_context_type_check CHECK (((context_type)::text = ANY ((ARRAY['order'::character varying, 'purchase'::character varying])::text[]))),
    CONSTRAINT payments_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'completed'::character varying, 'cancelled'::character varying])::text[])))
);


ALTER TABLE public.payments OWNER TO postgres;

--
-- TOC entry 251 (class 1259 OID 50191)
-- Name: payments_payment_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.payments_payment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.payments_payment_id_seq OWNER TO postgres;

--
-- TOC entry 5091 (class 0 OID 0)
-- Dependencies: 251
-- Name: payments_payment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.payments_payment_id_seq OWNED BY public.payments.payment_id;


--
-- TOC entry 248 (class 1259 OID 33402)
-- Name: predictions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.predictions (
    prediction_id integer NOT NULL,
    product_id integer,
    predicted_month character varying(7) NOT NULL,
    predicted_quantity integer NOT NULL,
    confidence numeric(3,2) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT predictions_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric))),
    CONSTRAINT predictions_predicted_quantity_check CHECK ((predicted_quantity >= 0))
);


ALTER TABLE public.predictions OWNER TO postgres;

--
-- TOC entry 247 (class 1259 OID 33401)
-- Name: predictions_prediction_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.predictions_prediction_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.predictions_prediction_id_seq OWNER TO postgres;

--
-- TOC entry 5092 (class 0 OID 0)
-- Dependencies: 247
-- Name: predictions_prediction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.predictions_prediction_id_seq OWNED BY public.predictions.prediction_id;


--
-- TOC entry 226 (class 1259 OID 33116)
-- Name: products; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.products (
    product_id integer NOT NULL,
    name character varying(255) NOT NULL,
    barcode character varying(100) NOT NULL,
    description text,
    price numeric(10,2) NOT NULL,
    cost_price numeric(10,2) NOT NULL,
    stock integer DEFAULT 0,
    image_url character varying(255),
    minimum_inventory integer DEFAULT 10,
    maximum_inventory integer DEFAULT 100,
    category_id integer,
    unit_id integer,
    supplier_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    is_active boolean DEFAULT true
);


ALTER TABLE public.products OWNER TO postgres;

--
-- TOC entry 225 (class 1259 OID 33115)
-- Name: products_product_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.products_product_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.products_product_id_seq OWNER TO postgres;

--
-- TOC entry 5093 (class 0 OID 0)
-- Dependencies: 225
-- Name: products_product_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.products_product_id_seq OWNED BY public.products.product_id;


--
-- TOC entry 234 (class 1259 OID 33194)
-- Name: promotion_categories; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.promotion_categories (
    promotion_category_id integer NOT NULL,
    promotion_id integer,
    category_id integer
);


ALTER TABLE public.promotion_categories OWNER TO postgres;

--
-- TOC entry 233 (class 1259 OID 33193)
-- Name: promotion_categories_promotion_category_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.promotion_categories_promotion_category_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.promotion_categories_promotion_category_id_seq OWNER TO postgres;

--
-- TOC entry 5094 (class 0 OID 0)
-- Dependencies: 233
-- Name: promotion_categories_promotion_category_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.promotion_categories_promotion_category_id_seq OWNED BY public.promotion_categories.promotion_category_id;


--
-- TOC entry 236 (class 1259 OID 33213)
-- Name: promotion_products; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.promotion_products (
    promotion_product_id integer NOT NULL,
    promotion_id integer,
    product_id integer
);


ALTER TABLE public.promotion_products OWNER TO postgres;

--
-- TOC entry 235 (class 1259 OID 33212)
-- Name: promotion_products_promotion_product_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.promotion_products_promotion_product_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.promotion_products_promotion_product_id_seq OWNER TO postgres;

--
-- TOC entry 5095 (class 0 OID 0)
-- Dependencies: 235
-- Name: promotion_products_promotion_product_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.promotion_products_promotion_product_id_seq OWNED BY public.promotion_products.promotion_product_id;


--
-- TOC entry 232 (class 1259 OID 33171)
-- Name: promotions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.promotions (
    promotion_id integer NOT NULL,
    name character varying(255) NOT NULL,
    discount_percent numeric(5,2) NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT promotions_discount_percent_check CHECK (((discount_percent >= (0)::numeric) AND (discount_percent <= (100)::numeric)))
);


ALTER TABLE public.promotions OWNER TO postgres;

--
-- TOC entry 231 (class 1259 OID 33170)
-- Name: promotions_promotion_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.promotions_promotion_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.promotions_promotion_id_seq OWNER TO postgres;

--
-- TOC entry 5096 (class 0 OID 0)
-- Dependencies: 231
-- Name: promotions_promotion_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.promotions_promotion_id_seq OWNED BY public.promotions.promotion_id;


--
-- TOC entry 244 (class 1259 OID 33313)
-- Name: purchase_details; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.purchase_details (
    purchase_detail_id integer NOT NULL,
    purchase_id integer,
    product_id integer,
    quantity integer NOT NULL,
    unit_cost numeric(10,2) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT purchase_details_quantity_check CHECK ((quantity >= 0))
);


ALTER TABLE public.purchase_details OWNER TO postgres;

--
-- TOC entry 243 (class 1259 OID 33312)
-- Name: purchase_details_purchase_detail_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.purchase_details_purchase_detail_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.purchase_details_purchase_detail_id_seq OWNER TO postgres;

--
-- TOC entry 5097 (class 0 OID 0)
-- Dependencies: 243
-- Name: purchase_details_purchase_detail_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.purchase_details_purchase_detail_id_seq OWNED BY public.purchase_details.purchase_detail_id;


--
-- TOC entry 242 (class 1259 OID 33288)
-- Name: purchases; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.purchases (
    purchase_id integer NOT NULL,
    purchase_number character varying(100) NOT NULL,
    employee_id integer,
    purchase_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    total_amount numeric(10,2) DEFAULT 0 NOT NULL,
    amount_paid numeric(10,2) DEFAULT 0 NOT NULL,
    payment_method_id integer,
    status character varying(50) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT purchases_status_check CHECK (((status)::text = ANY ((ARRAY['pending'::character varying, 'completed'::character varying, 'concelled'::character varying])::text[])))
);


ALTER TABLE public.purchases OWNER TO postgres;

--
-- TOC entry 241 (class 1259 OID 33287)
-- Name: purchases_purchase_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.purchases_purchase_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.purchases_purchase_id_seq OWNER TO postgres;

--
-- TOC entry 5098 (class 0 OID 0)
-- Dependencies: 241
-- Name: purchases_purchase_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.purchases_purchase_id_seq OWNED BY public.purchases.purchase_id;


--
-- TOC entry 224 (class 1259 OID 33106)
-- Name: suppliers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.suppliers (
    supplier_id integer NOT NULL,
    name character varying(255) NOT NULL,
    phone character varying(20),
    email character varying(100),
    address text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.suppliers OWNER TO postgres;

--
-- TOC entry 223 (class 1259 OID 33105)
-- Name: suppliers_supplier_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.suppliers_supplier_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.suppliers_supplier_id_seq OWNER TO postgres;

--
-- TOC entry 5099 (class 0 OID 0)
-- Dependencies: 223
-- Name: suppliers_supplier_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.suppliers_supplier_id_seq OWNED BY public.suppliers.supplier_id;


--
-- TOC entry 222 (class 1259 OID 33096)
-- Name: units; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.units (
    unit_id integer NOT NULL,
    name character varying(255) NOT NULL,
    description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.units OWNER TO postgres;

--
-- TOC entry 221 (class 1259 OID 33095)
-- Name: units_unit_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.units_unit_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.units_unit_id_seq OWNER TO postgres;

--
-- TOC entry 5100 (class 0 OID 0)
-- Dependencies: 221
-- Name: units_unit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.units_unit_id_seq OWNED BY public.units.unit_id;


--
-- TOC entry 253 (class 1259 OID 50261)
-- Name: v_ai_stock_features; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_ai_stock_features AS
 WITH sales AS (
         SELECT od.product_id,
            (date_trunc('month'::text, o.order_date))::date AS month_date,
            sum(od.quantity) AS qty_sold
           FROM (public.order_details od
             JOIN public.orders o ON ((o.order_id = od.order_id)))
          WHERE ((o.status)::text = 'completed'::text)
          GROUP BY od.product_id, (date_trunc('month'::text, o.order_date))
        ), purchases AS (
         SELECT pd.product_id,
            (date_trunc('month'::text, p.purchase_date))::date AS month_date,
            sum(pd.quantity) AS qty_purchased
           FROM (public.purchase_details pd
             JOIN public.purchases p ON ((p.purchase_id = pd.purchase_id)))
          WHERE ((p.status)::text = 'completed'::text)
          GROUP BY pd.product_id, (date_trunc('month'::text, p.purchase_date))
        )
 SELECT pr.product_id,
    pr.name AS product_name,
    COALESCE(s.month_date, pu.month_date) AS month_date,
    (EXTRACT(month FROM COALESCE(s.month_date, pu.month_date)))::integer AS month_num,
    COALESCE(s.qty_sold, (0)::bigint) AS qty_sold,
    COALESCE(pu.qty_purchased, (0)::bigint) AS qty_purchased,
    pr.stock,
    pr.minimum_inventory
   FROM ((public.products pr
     LEFT JOIN sales s ON ((s.product_id = pr.product_id)))
     LEFT JOIN purchases pu ON ((pu.product_id = pr.product_id)))
  ORDER BY pr.product_id, COALESCE(s.month_date, pu.month_date);


ALTER VIEW public.v_ai_stock_features OWNER TO postgres;

--
-- TOC entry 4781 (class 2604 OID 33441)
-- Name: alerts alert_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.alerts ALTER COLUMN alert_id SET DEFAULT nextval('public.alerts_alert_id_seq'::regclass);


--
-- TOC entry 4741 (class 2604 OID 33089)
-- Name: categories category_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories ALTER COLUMN category_id SET DEFAULT nextval('public.categories_category_id_seq'::regclass);


--
-- TOC entry 4754 (class 2604 OID 33150)
-- Name: customers customer_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers ALTER COLUMN customer_id SET DEFAULT nextval('public.customers_customer_id_seq'::regclass);


--
-- TOC entry 4756 (class 2604 OID 33161)
-- Name: employees employee_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employees ALTER COLUMN employee_id SET DEFAULT nextval('public.employees_employee_id_seq'::regclass);


--
-- TOC entry 4777 (class 2604 OID 33361)
-- Name: financial_transactions transaction_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.financial_transactions ALTER COLUMN transaction_id SET DEFAULT nextval('public.financial_transactions_transaction_id_seq'::regclass);


--
-- TOC entry 4767 (class 2604 OID 33270)
-- Name: order_details order_detail_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_details ALTER COLUMN order_detail_id SET DEFAULT nextval('public.order_details_order_detail_id_seq'::regclass);


--
-- TOC entry 4762 (class 2604 OID 33235)
-- Name: orders order_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders ALTER COLUMN order_id SET DEFAULT nextval('public.orders_order_id_seq'::regclass);


--
-- TOC entry 4738 (class 2604 OID 33076)
-- Name: payment_methods payment_method_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payment_methods ALTER COLUMN payment_method_id SET DEFAULT nextval('public.payment_methods_payment_method_id_seq'::regclass);


--
-- TOC entry 4785 (class 2604 OID 50195)
-- Name: payments payment_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payments ALTER COLUMN payment_id SET DEFAULT nextval('public.payments_payment_id_seq'::regclass);


--
-- TOC entry 4779 (class 2604 OID 33405)
-- Name: predictions prediction_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.predictions ALTER COLUMN prediction_id SET DEFAULT nextval('public.predictions_prediction_id_seq'::regclass);


--
-- TOC entry 4747 (class 2604 OID 33119)
-- Name: products product_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products ALTER COLUMN product_id SET DEFAULT nextval('public.products_product_id_seq'::regclass);


--
-- TOC entry 4760 (class 2604 OID 33197)
-- Name: promotion_categories promotion_category_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotion_categories ALTER COLUMN promotion_category_id SET DEFAULT nextval('public.promotion_categories_promotion_category_id_seq'::regclass);


--
-- TOC entry 4761 (class 2604 OID 33216)
-- Name: promotion_products promotion_product_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotion_products ALTER COLUMN promotion_product_id SET DEFAULT nextval('public.promotion_products_promotion_product_id_seq'::regclass);


--
-- TOC entry 4758 (class 2604 OID 33174)
-- Name: promotions promotion_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotions ALTER COLUMN promotion_id SET DEFAULT nextval('public.promotions_promotion_id_seq'::regclass);


--
-- TOC entry 4775 (class 2604 OID 33316)
-- Name: purchase_details purchase_detail_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_details ALTER COLUMN purchase_detail_id SET DEFAULT nextval('public.purchase_details_purchase_detail_id_seq'::regclass);


--
-- TOC entry 4769 (class 2604 OID 33291)
-- Name: purchases purchase_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchases ALTER COLUMN purchase_id SET DEFAULT nextval('public.purchases_purchase_id_seq'::regclass);


--
-- TOC entry 4745 (class 2604 OID 33109)
-- Name: suppliers supplier_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.suppliers ALTER COLUMN supplier_id SET DEFAULT nextval('public.suppliers_supplier_id_seq'::regclass);


--
-- TOC entry 4743 (class 2604 OID 33099)
-- Name: units unit_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.units ALTER COLUMN unit_id SET DEFAULT nextval('public.units_unit_id_seq'::regclass);


--
-- TOC entry 5074 (class 0 OID 33438)
-- Dependencies: 250
-- Data for Name: alerts; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.alerts (alert_id, type, message, related_product_id, related_prediction_id, severity, is_resolved, created_at, updated_at) FROM stdin;
5	over_stock	Sản phẩm "Máy cắt lông thú cưng" vượt tồn kho tối đa (còn 25, trên ngưỡng 20)	20	\N	low	t	2025-12-03 03:31:24.272375	2025-12-03 03:31:24.272375
6	low_stock	Sản phẩm "Máy cắt lông thú cưng" sắp hết hàng (còn 0, dưới ngưỡng 5)	20	\N	medium	t	2025-12-03 04:04:02.48491	2025-12-03 04:06:57.370909
7	low_stock	Sản phẩm "Hihi" sắp hết hàng (còn 1, dưới ngưỡng 10)	21	\N	medium	t	2025-12-03 14:52:24.856733	2025-12-03 16:03:53.963211
8	low_stock	Sản phẩm "Hihi" sắp hết hàng (còn 1, dưới ngưỡng 10)	21	\N	medium	t	2025-12-03 16:06:38.684284	2025-12-03 16:25:24.407004
14	promotion_expired	Khuyến mãi Sale vắc-xin phòng dịch đã hết hạn vào 2025-11-30	\N	\N	low	t	2025-12-07 18:39:14.298006	2025-12-07 18:39:14.298006
13	promotion_expired	Khuyến mãi Giảm giá thuốc mùa hè đã hết hạn vào 2025-08-31	\N	\N	low	t	2025-12-07 18:38:59.825421	2025-12-07 18:38:59.825421
16	promotion_expired	Khuyến mãi Giảm giá thuốc mùa hè đã hết hạn vào 2025-08-31	\N	\N	low	t	2025-12-08 08:06:32.01888	2025-12-08 08:06:32.01888
15	promotion_expired	Khuyến mãi Giảm giá thuốc mùa hè đã hết hạn vào 2025-08-31	\N	\N	low	t	2025-12-08 08:06:06.857838	2025-12-08 08:06:06.857838
18	promotion_expired	Khuyến mãi Giảm giá thuốc mùa hè đã hết hạn vào 2025-08-31	\N	\N	low	t	2025-12-12 03:41:48.482161	2025-12-12 03:41:48.482161
17	promotion_expired	Khuyến mãi Giảm giá thuốc mùa hè đã hết hạn vào 2025-08-31	\N	\N	low	t	2025-12-12 03:41:39.869484	2025-12-12 03:41:39.869484
22	low_stock	Sản phẩm "Thuốc nhỏ mắt cho bé Mèo" sắp hết hàng (còn 2, dưới ngưỡng 10)	26	\N	medium	t	2025-12-14 12:02:42.326052	2025-12-14 12:09:56.478317
20	over_stock	Sản phẩm "Thuốc nhỏ mắt cho mèo" vượt tồn kho tối đa (còn 117, trên ngưỡng 100)	25	\N	low	t	2025-12-12 06:37:03.214382	2025-12-14 11:20:51.948048
24	over_stock	Sản phẩm Thuốc nhỏ mắt cho bé Mèo vượt tồn kho tối đa (còn 99, trên ngưỡng 50)	26	\N	low	t	2025-12-14 16:50:28.152258	2025-12-14 16:53:17.308348
25	over_stock	Sản phẩm Thuốc nhỏ mắt cho bé Mèo vượt tồn kho tối đa (còn 57, trên ngưỡng 50)	26	\N	low	t	2025-12-15 06:09:46.153096	2025-12-15 09:33:56.611202
26	over_stock	Sản phẩm "Thuốc nhỏ mắt cho bé Mèo" vượt tồn kho tối đa (còn 53, trên ngưỡng 50)	26	\N	low	t	2025-12-15 10:24:26.891381	2025-12-15 10:25:12.187935
\.


--
-- TOC entry 5044 (class 0 OID 33086)
-- Dependencies: 220
-- Data for Name: categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.categories (category_id, name, description, created_at) FROM stdin;
2	Vật tư y tế	Dụng cụ y tế như băng gạc, kim tiêm, dụng cụ phẫu thuật	2025-10-03 13:29:14.460139
3	Thức ăn	Thức ăn dinh dưỡng cho chó, mèo và các loài khác	2025-10-03 13:29:14.460139
4	Dịch vụ	Các dịch vụ khám chữa bệnh, tiêm chủng	2025-10-03 13:29:14.460139
5	Phụ kiện	Phụ kiện chăm sóc như vòng cổ, lồng vận chuyển	2025-10-03 13:29:14.460139
6	Vắc-xin	Vắc-xin phòng bệnh cho thú cưng	2025-10-03 13:29:14.460139
7	Thực phẩm bổ sung	Vitamin và thực phẩm bổ sung sức khỏe	2025-10-03 13:29:14.460139
8	Sản phẩm vệ sinh	Xà phòng, khăn lau, sản phẩm khử mùi	2025-10-03 13:29:14.460139
9	Thiết bị y tế	Máy đo huyết áp, máy siêu âm cho thú y	2025-10-03 13:29:14.460139
10	Khác	Các sản phẩm khác không thuộc danh mục trên	2025-10-03 13:29:14.460139
11	Hihi	da	2025-10-29 22:15:03.083692
13	Tú Đặng	\N	2025-10-29 22:16:19.766347
14	Thuốc kháng sinh Amoxicillin cho chó	\N	2025-10-29 22:23:25.409404
1	Thuốc	\N	2025-10-03 13:29:14.460139
\.


--
-- TOC entry 5052 (class 0 OID 33147)
-- Dependencies: 228
-- Data for Name: customers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.customers (customer_id, name, phone, email, gender, birthday, address, created_at) FROM stdin;
1	Nguyễn Văn A	0909876543	vana@gmail.com	Nam	1990-05-15	1 Đường ABC, Quận 1, TP.HCM	2025-10-03 13:29:14.460139
2	Trần Thị B	0918765432	thib@gmail.com	Nữ	1985-03-20	2 Đường DEF, Quận 2, TP.HCM	2025-10-03 13:29:14.460139
3	Lê Văn C	0927654321	vanc@gmail.com	Nam	1995-07-10	3 Đường GHI, Quận 3, TP.HCM	2025-10-03 13:29:14.460139
4	Phạm Thị D	0936543210	thid@gmail.com	Nữ	2000-01-25	4 Đường JKL, Quận 4, TP.HCM	2025-10-03 13:29:14.460139
5	Hoàng Văn E	0945432109	vane@gmail.com	Nam	1988-11-30	5 Đường MNO, Quận 5, TP.HCM	2025-10-03 13:29:14.460139
6	Vũ Thị F	0954321098	thif@gmail.com	Nữ	1992-09-05	6 Đường PQR, Quận 6, TP.HCM	2025-10-03 13:29:14.460139
7	Đặng Văn G	0963210987	vang@gmail.com	Nam	1998-04-12	7 Đường STU, Quận 7, TP.HCM	2025-10-03 13:29:14.460139
8	Bùi Thị H	0972109876	thih@gmail.com	Nữ	1983-02-18	8 Đường VWX, Quận 8, TP.HCM	2025-10-03 13:29:14.460139
9	Lý Văn I	0981098765	vani@gmail.com	Nam	1997-06-22	9 Đường YZA, Quận 9, TP.HCM	2025-10-03 13:29:14.460139
10	Hồ Thị J	0990987654	thij@gmail.com	Nữ	1991-08-28	10 Đường BCD, Quận 10, TP.HCM	2025-10-03 13:29:14.460139
11	Trương Văn K	0909876542	vank@gmail.com	Nam	1987-10-14	11 Đường EFG, Quận 11, TP.HCM	2025-10-03 13:29:14.460139
12	Dương Thị L	0918765431	thil@gmail.com	Nữ	1993-12-09	12 Đường HIJ, Quận 12, TP.HCM	2025-10-03 13:29:14.460139
13	Mai Văn M	0927654320	vanm@gmail.com	Nam	1996-01-03	13 Đường KLM, Quận Tân Bình, TP.HCM	2025-10-03 13:29:14.460139
14	Ngô Thị N	0936543209	thin@gmail.com	Nữ	1989-03-17	14 Đường NOP, Quận Bình Tân, TP.HCM	2025-10-03 13:29:14.460139
15	Đào Văn O	0945432108	vano@gmail.com	Nam	1994-05-21	15 Đường QRS, Quận Gò Vấp, TP.HCM	2025-10-03 13:29:14.460139
16	Nguyễn Thanh Trọng	0912345678	thanhtronglor@gmail.com	Nam	2003-12-11	Phú An, Thành phố Hồ Chí Minh	2025-12-14 16:10:19.618523
\.


--
-- TOC entry 5054 (class 0 OID 33158)
-- Dependencies: 230
-- Data for Name: employees; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.employees (employee_id, name, username, password_hash, role, avatar, created_at) FROM stdin;
3	Thu ngân B	thungan_b	$2b$10$examplehashforthuganb	cashier	/uploads/thungan_b_avatar.jpg	2025-10-03 13:29:14.460139
4	Nhân viên kho C	kho_c	$2b$10$examplehashforkhoc	warehouse	/uploads/kho_c_avatar.jpg	2025-10-03 13:29:14.460139
5	Thu ngân D	thungan_d	$2b$10$examplehashforthugand	cashier	/uploads/thungan_d_avatar.jpg	2025-10-03 13:29:14.460139
6	Admin phụ E	admin_e	$2b$10$examplehashforadmine	admin	/uploads/admin_e_avatar.jpg	2025-10-03 13:29:14.460139
8	Thu ngân G	thungan_g	$2b$10$examplehashforthugang	cashier	/uploads/thungan_g_avatar.jpg	2025-10-03 13:29:14.460139
9	Admin H	admin_h	$2b$10$examplehashforadminh	admin	/uploads/admin_h_avatar.jpg	2025-10-03 13:29:14.460139
11	Thu ngân J	thungan_j	$2b$10$examplehashforthuganj	cashier	/uploads/thungan_j_avatar.jpg	2025-10-03 13:29:14.460139
12	Admin K	admin_k	$2b$10$examplehashforadmink	admin	/uploads/admin_k_avatar.jpg	2025-10-03 13:29:14.460139
14	Thu ngân M	thungan_m	$2b$10$examplehashforthuganm	cashier	/uploads/thungan_m_avatar.jpg	2025-10-03 13:29:14.460139
15	Admin N	admin_n	$2b$10$examplehashforadminn	admin	/uploads/admin_n_avatar.jpg	2025-10-03 13:29:14.460139
2	Nhân viên kho A	kho_a	123456	warehouse	/uploads/kho_a_avatar.jpg	2025-10-03 13:29:14.460139
1	Admin Hệ thống	admin	123456	admin	/uploads/employees/1763620355678.jpg	2025-10-03 13:29:14.460139
19	Đặng Thanh Tú	admintu	$2b$10$nr7uYzqdsBcyMV88AWjnn.qGxY5gFT1Tpk92Oe2dDCm6nv05ufVsO	admin	/uploads/employees/1763624155429.jpeg	2025-10-22 22:43:23.828586
21	Trương Minh Nguyên	nguyen	$2b$10$xSdu1pR27IUmcIouDGfL7ut3uYuACShgxyo.pbde1.q4EK.0dE1rW	cashier	/uploads/employees/1763624168519.jfif	2025-11-07 11:31:36.534725
20	Nguyễn Quang Hậu	hau	$2b$10$OFTcGuTB2Grr./npdT9bKuJKMeZBBHCqjZS2oUNz.4.ra9HQ36V62	warehouse	/uploads/employees/1763624235055.jpeg	2025-10-29 21:53:45.956953
\.


--
-- TOC entry 5070 (class 0 OID 33358)
-- Dependencies: 246
-- Data for Name: financial_transactions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.financial_transactions (transaction_id, type, note, amount, transaction_date, employee_id, customer_id, supplier_id, payer_receiver_name, payer_receiver_phone, payer_receiver_address, related_order_id, related_purchase_id, payment_method_id, status, created_at, original_document_number) FROM stdin;
1	income	Thu tiền từ hóa đơn ORD-202501-001	300000.00	2025-01-05	2	1	\N	Nguyễn Văn A	0909876543	1 Đường ABC, Quận 1, TP.HCM	1	\N	1	completed	2025-10-03 13:29:14.460139	\N
2	income	Thu tiền từ hóa đơn ORD-202501-002	500000.00	2025-01-10	3	2	\N	Trần Thị B	0918765432	2 Đường DEF, Quận 2, TP.HCM	2	\N	2	completed	2025-10-03 13:29:14.460139	\N
3	income	Thu tiền từ hóa đơn ORD-202501-003	200000.00	2025-01-15	2	3	\N	Lê Văn C	0927654321	3 Đường GHI, Quận 3, TP.HCM	3	\N	1	completed	2025-10-03 13:29:14.460139	\N
4	income	Thu tiền từ hóa đơn ORD-202501-004	400000.00	2025-01-20	3	4	\N	Phạm Thị D	0936543210	4 Đường JKL, Quận 4, TP.HCM	4	\N	3	completed	2025-10-03 13:29:14.460139	\N
5	income	Thu tiền từ hóa đơn ORD-202501-005	150000.00	2025-01-25	2	5	\N	Hoàng Văn E	0945432109	5 Đường MNO, Quận 5, TP.HCM	5	\N	1	completed	2025-10-03 13:29:14.460139	\N
6	income	Thu tiền từ hóa đơn ORD-202502-001	350000.00	2025-02-05	3	6	\N	Vũ Thị F	0954321098	6 Đường PQR, Quận 6, TP.HCM	6	\N	2	completed	2025-10-03 13:29:14.460139	\N
7	income	Thu tiền từ hóa đơn ORD-202502-002	450000.00	2025-02-10	2	7	\N	Đặng Văn G	0963210987	7 Đường STU, Quận 7, TP.HCM	7	\N	1	completed	2025-10-03 13:29:14.460139	\N
8	income	Thu tiền từ hóa đơn ORD-202502-003	250000.00	2025-02-15	3	8	\N	Bùi Thị H	0972109876	8 Đường VWX, Quận 8, TP.HCM	8	\N	4	completed	2025-10-03 13:29:14.460139	\N
9	income	Thu tiền từ hóa đơn ORD-202502-004	550000.00	2025-02-20	2	9	\N	Lý Văn I	0981098765	9 Đường YZA, Quận 9, TP.HCM	9	\N	2	completed	2025-10-03 13:29:14.460139	\N
10	income	Thu tiền từ hóa đơn ORD-202502-005	100000.00	2025-02-25	3	10	\N	Hồ Thị J	0990987654	10 Đường BCD, Quận 10, TP.HCM	10	\N	1	completed	2025-10-03 13:29:14.460139	\N
11	income	Thu tiền từ hóa đơn ORD-202503-001	400000.00	2025-03-05	2	11	\N	Trương Văn K	0909876542	11 Đường EFG, Quận 11, TP.HCM	11	\N	3	completed	2025-10-03 13:29:14.460139	\N
12	income	Thu tiền từ hóa đơn ORD-202503-002	300000.00	2025-03-10	3	12	\N	Dương Thị L	0918765431	12 Đường HIJ, Quận 12, TP.HCM	12	\N	1	completed	2025-10-03 13:29:14.460139	\N
13	income	Thu tiền từ hóa đơn ORD-202503-003	600000.00	2025-03-15	2	13	\N	Mai Văn M	0927654320	13 Đường KLM, Quận Tân Bình, TP.HCM	13	\N	5	completed	2025-10-03 13:29:14.460139	\N
14	income	Thu tiền từ hóa đơn ORD-202503-004	200000.00	2025-03-20	3	14	\N	Ngô Thị N	0936543209	14 Đường NOP, Quận Bình Tân, TP.HCM	14	\N	2	completed	2025-10-03 13:29:14.460139	\N
15	income	Thu tiền từ hóa đơn ORD-202503-005	450000.00	2025-03-25	2	15	\N	Đào Văn O	0945432108	15 Đường QRS, Quận Gò Vấp, TP.HCM	15	\N	1	completed	2025-10-03 13:29:14.460139	\N
16	income	Thu tiền từ hóa đơn ORD-202504-001	550000.00	2025-04-05	3	1	\N	Nguyễn Văn A	0909876543	1 Đường ABC, Quận 1, TP.HCM	16	\N	4	completed	2025-10-03 13:29:14.460139	\N
17	income	Thu tiền từ hóa đơn ORD-202504-002	250000.00	2025-04-10	2	2	\N	Trần Thị B	0918765432	2 Đường DEF, Quận 2, TP.HCM	17	\N	1	completed	2025-10-03 13:29:14.460139	\N
18	income	Thu tiền từ hóa đơn ORD-202504-003	350000.00	2025-04-15	3	3	\N	Lê Văn C	0927654321	3 Đường GHI, Quận 3, TP.HCM	18	\N	6	completed	2025-10-03 13:29:14.460139	\N
19	income	Thu tiền từ hóa đơn ORD-202504-004	650000.00	2025-04-20	2	4	\N	Phạm Thị D	0936543210	4 Đường JKL, Quận 4, TP.HCM	19	\N	2	completed	2025-10-03 13:29:14.460139	\N
20	income	Thu tiền từ hóa đơn ORD-202504-005	150000.00	2025-04-25	3	5	\N	Hoàng Văn E	0945432109	5 Đường MNO, Quận 5, TP.HCM	20	\N	1	completed	2025-10-03 13:29:14.460139	\N
21	income	Thu tiền từ hóa đơn ORD-202505-001	500000.00	2025-05-05	2	6	\N	Vũ Thị F	0954321098	6 Đường PQR, Quận 6, TP.HCM	21	\N	3	completed	2025-10-03 13:29:14.460139	\N
22	income	Thu tiền từ hóa đơn ORD-202505-002	400000.00	2025-05-10	3	7	\N	Đặng Văn G	0963210987	7 Đường STU, Quận 7, TP.HCM	22	\N	1	completed	2025-10-03 13:29:14.460139	\N
23	income	Thu tiền từ hóa đơn ORD-202505-003	700000.00	2025-05-15	2	8	\N	Bùi Thị H	0972109876	8 Đường VWX, Quận 8, TP.HCM	23	\N	5	completed	2025-10-03 13:29:14.460139	\N
24	income	Thu tiền từ hóa đơn ORD-202505-004	300000.00	2025-05-20	3	9	\N	Lý Văn I	0981098765	9 Đường YZA, Quận 9, TP.HCM	24	\N	2	completed	2025-10-03 13:29:14.460139	\N
25	income	Thu tiền từ hóa đơn ORD-202505-005	550000.00	2025-05-25	2	10	\N	Hồ Thị J	0990987654	10 Đường BCD, Quận 10, TP.HCM	25	\N	1	completed	2025-10-03 13:29:14.460139	\N
26	income	Thu tiền từ hóa đơn ORD-202506-001	600000.00	2025-06-05	3	11	\N	Trương Văn K	0909876542	11 Đường EFG, Quận 11, TP.HCM	26	\N	4	completed	2025-10-03 13:29:14.460139	\N
27	income	Thu tiền từ hóa đơn ORD-202506-002	350000.00	2025-06-10	2	12	\N	Dương Thị L	0918765431	12 Đường HIJ, Quận 12, TP.HCM	27	\N	1	completed	2025-10-03 13:29:14.460139	\N
28	income	Thu tiền từ hóa đơn ORD-202506-003	450000.00	2025-06-15	3	13	\N	Mai Văn M	0927654320	13 Đường KLM, Quận Tân Bình, TP.HCM	28	\N	7	completed	2025-10-03 13:29:14.460139	\N
29	income	Thu tiền từ hóa đơn ORD-202506-004	750000.00	2025-06-20	2	14	\N	Ngô Thị N	0936543209	14 Đường NOP, Quận Bình Tân, TP.HCM	29	\N	2	completed	2025-10-03 13:29:14.460139	\N
30	income	Thu tiền từ hóa đơn ORD-202506-005	200000.00	2025-06-25	3	15	\N	Đào Văn O	0945432108	15 Đường QRS, Quận Gò Vấp, TP.HCM	30	\N	1	completed	2025-10-03 13:29:14.460139	\N
31	income	Thu tiền từ hóa đơn ORD-202507-001	650000.00	2025-07-05	2	1	\N	Nguyễn Văn A	0909876543	1 Đường ABC, Quận 1, TP.HCM	31	\N	5	completed	2025-10-03 13:29:14.460139	\N
32	income	Thu tiền từ hóa đơn ORD-202507-002	400000.00	2025-07-10	3	2	\N	Trần Thị B	0918765432	2 Đường DEF, Quận 2, TP.HCM	32	\N	1	completed	2025-10-03 13:29:14.460139	\N
33	income	Thu tiền từ hóa đơn ORD-202507-003	550000.00	2025-07-15	2	3	\N	Lê Văn C	0927654321	3 Đường GHI, Quận 3, TP.HCM	33	\N	8	completed	2025-10-03 13:29:14.460139	\N
34	income	Thu tiền từ hóa đơn ORD-202507-004	850000.00	2025-07-20	3	4	\N	Phạm Thị D	0936543210	4 Đường JKL, Quận 4, TP.HCM	34	\N	2	completed	2025-10-03 13:29:14.460139	\N
35	income	Thu tiền từ hóa đơn ORD-202507-005	250000.00	2025-07-25	2	5	\N	Hoàng Văn E	0945432109	5 Đường MNO, Quận 5, TP.HCM	35	\N	1	completed	2025-10-03 13:29:14.460139	\N
36	income	Thu tiền từ hóa đơn ORD-202508-001	700000.00	2025-08-05	3	6	\N	Vũ Thị F	0954321098	6 Đường PQR, Quận 6, TP.HCM	36	\N	6	completed	2025-10-03 13:29:14.460139	\N
37	income	Thu tiền từ hóa đơn ORD-202508-002	450000.00	2025-08-10	2	7	\N	Đặng Văn G	0963210987	7 Đường STU, Quận 7, TP.HCM	37	\N	1	completed	2025-10-03 13:29:14.460139	\N
38	income	Thu tiền từ hóa đơn ORD-202508-003	600000.00	2025-08-15	3	8	\N	Bùi Thị H	0972109876	8 Đường VWX, Quận 8, TP.HCM	38	\N	9	completed	2025-10-03 13:29:14.460139	\N
39	income	Thu tiền từ hóa đơn ORD-202508-004	900000.00	2025-08-20	2	9	\N	Lý Văn I	0981098765	9 Đường YZA, Quận 9, TP.HCM	39	\N	2	completed	2025-10-03 13:29:14.460139	\N
40	income	Thu tiền từ hóa đơn ORD-202508-005	300000.00	2025-08-25	3	10	\N	Hồ Thị J	0990987654	10 Đường BCD, Quận 10, TP.HCM	40	\N	1	completed	2025-10-03 13:29:14.460139	\N
41	income	Thu tiền từ hóa đơn ORD-202509-001	750000.00	2025-09-05	2	11	\N	Trương Văn K	0909876542	11 Đường EFG, Quận 11, TP.HCM	41	\N	7	completed	2025-10-03 13:29:14.460139	\N
42	income	Thu tiền từ hóa đơn ORD-202509-002	500000.00	2025-09-10	3	12	\N	Dương Thị L	0918765431	12 Đường HIJ, Quận 12, TP.HCM	42	\N	1	completed	2025-10-03 13:29:14.460139	\N
43	income	Thu tiền từ hóa đơn ORD-202509-003	650000.00	2025-09-15	2	13	\N	Mai Văn M	0927654320	13 Đường KLM, Quận Tân Bình, TP.HCM	43	\N	10	completed	2025-10-03 13:29:14.460139	\N
44	income	Thu tiền từ hóa đơn ORD-202509-004	950000.00	2025-09-20	3	14	\N	Ngô Thị N	0936543209	14 Đường NOP, Quận Bình Tân, TP.HCM	44	\N	2	completed	2025-10-03 13:29:14.460139	\N
45	income	Thu tiền từ hóa đơn ORD-202509-005	350000.00	2025-09-25	2	15	\N	Đào Văn O	0945432108	15 Đường QRS, Quận Gò Vấp, TP.HCM	45	\N	1	completed	2025-10-03 13:29:14.460139	\N
46	income	Thu tiền từ hóa đơn ORD-202510-001	800000.00	2025-10-05	3	1	\N	Nguyễn Văn A	0909876543	1 Đường ABC, Quận 1, TP.HCM	46	\N	8	completed	2025-10-03 13:29:14.460139	\N
47	income	Thu tiền từ hóa đơn ORD-202510-002	550000.00	2025-10-10	2	2	\N	Trần Thị B	0918765432	2 Đường DEF, Quận 2, TP.HCM	47	\N	1	completed	2025-10-03 13:29:14.460139	\N
48	income	Thu tiền từ hóa đơn ORD-202510-003	700000.00	2025-10-15	3	3	\N	Lê Văn C	0927654321	3 Đường GHI, Quận 3, TP.HCM	48	\N	1	completed	2025-10-03 13:29:14.460139	\N
49	income	Thu tiền từ hóa đơn ORD-202510-004	1000000.00	2025-10-20	2	4	\N	Phạm Thị D	0936543210	4 Đường JKL, Quận 4, TP.HCM	49	\N	2	completed	2025-10-03 13:29:14.460139	\N
50	income	Thu tiền từ hóa đơn ORD-202510-005	400000.00	2025-10-25	3	5	\N	Hoàng Văn E	0945432109	5 Đường MNO, Quận 5, TP.HCM	50	\N	1	completed	2025-10-03 13:29:14.460139	\N
51	expense	Chi tiền nhập hàng PUR-202501-001	600000.00	2025-01-03	4	\N	\N	\N	\N	\N	\N	1	2	completed	2025-10-03 13:29:14.460139	\N
52	expense	Chi tiền nhập hàng PUR-202501-002	800000.00	2025-01-08	5	\N	\N	\N	\N	\N	\N	2	2	completed	2025-10-03 13:29:14.460139	\N
53	expense	Chi tiền nhập hàng PUR-202501-003	400000.00	2025-01-13	4	\N	\N	\N	\N	\N	\N	3	2	completed	2025-10-03 13:29:14.460139	\N
54	expense	Chi tiền nhập hàng PUR-202501-004	700000.00	2025-01-18	5	\N	\N	\N	\N	\N	\N	4	2	completed	2025-10-03 13:29:14.460139	\N
55	expense	Chi tiền nhập hàng PUR-202501-005	300000.00	2025-01-23	4	\N	\N	\N	\N	\N	\N	5	2	completed	2025-10-03 13:29:14.460139	\N
56	expense	Chi tiền nhập hàng PUR-202502-001	700000.00	2025-02-03	5	\N	\N	\N	\N	\N	\N	6	2	completed	2025-10-03 13:29:14.460139	\N
57	expense	Chi tiền nhập hàng PUR-202502-002	900000.00	2025-02-08	4	\N	\N	\N	\N	\N	\N	7	2	completed	2025-10-03 13:29:14.460139	\N
58	expense	Chi tiền nhập hàng PUR-202502-003	500000.00	2025-02-13	5	\N	\N	\N	\N	\N	\N	8	2	completed	2025-10-03 13:29:14.460139	\N
59	expense	Chi tiền nhập hàng PUR-202502-004	800000.00	2025-02-18	4	\N	\N	\N	\N	\N	\N	9	2	completed	2025-10-03 13:29:14.460139	\N
60	expense	Chi tiền nhập hàng PUR-202502-005	400000.00	2025-02-23	5	\N	\N	\N	\N	\N	\N	10	2	completed	2025-10-03 13:29:14.460139	\N
61	expense	Chi tiền nhập hàng PUR-202503-001	800000.00	2025-03-03	4	\N	\N	\N	\N	\N	\N	11	2	completed	2025-10-03 13:29:14.460139	\N
62	expense	Chi tiền nhập hàng PUR-202503-002	600000.00	2025-03-08	5	\N	\N	\N	\N	\N	\N	12	2	completed	2025-10-03 13:29:14.460139	\N
63	expense	Chi tiền nhập hàng PUR-202503-003	900000.00	2025-03-13	4	\N	\N	\N	\N	\N	\N	13	2	completed	2025-10-03 13:29:14.460139	\N
64	expense	Chi tiền nhập hàng PUR-202503-004	500000.00	2025-03-18	5	\N	\N	\N	\N	\N	\N	14	2	completed	2025-10-03 13:29:14.460139	\N
65	expense	Chi tiền nhập hàng PUR-202503-005	700000.00	2025-03-23	4	\N	\N	\N	\N	\N	\N	15	2	completed	2025-10-03 13:29:14.460139	\N
66	expense	Chi tiền nhập hàng PUR-202504-001	900000.00	2025-04-03	5	\N	\N	\N	\N	\N	\N	16	2	completed	2025-10-03 13:29:14.460139	\N
67	expense	Chi tiền nhập hàng PUR-202504-002	700000.00	2025-04-08	4	\N	\N	\N	\N	\N	\N	17	2	completed	2025-10-03 13:29:14.460139	\N
68	expense	Chi tiền nhập hàng PUR-202504-003	1000000.00	2025-04-13	5	\N	\N	\N	\N	\N	\N	18	2	completed	2025-10-03 13:29:14.460139	\N
69	expense	Chi tiền nhập hàng PUR-202504-004	600000.00	2025-04-18	4	\N	\N	\N	\N	\N	\N	19	2	completed	2025-10-03 13:29:14.460139	\N
70	expense	Chi tiền nhập hàng PUR-202504-005	800000.00	2025-04-23	5	\N	\N	\N	\N	\N	\N	20	2	completed	2025-10-03 13:29:14.460139	\N
71	expense	Chi tiền nhập hàng PUR-202505-001	1000000.00	2025-05-03	4	\N	\N	\N	\N	\N	\N	21	2	completed	2025-10-03 13:29:14.460139	\N
72	expense	Chi tiền nhập hàng PUR-202505-002	800000.00	2025-05-08	5	\N	\N	\N	\N	\N	\N	22	2	completed	2025-10-03 13:29:14.460139	\N
73	expense	Chi tiền nhập hàng PUR-202505-003	1100000.00	2025-05-13	4	\N	\N	\N	\N	\N	\N	23	2	completed	2025-10-03 13:29:14.460139	\N
74	expense	Chi tiền nhập hàng PUR-202505-004	700000.00	2025-05-18	5	\N	\N	\N	\N	\N	\N	24	2	completed	2025-10-03 13:29:14.460139	\N
75	expense	Chi tiền nhập hàng PUR-202505-005	900000.00	2025-05-23	4	\N	\N	\N	\N	\N	\N	25	2	completed	2025-10-03 13:29:14.460139	\N
76	expense	Chi tiền nhập hàng PUR-202506-001	1100000.00	2025-06-03	5	\N	\N	\N	\N	\N	\N	26	2	completed	2025-10-03 13:29:14.460139	\N
77	expense	Chi tiền nhập hàng PUR-202506-002	900000.00	2025-06-08	4	\N	\N	\N	\N	\N	\N	27	2	completed	2025-10-03 13:29:14.460139	\N
78	expense	Chi tiền nhập hàng PUR-202506-003	1200000.00	2025-06-13	5	\N	\N	\N	\N	\N	\N	28	2	completed	2025-10-03 13:29:14.460139	\N
79	expense	Chi tiền nhập hàng PUR-202506-004	800000.00	2025-06-18	4	\N	\N	\N	\N	\N	\N	29	2	completed	2025-10-03 13:29:14.460139	\N
80	expense	Chi tiền nhập hàng PUR-202506-005	1000000.00	2025-06-23	5	\N	\N	\N	\N	\N	\N	30	2	completed	2025-10-03 13:29:14.460139	\N
81	expense	Chi tiền nhập hàng PUR-202507-001	1200000.00	2025-07-03	4	\N	\N	\N	\N	\N	\N	31	2	completed	2025-10-03 13:29:14.460139	\N
82	expense	Chi tiền nhập hàng PUR-202507-002	1000000.00	2025-07-08	5	\N	\N	\N	\N	\N	\N	32	2	completed	2025-10-03 13:29:14.460139	\N
83	expense	Chi tiền nhập hàng PUR-202507-003	1300000.00	2025-07-13	4	\N	\N	\N	\N	\N	\N	33	2	completed	2025-10-03 13:29:14.460139	\N
84	expense	Chi tiền nhập hàng PUR-202507-004	900000.00	2025-07-18	5	\N	\N	\N	\N	\N	\N	34	2	completed	2025-10-03 13:29:14.460139	\N
85	expense	Chi tiền nhập hàng PUR-202507-005	1100000.00	2025-07-23	4	\N	\N	\N	\N	\N	\N	35	2	completed	2025-10-03 13:29:14.460139	\N
86	expense	Chi tiền nhập hàng PUR-202508-001	1300000.00	2025-08-03	5	\N	\N	\N	\N	\N	\N	36	2	completed	2025-10-03 13:29:14.460139	\N
87	expense	Chi tiền nhập hàng PUR-202508-002	1100000.00	2025-08-08	4	\N	\N	\N	\N	\N	\N	37	2	completed	2025-10-03 13:29:14.460139	\N
88	expense	Chi tiền nhập hàng PUR-202508-003	1400000.00	2025-08-13	5	\N	\N	\N	\N	\N	\N	38	2	completed	2025-10-03 13:29:14.460139	\N
89	expense	Chi tiền nhập hàng PUR-202508-004	1000000.00	2025-08-18	4	\N	\N	\N	\N	\N	\N	39	2	completed	2025-10-03 13:29:14.460139	\N
90	expense	Chi tiền nhập hàng PUR-202508-005	1200000.00	2025-08-23	5	\N	\N	\N	\N	\N	\N	40	2	completed	2025-10-03 13:29:14.460139	\N
91	expense	Chi tiền nhập hàng PUR-202509-001	1400000.00	2025-09-03	4	\N	\N	\N	\N	\N	\N	41	2	completed	2025-10-03 13:29:14.460139	\N
92	expense	Chi tiền nhập hàng PUR-202509-002	1200000.00	2025-09-08	5	\N	\N	\N	\N	\N	\N	42	2	completed	2025-10-03 13:29:14.460139	\N
93	expense	Chi tiền nhập hàng PUR-202509-003	1500000.00	2025-09-13	4	\N	\N	\N	\N	\N	\N	43	2	completed	2025-10-03 13:29:14.460139	\N
94	expense	Chi tiền nhập hàng PUR-202509-004	1100000.00	2025-09-18	5	\N	\N	\N	\N	\N	\N	44	2	completed	2025-10-03 13:29:14.460139	\N
95	expense	Chi tiền nhập hàng PUR-202509-005	1300000.00	2025-09-23	4	\N	\N	\N	\N	\N	\N	45	2	completed	2025-10-03 13:29:14.460139	\N
96	expense	Chi tiền nhập hàng PUR-202510-001	1500000.00	2025-10-03	5	\N	\N	\N	\N	\N	\N	46	2	completed	2025-10-03 13:29:14.460139	\N
97	expense	Chi tiền nhập hàng PUR-202510-002	1300000.00	2025-10-08	4	\N	\N	\N	\N	\N	\N	47	2	completed	2025-10-03 13:29:14.460139	\N
98	expense	Chi tiền nhập hàng PUR-202510-003	1600000.00	2025-10-13	5	\N	\N	\N	\N	\N	\N	48	2	completed	2025-10-03 13:29:14.460139	\N
99	expense	Chi tiền nhập hàng PUR-202510-004	1200000.00	2025-10-18	4	\N	\N	\N	\N	\N	\N	49	2	completed	2025-10-03 13:29:14.460139	\N
100	expense	Chi tiền nhập hàng PUR-202510-005	1400000.00	2025-10-23	5	\N	\N	\N	\N	\N	\N	50	2	completed	2025-10-03 13:29:14.460139	\N
101	income	Thu tiền từ hóa đơn tháng 1	300000.00	2025-01-05	2	1	\N	Nguyễn Văn A	0909876543	1 Đường ABC	1	\N	1	completed	2025-10-03 13:29:14.460139	\N
102	expense	Chi tiền nhập hàng tháng 1	600000.00	2025-01-03	4	\N	1	Công ty Dược phẩm Thú y Việt Nam	0901234567	123 Đường Nguyễn Huệ	\N	1	2	completed	2025-10-03 13:29:14.460139	\N
103	income	Thu tiền từ hóa đơn tháng 1	500000.00	2025-01-10	3	2	\N	Trần Thị B	0918765432	2 Đường DEF	2	\N	2	completed	2025-10-03 13:29:14.460139	\N
104	expense	Chi tiền nhập hàng tháng 1	800000.00	2025-01-08	5	\N	2	Nhà cung cấp Vật tư Y tế ABC	0912345678	456 Đường Lê Lợi	\N	2	2	completed	2025-10-03 13:29:14.460139	\N
105	income	Thu tiền từ hóa đơn tháng 1	200000.00	2025-01-15	2	3	\N	Lê Văn C	0927654321	3 Đường GHI	3	\N	1	completed	2025-10-03 13:29:14.460139	\N
106	expense	Chi tiền nhập hàng tháng 1	400000.00	2025-01-13	4	\N	3	Công ty Thức ăn Thú cưng Global	0923456789	789 Đường Võ Văn Kiệt	\N	3	2	completed	2025-10-03 13:29:14.460139	\N
107	income	Thu tiền từ hóa đơn tháng 1	400000.00	2025-01-20	3	4	\N	Phạm Thị D	0936543210	4 Đường JKL	4	\N	3	completed	2025-10-03 13:29:14.460139	\N
108	expense	Chi tiền nhập hàng tháng 1	700000.00	2025-01-18	5	\N	4	Nhà phân phối Vắc-xin Quốc tế	0934567890	1011 Đường Phạm Văn Đồng	\N	4	2	completed	2025-10-03 13:29:14.460139	\N
109	income	Thu tiền từ hóa đơn tháng 1	150000.00	2025-01-25	2	5	\N	Hoàng Văn E	0945432109	5 Đường MNO	5	\N	1	completed	2025-10-03 13:29:14.460139	\N
110	expense	Chi tiền nhập hàng tháng 1	300000.00	2025-01-23	4	\N	5	Công ty Phụ kiện Thú cưng PetShop	0945678901	1213 Đường Trường Chinh	\N	5	2	completed	2025-10-03 13:29:14.460139	\N
111	income	Thu tiền từ hóa đơn tháng 2	350000.00	2025-02-05	3	6	\N	Vũ Thị F	0954321098	6 Đường PQR	6	\N	2	completed	2025-10-03 13:29:14.460139	\N
112	expense	Chi tiền nhập hàng tháng 2	700000.00	2025-02-03	5	\N	6	Nhà cung cấp Thiết bị Y tế MedTech	0956789012	1415 Đường CMT8	\N	6	2	completed	2025-10-03 13:29:14.460139	\N
113	income	Thu tiền từ hóa đơn tháng 2	450000.00	2025-02-10	2	7	\N	Đặng Văn G	0963210987	7 Đường STU	7	\N	1	completed	2025-10-03 13:29:14.460139	\N
114	expense	Chi tiền nhập hàng tháng 2	900000.00	2025-02-08	4	\N	7	Công ty Thực phẩm Bổ sung BioLife	0967890123	1617 Đường Lý Thường Kiệt	\N	7	2	completed	2025-10-03 13:29:14.460139	\N
115	income	Thu tiền từ hóa đơn tháng 2	250000.00	2025-02-15	3	8	\N	Bùi Thị H	0972109876	8 Đường VWX	8	\N	4	completed	2025-10-03 13:29:14.460139	\N
116	expense	Chi tiền nhập hàng tháng 2	500000.00	2025-02-13	5	\N	8	Nhà phân phối Sản phẩm Vệ sinh CleanPet	0978901234	1819 Đường Nguyễn Văn Linh	\N	8	2	completed	2025-10-03 13:29:14.460139	\N
117	income	Thu tiền từ hóa đơn tháng 2	550000.00	2025-02-20	2	9	\N	Lý Văn I	0981098765	9 Đường YZA	9	\N	2	completed	2025-10-03 13:29:14.460139	\N
118	expense	Chi tiền nhập hàng tháng 2	800000.00	2025-02-18	4	\N	9	Công ty Dụng cụ Game PetFun	0989012345	2021 Đường Trần Hưng Đạo	\N	9	2	completed	2025-10-03 13:29:14.460139	\N
119	income	Thu tiền từ hóa đơn tháng 2	100000.00	2025-02-25	3	10	\N	Hồ Thị J	0990987654	10 Đường BCD	10	\N	1	completed	2025-10-03 13:29:14.460139	\N
120	expense	Chi tiền nhập hàng tháng 2	400000.00	2025-02-23	5	\N	10	Nhà cung cấp Khác MiscSupply	0990123456	2223 Đường Hoàng Văn Thụ	\N	10	2	completed	2025-10-03 13:29:14.460139	\N
121	income	Thu tiền từ hóa đơn tháng 3	400000.00	2025-03-05	2	11	\N	Trương Văn K	0909876542	11 Đường EFG	11	\N	3	completed	2025-10-03 13:29:14.460139	\N
122	expense	Chi tiền nhập hàng tháng 3	800000.00	2025-03-03	4	\N	1	Công ty Dược phẩm Thú y Việt Nam	0901234567	123 Đường Nguyễn Huệ	\N	11	2	completed	2025-10-03 13:29:14.460139	\N
123	income	Thu tiền từ hóa đơn tháng 3	300000.00	2025-03-10	3	12	\N	Dương Thị L	0918765431	12 Đường HIJ	12	\N	1	completed	2025-10-03 13:29:14.460139	\N
124	expense	Chi tiền nhập hàng tháng 3	600000.00	2025-03-08	5	\N	2	Nhà cung cấp Vật tư Y tế ABC	0912345678	456 Đường Lê Lợi	\N	12	2	completed	2025-10-03 13:29:14.460139	\N
125	income	Thu tiền từ hóa đơn tháng 3	600000.00	2025-03-15	2	13	\N	Mai Văn M	0927654320	13 Đường KLM	13	\N	5	completed	2025-10-03 13:29:14.460139	\N
126	expense	Chi tiền nhập hàng tháng 3	900000.00	2025-03-13	4	\N	3	Công ty Thức ăn Thú cưng Global	0923456789	789 Đường Võ Văn Kiệt	\N	13	2	completed	2025-10-03 13:29:14.460139	\N
127	income	Thu tiền từ hóa đơn tháng 3	200000.00	2025-03-20	3	14	\N	Ngô Thị N	0936543209	14 Đường NOP	14	\N	2	completed	2025-10-03 13:29:14.460139	\N
128	expense	Chi tiền nhập hàng tháng 3	500000.00	2025-03-18	5	\N	4	Nhà phân phối Vắc-xin Quốc tế	0934567890	1011 Đường Phạm Văn Đồng	\N	14	2	completed	2025-10-03 13:29:14.460139	\N
129	income	Thu tiền từ hóa đơn tháng 3	450000.00	2025-03-25	2	15	\N	Đào Văn O	0945432108	15 Đường QRS	15	\N	1	completed	2025-10-03 13:29:14.460139	\N
130	expense	Chi tiền nhập hàng tháng 3	700000.00	2025-03-23	4	\N	5	Công ty Phụ kiện Thú cưng PetShop	0945678901	1213 Đường Trường Chinh	\N	15	2	completed	2025-10-03 13:29:14.460139	\N
131	income	Thu tiền từ hóa đơn tháng 4	550000.00	2025-04-05	3	1	\N	Nguyễn Văn A	0909876543	1 Đường ABC	16	\N	4	completed	2025-10-03 13:29:14.460139	\N
132	expense	Chi tiền nhập hàng tháng 4	900000.00	2025-04-03	5	\N	6	Nhà cung cấp Thiết bị Y tế MedTech	0956789012	1415 Đường CMT8	\N	16	2	completed	2025-10-03 13:29:14.460139	\N
133	income	Thu tiền từ hóa đơn tháng 4	250000.00	2025-04-10	2	2	\N	Trần Thị B	0918765432	2 Đường DEF	17	\N	1	completed	2025-10-03 13:29:14.460139	\N
134	expense	Chi tiền nhập hàng tháng 4	700000.00	2025-04-08	4	\N	7	Công ty Thực phẩm Bổ sung BioLife	0967890123	1617 Đường Lý Thường Kiệt	\N	17	2	completed	2025-10-03 13:29:14.460139	\N
135	income	Thu tiền từ hóa đơn tháng 4	350000.00	2025-04-15	3	3	\N	Lê Văn C	0927654321	3 Đường GHI	18	\N	6	completed	2025-10-03 13:29:14.460139	\N
136	expense	Chi tiền nhập hàng tháng 4	1000000.00	2025-04-13	5	\N	8	Nhà phân phối Sản phẩm Vệ sinh CleanPet	0978901234	1819 Đường Nguyễn Văn Linh	\N	18	2	completed	2025-10-03 13:29:14.460139	\N
137	income	Thu tiền từ hóa đơn tháng 4	650000.00	2025-04-20	2	4	\N	Phạm Thị D	0936543210	4 Đường JKL	19	\N	2	completed	2025-10-03 13:29:14.460139	\N
138	expense	Chi tiền nhập hàng tháng 4	600000.00	2025-04-18	4	\N	9	Công ty Dụng cụ Game PetFun	0989012345	2021 Đường Trần Hưng Đạo	\N	19	2	completed	2025-10-03 13:29:14.460139	\N
139	income	Thu tiền từ hóa đơn tháng 4	150000.00	2025-04-25	3	5	\N	Hoàng Văn E	0945432109	5 Đường MNO	20	\N	1	completed	2025-10-03 13:29:14.460139	\N
140	expense	Chi tiền nhập hàng tháng 4	800000.00	2025-04-23	5	\N	10	Nhà cung cấp Khác MiscSupply	0990123456	2223 Đường Hoàng Văn Thụ	\N	20	2	completed	2025-10-03 13:29:14.460139	\N
141	income	Thu tiền từ hóa đơn tháng 5	500000.00	2025-05-05	2	6	\N	Vũ Thị F	0954321098	6 Đường PQR	21	\N	3	completed	2025-10-03 13:29:14.460139	\N
142	expense	Chi tiền nhập hàng tháng 5	1000000.00	2025-05-03	4	\N	1	Công ty Dược phẩm Thú y Việt Nam	0901234567	123 Đường Nguyễn Huệ	\N	21	2	completed	2025-10-03 13:29:14.460139	\N
143	income	Thu tiền từ hóa đơn tháng 5	400000.00	2025-05-10	3	7	\N	Đặng Văn G	0963210987	7 Đường STU	22	\N	1	completed	2025-10-03 13:29:14.460139	\N
144	expense	Chi tiền nhập hàng tháng 5	800000.00	2025-05-08	5	\N	2	Nhà cung cấp Vật tư Y tế ABC	0912345678	456 Đường Lê Lợi	\N	22	2	completed	2025-10-03 13:29:14.460139	\N
145	income	Thu tiền từ hóa đơn tháng 5	700000.00	2025-05-15	2	8	\N	Bùi Thị H	0972109876	8 Đường VWX	23	\N	7	completed	2025-10-03 13:29:14.460139	\N
146	expense	Chi tiền nhập hàng tháng 5	1100000.00	2025-05-13	4	\N	3	Công ty Thức ăn Thú cưng Global	0923456789	789 Đường Võ Văn Kiệt	\N	23	2	completed	2025-10-03 13:29:14.460139	\N
147	income	Thu tiền từ hóa đơn tháng 5	300000.00	2025-05-20	3	9	\N	Lý Văn I	0981098765	9 Đường YZA	24	\N	2	completed	2025-10-03 13:29:14.460139	\N
148	expense	Chi tiền nhập hàng tháng 5	700000.00	2025-05-18	5	\N	4	Nhà phân phối Vắc-xin Quốc tế	0934567890	1011 Đường Phạm Văn Đồng	\N	24	2	completed	2025-10-03 13:29:14.460139	\N
149	income	Thu tiền từ hóa đơn tháng 5	550000.00	2025-05-25	2	10	\N	Hồ Thị J	0990987654	10 Đường BCD	25	\N	1	completed	2025-10-03 13:29:14.460139	\N
150	expense	Chi tiền nhập hàng tháng 5	900000.00	2025-05-23	4	\N	5	Công ty Phụ kiện Thú cưng PetShop	0945678901	1213 Đường Trường Chinh	\N	25	2	completed	2025-10-03 13:29:14.460139	\N
151	income	Thu tiền từ hóa đơn tháng 6	600000.00	2025-06-05	3	11	\N	Trương Văn K	0909876542	11 Đường EFG	26	\N	1	completed	2025-10-03 13:29:14.460139	\N
152	expense	Chi tiền nhập hàng tháng 6	1100000.00	2025-06-03	5	\N	6	Nhà cung cấp Thiết bị Y tế MedTech	0956789012	1415 Đường CMT8	\N	26	2	completed	2025-10-03 13:29:14.460139	\N
153	income	Thu tiền từ hóa đơn tháng 6	350000.00	2025-06-10	2	12	\N	Dương Thị L	0918765431	12 Đường HIJ	27	\N	1	completed	2025-10-03 13:29:14.460139	\N
154	expense	Chi tiền nhập hàng tháng 6	900000.00	2025-06-08	4	\N	7	Công ty Thực phẩm Bổ sung BioLife	0967890123	1617 Đường Lý Thường Kiệt	\N	27	2	completed	2025-10-03 13:29:14.460139	\N
155	income	Thu tiền từ hóa đơn tháng 6	450000.00	2025-06-15	3	13	\N	Mai Văn M	0927654320	13 Đường KLM	28	\N	1	completed	2025-10-03 13:29:14.460139	\N
156	expense	Chi tiền nhập hàng tháng 6	1200000.00	2025-06-13	5	\N	8	Nhà phân phối Sản phẩm Vệ sinh CleanPet	0978901234	1819 Đường Nguyễn Văn Linh	\N	28	2	completed	2025-10-03 13:29:14.460139	\N
157	income	Thu tiền từ hóa đơn tháng 6	750000.00	2025-06-20	2	14	\N	Ngô Thị N	0936543209	14 Đường NOP	29	\N	2	completed	2025-10-03 13:29:14.460139	\N
158	expense	Chi tiền nhập hàng tháng 6	800000.00	2025-06-18	4	\N	9	Công ty Dụng cụ Game PetFun	0989012345	2021 Đường Trần Hưng Đạo	\N	29	2	completed	2025-10-03 13:29:14.460139	\N
159	income	Thu tiền từ hóa đơn tháng 6	200000.00	2025-06-25	3	15	\N	Đào Văn O	0945432108	15 Đường QRS	30	\N	1	completed	2025-10-03 13:29:14.460139	\N
160	expense	Chi tiền nhập hàng tháng 6	1000000.00	2025-06-23	5	\N	10	Nhà cung cấp Khác MiscSupply	0990123456	2223 Đường Hoàng Văn Thụ	\N	30	2	completed	2025-10-03 13:29:14.460139	\N
161	income	Thu tiền từ hóa đơn tháng 7	650000.00	2025-07-05	2	1	\N	Nguyễn Văn A	0909876543	1 Đường ABC	31	\N	7	completed	2025-10-03 13:29:14.460139	\N
162	expense	Chi tiền nhập hàng tháng 7	1200000.00	2025-07-03	4	\N	1	Công ty Dược phẩm Thú y Việt Nam	0901234567	123 Đường Nguyễn Huệ	\N	31	2	completed	2025-10-03 13:29:14.460139	\N
163	income	Thu tiền từ hóa đơn tháng 7	400000.00	2025-07-10	3	2	\N	Trần Thị B	0918765432	2 Đường DEF	32	\N	1	completed	2025-10-03 13:29:14.460139	\N
164	expense	Chi tiền nhập hàng tháng 7	1000000.00	2025-07-08	5	\N	2	Nhà cung cấp Vật tư Y tế ABC	0912345678	456 Đường Lê Lợi	\N	32	2	completed	2025-10-03 13:29:14.460139	\N
165	income	Thu tiền từ hóa đơn tháng 7	550000.00	2025-07-15	2	3	\N	Lê Văn C	0927654321	3 Đường GHI	33	\N	7	completed	2025-10-03 13:29:14.460139	\N
166	expense	Chi tiền nhập hàng tháng 7	1300000.00	2025-07-13	4	\N	3	Công ty Thức ăn Thú cưng Global	0923456789	789 Đường Võ Văn Kiệt	\N	33	2	completed	2025-10-03 13:29:14.460139	\N
167	income	Thu tiền từ hóa đơn tháng 7	850000.00	2025-07-20	3	4	\N	Phạm Thị D	0936543210	4 Đường JKL	34	\N	2	completed	2025-10-03 13:29:14.460139	\N
168	expense	Chi tiền nhập hàng tháng 7	900000.00	2025-07-18	5	\N	4	Nhà phân phối Vắc-xin Quốc tế	0934567890	1011 Đường Phạm Văn Đồng	\N	34	2	completed	2025-10-03 13:29:14.460139	\N
169	income	Thu tiền từ hóa đơn tháng 7	250000.00	2025-07-25	2	5	\N	Hoàng Văn E	0945432109	5 Đường MNO	35	\N	7	completed	2025-10-03 13:29:14.460139	\N
170	expense	Chi tiền nhập hàng tháng 7	1100000.00	2025-07-23	4	\N	5	Công ty Phụ kiện Thú cưng PetShop	0945678901	1213 Đường Trường Chinh	\N	35	2	completed	2025-10-03 13:29:14.460139	\N
171	income	Thu tiền từ hóa đơn tháng 8	700000.00	2025-08-05	3	6	\N	Vũ Thị F	0954321098	6 Đường PQR	36	\N	1	completed	2025-10-03 13:29:14.460139	\N
172	expense	Chi tiền nhập hàng tháng 8	1300000.00	2025-08-03	5	\N	6	Nhà cung cấp Thiết bị Y tế MedTech	0956789012	1415 Đường CMT8	\N	36	2	completed	2025-10-03 13:29:14.460139	\N
173	income	Thu tiền từ hóa đơn tháng 8	450000.00	2025-08-10	2	7	\N	Đặng Văn G	0963210987	7 Đường STU	37	\N	1	completed	2025-10-03 13:29:14.460139	\N
174	expense	Chi tiền nhập hàng tháng 8	1100000.00	2025-08-08	4	\N	7	Công ty Thực phẩm Bổ sung BioLife	0967890123	1617 Đường Lý Thường Kiệt	\N	37	2	completed	2025-10-03 13:29:14.460139	\N
175	income	Thu tiền từ hóa đơn tháng 8	600000.00	2025-08-15	3	8	\N	Bùi Thị H	0972109876	8 Đường VWX	38	\N	9	completed	2025-10-03 13:29:14.460139	\N
176	expense	Chi tiền nhập hàng tháng 8	1400000.00	2025-08-13	5	\N	8	Nhà phân phối Sản phẩm Vệ sinh CleanPet	0978901234	1819 Đường Nguyễn Văn Linh	\N	38	2	completed	2025-10-03 13:29:14.460139	\N
177	income	Thu tiền từ hóa đơn tháng 8	900000.00	2025-08-20	2	9	\N	Lý Văn I	0981098765	9 Đường YZA	39	\N	2	completed	2025-10-03 13:29:14.460139	\N
178	expense	Chi tiền nhập hàng tháng 8	1000000.00	2025-08-18	4	\N	9	Công ty Dụng cụ Game PetFun	0989012345	2021 Đường Trần Hưng Đạo	\N	39	2	completed	2025-10-03 13:29:14.460139	\N
179	income	Thu tiền từ hóa đơn tháng 8	300000.00	2025-08-25	3	10	\N	Hồ Thị J	0990987654	10 Đường BCD	40	\N	1	completed	2025-10-03 13:29:14.460139	\N
180	expense	Chi tiền nhập hàng tháng 8	1200000.00	2025-08-23	5	\N	10	Nhà cung cấp Khác MiscSupply	0990123456	2223 Đường Hoàng Văn Thụ	\N	40	2	completed	2025-10-03 13:29:14.460139	\N
181	income	Thu tiền từ hóa đơn tháng 9	750000.00	2025-09-05	2	11	\N	Trương Văn K	0909876542	11 Đường EFG	41	\N	2	completed	2025-10-03 13:29:14.460139	\N
182	expense	Chi tiền nhập hàng tháng 9	1400000.00	2025-09-03	4	\N	1	Công ty Dược phẩm Thú y Việt Nam	0901234567	123 Đường Nguyễn Huệ	\N	41	2	completed	2025-10-03 13:29:14.460139	\N
183	income	Thu tiền từ hóa đơn tháng 9	500000.00	2025-09-10	3	12	\N	Dương Thị L	0918765431	12 Đường HIJ	42	\N	1	completed	2025-10-03 13:29:14.460139	\N
184	expense	Chi tiền nhập hàng tháng 9	1200000.00	2025-09-08	5	\N	2	Nhà cung cấp Vật tư Y tế ABC	0912345678	456 Đường Lê Lợi	\N	42	2	completed	2025-10-03 13:29:14.460139	\N
185	income	Thu tiền từ hóa đơn tháng 9	650000.00	2025-09-15	2	13	\N	Mai Văn M	0927654320	13 Đường KLM	43	\N	10	completed	2025-10-03 13:29:14.460139	\N
186	expense	Chi tiền nhập hàng tháng 9	1500000.00	2025-09-13	4	\N	3	Công ty Thức ăn Thú cưng Global	0923456789	789 Đường Võ Văn Kiệt	\N	43	2	completed	2025-10-03 13:29:14.460139	\N
187	income	Thu tiền từ hóa đơn tháng 9	950000.00	2025-09-20	3	14	\N	Ngô Thị N	0936543209	14 Đường NOP	44	\N	2	completed	2025-10-03 13:29:14.460139	\N
188	expense	Chi tiền nhập hàng tháng 9	1100000.00	2025-09-18	5	\N	4	Nhà phân phối Vắc-xin Quốc tế	0934567890	1011 Đường Phạm Văn Đồng	\N	44	2	completed	2025-10-03 13:29:14.460139	\N
189	income	Thu tiền từ hóa đơn tháng 9	350000.00	2025-09-25	2	15	\N	Đào Văn O	0945432108	15 Đường QRS	45	\N	1	completed	2025-10-03 13:29:14.460139	\N
190	expense	Chi tiền nhập hàng tháng 9	1300000.00	2025-09-23	4	\N	5	Công ty Phụ kiện Thú cưng PetShop	0945678901	1213 Đường Trường Chinh	\N	45	2	completed	2025-10-03 13:29:14.460139	\N
191	income	Thu tiền từ hóa đơn tháng 10	800000.00	2025-10-05	3	1	\N	Nguyễn Văn A	0909876543	1 Đường ABC	46	\N	8	completed	2025-10-03 13:29:14.460139	\N
192	expense	Chi tiền nhập hàng tháng 10	1500000.00	2025-10-03	5	\N	6	Nhà cung cấp Thiết bị Y tế MedTech	0956789012	1415 Đường CMT8	\N	46	2	completed	2025-10-03 13:29:14.460139	\N
193	income	Thu tiền từ hóa đơn tháng 10	550000.00	2025-10-10	2	2	\N	Trần Thị B	0918765432	2 Đường DEF	47	\N	1	completed	2025-10-03 13:29:14.460139	\N
194	expense	Chi tiền nhập hàng tháng 10	1300000.00	2025-10-08	4	\N	7	Công ty Thực phẩm Bổ sung BioLife	0967890123	1617 Đường Lý Thường Kiệt	\N	47	2	completed	2025-10-03 13:29:14.460139	\N
195	income	Thu tiền từ hóa đơn tháng 10	700000.00	2025-10-15	3	3	\N	Lê Văn C	0927654321	3 Đường GHI	48	\N	1	completed	2025-10-03 13:29:14.460139	\N
196	expense	Chi tiền nhập hàng tháng 10	1600000.00	2025-10-13	5	\N	8	Nhà phân phối Sản phẩm Vệ sinh CleanPet	0978901234	1819 Đường Nguyễn Văn Linh	\N	48	2	completed	2025-10-03 13:29:14.460139	\N
197	income	Thu tiền từ hóa đơn tháng 10	1000000.00	2025-10-20	2	4	\N	Phạm Thị D	0936543210	4 Đường JKL	49	\N	2	completed	2025-10-03 13:29:14.460139	\N
198	expense	Chi tiền nhập hàng tháng 10	1200000.00	2025-10-18	4	\N	9	Công ty Dụng cụ Game PetFun	0989012345	2021 Đường Trần Hưng Đạo	\N	49	2	completed	2025-10-03 13:29:14.460139	\N
199	income	Thu tiền từ hóa đơn tháng 10	400000.00	2025-10-25	3	5	\N	Hoàng Văn E	0945432109	5 Đường MNO	50	\N	1	completed	2025-10-03 13:29:14.460139	\N
200	expense	Chi tiền nhập hàng tháng 10	1400000.00	2025-10-23	5	\N	10	Nhà cung cấp Khác MiscSupply	0990123456	2223 Đường Hoàng Văn Thụ	\N	50	2	completed	2025-10-03 13:29:14.460139	\N
202	income	Thu tiền từ hóa đơn HD-20251021-143828	150000.00	2025-10-21	1	2	\N	Trần Thị B	0918765432	2 Đường DEF, Quận 2, TP.HCM	52	\N	\N	completed	2025-10-21 14:38:28.639714	\N
203	income	Thu tiền từ hóa đơn HD-20251021-151248	150000.00	2025-10-21	1	1	\N	Nguyễn Văn A	0909876543	1 Đường ABC, Quận 1, TP.HCM	53	\N	1	pending	2025-10-21 15:12:48.666165	\N
204	income	Thu tiền từ hóa đơn HD-20251021-153217	150000.00	2025-10-21	1	8	\N	Bùi Thị H	0972109876	8 Đường VWX, Quận 8, TP.HCM	54	\N	1	pending	2025-10-21 15:32:17.964447	\N
205	income	Thu tiền từ hóa đơn HD-20251021-164850	1050000.00	2025-10-21	1	4	\N	Phạm Thị D	0936543210	4 Đường JKL, Quận 4, TP.HCM	55	\N	4	pending	2025-10-21 16:48:50.223786	\N
201	income	Thu tiền từ hóa đơn HD-20251021-143655	150000.00	2025-10-21	1	2	\N	Trần Thị B	0918765432	2 Đường DEF, Quận 2, TP.HCM	\N	\N	\N	completed	2025-10-21 14:36:55.162685	\N
206	income	Thu tiền từ hóa đơn HD-20251022-105323	150000.00	2025-10-22	1	2	\N	Trần Thị B	0918765432	2 Đường DEF, Quận 2, TP.HCM	\N	\N	2	completed	2025-10-22 10:53:23.389215	\N
207	income	Thu tiền từ hóa đơn HD-20251023-004246	150000.00	2025-10-23	1	2	\N	Trần Thị B	0918765432	2 Đường DEF, Quận 2, TP.HCM	58	\N	3	completed	2025-10-23 00:42:46.69192	\N
268	income	Thu tiền từ hóa đơn HD-20251121-132805	500000.00	2025-11-21	1	\N	\N	\N	\N	\N	90	\N	2	completed	2025-11-21 13:28:05.439754	\N
209	income	Thu tiền từ hóa đơn HD-20251024-163534	3000000.00	2025-10-24	1	1	\N	Nguyễn Văn A	0909876543	1 Đường ABC, Quận 1, TP.HCM	59	\N	1	completed	2025-10-24 16:35:35.00506	\N
210	income	Thu tiền từ hóa đơn HD-20251025-011802	100000.00	2025-10-25	1	1	\N	Nguyễn Văn A	0909876543	1 Đường ABC, Quận 1, TP.HCM	60	\N	1	completed	2025-10-25 01:18:02.776451	\N
213	expense	Chi tiền nhập hàng PN-1761585180950	600000.00	2025-10-28	1	\N	\N	\N	\N	\N	\N	54	2	completed	2025-10-28 00:13:00.961393	\N
214	income	Thu tiền từ hóa đơn HD-20251028-212936	2000000.00	2025-10-28	1	\N	\N	\N	\N	\N	61	\N	1	completed	2025-10-28 21:29:36.721139	\N
251	income	Thu tiền từ hóa đơn HD-20251121-130439	100000.00	2025-11-21	1	\N	\N	\N	\N	\N	80	\N	2	completed	2025-11-21 13:04:39.143303	\N
252	income	Thu tiền từ hóa đơn HD-20251121-130540	100000.00	2025-11-21	1	\N	\N	\N	\N	\N	81	\N	2	completed	2025-11-21 13:05:40.695914	\N
230	expense	Chi tiền nhập hàng PN-1761749343754	100.00	2025-10-29	1	\N	\N	\N	\N	\N	\N	\N	1	completed	2025-10-29 21:49:03.753536	\N
229	expense	Chi tiền nhập hàng PN-1761748867042	100.00	2025-10-29	1	\N	\N	\N	\N	\N	\N	\N	1	completed	2025-10-29 21:41:07.040968	\N
227	expense	Chi tiền nhập hàng PN-1761748249529	101.00	2025-10-29	1	\N	\N	\N	\N	\N	\N	\N	1	completed	2025-10-29 21:30:49.529134	\N
231	expense	Chi tiền nhập hàng PN-1761749748288	100.00	2025-10-29	20	\N	\N	\N	\N	\N	\N	\N	1	completed	2025-10-29 21:55:48.287907	\N
228	expense	Chi tiền nhập hàng PN-1761748292019	100.00	2025-10-29	1	\N	\N	\N	\N	\N	\N	\N	1	completed	2025-10-29 21:31:32.019731	\N
212	expense	Chi tiền nhập hàng PN-1761582150237	100.00	2025-10-27	1	\N	\N	\N	\N	\N	\N	\N	2	completed	2025-10-27 23:22:30.263759	\N
211	expense	Chi tiền nhập hàng PN-1761330499052	30000.00	2025-10-25	1	\N	\N	\N	\N	\N	\N	\N	1	completed	2025-10-25 01:28:19.077364	\N
226	income	Thu tiền từ hóa đơn HD-20251029-013537	20000.00	2025-10-29	1	\N	\N	\N	\N	\N	\N	\N	1	completed	2025-10-29 01:35:37.40589	\N
225	income	Thu tiền từ hóa đơn HD-20251029-005222	10000.00	2025-10-29	1	\N	\N	\N	\N	\N	\N	\N	2	completed	2025-10-29 00:52:22.393467	\N
232	income	Thu tiền từ hóa đơn HD-20251104-155218	20000.00	2025-11-04	1	\N	\N	\N	\N	\N	\N	\N	1	completed	2025-11-04 15:52:18.332743	\N
220	income	Thu tiền từ hóa đơn HD-20251028-230924	500000.00	2025-10-28	1	\N	\N	\N	\N	\N	\N	\N	1	completed	2025-10-28 23:09:24.477309	\N
233	income	Thu tiền từ hóa đơn HD-20251104-224728	10000.00	2025-11-04	1	\N	\N	\N	\N	\N	68	\N	2	completed	2025-11-04 22:47:28.61011	\N
234	income	Thu tiền từ hóa đơn HD-20251106-001011	7500000.00	2025-11-06	1	\N	\N	\N	\N	\N	69	\N	1	completed	2025-11-06 00:10:11.737483	\N
235	income	Thu tiền từ hóa đơn HD-20251106-004922	490000.00	2025-11-06	1	\N	\N	\N	\N	\N	70	\N	1	completed	2025-11-06 00:49:22.609722	\N
236	expense	Chi tiền nhập hàng PN-1762365099105	5000.00	2025-11-06	1	\N	\N	\N	\N	\N	\N	60	2	completed	2025-11-06 00:51:39.106319	\N
237	expense	Chi tiền nhập hàng PN-1762365136743	1000.00	2025-11-06	1	\N	\N	\N	\N	\N	\N	61	1	completed	2025-11-06 00:52:16.74421	\N
238	expense	Chi tiền nhập hàng PN-1762366014656	10000.00	2025-11-06	1	\N	\N	\N	\N	\N	\N	62	2	completed	2025-11-06 01:06:54.656918	\N
239	income	Thu tiền từ hóa đơn HD-20251106-010810	1000000.00	2025-11-06	1	\N	\N	\N	\N	\N	71	\N	2	completed	2025-11-06 01:08:10.998619	\N
240	expense	Chi tiền nhập hàng PN-1762490886111	20000.00	2025-11-07	20	\N	\N	\N	\N	\N	\N	63	1	completed	2025-11-07 11:48:06.111092	\N
241	expense	Chi tiền nhập hàng PN-1762491234173	2000.00	2025-11-07	1	\N	\N	\N	\N	\N	\N	64	2	completed	2025-11-07 11:53:54.173905	\N
242	income	Thu tiền từ hóa đơn HD-20251107-115437	720000.00	2025-11-07	1	\N	\N	\N	\N	\N	72	\N	1	completed	2025-11-07 11:54:37.432965	\N
243	income	Thu tiền từ hóa đơn HD-20251120-215932	50000.00	2025-11-20	1	\N	\N	\N	\N	\N	73	\N	1	completed	2025-11-20 21:59:32.462344	\N
244	income	Thu tiền từ hóa đơn HD-20251121-122140	40000.00	2025-11-21	1	\N	\N	\N	\N	\N	74	\N	3	completed	2025-11-21 12:21:41.974078	\N
245	income	Thu tiền từ hóa đơn HD-20251121-122137	40000.00	2025-11-21	1	\N	\N	\N	\N	\N	75	\N	3	completed	2025-11-21 12:21:41.915326	\N
246	income	Thu tiền từ hóa đơn HD-20251121-122648	60000.00	2025-11-21	1	\N	\N	\N	\N	\N	76	\N	1	completed	2025-11-21 12:26:48.883163	\N
247	income	Thu tiền từ hóa đơn HD-20251121-123903	100000.00	2025-11-21	1	\N	\N	\N	\N	\N	77	\N	3	completed	2025-11-21 12:39:03.457226	\N
248	income	Thu tiền từ hóa đơn HD-20251121-123951	700000.00	2025-11-21	1	\N	\N	\N	\N	\N	78	\N	1	completed	2025-11-21 12:39:51.365329	\N
249	expense	Chi tiền nhập hàng PN-1763703651955	10000.00	2025-11-21	1	\N	\N	\N	\N	\N	\N	65	1	completed	2025-11-21 12:40:51.955519	\N
250	income	Thu tiền từ hóa đơn HD-20251121-124118	100000.00	2025-11-21	1	\N	\N	\N	\N	\N	79	\N	2	completed	2025-11-21 12:41:18.176443	\N
253	income	Thu tiền từ hóa đơn HD-20251121-130939	100000.00	2025-11-21	1	\N	\N	\N	\N	\N	82	\N	2	completed	2025-11-21 13:09:39.484565	\N
254	income	Thu tiền từ hóa đơn HD-20251121-131017	700000.00	2025-11-21	1	\N	\N	\N	\N	\N	83	\N	2	pending	2025-11-21 13:10:17.210784	\N
255	expense	Chi tiền nhập hàng PN-1763705443649	3000.00	2025-11-21	1	\N	\N	\N	\N	\N	\N	66	2	completed	2025-11-21 13:10:43.649429	\N
256	income	Thu tiền từ hóa đơn HD-20251121-131107	100000.00	2025-11-21	1	\N	\N	\N	\N	\N	84	\N	2	completed	2025-11-21 13:11:07.946497	\N
257	income	Thu tiền từ hóa đơn HD-20251121-131532	50000.00	2025-11-21	1	\N	\N	\N	\N	\N	85	\N	2	completed	2025-11-21 13:15:32.350718	\N
258	expense	Chi tiền nhập hàng PN-1763705801512	2000.00	2025-11-21	1	\N	\N	\N	\N	\N	\N	67	1	completed	2025-11-21 13:16:41.512895	\N
259	income	Thu tiền từ hóa đơn HD-20251121-131656	50000.00	2025-11-21	1	\N	\N	\N	\N	\N	86	\N	2	completed	2025-11-21 13:16:56.343714	\N
260	income	Thu tiền từ hóa đơn HD-20251121-131718	100000.00	2025-11-21	1	\N	\N	\N	\N	\N	87	\N	2	pending	2025-11-21 13:17:18.146762	\N
261	expense	Chi tiền nhập hàng PN-1763705879828	3000.00	2025-11-21	1	\N	\N	\N	\N	\N	\N	68	2	completed	2025-11-21 13:17:59.829594	\N
262	expense	Chi tiền nhập hàng PN-1763705899544	500.00	2025-11-21	1	\N	\N	\N	\N	\N	\N	69	2	completed	2025-11-21 13:18:19.544731	\N
263	expense	Chi tiền nhập hàng PN-1763705927534	1600000.00	2025-11-21	1	\N	\N	\N	\N	\N	\N	70	2	completed	2025-11-21 13:18:47.534845	\N
264	income	Thu tiền từ hóa đơn HD-20251121-132048	1500000.00	2025-11-21	1	\N	\N	\N	\N	\N	88	\N	2	completed	2025-11-21 13:20:48.073837	\N
265	expense	Chi tiền nhập hàng PN-1763706077280	2800000.00	2025-11-21	1	\N	\N	\N	\N	\N	\N	71	1	completed	2025-11-21 13:21:17.27951	\N
266	income	Thu tiền từ hóa đơn HD-20251121-132333	400000.00	2025-11-21	1	\N	\N	\N	\N	\N	89	\N	1	completed	2025-11-21 13:23:33.356795	\N
267	expense	Chi tiền nhập hàng PN-1763706451672	5000.00	2025-11-21	1	\N	\N	\N	\N	\N	\N	72	1	completed	2025-11-21 13:27:31.672081	\N
269	income	Thu tiền từ hóa đơn HD-20251121-133257	60000.00	2025-11-21	1	\N	\N	\N	\N	\N	91	\N	1	completed	2025-11-21 13:32:57.740776	\N
271	expense	Chi tiền nhập hàng PN-1763706832454	800000.00	2025-11-21	1	\N	\N	\N	\N	\N	\N	73	1	completed	2025-11-21 13:33:52.454756	\N
272	income	Thu tiền từ hóa đơn HD-20251121-135050	3300000.00	2025-11-21	1	\N	\N	\N	\N	\N	93	\N	2	completed	2025-11-21 13:50:50.613383	\N
273	expense	Chi tiền nhập hàng PN-1763710851929	4005000.00	2025-11-21	20	\N	\N	\N	\N	\N	\N	74	2	completed	2025-11-21 14:40:51.928748	\N
274	expense	Chi tiền nhập hàng PN-1763711261261	5000.00	2025-11-21	20	\N	\N	\N	\N	\N	\N	75	1	completed	2025-11-21 14:47:41.261917	\N
275	income	Thu tiền từ hóa đơn HD-20251121-145526	10000.00	2025-11-21	21	\N	\N	\N	\N	\N	94	\N	4	completed	2025-11-21 14:55:26.412494	\N
276	income	Thu tiền từ hóa đơn HD-20251121-150159	510000.00	2025-11-21	21	\N	\N	\N	\N	\N	95	\N	5	completed	2025-11-21 15:01:59.324016	\N
277	income	Thu tiền từ hóa đơn HD-20251126-011426	10000.00	2025-11-26	1	\N	\N	\N	\N	\N	96	\N	1	pending	2025-11-26 01:14:26.609016	\N
278	income	Thu tiền từ hóa đơn HD-20251126-011431	10000.00	2025-11-26	1	\N	\N	\N	\N	\N	97	\N	1	pending	2025-11-26 01:14:31.449569	\N
279	expense	Chi tiền nhập hàng PN-1764135565530	100.00	2025-11-26	1	\N	\N	\N	\N	\N	\N	76	2	completed	2025-11-26 12:39:25.529827	\N
281	income	Thu tiền từ hóa đơn HD-20251126-173339	10000.00	2025-11-26	1	\N	\N	\N	\N	\N	98	\N	2	pending	2025-11-26 17:33:39.02829	\N
282	income	Thu tiền từ hóa đơn HD-20251126-173353	10000.00	2025-11-26	1	\N	\N	\N	\N	\N	99	\N	2	pending	2025-11-26 17:33:53.277183	\N
283	income	Thu tiền từ hóa đơn HD-20251126-173421	10000.00	2025-11-26	1	\N	\N	\N	\N	\N	100	\N	2	pending	2025-11-26 17:34:21.380176	\N
284	income	Thu tiền từ hóa đơn HD-20251126-173933	10000.00	2025-11-26	1	\N	\N	\N	\N	\N	101	\N	1	pending	2025-11-26 17:39:33.303693	\N
285	income	Thu tiền từ hóa đơn HD-20251126-174347	10000.00	2025-11-26	1	\N	\N	\N	\N	\N	102	\N	1	pending	2025-11-26 17:43:47.792819	\N
286	income	Thu tiền từ hóa đơn HD-20251126-174405	10000.00	2025-11-26	1	\N	\N	\N	\N	\N	103	\N	1	pending	2025-11-26 17:44:05.998467	\N
287	income	Thu tiền từ hóa đơn HD-20251126-174654	10000.00	2025-11-26	1	\N	\N	\N	\N	\N	104	\N	1	pending	2025-11-26 17:46:54.952618	\N
293	income	Thu tiền từ hóa đơn HD-20251126-181109	10000.00	2025-11-26	1	\N	\N	\N	\N	\N	110	\N	1	pending	2025-11-26 18:11:09.965978	\N
297	expense	Chi tiền nhập hàng PN-1764156168072	100.00	2025-11-26	1	\N	\N	\N	\N	\N	\N	\N	\N	completed	2025-11-26 18:22:48.072348	\N
295	expense	Chi tiền nhập hàng PN-1764155568113	100.00	2025-11-26	1	\N	\N	\N	\N	\N	\N	\N	2	completed	2025-11-26 18:12:48.112027	\N
303	income	Thu tiền từ hóa đơn HD-20251127-172627	10000.00	2025-11-27	1	\N	\N	\N	\N	\N	\N	\N	\N	pending	2025-11-27 17:26:28.000875	\N
304	income	Thu tiền từ hóa đơn HD-20251127-175137	10000.00	2025-11-27	1	\N	\N	\N	\N	\N	\N	\N	\N	pending	2025-11-27 17:51:37.618259	\N
302	income	Thu tiền từ hóa đơn HD-20251127-171959	10000.00	2025-11-27	1	\N	\N	\N	\N	\N	\N	\N	\N	pending	2025-11-27 17:19:59.69615	\N
301	income	Thu tiền từ hóa đơn HD-20251127-171827	10000.00	2025-11-27	1	\N	\N	\N	\N	\N	\N	\N	\N	pending	2025-11-27 17:18:27.999861	\N
306	income	Thu tiền từ hóa đơn HD-20251127-183238	10000.00	2025-11-27	1	1	\N	Nguyễn Văn A	0909876543	1 Đường ABC, Quận 1, TP.HCM	121	\N	\N	completed	2025-11-27 18:32:38.604637	\N
313	income	Thu tiền từ hóa đơn HD-20251127-203226	10000.00	2025-11-27	1	\N	\N	\N	\N	\N	128	\N	\N	pending	2025-11-27 20:32:27.101201	\N
311	income	Thu tiền từ hóa đơn HD-20251127-201332	10000.00	2025-11-27	1	\N	\N	\N	\N	\N	\N	\N	\N	pending	2025-11-27 20:13:32.26807	\N
310	income	Thu tiền từ hóa đơn HD-20251127-195549	30000.00	2025-11-27	1	\N	\N	\N	\N	\N	\N	\N	\N	pending	2025-11-27 19:55:49.187679	\N
309	income	Thu tiền từ hóa đơn HD-20251127-193432	10000.00	2025-11-27	1	\N	\N	\N	\N	\N	\N	\N	\N	pending	2025-11-27 19:34:32.566964	\N
307	income	Thu tiền từ hóa đơn HD-20251127-184500	10000.00	2025-11-27	1	\N	\N	\N	\N	\N	\N	\N	\N	pending	2025-11-27 18:45:00.86343	\N
308	income	Thu tiền từ hóa đơn HD-20251127-190454	10000.00	2025-11-27	1	\N	\N	\N	\N	\N	\N	\N	\N	pending	2025-11-27 19:04:54.141387	\N
305	income	Thu tiền từ hóa đơn HD-20251127-180436	20000.00	2025-11-27	1	\N	\N	\N	\N	\N	\N	\N	\N	pending	2025-11-27 18:04:37.025008	\N
300	income	Thu tiền từ hóa đơn HD-20251126-223630	10000.00	2025-11-26	1	\N	\N	\N	\N	\N	\N	\N	\N	pending	2025-11-26 22:36:30.960539	\N
299	income	Thu tiền từ hóa đơn HD-20251126-183429	10000.00	2025-11-26	1	\N	\N	\N	\N	\N	\N	\N	\N	pending	2025-11-26 18:34:29.386338	\N
298	income	Thu tiền từ hóa đơn HD-20251126-182918	10000.00	2025-11-26	1	\N	\N	\N	\N	\N	\N	\N	\N	pending	2025-11-26 18:29:18.543687	\N
289	income	Thu tiền từ hóa đơn HD-20251126-175335	10000.00	2025-11-26	1	\N	\N	\N	\N	\N	\N	\N	1	pending	2025-11-26 17:53:35.320398	\N
290	income	Thu tiền từ hóa đơn HD-20251126-175350	10000.00	2025-11-26	1	\N	\N	\N	\N	\N	\N	\N	1	pending	2025-11-26 17:53:50.892664	\N
292	income	Thu tiền từ hóa đơn HD-20251126-181043	10000.00	2025-11-26	1	\N	\N	\N	\N	\N	\N	\N	1	pending	2025-11-26 18:10:43.535963	\N
288	income	Thu tiền từ hóa đơn HD-20251126-175318	10000.00	2025-11-26	1	\N	\N	\N	\N	\N	\N	\N	1	pending	2025-11-26 17:53:18.508727	\N
291	income	Thu tiền từ hóa đơn HD-20251126-180630	10000.00	2025-11-26	1	\N	\N	\N	\N	\N	\N	\N	1	pending	2025-11-26 18:06:30.235407	\N
314	expense	Chi tiền nhập hàng PN-1764297329714	100.00	2025-11-28	1	\N	\N	\N	\N	\N	\N	\N	\N	completed	2025-11-28 09:35:29.71456	\N
280	expense	Chi tiền nhập hàng PN-1764135717884	100.00	2025-11-26	1	\N	\N	\N	\N	\N	\N	\N	1	completed	2025-11-26 12:41:57.88416	\N
294	income	Thu tiền từ hóa đơn HD-20251126-181227	10000.00	2025-11-26	1	\N	\N	\N	\N	\N	\N	\N	1	pending	2025-11-26 18:12:27.84867	\N
315	income	Thu tiền từ hóa đơn HD-20251128-093844	510000.00	2025-11-28	1	\N	\N	\N	\N	\N	\N	\N	\N	pending	2025-11-28 09:38:44.922522	\N
296	income	Thu tiền từ hóa đơn HD-20251126-181731	10000.00	2025-11-26	1	\N	\N	\N	\N	\N	\N	\N	\N	pending	2025-11-26 18:17:31.625351	\N
317	income	Thu tiền từ hóa đơn HD-20251128-100139	10000.00	2025-11-28	1	\N	\N	\N	\N	\N	131	\N	\N	pending	2025-11-28 10:01:39.089315	\N
318	income	Thu tiền từ hóa đơn HD-20251128-101047	10000.00	2025-11-28	1	\N	\N	\N	\N	\N	132	\N	\N	pending	2025-11-28 10:10:47.491633	\N
319	income	Thu tiền từ hóa đơn HD-20251128-110854	10000.00	2025-11-28	1	\N	\N	\N	\N	\N	133	\N	\N	pending	2025-11-28 11:08:54.532301	\N
316	income	Thu tiền từ hóa đơn HD-20251128-094654	10000.00	2025-11-28	1	\N	\N	\N	\N	\N	\N	\N	\N	pending	2025-11-28 09:46:54.973109	\N
270	income	Thu tiền từ hóa đơn HD-20251121-133307	3000000.00	2025-11-21	1	\N	\N	\N	\N	\N	\N	\N	1	pending	2025-11-21 13:33:07.730319	\N
312	income	Thu tiền từ hóa đơn HD-20251127-202256	10000.00	2025-11-27	1	\N	\N	\N	\N	\N	\N	\N	\N	pending	2025-11-27 20:22:56.157672	\N
320	income	Thu tiền từ hóa đơn HD-20251128-111220	10000.00	2025-11-28	1	\N	\N	\N	\N	\N	134	\N	\N	pending	2025-11-28 11:12:20.636342	\N
321	income	Thu tiền từ hóa đơn HD-20251128-111943	10000.00	2025-11-28	1	\N	\N	\N	\N	\N	\N	\N	\N	pending	2025-11-28 11:19:43.527535	\N
322	income	Thu tiền từ hóa đơn HD-20251128-113650	10000.00	2025-11-28	1	\N	\N	\N	\N	\N	136	\N	\N	pending	2025-11-28 11:36:50.177981	\N
323	income	Thu tiền từ hóa đơn HD-20251128-125745	10000.00	2025-11-28	1	\N	\N	\N	\N	\N	137	\N	\N	pending	2025-11-28 12:57:45.209201	\N
324	income	Thu tiền từ hóa đơn HD-20251128-130938	10000.00	2025-11-28	1	\N	\N	\N	\N	\N	138	\N	\N	completed	2025-11-28 13:09:38.431984	\N
325	income	Thu tiền từ hóa đơn HD-20251128-133155	10000.00	2025-11-28	1	\N	\N	\N	\N	\N	139	\N	1	completed	2025-11-28 13:31:55.906477	\N
326	expense	Chi tiền nhập hàng PN-1764311784093	100.00	2025-11-28	1	\N	\N	\N	\N	\N	\N	\N	\N	completed	2025-11-28 13:36:24.093348	\N
328	income	Thu tiền từ hóa đơn HD-20251128-134408	10000.00	2025-11-28	1	\N	\N	\N	\N	\N	140	\N	2	pending	2025-11-28 13:44:08.8975	\N
327	expense	Chi tiền nhập hàng PN-1764312228386	100.00	2025-11-28	1	\N	\N	\N	\N	\N	\N	\N	2	completed	2025-11-28 13:43:48.386798	\N
331	expense	Chi tiền nhập hàng PN-1764313451922	100.00	2025-11-28	1	\N	\N	\N	\N	\N	\N	\N	\N	completed	2025-11-28 14:04:11.922588	\N
330	expense	Chi tiền nhập hàng PN-20251128-140122	100.00	2025-11-28	1	\N	\N	\N	\N	\N	\N	\N	\N	completed	2025-11-28 14:01:22.577942	\N
329	expense	Chi tiền nhập hàng PN-1764312859230	100.00	2025-11-28	1	\N	\N	\N	\N	\N	\N	\N	2	completed	2025-11-28 13:54:19.230319	\N
333	expense	Chi tiền nhập hàng PN-1764313966954	100.00	2025-11-28	1	\N	\N	\N	\N	\N	\N	\N	\N	completed	2025-11-28 14:12:46.955114	\N
332	expense	Chi tiền nhập hàng PN-1764313628782	100.00	2025-11-28	1	\N	\N	\N	\N	\N	\N	\N	\N	completed	2025-11-28 14:07:08.782962	\N
335	expense	Chi tiền nhập hàng PN-1764315638090	100.00	2025-11-28	1	\N	\N	\N	\N	\N	\N	\N	\N	completed	2025-11-28 14:40:38.091509	\N
334	expense	Chi tiền nhập hàng PN-1764315163722	100.00	2025-11-28	1	\N	\N	\N	\N	\N	\N	\N	\N	completed	2025-11-28 14:32:43.722899	\N
336	expense	Chi tiền nhập hàng PN-1764316170498	100.00	2025-11-28	1	\N	\N	\N	\N	\N	\N	90	1	completed	2025-11-28 14:49:30.498216	\N
337	expense	Chi tiền nhập hàng PN-1764316181933	100.00	2025-11-28	1	\N	\N	\N	\N	\N	\N	91	\N	completed	2025-11-28 14:49:41.933856	\N
339	expense	Chi tiền nhập hàng PN-1764316360749	100.00	2025-11-28	1	\N	\N	\N	\N	\N	\N	\N	1	pending	2025-11-28 14:52:40.750602	\N
338	expense	Chi tiền nhập hàng PN-1764316316594	100.00	2025-11-28	1	\N	\N	\N	\N	\N	\N	\N	\N	pending	2025-11-28 14:51:56.594392	\N
340	expense	Chi tiền nhập hàng PN-1764316797752	100.00	2025-11-28	1	\N	\N	\N	\N	\N	\N	94	\N	pending	2025-11-28 14:59:57.751909	\N
341	expense	Chi tiền nhập hàng PN-1764316873677	400000.00	2025-11-28	1	\N	\N	\N	\N	\N	\N	95	1	completed	2025-11-28 15:01:13.6782	\N
342	expense	Chi tiền nhập hàng PN-1764320737806	2000.00	2025-11-28	1	\N	\N	\N	\N	\N	\N	96	\N	pending	2025-11-28 16:05:37.806014	\N
343	expense	Chi tiền nhập hàng PN-1764321194559	3000.00	2025-11-28	1	\N	\N	\N	\N	\N	\N	\N	2	pending	2025-11-28 16:13:14.559795	\N
344	expense	Chi tiền nhập hàng PN-1764321221830	5000.00	2025-11-28	1	\N	\N	\N	\N	\N	\N	98	2	pending	2025-11-28 16:13:41.831246	\N
351	expense	Chi tiền nhập hàng PN-1764707484272	6000000.00	2025-12-03	1	\N	\N	\N	\N	\N	\N	\N	1	completed	2025-12-03 03:31:24.272375	DOC-PN-1764707484272
352	income	Thu tiền từ hóa đơn HD-20251203-040402	5000000.00	2025-12-03	1	\N	\N	\N	\N	\N	141	\N	1	completed	2025-12-03 04:04:02.451987	DOC-HD-20251203-040402
353	expense	Chi tiền nhập hàng PN-1764709509387	16000000.00	2025-12-03	1	\N	\N	\N	\N	\N	\N	100	1	completed	2025-12-03 04:05:09.387723	DOC-PN-1764709509387
354	income	Thu tiền từ hóa đơn HD-20251203-040657	5000000.00	2025-12-03	1	\N	\N	\N	\N	\N	142	\N	1	completed	2025-12-03 04:06:57.349098	DOC-HD-20251203-040657
355	income	Thu tiền từ hóa đơn HD-20251203-135901	5000000.00	2025-12-03	1	\N	\N	\N	\N	\N	143	\N	1	completed	2025-12-03 13:59:01.423336	DOC-HD-20251203-135901
356	income	Thu tiền từ hóa đơn HD-20251203-140733	3000000.00	2025-12-03	1	\N	\N	\N	\N	\N	144	\N	1	completed	2025-12-03 14:07:33.421237	DOC-HD-20251203-140733
357	income	Thu tiền từ hóa đơn HD-20251203-145224	850000.00	2025-12-03	19	\N	\N	\N	\N	\N	145	\N	1	completed	2025-12-03 14:52:24.828788	DOC-HD-20251203-145224
358	expense	Chi tiền nhập hàng PN-1764749151768	110000.00	2025-12-03	19	\N	\N	\N	\N	\N	\N	101	1	completed	2025-12-03 15:05:51.768841	DOC-PN-1764749151768
359	expense	Chi tiền nhập hàng PN-1764752617212	1000.00	2025-12-03	19	\N	\N	\N	\N	\N	\N	102	1	completed	2025-12-03 16:03:37.212157	DOC-PN-1764752617212
360	income	Thu tiền từ hóa đơn HD-20251203-160353	10000.00	2025-12-03	19	\N	\N	\N	\N	\N	146	\N	1	completed	2025-12-03 16:03:53.734502	DOC-HD-20251203-160353
361	income	Thu tiền từ hóa đơn HD-20251203-160638	1100000.00	2025-12-03	19	\N	\N	\N	\N	\N	147	\N	1	completed	2025-12-03 16:06:38.666405	DOC-HD-20251203-160638
362	expense	Chi tiền nhập hàng PN-1764752833217	112000.00	2025-12-03	19	\N	\N	\N	\N	\N	\N	103	1	completed	2025-12-03 16:07:13.216957	DOC-PN-1764752833217
363	expense	Chi tiền nhập hàng PN-1764753625864	1000.00	2025-12-03	19	\N	\N	\N	\N	\N	\N	104	1	completed	2025-12-03 16:20:25.865572	DOC-PN-1764753625864
364	expense	Chi tiền nhập hàng PN-1764753877261	1000.00	2025-12-03	19	\N	\N	\N	\N	\N	\N	105	1	completed	2025-12-03 16:24:37.261583	DOC-PN-1764753877261
365	income	Thu tiền từ hóa đơn HD-20251203-162524	500000.00	2025-12-03	19	\N	\N	\N	\N	\N	148	\N	1	completed	2025-12-03 16:25:24.38895	DOC-HD-20251203-162524
366	income	Thu tiền từ hóa đơn HD-20251203-162545	640000.00	2025-12-03	19	\N	\N	\N	\N	\N	149	\N	1	completed	2025-12-03 16:25:45.650332	DOC-HD-20251203-162545
370	expense	Chi tiền nhập hàng PN-1764756617588	1000.00	2025-12-03	1	\N	\N	\N	\N	\N	\N	\N	1	completed	2025-12-03 17:10:17.587971	DOC-PN-1764756617588
371	expense	Chi tiền nhập hàng PN-1764757434851	1000.00	2025-12-03	1	\N	\N	\N	\N	\N	\N	110	1	completed	2025-12-03 17:23:54.851294	DOC-PN-1764757434851
372	expense	Chi tiền nhập hàng PN-1764757489510	5000.00	2025-12-03	1	\N	\N	\N	\N	\N	\N	111	1	completed	2025-12-03 17:24:49.510693	DOC-PN-1764757489510
373	expense	Chi tiền nhập hàng PN-1764757722273	1000.00	2025-12-03	1	\N	\N	\N	\N	\N	\N	112	1	completed	2025-12-03 17:28:42.274026	DOC-PN-1764757722273
379	expense	Chi tiền nhập hàng PN-1764758748998	2000.00	2025-12-03	1	\N	\N	\N	\N	\N	\N	118	1	completed	2025-12-03 17:45:48.998512	DOC-PN-1764758748998
381	expense	Chi tiền nhập hàng PN-1764759416866	2000.00	2025-12-03	1	\N	\N	\N	\N	\N	\N	120	1	completed	2025-12-03 17:56:56.865365	DOC-PN-1764759416866
382	income	Thu tiền từ hóa đơn HD-20251203-175823	60000.00	2025-12-03	1	\N	\N	\N	\N	\N	150	\N	1	completed	2025-12-03 17:58:23.686272	DOC-HD-20251203-175823
386	expense	Chi tiền nhập hàng PN-1764760332374	2000.00	2025-12-03	1	\N	\N	\N	\N	\N	\N	124	1	completed	2025-12-03 18:12:12.374208	DOC-PN-1764760332374
387	expense	Chi tiền nhập hàng PN-1764760405827	2000.00	2025-12-03	1	\N	\N	\N	\N	\N	\N	125	1	completed	2025-12-03 18:13:25.827329	DOC-PN-1764760405827
388	expense	Chi tiền nhập hàng PN-1764760489730	1000.00	2025-12-03	1	\N	\N	\N	\N	\N	\N	126	1	completed	2025-12-03 18:14:49.730595	DOC-PN-1764760489730
389	income	Thu tiền từ hóa đơn HD-20251203-181517	40000.00	2025-12-03	1	\N	\N	\N	\N	\N	151	\N	1	completed	2025-12-03 18:15:17.958975	DOC-HD-20251203-181517
390	expense	Chi tiền nhập hàng PN-1764760534894	2000.00	2025-12-03	1	\N	\N	\N	\N	\N	\N	127	1	completed	2025-12-03 18:15:34.894494	DOC-PN-1764760534894
391	expense	Chi tiền nhập hàng PN-1764760554147	4000.00	2025-12-03	1	\N	\N	\N	\N	\N	\N	128	1	completed	2025-12-03 18:15:54.147913	DOC-PN-1764760554147
392	income	Thu tiền từ hóa đơn HD-20251205-114600	20000.00	2025-12-05	1	\N	\N	\N	\N	\N	152	\N	2	pending	2025-12-05 11:46:00.540017	DOC-HD-20251205-114600
393	income	Thu tiền từ hóa đơn HD-20251205-114732	10000.00	2025-12-05	1	\N	\N	\N	\N	\N	153	\N	2	pending	2025-12-05 11:47:32.070193	DOC-HD-20251205-114732
395	income	Thu tiền từ hóa đơn HD-20251207-183859	10000.00	2025-12-07	1	\N	\N	\N	\N	\N	154	\N	1	completed	2025-12-07 18:38:59.825421	DOC-HD-20251207-183859
396	income	Thu tiền từ hóa đơn HD-20251207-183914	20000.00	2025-12-07	1	\N	\N	\N	\N	\N	155	\N	2	pending	2025-12-07 18:39:14.298006	DOC-HD-20251207-183914
397	income	\N	50000.00	2025-12-09	1	\N	\N	Tu	\N	\N	\N	\N	\N	completed	2025-12-09 06:41:29.55865	\N
394	expense	Chi tiền nhập hàng PN-1765105470918	1000.00	2025-12-07	1	\N	\N	\N	\N	\N	\N	129	2	pending	2025-12-07 18:04:30.91934	DOC-PN-1765105470918
399	income	Thu tiền từ hóa đơn HD-20251212-031611	10000.00	2025-12-12	1	1	\N	Nguyễn Văn A	0909876543	1 Đường ABC, Quận 1, TP.HCM	\N	\N	1	cancelled	2025-12-12 03:16:11.727677	DOC-HD-20251212-031611
400	income	Thu tiền từ hóa đơn HD-20251212-034139	10000.00	2025-12-12	1	1	\N	Nguyễn Văn A	0909876543	1 Đường ABC, Quận 1, TP.HCM	158	\N	1	pending	2025-12-12 03:41:39.869484	DOC-HD-20251212-034139
401	expense	Chi tiền nhập hàng PN-1765487585665	25000.00	2025-12-12	1	\N	\N	\N	\N	\N	\N	130	1	completed	2025-12-12 04:13:05.665006	DOC-PN-1765487585665
404	income	Thu tiền từ hóa đơn HD-20251212-063329	60000.00	2025-12-12	1	1	\N	Nguyễn Văn A	0909876543	1 Đường ABC, Quận 1, TP.HCM	159	\N	2	completed	2025-12-12 06:33:29.432523	DOC-HD-20251212-063329
405	income	Thu tiền từ hóa đơn HD-20251212-063457	40000.00	2025-12-12	1	\N	\N	\N	\N	\N	160	\N	2	pending	2025-12-12 06:34:57.487124	DOC-HD-20251212-063457
407	expense	Luong cho nhan vien thang 11	5000000.00	2025-12-12	1	\N	\N	Dang thanh tu	123456789	\N	\N	\N	1	completed	2025-12-12 06:40:05.177514	\N
416	income	Thu tiền từ hóa đơn HD-20251214-105856	40000.00	2025-12-14	1	\N	\N	\N	\N	\N	161	\N	1	completed	2025-12-14 10:58:56.253294	DOC-HD-20251214-105856
417	income	Thu tiền từ hóa đơn HD-20251214-105900	40000.00	2025-12-14	1	\N	\N	\N	\N	\N	162	\N	1	completed	2025-12-14 10:59:00.711055	DOC-HD-20251214-105900
418	income	Thu tiền từ hóa đơn HD-20251214-105920	40000.00	2025-12-14	1	\N	\N	\N	\N	\N	163	\N	1	completed	2025-12-14 10:59:20.691371	DOC-HD-20251214-105920
420	income	Thu tiền từ hóa đơn HD-20251214-110026	50000.00	2025-12-14	1	\N	\N	\N	\N	\N	165	\N	1	completed	2025-12-14 11:00:26.654028	DOC-HD-20251214-110026
419	income	Thu tiền từ hóa đơn HD-20251214-105924	40000.00	2025-12-14	1	\N	\N	\N	\N	\N	\N	\N	2	cancelled	2025-12-14 10:59:24.889134	DOC-HD-20251214-105924
421	income	Thu tiền từ hóa đơn HD-20251214-110035	40000.00	2025-12-14	1	\N	\N	\N	\N	\N	\N	\N	2	cancelled	2025-12-14 11:00:35.121917	DOC-HD-20251214-110035
422	income	Thu tiền từ hóa đơn HD-20251214-110500	40000.00	2025-12-14	1	\N	\N	\N	\N	\N	167	\N	2	pending	2025-12-14 11:05:00.462269	DOC-HD-20251214-110500
424	expense	Chi tiền nhập hàng PN-1765685297186	30000.00	2025-12-14	1	\N	\N	\N	\N	\N	\N	143	2	completed	2025-12-14 11:08:17.186075	DOC-PN-1765685297186
427	expense	Chi tiền nhập hàng PN-1765685367422	5000.00	2025-12-14	1	\N	\N	\N	\N	\N	\N	146	1	completed	2025-12-14 11:09:27.422918	DOC-PN-1765685367422
428	expense	Chi tiền nhập hàng PN-1765685456302	30000.00	2025-12-14	1	\N	\N	\N	\N	\N	\N	147	2	completed	2025-12-14 11:10:56.302226	DOC-PN-1765685456302
431	expense	Chi tiền nhập hàng PN-1765686116597	30000.00	2025-12-14	1	\N	\N	\N	\N	\N	\N	\N	1	cancelled	2025-12-14 11:21:56.596521	DOC-PN-1765686116597
433	income	Thu tiền từ hóa đơn HD-20251214-112555	50000.00	2025-12-14	1	\N	\N	\N	\N	\N	168	\N	1	completed	2025-12-14 11:25:55.593846	DOC-HD-20251214-112555
406	expense	Chi tiền nhập hàng PN-1765496223214	2000000.00	2025-12-12	1	\N	\N	\N	\N	\N	\N	\N	1	cancelled	2025-12-12 06:37:03.214382	DOC-PN-1765496223214
434	income	Thu tiền từ hóa đơn HD-20251214-115044	100000.00	2025-12-14	1	\N	\N	\N	\N	\N	169	\N	1	completed	2025-12-14 11:50:44.35512	DOC-HD-20251214-115044
403	expense	Chi tiền nhập hàng PN-1765495918782	125000.00	2025-12-12	1	\N	\N	\N	\N	\N	\N	\N	1	cancelled	2025-12-12 06:31:58.782141	DOC-PN-1765495918782
432	expense	Chi tiền nhập hàng PN-1765686338155	30000.00	2025-12-14	1	\N	\N	\N	\N	\N	\N	151	1	completed	2025-12-14 11:25:38.154966	DOC-PN-1765686338155
435	expense	Chi tiền nhập hàng PN-1765687854937	60000.00	2025-12-14	1	\N	\N	\N	\N	\N	\N	152	2	completed	2025-12-14 11:50:54.936932	DOC-PN-1765687854937
436	income	Thu tiền từ hóa đơn HD-20251214-120242	900000.00	2025-12-14	1	\N	\N	\N	\N	\N	170	\N	1	completed	2025-12-14 12:02:42.31114	DOC-HD-20251214-120242
437	expense	Chi tiền nhập hàng PN-1765688996214	1110000.00	2025-12-14	1	\N	\N	\N	\N	\N	\N	153	1	completed	2025-12-14 12:09:56.213723	DOC-PN-1765688996214
438	income	Thu tiền từ hóa đơn HD-20251214-121823	2500000.00	2025-12-14	1	\N	\N	\N	\N	\N	171	\N	1	completed	2025-12-14 12:18:23.104338	DOC-HD-20251214-121823
439	income	Thu tiền từ hóa đơn HD-20251214-150035	100000.00	2025-12-14	19	\N	\N	\N	\N	\N	172	\N	2	pending	2025-12-14 15:00:35.704633	DOC-HD-20251214-150035
440	expense	Chi tiền nhập hàng PN-1765700793899	30000.00	2025-12-14	19	\N	\N	\N	\N	\N	\N	154	2	completed	2025-12-14 15:26:33.900475	DOC-PN-1765700793899
441	expense	Chi tiền nhập hàng PN-1765700824987	600000.00	2025-12-14	19	\N	\N	\N	\N	\N	\N	155	1	completed	2025-12-14 15:27:04.987708	DOC-PN-1765700824987
442	income	Thu tiền từ hóa đơn HD-20251214-154958	100000.00	2025-12-14	1	\N	\N	\N	\N	\N	173	\N	2	completed	2025-12-14 15:49:58.114467	DOC-HD-20251214-154958
443	income	Thu tiền từ hóa đơn HD-20251214-163447	450000.00	2025-12-14	21	\N	\N	\N	\N	\N	174	\N	1	completed	2025-12-14 16:34:47.695152	DOC-HD-20251214-163447
444	expense	Chi tiền nhập hàng PN-1765705828152	1500000.00	2025-12-14	1	\N	\N	\N	\N	\N	\N	156	1	completed	2025-12-14 16:50:28.152258	DOC-PN-1765705828152
445	income	Thu tiền từ hóa đơn HD-20251214-165053	2500000.00	2025-12-14	1	\N	\N	\N	\N	\N	175	\N	1	completed	2025-12-14 16:50:53.653706	DOC-HD-20251214-165053
447	income	Thu tiền từ hóa đơn HD-20251214-171410	50000.00	2025-12-14	1	\N	\N	\N	\N	\N	\N	\N	1	cancelled	2025-12-14 17:14:10.590706	DOC-HD-20251214-171410
446	income	Thu tiền từ hóa đơn HD-20251214-165317	50000.00	2025-12-14	1	\N	\N	\N	\N	\N	\N	\N	1	cancelled	2025-12-14 16:53:17.234699	DOC-HD-20251214-165317
448	income	Thu tiền từ hóa đơn HD-20251215-015221	100000.00	2025-12-15	1	16	\N	Nguyễn Thanh Trọng	0912345678	Phú An, Thành phố Hồ Chí Minh	\N	\N	1	cancelled	2025-12-15 01:52:21.339583	DOC-HD-20251215-015221
449	expense	Chi tiền nhập hàng PN-1765753786152	450000.00	2025-12-15	1	\N	\N	\N	\N	\N	\N	157	2	completed	2025-12-15 06:09:46.153096	DOC-PN-1765753786152
450	income	Thu tiền từ hóa đơn HD-20251215-063509	10000.00	2025-12-15	1	16	\N	Nguyễn Thanh Trọng	0912345678	Phú An, Thành phố Hồ Chí Minh	179	\N	2	completed	2025-12-15 06:35:09.992702	DOC-HD-20251215-063509
451	income	Thu tiền từ hóa đơn HD-20251215-093356	50000.00	2025-12-15	1	16	\N	Nguyễn Thanh Trọng	0912345678	Phú An, Thành phố Hồ Chí Minh	180	\N	2	completed	2025-12-15 09:33:56.50797	DOC-HD-20251215-093356
452	expense	Chi tiền nhập hàng PN-1765769066891	180000.00	2025-12-15	1	\N	\N	\N	\N	\N	\N	158	1	completed	2025-12-15 10:24:26.891381	DOC-PN-1765769066891
453	income	Thu tiền từ hóa đơn HD-20251215-102512	100000.00	2025-12-15	1	16	\N	Nguyễn Thanh Trọng	0912345678	Phú An, Thành phố Hồ Chí Minh	181	\N	2	pending	2025-12-15 10:25:12.174659	DOC-HD-20251215-102512
\.


--
-- TOC entry 5064 (class 0 OID 33267)
-- Dependencies: 240
-- Data for Name: order_details; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.order_details (order_detail_id, order_id, product_id, quantity, price, created_at) FROM stdin;
1	1	1	2	150000.00	2025-10-03 13:29:14.460139
2	1	4	1	50000.00	2025-10-03 13:29:14.460139
3	2	3	1	500000.00	2025-10-03 13:29:14.460139
4	3	2	3	200000.00	2025-10-03 13:29:14.460139
5	4	5	2	100000.00	2025-10-03 13:29:14.460139
6	5	6	1	80000.00	2025-10-03 13:29:14.460139
7	6	7	1	2000000.00	2025-10-03 13:29:14.460139
8	7	8	4	150000.00	2025-10-03 13:29:14.460139
9	8	9	5	40000.00	2025-10-03 13:29:14.460139
10	9	10	2	300000.00	2025-10-03 13:29:14.460139
11	10	11	3	120000.00	2025-10-03 13:29:14.460139
12	11	12	1	250000.00	2025-10-03 13:29:14.460139
13	12	13	10	100000.00	2025-10-03 13:29:14.460139
14	13	14	2	80000.00	2025-10-03 13:29:14.460139
15	14	15	5	300000.00	2025-10-03 13:29:14.460139
16	15	16	4	150000.00	2025-10-03 13:29:14.460139
17	16	17	3	50000.00	2025-10-03 13:29:14.460139
18	17	18	10	30000.00	2025-10-03 13:29:14.460139
19	18	19	2	100000.00	2025-10-03 13:29:14.460139
20	19	20	1	500000.00	2025-10-03 13:29:14.460139
21	20	1	3	150000.00	2025-10-03 13:29:14.460139
22	21	2	2	200000.00	2025-10-03 13:29:14.460139
23	22	3	1	500000.00	2025-10-03 13:29:14.460139
24	23	4	5	50000.00	2025-10-03 13:29:14.460139
25	24	5	2	100000.00	2025-10-03 13:29:14.460139
26	25	6	3	80000.00	2025-10-03 13:29:14.460139
27	26	7	1	2000000.00	2025-10-03 13:29:14.460139
28	27	8	4	150000.00	2025-10-03 13:29:14.460139
29	28	9	5	40000.00	2025-10-03 13:29:14.460139
30	29	10	2	300000.00	2025-10-03 13:29:14.460139
31	30	11	3	120000.00	2025-10-03 13:29:14.460139
32	31	12	1	250000.00	2025-10-03 13:29:14.460139
33	32	13	10	100000.00	2025-10-03 13:29:14.460139
34	33	14	2	80000.00	2025-10-03 13:29:14.460139
35	34	15	5	300000.00	2025-10-03 13:29:14.460139
36	35	16	4	150000.00	2025-10-03 13:29:14.460139
37	36	17	3	50000.00	2025-10-03 13:29:14.460139
38	37	18	10	30000.00	2025-10-03 13:29:14.460139
39	38	19	2	100000.00	2025-10-03 13:29:14.460139
40	39	20	1	500000.00	2025-10-03 13:29:14.460139
41	40	1	4	150000.00	2025-10-03 13:29:14.460139
42	41	2	3	200000.00	2025-10-03 13:29:14.460139
43	42	3	2	500000.00	2025-10-03 13:29:14.460139
44	43	4	6	50000.00	2025-10-03 13:29:14.460139
45	44	5	3	100000.00	2025-10-03 13:29:14.460139
46	45	6	4	80000.00	2025-10-03 13:29:14.460139
47	46	7	2	2000000.00	2025-10-03 13:29:14.460139
48	47	8	5	150000.00	2025-10-03 13:29:14.460139
49	48	9	6	40000.00	2025-10-03 13:29:14.460139
51	50	11	4	120000.00	2025-10-03 13:29:14.460139
52	1	12	2	250000.00	2025-10-03 13:29:14.460139
53	2	13	11	100000.00	2025-10-03 13:29:14.460139
54	3	14	3	80000.00	2025-10-03 13:29:14.460139
55	4	15	6	300000.00	2025-10-03 13:29:14.460139
56	5	16	5	150000.00	2025-10-03 13:29:14.460139
57	6	17	4	50000.00	2025-10-03 13:29:14.460139
58	7	18	11	30000.00	2025-10-03 13:29:14.460139
59	8	19	3	100000.00	2025-10-03 13:29:14.460139
60	9	20	2	500000.00	2025-10-03 13:29:14.460139
61	10	1	5	150000.00	2025-10-03 13:29:14.460139
63	52	1	1	150000.00	2025-10-21 14:38:28.659623
64	53	1	1	150000.00	2025-10-21 15:12:48.703859
66	55	1	1	150000.00	2025-10-21 16:48:50.330185
67	55	2	2	200000.00	2025-10-21 16:48:50.341096
68	55	3	1	500000.00	2025-10-21 16:48:50.344133
70	58	1	1	150000.00	2025-10-23 00:42:46.754211
87	49	10	3	300000.00	2025-11-04 22:47:12.948646
89	68	21	1	10000.00	2025-11-04 22:47:41.386702
90	61	20	1	500000.00	2025-11-04 22:47:58.776003
91	60	19	10	100000.00	2025-11-04 22:48:14.144696
92	59	18	10	30000.00	2025-11-04 22:48:36.04585
93	54	13	1	100000.00	2025-11-04 22:49:03.265218
94	69	20	15	500000.00	2025-11-06 00:10:11.78922
95	70	21	49	10000.00	2025-11-06 00:49:22.63697
97	71	21	100	10000.00	2025-11-07 11:32:02.881245
98	72	21	2	10000.00	2025-11-07 11:54:37.474708
99	72	20	1	500000.00	2025-11-07 11:54:37.4847
100	72	19	2	100000.00	2025-11-07 11:54:37.491316
101	73	21	5	10000.00	2025-11-20 21:59:32.521012
102	74	21	4	10000.00	2025-11-21 12:21:42.17804
103	75	21	4	10000.00	2025-11-21 12:21:42.178626
104	76	21	6	10000.00	2025-11-21 12:26:48.902856
105	77	21	10	10000.00	2025-11-21 12:39:03.477264
106	78	21	70	10000.00	2025-11-21 12:39:51.373452
107	79	21	10	10000.00	2025-11-21 12:41:18.196772
110	82	21	10	10000.00	2025-11-21 13:09:39.506949
111	83	21	70	10000.00	2025-11-21 13:10:17.213546
112	84	21	10	10000.00	2025-11-21 13:11:07.9666
113	85	21	5	10000.00	2025-11-21 13:15:32.371123
114	86	21	5	10000.00	2025-11-21 13:16:56.362031
115	87	21	10	10000.00	2025-11-21 13:17:18.150176
116	88	20	3	500000.00	2025-11-21 13:20:48.093312
117	89	21	40	10000.00	2025-11-21 13:23:33.371127
118	90	21	50	10000.00	2025-11-21 13:28:05.461349
119	91	21	6	10000.00	2025-11-21 13:32:57.771977
121	93	21	80	10000.00	2025-11-21 13:50:50.632567
122	93	20	5	500000.00	2025-11-21 13:50:50.645646
123	94	21	1	10000.00	2025-11-21 14:55:26.435736
124	95	20	1	500000.00	2025-11-21 15:01:59.344135
125	95	21	1	10000.00	2025-11-21 15:01:59.354102
126	96	21	1	10000.00	2025-11-26 01:14:26.677775
127	97	21	1	10000.00	2025-11-26 01:14:31.454883
128	98	21	1	10000.00	2025-11-26 17:33:39.080416
129	99	21	1	10000.00	2025-11-26 17:33:53.279477
130	100	21	1	10000.00	2025-11-26 17:34:21.382597
131	101	21	1	10000.00	2025-11-26 17:39:33.329535
133	103	21	1	10000.00	2025-11-26 17:44:06.015289
134	104	21	1	10000.00	2025-11-26 17:46:54.977206
151	121	21	1	10000.00	2025-11-27 18:32:38.651891
159	128	21	1	10000.00	2025-11-28 09:10:12.600284
162	110	21	1	10000.00	2025-11-28 09:38:00.602788
163	102	21	1	10000.00	2025-11-28 09:38:11.984848
167	131	21	1	10000.00	2025-11-28 10:01:39.109758
169	133	21	1	10000.00	2025-11-28 11:08:54.556703
172	134	21	1	10000.00	2025-11-28 11:13:55.365655
174	132	21	1	10000.00	2025-11-28 11:19:34.368164
176	136	21	1	10000.00	2025-11-28 11:36:50.206062
177	137	21	1	10000.00	2025-11-28 12:57:45.257511
178	138	21	1	10000.00	2025-11-28 13:09:38.474115
179	139	21	1	10000.00	2025-11-28 13:31:55.992505
180	140	21	1	10000.00	2025-11-28 13:44:08.920629
181	141	20	10	500000.00	2025-12-03 04:04:02.48491
182	142	20	10	500000.00	2025-12-03 04:06:57.370909
183	143	20	10	500000.00	2025-12-03 13:59:01.474739
184	144	20	6	500000.00	2025-12-03 14:07:33.425859
185	145	21	85	10000.00	2025-12-03 14:52:24.856733
186	146	21	1	10000.00	2025-12-03 16:03:53.963211
187	147	21	110	10000.00	2025-12-03 16:06:38.684284
188	148	21	50	10000.00	2025-12-03 16:25:24.407004
189	149	21	64	10000.00	2025-12-03 16:25:45.653586
190	150	21	6	10000.00	2025-12-03 17:58:23.710334
191	151	21	4	10000.00	2025-12-03 18:15:17.984901
192	152	21	2	10000.00	2025-12-05 11:46:00.601078
193	153	21	1	10000.00	2025-12-05 11:47:32.097198
195	155	21	2	10000.00	2025-12-07 18:39:14.323436
197	154	21	1	10000.00	2025-12-08 08:06:32.025763
201	158	21	1	10000.00	2025-12-12 03:41:48.492626
202	159	25	1	40000.00	2025-12-12 06:33:29.477487
203	159	21	2	10000.00	2025-12-12 06:33:29.493946
204	160	25	1	40000.00	2025-12-12 06:34:57.492813
205	161	25	1	40000.00	2025-12-14 10:58:56.277441
206	162	25	1	40000.00	2025-12-14 10:59:00.728555
207	163	25	1	40000.00	2025-12-14 10:59:20.708845
209	165	24	1	50000.00	2025-12-14 11:00:26.666004
211	167	25	1	40000.00	2025-12-14 11:05:00.484533
214	168	26	1	50000.00	2025-12-14 11:26:18.591515
215	169	26	2	50000.00	2025-12-14 11:50:44.375831
216	170	26	18	50000.00	2025-12-14 12:02:42.326052
217	171	20	5	500000.00	2025-12-14 12:18:23.134135
218	172	26	1	50000.00	2025-12-14 15:00:35.757254
219	172	24	1	50000.00	2025-12-14 15:00:35.780267
220	173	26	1	50000.00	2025-12-14 15:49:58.148657
221	173	24	1	50000.00	2025-12-14 15:49:58.159178
222	174	26	9	50000.00	2025-12-14 16:34:47.728504
229	175	26	50	50000.00	2025-12-15 02:00:20.511394
230	179	21	1	10000.00	2025-12-15 06:35:10.046925
231	180	26	1	50000.00	2025-12-15 09:33:56.596733
232	181	26	1	50000.00	2025-12-15 10:25:12.181446
233	181	24	1	50000.00	2025-12-15 10:25:12.189818
\.


--
-- TOC entry 5062 (class 0 OID 33232)
-- Dependencies: 238
-- Data for Name: orders; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.orders (order_id, order_number, customer_id, employee_id, order_date, total_amount, payment_method_id, status, promotion_id, created_at, updated_at) FROM stdin;
1	ORD-202501-001	1	2	2025-01-05 00:00:00	300000.00	1	completed	4	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
2	ORD-202501-002	2	3	2025-01-10 00:00:00	500000.00	2	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
3	ORD-202501-003	3	2	2025-01-15 00:00:00	200000.00	1	completed	4	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
4	ORD-202501-004	4	3	2025-01-20 00:00:00	400000.00	3	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
5	ORD-202501-005	5	2	2025-01-25 00:00:00	150000.00	1	completed	4	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
6	ORD-202502-001	6	3	2025-02-05 00:00:00	350000.00	2	completed	6	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
7	ORD-202502-002	7	2	2025-02-10 00:00:00	450000.00	1	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
8	ORD-202502-003	8	3	2025-02-15 00:00:00	250000.00	4	completed	6	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
9	ORD-202502-004	9	2	2025-02-20 00:00:00	550000.00	2	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
10	ORD-202502-005	10	3	2025-02-25 00:00:00	100000.00	1	completed	6	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
11	ORD-202503-001	11	2	2025-03-05 00:00:00	400000.00	3	completed	10	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
12	ORD-202503-002	12	3	2025-03-10 00:00:00	300000.00	1	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
13	ORD-202503-003	13	2	2025-03-15 00:00:00	600000.00	5	completed	10	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
14	ORD-202503-004	14	3	2025-03-20 00:00:00	200000.00	2	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
15	ORD-202503-005	15	2	2025-03-25 00:00:00	450000.00	1	completed	10	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
16	ORD-202504-001	1	3	2025-04-05 00:00:00	550000.00	4	completed	3	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
17	ORD-202504-002	2	2	2025-04-10 00:00:00	250000.00	1	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
18	ORD-202504-003	3	3	2025-04-15 00:00:00	350000.00	6	completed	3	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
19	ORD-202504-004	4	2	2025-04-20 00:00:00	650000.00	2	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
20	ORD-202504-005	5	3	2025-04-25 00:00:00	150000.00	1	completed	3	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
21	ORD-202505-001	6	2	2025-05-05 00:00:00	500000.00	3	completed	9	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
22	ORD-202505-002	7	3	2025-05-10 00:00:00	400000.00	1	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
23	ORD-202505-003	8	2	2025-05-15 00:00:00	700000.00	5	completed	9	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
24	ORD-202505-004	9	3	2025-05-20 00:00:00	300000.00	2	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
25	ORD-202505-005	10	2	2025-05-25 00:00:00	550000.00	1	completed	9	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
27	ORD-202506-002	12	2	2025-06-10 00:00:00	350000.00	1	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
29	ORD-202506-004	14	2	2025-06-20 00:00:00	750000.00	2	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
31	ORD-202507-001	1	2	2025-07-05 00:00:00	650000.00	5	completed	7	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
32	ORD-202507-002	2	3	2025-07-10 00:00:00	400000.00	1	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
33	ORD-202507-003	3	2	2025-07-15 00:00:00	550000.00	8	completed	7	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
34	ORD-202507-004	4	3	2025-07-20 00:00:00	850000.00	2	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
35	ORD-202507-005	5	2	2025-07-25 00:00:00	250000.00	1	completed	7	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
37	ORD-202508-002	7	2	2025-08-10 00:00:00	450000.00	1	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
39	ORD-202508-004	9	2	2025-08-20 00:00:00	900000.00	2	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
42	ORD-202509-002	12	3	2025-09-10 00:00:00	500000.00	1	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
44	ORD-202509-004	14	3	2025-09-20 00:00:00	950000.00	2	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
46	ORD-202510-001	1	3	2025-10-05 00:00:00	800000.00	8	completed	8	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
47	ORD-202510-002	2	2	2025-10-10 00:00:00	550000.00	1	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
48	ORD-202510-003	3	3	2025-10-15 00:00:00	700000.00	1	completed	8	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
50	ORD-202510-005	5	3	2025-10-25 00:00:00	400000.00	1	completed	8	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
55	HD-20251021-164850	4	1	2025-10-21 00:00:00	1050000.00	4	pending	4	2025-10-21 16:48:50.223786	2025-10-21 16:48:50.223786
71	HD-20251106-010810	1	1	2025-11-06 01:08:10.998619	1000000.00	2	completed	\N	2025-11-06 01:08:10.998619	2025-11-06 01:08:10.998619
49	ORD-202510-004	1	2	2025-10-20 00:00:00	900000.00	2	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
68	HD-20251104-224728	2	1	2025-11-04 22:47:28.61011	10000.00	2	completed	\N	2025-11-04 22:47:28.61011	2025-11-04 22:47:28.61011
69	HD-20251106-001011	\N	1	2025-11-06 00:10:11.737483	7500000.00	1	completed	\N	2025-11-06 00:10:11.737483	2025-11-06 00:10:11.737483
70	HD-20251106-004922	\N	1	2025-11-06 00:49:22.609722	490000.00	1	completed	\N	2025-11-06 00:49:22.609722	2025-11-06 00:49:22.609722
61	HD-20251028-212936	7	1	2025-10-28 00:00:00	500000.00	1	completed	\N	2025-10-28 21:29:36.721139	2025-10-28 21:29:36.721139
60	HD-20251025-011802	2	1	2025-10-25 00:00:00	1000000.00	1	completed	\N	2025-10-25 01:18:02.776451	2025-10-25 01:18:02.776451
59	HD-20251024-163534	2	1	2025-10-24 00:00:00	300000.00	1	completed	\N	2025-10-24 16:35:35.00506	2025-10-24 16:35:35.00506
72	HD-20251107-115437	\N	1	2025-11-07 11:54:37.432965	720000.00	1	completed	\N	2025-11-07 11:54:37.432965	2025-11-07 11:54:37.432965
73	HD-20251120-215932	\N	1	2025-11-20 21:59:32.462344	50000.00	1	completed	\N	2025-11-20 21:59:32.462344	2025-11-20 21:59:32.462344
74	HD-20251121-122140	\N	1	2025-11-21 12:21:41.974078	40000.00	3	completed	\N	2025-11-21 12:21:41.974078	2025-11-21 12:21:41.974078
75	HD-20251121-122137	\N	1	2025-11-21 12:21:41.915326	40000.00	3	completed	\N	2025-11-21 12:21:41.915326	2025-11-21 12:21:41.915326
76	HD-20251121-122648	\N	1	2025-11-21 12:26:48.883163	60000.00	1	completed	\N	2025-11-21 12:26:48.883163	2025-11-21 12:26:48.883163
77	HD-20251121-123903	\N	1	2025-11-21 12:39:03.457226	100000.00	3	completed	\N	2025-11-21 12:39:03.457226	2025-11-21 12:39:03.457226
78	HD-20251121-123951	\N	1	2025-11-21 12:39:51.365329	700000.00	1	completed	\N	2025-11-21 12:39:51.365329	2025-11-21 12:39:51.365329
79	HD-20251121-124118	\N	1	2025-11-21 12:41:18.176443	100000.00	2	completed	\N	2025-11-21 12:41:18.176443	2025-11-21 12:41:18.176443
41	ORD-202509-001	11	2	2025-09-05 00:00:00	750000.00	7	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
43	ORD-202509-003	13	2	2025-09-15 00:00:00	650000.00	10	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
45	ORD-202509-005	15	2	2025-09-25 00:00:00	350000.00	1	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
52	HD-20251021-143828	2	1	2025-10-21 00:00:00	150000.00	\N	completed	\N	2025-10-21 14:38:28.639714	2025-10-21 14:38:28.639714
58	HD-20251023-004246	2	1	2025-10-23 00:00:00	150000.00	3	completed	\N	2025-10-23 00:42:46.69192	2025-10-23 00:42:46.69192
54	HD-20251021-153217	8	1	2025-10-21 00:00:00	100000.00	1	completed	\N	2025-10-21 15:32:17.964447	2025-10-21 15:32:17.964447
80	HD-20251121-130439	\N	1	2025-11-21 13:04:39.143303	100000.00	2	completed	\N	2025-11-21 13:04:39.143303	2025-11-21 13:04:39.143303
81	HD-20251121-130540	\N	1	2025-11-21 13:05:40.695914	100000.00	2	completed	\N	2025-11-21 13:05:40.695914	2025-11-21 13:05:40.695914
82	HD-20251121-130939	\N	1	2025-11-21 13:09:39.484565	100000.00	2	completed	\N	2025-11-21 13:09:39.484565	2025-11-21 13:09:39.484565
83	HD-20251121-131017	\N	1	2025-11-21 13:10:17.210784	700000.00	2	pending	\N	2025-11-21 13:10:17.210784	2025-11-21 13:10:17.210784
84	HD-20251121-131107	\N	1	2025-11-21 13:11:07.946497	100000.00	2	completed	\N	2025-11-21 13:11:07.946497	2025-11-21 13:11:07.946497
85	HD-20251121-131532	\N	1	2025-11-21 13:15:32.350718	50000.00	2	completed	\N	2025-11-21 13:15:32.350718	2025-11-21 13:15:32.350718
86	HD-20251121-131656	\N	1	2025-11-21 13:16:56.343714	50000.00	2	completed	\N	2025-11-21 13:16:56.343714	2025-11-21 13:16:56.343714
87	HD-20251121-131718	\N	1	2025-11-21 13:17:18.146762	100000.00	2	pending	\N	2025-11-21 13:17:18.146762	2025-11-21 13:17:18.146762
88	HD-20251121-132048	\N	1	2025-11-21 13:20:48.073837	1500000.00	2	completed	\N	2025-11-21 13:20:48.073837	2025-11-21 13:20:48.073837
89	HD-20251121-132333	\N	1	2025-11-21 13:23:33.356795	400000.00	1	completed	\N	2025-11-21 13:23:33.356795	2025-11-21 13:23:33.356795
90	HD-20251121-132805	\N	1	2025-11-21 13:28:05.439754	500000.00	2	completed	\N	2025-11-21 13:28:05.439754	2025-11-21 13:28:05.439754
91	HD-20251121-133257	\N	1	2025-11-21 13:32:57.740776	60000.00	1	completed	\N	2025-11-21 13:32:57.740776	2025-11-21 13:32:57.740776
93	HD-20251121-135050	\N	1	2025-11-21 13:50:50.613383	3300000.00	2	completed	\N	2025-11-21 13:50:50.613383	2025-11-21 13:50:50.613383
94	HD-20251121-145526	\N	21	2025-11-21 14:55:26.412494	10000.00	4	completed	\N	2025-11-21 14:55:26.412494	2025-11-21 14:55:26.412494
95	HD-20251121-150159	\N	21	2025-11-21 15:01:59.324016	510000.00	5	completed	\N	2025-11-21 15:01:59.324016	2025-11-21 15:01:59.324016
96	HD-20251126-011426	\N	1	2025-11-26 01:14:26.609016	10000.00	1	pending	\N	2025-11-26 01:14:26.609016	2025-11-26 01:14:26.609016
97	HD-20251126-011431	\N	1	2025-11-26 01:14:31.449569	10000.00	1	pending	\N	2025-11-26 01:14:31.449569	2025-11-26 01:14:31.449569
98	HD-20251126-173339	\N	1	2025-11-26 17:33:39.02829	10000.00	2	pending	\N	2025-11-26 17:33:39.02829	2025-11-26 17:33:39.02829
99	HD-20251126-173353	\N	1	2025-11-26 17:33:53.277183	10000.00	2	pending	\N	2025-11-26 17:33:53.277183	2025-11-26 17:33:53.277183
100	HD-20251126-173421	\N	1	2025-11-26 17:34:21.380176	10000.00	2	pending	\N	2025-11-26 17:34:21.380176	2025-11-26 17:34:21.380176
101	HD-20251126-173933	\N	1	2025-11-26 17:39:33.303693	10000.00	1	pending	\N	2025-11-26 17:39:33.303693	2025-11-26 17:39:33.303693
103	HD-20251126-174405	\N	1	2025-11-26 17:44:05.998467	10000.00	1	pending	\N	2025-11-26 17:44:05.998467	2025-11-26 17:44:05.998467
104	HD-20251126-174654	\N	1	2025-11-26 17:46:54.952618	10000.00	1	pending	\N	2025-11-26 17:46:54.952618	2025-11-26 17:46:54.952618
121	HD-20251127-183238	1	1	2025-11-27 18:32:38.604637	10000.00	\N	completed	\N	2025-11-27 18:32:38.604637	2025-11-27 18:32:38.604637
134	HD-20251128-111220	\N	1	2025-11-28 11:12:20.636342	10000.00	\N	completed	\N	2025-11-28 11:12:20.636342	2025-11-28 11:12:48.011542
154	HD-20251207-183859	\N	1	2025-12-07 18:38:59.825421	10000.00	1	completed	\N	2025-12-07 18:38:59.825421	2025-12-07 18:38:59.825421
132	HD-20251128-101047	\N	1	2025-11-28 10:10:47.491633	10000.00	\N	completed	\N	2025-11-28 10:10:47.491633	2025-11-28 11:05:15.212131
110	HD-20251126-181109	\N	1	2025-11-26 18:11:09.965978	10000.00	1	completed	\N	2025-11-26 18:11:09.965978	2025-11-26 18:11:09.965978
102	HD-20251126-174347	\N	1	2025-11-26 17:43:47.792819	10000.00	1	completed	\N	2025-11-26 17:43:47.792819	2025-11-26 17:43:47.792819
131	HD-20251128-100139	\N	1	2025-11-28 10:01:39.089315	10000.00	\N	completed	\N	2025-11-28 10:01:39.089315	2025-11-28 10:56:12.011628
128	HD-20251127-203226	1	1	2025-11-27 20:32:27.101201	10000.00	2	completed	\N	2025-11-27 20:32:27.101201	2025-11-28 11:05:06.662048
158	HD-20251212-034139	1	1	2025-12-12 03:41:39.869484	10000.00	1	pending	\N	2025-12-12 03:41:39.869484	2025-12-12 03:41:39.869484
133	HD-20251128-110854	\N	1	2025-11-28 11:08:54.532301	10000.00	\N	completed	\N	2025-11-28 11:08:54.532301	2025-11-28 11:09:21.74786
155	HD-20251207-183914	\N	1	2025-12-07 18:39:14.298006	20000.00	2	pending	\N	2025-12-07 18:39:14.298006	2025-12-07 18:39:14.298006
136	HD-20251128-113650	\N	1	2025-11-28 11:36:50.177981	10000.00	\N	pending	\N	2025-11-28 11:36:50.177981	2025-11-28 11:36:50.177981
137	HD-20251128-125745	\N	1	2025-11-28 12:57:45.209201	10000.00	\N	pending	\N	2025-11-28 12:57:45.209201	2025-11-28 12:57:45.209201
138	HD-20251128-130938	\N	1	2025-11-28 13:09:38.431984	10000.00	\N	completed	\N	2025-11-28 13:09:38.431984	2025-11-28 13:09:38.431984
139	HD-20251128-133155	\N	1	2025-11-28 13:31:55.906477	10000.00	1	completed	\N	2025-11-28 13:31:55.906477	2025-11-28 13:31:55.906477
140	HD-20251128-134408	\N	1	2025-11-28 13:44:08.8975	10000.00	2	pending	\N	2025-11-28 13:44:08.8975	2025-11-28 13:44:08.8975
141	HD-20251203-040402	\N	1	2025-12-03 04:04:02.451987	5000000.00	1	completed	\N	2025-12-03 04:04:02.451987	2025-12-03 04:04:02.451987
142	HD-20251203-040657	\N	1	2025-12-03 04:06:57.349098	5000000.00	1	completed	\N	2025-12-03 04:06:57.349098	2025-12-03 04:06:57.349098
143	HD-20251203-135901	\N	1	2025-12-03 13:59:01.423336	5000000.00	1	completed	\N	2025-12-03 13:59:01.423336	2025-12-03 13:59:01.423336
144	HD-20251203-140733	\N	1	2025-12-03 14:07:33.421237	3000000.00	1	completed	\N	2025-12-03 14:07:33.421237	2025-12-03 14:07:33.421237
145	HD-20251203-145224	\N	19	2025-12-03 14:52:24.828788	850000.00	1	completed	\N	2025-12-03 14:52:24.828788	2025-12-03 14:52:24.828788
146	HD-20251203-160353	\N	19	2025-12-03 16:03:53.734502	10000.00	1	completed	\N	2025-12-03 16:03:53.734502	2025-12-03 16:03:53.734502
147	HD-20251203-160638	\N	19	2025-12-03 16:06:38.666405	1100000.00	1	completed	\N	2025-12-03 16:06:38.666405	2025-12-03 16:06:38.666405
148	HD-20251203-162524	\N	19	2025-12-03 16:25:24.38895	500000.00	1	completed	\N	2025-12-03 16:25:24.38895	2025-12-03 16:25:24.38895
149	HD-20251203-162545	\N	19	2025-12-03 16:25:45.650332	640000.00	1	completed	\N	2025-12-03 16:25:45.650332	2025-12-03 16:25:45.650332
150	HD-20251203-175823	\N	1	2025-12-03 17:58:23.686272	60000.00	1	completed	\N	2025-12-03 17:58:23.686272	2025-12-03 17:58:23.686272
151	HD-20251203-181517	\N	1	2025-12-03 18:15:17.958975	40000.00	1	completed	\N	2025-12-03 18:15:17.958975	2025-12-03 18:15:17.958975
152	HD-20251205-114600	\N	1	2025-12-05 11:46:00.540017	20000.00	2	completed	\N	2025-12-05 11:46:00.540017	2025-12-05 11:46:41.477913
153	HD-20251205-114732	\N	1	2025-12-05 11:47:32.070193	10000.00	2	pending	\N	2025-12-05 11:47:32.070193	2025-12-05 11:47:32.070193
159	HD-20251212-063329	1	1	2025-12-12 06:33:29.432523	60000.00	2	completed	5	2025-12-12 06:33:29.432523	2025-12-12 06:34:16.269569
160	HD-20251212-063457	\N	1	2025-12-12 06:34:57.487124	40000.00	2	pending	\N	2025-12-12 06:34:57.487124	2025-12-12 06:34:57.487124
26	ORD-202506-001	11	3	2025-06-05 00:00:00	600000.00	4	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
28	ORD-202506-003	13	3	2025-06-15 00:00:00	450000.00	7	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
30	ORD-202506-005	15	3	2025-06-25 00:00:00	200000.00	1	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
36	ORD-202508-001	6	3	2025-08-05 00:00:00	700000.00	6	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
38	ORD-202508-003	8	3	2025-08-15 00:00:00	600000.00	9	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
40	ORD-202508-005	10	3	2025-08-25 00:00:00	300000.00	1	completed	\N	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
53	HD-20251021-151248	1	1	2025-10-21 00:00:00	150000.00	1	pending	\N	2025-10-21 15:12:48.666165	2025-10-21 15:12:48.666165
161	HD-20251214-105856	\N	1	2025-12-14 10:58:56.253294	40000.00	1	completed	\N	2025-12-14 10:58:56.253294	2025-12-14 10:58:56.253294
162	HD-20251214-105900	\N	1	2025-12-14 10:59:00.711055	40000.00	1	completed	\N	2025-12-14 10:59:00.711055	2025-12-14 10:59:00.711055
163	HD-20251214-105920	\N	1	2025-12-14 10:59:20.691371	40000.00	1	completed	\N	2025-12-14 10:59:20.691371	2025-12-14 10:59:20.691371
165	HD-20251214-110026	\N	1	2025-12-14 11:00:26.654028	50000.00	1	completed	\N	2025-12-14 11:00:26.654028	2025-12-14 11:00:26.654028
167	HD-20251214-110500	\N	1	2025-12-14 11:05:00.462269	40000.00	2	pending	\N	2025-12-14 11:05:00.462269	2025-12-14 11:05:00.462269
169	HD-20251214-115044	\N	1	2025-12-14 11:50:44.35512	100000.00	1	completed	\N	2025-12-14 11:50:44.35512	2025-12-14 11:50:44.35512
168	HD-20251214-112555	\N	1	2025-12-14 11:25:55.593846	50000.00	1	completed	\N	2025-12-14 11:25:55.593846	2025-12-14 11:25:55.593846
170	HD-20251214-120242	\N	1	2025-12-14 12:02:42.31114	900000.00	1	completed	\N	2025-12-14 12:02:42.31114	2025-12-14 12:02:42.31114
171	HD-20251214-121823	\N	1	2025-12-14 12:18:23.104338	2500000.00	1	completed	\N	2025-12-14 12:18:23.104338	2025-12-14 12:18:23.104338
172	HD-20251214-150035	\N	19	2025-12-14 15:00:35.704633	100000.00	2	pending	\N	2025-12-14 15:00:35.704633	2025-12-14 15:00:35.704633
173	HD-20251214-154958	\N	1	2025-12-14 15:49:58.114467	100000.00	2	completed	11	2025-12-14 15:49:58.114467	2025-12-14 15:50:37.644147
174	HD-20251214-163447	\N	21	2025-12-14 16:34:47.695152	450000.00	1	completed	\N	2025-12-14 16:34:47.695152	2025-12-14 16:34:47.695152
175	HD-20251214-165053	16	1	2025-12-14 16:50:53.653706	2500000.00	1	completed	\N	2025-12-14 16:50:53.653706	2025-12-14 16:50:53.653706
179	HD-20251215-063509	16	1	2025-12-15 06:35:09.992702	10000.00	2	completed	11	2025-12-15 06:35:09.992702	2025-12-15 06:35:42.465756
180	HD-20251215-093356	16	1	2025-12-15 09:33:56.50797	50000.00	2	completed	11	2025-12-15 09:33:56.50797	2025-12-15 09:34:35.340418
181	HD-20251215-102512	16	1	2025-12-15 10:25:12.174659	100000.00	2	pending	11	2025-12-15 10:25:12.174659	2025-12-15 10:25:12.174659
\.


--
-- TOC entry 5042 (class 0 OID 33073)
-- Dependencies: 218
-- Data for Name: payment_methods; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.payment_methods (payment_method_id, code, name, description, is_active, created_at) FROM stdin;
1	cash	Tiền mặt	Thanh toán trực tiếp bằng tiền mặt tại quầy	t	2025-10-03 13:29:14.460139
2	bank_transfer	Chuyển khoản ngân hàng	Thanh toán qua chuyển khoản ngân hàng, yêu cầu xác nhận biên lai	t	2025-10-03 13:29:14.460139
3	credit_card	Thẻ tín dụng	Thanh toán bằng thẻ tín dụng Visa/Mastercard	t	2025-10-03 13:29:14.460139
4	momo	Ví Momo	Thanh toán qua ví điện tử Momo, quét QR code	t	2025-10-03 13:29:14.460139
5	zalo_pay	ZaloPay	Thanh toán qua ví ZaloPay, hỗ trợ hoàn tiền nhanh	t	2025-10-03 13:29:14.460139
6	vnpay	VNPay	Thanh toán qua cổng VNPay, hỗ trợ nhiều ngân hàng	t	2025-10-03 13:29:14.460139
7	cash_on_delivery	Trả tiền khi nhận hàng	Chỉ áp dụng cho đơn hàng giao tận nơi, thu tiền tại chỗ	t	2025-10-03 13:29:14.460139
8	installment	Trả góp	Thanh toán trả góp qua ngân hàng đối tác, yêu cầu kiểm tra tín dụng	t	2025-10-03 13:29:14.460139
9	paypal	PayPal	Thanh toán quốc tế qua PayPal, dành cho khách nước ngoài	f	2025-10-03 13:29:14.460139
10	bitcoin	Bitcoin	Thanh toán bằng tiền điện tử Bitcoin, thử nghiệm	f	2025-10-03 13:29:14.460139
\.


--
-- TOC entry 5076 (class 0 OID 50192)
-- Dependencies: 252
-- Data for Name: payments; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.payments (payment_id, context_type, order_number, purchase_number, pay_code, provider, reference, amount, status, checkout_url, data, created_by, created_at, updated_at, qr_base64) FROM stdin;
1	order	HD-20251127-193432	\N	1764246872638	payos	4c9761da5a2646d6acbbd3df3f5d4992	10000.00	pending	https://pay.payos.vn/web/4c9761da5a2646d6acbbd3df3f5d4992	{"bin": "970418", "amount": 10000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA53037045405100005802VN62350831CSAZ4TTYZQ2 PayHD20251127193432630437CA", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764246872638, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/4c9761da5a2646d6acbbd3df3f5d4992", "description": "CSAZ4TTYZQ2 PayHD20251127193432", "accountNumber": "V3CAS6504398884", "paymentLinkId": "4c9761da5a2646d6acbbd3df3f5d4992"}	1	2025-11-27 19:34:32.966917	2025-11-27 19:34:32.966917	\N
2	order	HD-20251127-195549	\N	1764248149243	payos	2e9cf78641d749c6ac671ea564ac3e17	30000.00	pending	https://pay.payos.vn/web/2e9cf78641d749c6ac671ea564ac3e17	{"bin": "970418", "amount": 30000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA53037045405300005802VN62350831CSFU5OIHR95 PayHD202511271955496304FF59", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764248149243, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/2e9cf78641d749c6ac671ea564ac3e17", "description": "CSFU5OIHR95 PayHD20251127195549", "accountNumber": "V3CAS6504398884", "paymentLinkId": "2e9cf78641d749c6ac671ea564ac3e17"}	1	2025-11-27 19:55:49.563456	2025-11-27 19:55:49.563456	\N
3	order	HD-20251127-202256	\N	1764249776219	payos	17d3658ea9ce4bf78ca915c71dcf797e	10000.00	pending	https://pay.payos.vn/web/17d3658ea9ce4bf78ca915c71dcf797e	{"bin": "970418", "amount": 10000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA53037045405100005802VN62350831CSIRF624ES8 PayHD2025112720225663049C0D", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764249776219, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/17d3658ea9ce4bf78ca915c71dcf797e", "description": "CSIRF624ES8 PayHD20251127202256", "accountNumber": "V3CAS6504398884", "paymentLinkId": "17d3658ea9ce4bf78ca915c71dcf797e"}	\N	2025-11-27 20:22:56.700324	2025-11-27 20:22:56.700324	data:image/png;base64,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
5	purchase	\N	PN-1764297329714	1764297329776	payos	46988fe3b99e4a2fb50319ff7b49ecca	100.00	pending	https://pay.payos.vn/web/46988fe3b99e4a2fb50319ff7b49ecca	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CSO7WJ7OLF3 PayPN176429732971463045107", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764297329776, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/46988fe3b99e4a2fb50319ff7b49ecca", "description": "CSO7WJ7OLF3 PayPN1764297329714", "accountNumber": "V3CAS6504398884", "paymentLinkId": "46988fe3b99e4a2fb50319ff7b49ecca"}	\N	2025-11-28 09:35:30.172543	2025-11-28 09:35:30.172543	data:image/png;base64,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
6	order	HD-20251128-093844	\N	1764297524969	payos	ea010b431b5349d6b5d0529e1920f703	510000.00	pending	https://pay.payos.vn/web/ea010b431b5349d6b5d0529e1920f703	{"bin": "970418", "amount": 510000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454065100005802VN62350831CSUTK0NHJP3 PayHD20251128093844630462A8", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764297524969, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/ea010b431b5349d6b5d0529e1920f703", "description": "CSUTK0NHJP3 PayHD20251128093844", "accountNumber": "V3CAS6504398884", "paymentLinkId": "ea010b431b5349d6b5d0529e1920f703"}	\N	2025-11-28 09:38:45.215091	2025-11-28 09:38:45.215091	data:image/png;base64,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
4	order	HD-20251127-203226	\N	1764250347149	payos	47d273e3b10a419d828f214042efbdbb	10000.00	completed	https://pay.payos.vn/web/47d273e3b10a419d828f214042efbdbb	{"code": "00", "desc": "success", "amount": 10000, "currency": "VND", "orderCode": 1764250347149, "reference": "22b9d74b-7b1d-4f37-8aaa-d0c504e95efd", "description": "CSY7BI223A3 PayHD20251127203226", "accountNumber": "6504398884", "paymentLinkId": "47d273e3b10a419d828f214042efbdbb", "counterAccountName": null, "virtualAccountName": "", "transactionDateTime": "2025-11-28 08:42:03", "counterAccountBankId": "", "counterAccountNumber": null, "virtualAccountNumber": "V3CAS6504398884", "counterAccountBankName": ""}	\N	2025-11-27 20:32:27.377738	2025-11-28 11:05:06.660471	data:image/png;base64,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
8	order	HD-20251128-100139	\N	1764298899128	payos	2700370f986d47afb7852651bce8210c	10000.00	completed	https://pay.payos.vn/web/2700370f986d47afb7852651bce8210c	{"code": "00", "desc": "success", "amount": 10000, "currency": "VND", "orderCode": 1764298899128, "reference": "53a92a80-c7cb-474a-9c64-ee00429e4bea", "description": "CS66RCYF0J7 PayHD20251128100139", "accountNumber": "6504398884", "paymentLinkId": "2700370f986d47afb7852651bce8210c", "counterAccountName": null, "virtualAccountName": "", "transactionDateTime": "2025-11-28 10:02:08", "counterAccountBankId": "", "counterAccountNumber": null, "virtualAccountNumber": "V3CAS6504398884", "counterAccountBankName": ""}	\N	2025-11-28 10:01:39.559105	2025-11-28 10:56:12.006734	data:image/png;base64,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
9	order	HD-20251128-101047	\N	1764299447526	payos	b9e07f00602f478e816a15a9eba828d5	10000.00	completed	https://pay.payos.vn/web/b9e07f00602f478e816a15a9eba828d5	{"code": "00", "desc": "success", "amount": 10000, "currency": "VND", "orderCode": 1764299447526, "reference": "fe2e9fbb-f447-4d04-90d9-820577e5c0fa", "description": "CS9FKSMHI76 PayHD20251128101047", "accountNumber": "6504398884", "paymentLinkId": "b9e07f00602f478e816a15a9eba828d5", "counterAccountName": null, "virtualAccountName": "", "transactionDateTime": "2025-11-28 10:11:11", "counterAccountBankId": "", "counterAccountNumber": null, "virtualAccountNumber": "V3CAS6504398884", "counterAccountBankName": ""}	\N	2025-11-28 10:10:47.907719	2025-11-28 11:05:15.210629	data:image/png;base64,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
7	order	HD-20251128-094654	\N	1764298015006	payos	ce50673efc03435fbaa6873dcddd3795	10000.00	completed	https://pay.payos.vn/web/ce50673efc03435fbaa6873dcddd3795	{"code": "00", "desc": "success", "amount": 10000, "currency": "VND", "orderCode": 1764298015006, "reference": "d468e6db-783f-45e9-9f4c-bafa289152ad", "description": "CS1A00N0KC6 PayHD20251128094654", "accountNumber": "6504398884", "paymentLinkId": "ce50673efc03435fbaa6873dcddd3795", "counterAccountName": null, "virtualAccountName": "", "transactionDateTime": "2025-11-28 09:47:14", "counterAccountBankId": "", "counterAccountNumber": null, "virtualAccountNumber": "V3CAS6504398884", "counterAccountBankName": ""}	\N	2025-11-28 09:46:55.407941	2025-11-28 11:15:18.088179	data:image/png;base64,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
10	order	HD-20251128-110854	\N	1764302934602	payos	a67f4200a7604ca48ff3bb39449ae0bb	10000.00	completed	https://pay.payos.vn/web/a67f4200a7604ca48ff3bb39449ae0bb	{"code": "00", "desc": "success", "amount": 10000, "currency": "VND", "orderCode": 1764302934602, "reference": "46d6090a-fef7-4154-9b44-892685b4b09c", "description": "CS9VIKYOZ61 PayHD20251128110854", "accountNumber": "6504398884", "paymentLinkId": "a67f4200a7604ca48ff3bb39449ae0bb", "counterAccountName": null, "virtualAccountName": "", "transactionDateTime": "2025-11-28 11:09:20", "counterAccountBankId": "", "counterAccountNumber": null, "virtualAccountNumber": "V3CAS6504398884", "counterAccountBankName": ""}	\N	2025-11-28 11:08:55.011394	2025-11-28 11:09:21.743066	data:image/png;base64,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
11	order	HD-20251128-111220	\N	1764303140675	payos	742438ad61b64ba19764cb13a8069593	10000.00	completed	https://pay.payos.vn/web/742438ad61b64ba19764cb13a8069593	{"code": "00", "desc": "success", "amount": 10000, "currency": "VND", "orderCode": 1764303140675, "reference": "27b7af7e-963f-4b89-88ff-03fb72bed416", "description": "CSWZ6A8LEQ8 PayHD20251128111220", "accountNumber": "6504398884", "paymentLinkId": "742438ad61b64ba19764cb13a8069593", "counterAccountName": null, "virtualAccountName": "", "transactionDateTime": "2025-11-28 11:12:46", "counterAccountBankId": "", "counterAccountNumber": null, "virtualAccountNumber": "V3CAS6504398884", "counterAccountBankName": ""}	\N	2025-11-28 11:12:20.930372	2025-11-28 11:12:48.00974	data:image/png;base64,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
12	order	HD-20251128-111943	\N	1764303583561	payos	a0e5ba32bd684e659002fc708d6e3949	10000.00	pending	https://pay.payos.vn/web/a0e5ba32bd684e659002fc708d6e3949	{"bin": "970418", "amount": 10000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA53037045405100005802VN62350831CSVFXQSA3G8 PayHD202511281119436304F5C4", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764303583561, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/a0e5ba32bd684e659002fc708d6e3949", "description": "CSVFXQSA3G8 PayHD20251128111943", "accountNumber": "V3CAS6504398884", "paymentLinkId": "a0e5ba32bd684e659002fc708d6e3949"}	\N	2025-11-28 11:19:43.805389	2025-11-28 11:19:43.805389	data:image/png;base64,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
13	order	HD-20251128-113650	\N	1764304610225	payos	b941ab8258b34d118df3d6fe0ef409f2	10000.00	pending	https://pay.payos.vn/web/b941ab8258b34d118df3d6fe0ef409f2	{"bin": "970418", "amount": 10000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA53037045405100005802VN62350831CSUHIWVYSQ0 PayHD202511281136506304432C", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764304610225, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/b941ab8258b34d118df3d6fe0ef409f2", "description": "CSUHIWVYSQ0 PayHD20251128113650", "accountNumber": "V3CAS6504398884", "paymentLinkId": "b941ab8258b34d118df3d6fe0ef409f2"}	\N	2025-11-28 11:36:50.478374	2025-11-28 11:36:50.478374	data:image/png;base64,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
14	order	HD-20251128-125745	\N	1764309465274	payos	69c1ae9ce1bc4c099ef6ff41ba295eb5	10000.00	pending	https://pay.payos.vn/web/69c1ae9ce1bc4c099ef6ff41ba295eb5	{"bin": "970418", "amount": 10000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA53037045405100005802VN62350831CSPWBNY7BP0 PayHD2025112812574563040AAB", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764309465274, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/69c1ae9ce1bc4c099ef6ff41ba295eb5", "description": "CSPWBNY7BP0 PayHD20251128125745", "accountNumber": "V3CAS6504398884", "paymentLinkId": "69c1ae9ce1bc4c099ef6ff41ba295eb5"}	\N	2025-11-28 12:57:45.554086	2025-11-28 12:57:45.554086	data:image/png;base64,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
15	purchase	\N	PN-1764311784093	1764311784151	payos	77acb6c7a57f43cfb6cecd8e7ad6c275	100.00	pending	https://pay.payos.vn/web/77acb6c7a57f43cfb6cecd8e7ad6c275	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CSU0BBFMYC5 PayPN176431178409363047E25", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764311784151, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/77acb6c7a57f43cfb6cecd8e7ad6c275", "description": "CSU0BBFMYC5 PayPN1764311784093", "accountNumber": "V3CAS6504398884", "paymentLinkId": "77acb6c7a57f43cfb6cecd8e7ad6c275"}	\N	2025-11-28 13:36:24.420947	2025-11-28 13:36:24.420947	data:image/png;base64,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
16	purchase	\N	PN-1764312228386	1764312228447	payos	ba8940187ffd4f26baea1dbbc7f22941	100.00	pending	https://pay.payos.vn/web/ba8940187ffd4f26baea1dbbc7f22941	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CS4H3FN9Z59 PayPN17643122283866304AF90", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764312228447, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/ba8940187ffd4f26baea1dbbc7f22941", "description": "CS4H3FN9Z59 PayPN1764312228386", "accountNumber": "V3CAS6504398884", "paymentLinkId": "ba8940187ffd4f26baea1dbbc7f22941"}	\N	2025-11-28 13:43:48.651581	2025-11-28 13:43:48.651581	data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAMQAAADECAYAAADApo5rAAAAAklEQVR4AewaftIAAAjRSURBVO3BQY4kSXIAQdVA/f/LygYPDuPFgUBm9ewsTcT+YK31vx7WWsfDWut4WGsdD2ut42GtdTystY6HtdbxsNY6HtZax8Na63hYax0Pa63jYa11PKy1joe11vHDh1T+popPqEwVk8pUMancVEwqn6iYVG4qJpWbijdUbiomlb+p4hMPa63jYa11PKy1jh++rOKbVN5QeUNlqviEylTxmypuKiaVSWWquKn4RMU3qXzTw1rreFhrHQ9rreOHX6byRsUnKiaVb6qYVL5J5aZiUpkqJpVPqNxUfELljYrf9LDWOh7WWsfDWuv44b+MyhsVk8obFZPKGypvqNyoTBU3KjcV/588rLWOh7XW8bDWOn5Y/0fFpDJV3FS8UfEJlU9U3KhMFZPKVPFv9rDWOh7WWsfDWuv44ZdV/CaVm4oblaniDZWbihuVT1RMKpPKVDGpTBVTxaQyVXyi4j/Jw1rreFhrHQ9rreOHL1P5J1VMKlPFb6qYVKaKm4pJZaqYVKaKSeUTKlPFpDJV3Kj8J3tYax0Pa63jYa112B/8F1GZKm5UpopJZaqYVN6ouFF5o+INlaliUnmj4r/Jw1rreFhrHQ9rrcP+4AMqU8WNylQxqdxUTCpvVLyhMlW8oTJVTCpTxaTyRsUbKm9UTCo3FZPKVPGf5GGtdTystY6Htdbxw5ep3FRMKjcVk8pUMalMFZPKVDGpTBWfqHhD5Y2KN1SmikllqphUbio+oTJV3KhMFZ94WGsdD2ut42GtdfzwD6u4UXmjYlJ5o+JGZaq4UXmjYlL5hMpUcVPxCZWp4kblRuVvelhrHQ9rreNhrXX88Msq3lCZKm5UbiomlRuVm4pJZaqYKiaVG5WpYlL5hMpNxW+quFH5Jz2stY6HtdbxsNY6fvhlKlPFpHKjclNxozJVTCo3FZPKGypTxaRyozJV3Kh8QuWm4g2VqWJSmSomlb/pYa11PKy1joe11mF/8ItUpopJZar4hMpU8YbKTcWNylRxo/KJijdUpoo3VKaKSWWqeENlqrhRmSo+8bDWOh7WWsfDWuv44ctUpopPqPybVEwqNxU3Km+oTBU3Km9UTCo3KlPFpDJV3Kj8poe11vGw1joe1lrHDx9SmSreqJhUpoo3VG5UpoqbikllqphUpooblaliqphUbipuKiaVm4pJZar4TSo3Fd/0sNY6HtZax8Na6/jhQxWTylQxqUwVU8Wk8ptUPqEyVXxCZaqYKiaVm4pJZaq4UfkmlaliUrmp+E0Pa63jYa11PKy1DvuDD6i8UTGp3FTcqEwVk8pUMam8UXGj8psq3lC5qbhRmSomlaniN6lMFd/0sNY6HtZax8Na6/jhP0zFpPKJikllqrhRmVSmipuKT6jcqNxU3KhMFZ9Quan4JpWp4hMPa63jYa11PKy1DvuDf5DKTcWNyicqJpWp4ptU3qh4Q2WquFG5qbhRmSomld9U8U0Pa63jYa11PKy1DvuDD6h8U8WkclMxqUwVk8obFZPKGxWfUJkqJpWpYlK5qZhUbireUHmj4kblpuITD2ut42GtdTystY4fvqziEypTxY3KjcpUcaNyUzGpvKHyTRWTylTxiYpJ5abib6r4poe11vGw1joe1lqH/cEHVN6ouFF5o+INlaniEypTxaQyVUwqU8UbKp+ouFGZKm5UpopJZaqYVKaKv+lhrXU8rLWOh7XWYX/wAZWbiknljYoblTcqJpWbikllqnhD5Z9U8U0qb1RMKjcVf9PDWut4WGsdD2ut44cPVdyofELlm1TeUHlD5Y2KSWWqeEPlDZWp4kZlqrhReaNiUnmj4hMPa63jYa11PKy1DvuDL1K5qfgmlaniN6lMFZ9QeaPiRmWqeENlqnhD5Y2KN1Smim96WGsdD2ut42Gtddgf/CKVqeJG5Y2KN1SmikllqrhRmSomlZuKN1RuKiaVqWJSeaPiDZWpYlL5RMU3Pay1joe11vGw1jp++JDKVDFVTCpvVEwq/2YV31QxqUwVk8pU8QmVm4pJZaqYVKaKv+lhrXU8rLWOh7XWYX/wAZVPVNyofKJiUvlExaQyVUwqNxWTylRxo/JGxaQyVUwqU8UnVN6omFSmim96WGsdD2ut42GtddgffJHKTcWkMlV8QuUTFZPKTcWk8omKSWWqmFQ+UTGpTBWTylQxqdxU/Cd7WGsdD2ut42GtdfzwIZWpYlKZVG5Ubio+UTGpvFExqUwVk8pU8UbFpPKJipuKSeWNijdUpoo3VKaKTzystY6HtdbxsNY6fvhQxU3FjcpUcaNyUzGpvKHyRsWkMlV8QmWqmFSmikllUrmpmCreUPk3e1hrHQ9rreNhrXX88CGVqeJGZaqYVG4qJpWbipuKSWWqeKNiUpkqblQ+oXJT8YbKVDGp/Dd5WGsdD2ut42Gtddgf/Iup3FRMKlPFN6ncVHxC5TdV3KjcVLyhMlW8oTJVfOJhrXU8rLWOh7XW8cOHVP6miqniRmWquFGZKm5UpopJZVL5J1XcqEwVn1CZKt5Quan4poe11vGw1joe1lrHD19W8U0qNypTxRsqb6hMFd9UcaMyVUwqU8U/qeINlZuK3/Sw1joe1lrHw1rr+OGXqbxR8UbFGypTxT+p4o2KSWWqmFSmipuKm4pJZVL5TSpTxTc9rLWOh7XW8bDWOn74l1N5o2JSmSreUPlNKm+o3KjcVPxNFZPKGypTxSce1lrHw1rreFhrHT/8y1XcqEwqU8WkclNxozJV3KhMFVPFpHJTMalMFW+oTBVTxaTyhspNxY3KNz2stY6HtdbxsNY6fvhlFf+kiknlpmJSmVSmijdUpopJZaqYKm5UblSmikllqrhRmSpuVKaKT1R808Na63hYax0Pa63D/uADKn9TxaTymypuVN6omFSmihuVqeITKlPFpDJVvKHyTRW/6WGtdTystY6HtdZhf7DW+l8Pa63jYa11PKy1joe11vGw1joe1lrHw1rreFhrHQ9rreNhrXU8rLWOh7XW8bDWOh7WWsfDWuv4H0rysq5L5RmdAAAAAElFTkSuQmCC
17	order	HD-20251128-134408	\N	1764312248936	payos	3fab8f2076d0435ea4fab2bfa007fe7d	10000.00	pending	https://pay.payos.vn/web/3fab8f2076d0435ea4fab2bfa007fe7d	{"bin": "970418", "amount": 10000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA53037045405100005802VN62350831CSK3WTKO789 PayHD202511281344086304D2BD", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764312248936, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/3fab8f2076d0435ea4fab2bfa007fe7d", "description": "CSK3WTKO789 PayHD20251128134408", "accountNumber": "V3CAS6504398884", "paymentLinkId": "3fab8f2076d0435ea4fab2bfa007fe7d"}	\N	2025-11-28 13:44:09.144497	2025-11-28 13:44:09.144497	data:image/png;base64,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
18	purchase	\N	PN-1764312859230	1764312859268	payos	f3e4f649ae7f41cdbd1bb5ff418cc1c9	100.00	pending	https://pay.payos.vn/web/f3e4f649ae7f41cdbd1bb5ff418cc1c9	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CS6ZOY294Z9 PayPN17643128592306304684B", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764312859268, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/f3e4f649ae7f41cdbd1bb5ff418cc1c9", "description": "CS6ZOY294Z9 PayPN1764312859230", "accountNumber": "V3CAS6504398884", "paymentLinkId": "f3e4f649ae7f41cdbd1bb5ff418cc1c9"}	\N	2025-11-28 13:54:19.490932	2025-11-28 13:54:19.490932	data:image/png;base64,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
19	purchase	\N	PN-20251128-140122	1764313282617	payos	148024cda3a64a948d2c9641205d664f	100.00	pending	https://pay.payos.vn/web/148024cda3a64a948d2c9641205d664f	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62350831CSA2CGOCLS1 PayPN202511281401226304A9C3", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764313282617, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/148024cda3a64a948d2c9641205d664f", "description": "CSA2CGOCLS1 PayPN20251128140122", "accountNumber": "V3CAS6504398884", "paymentLinkId": "148024cda3a64a948d2c9641205d664f"}	\N	2025-11-28 14:01:22.864773	2025-11-28 14:01:22.864773	data:image/png;base64,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
20	purchase	\N	PN-20251128-140411	1764313451936	payos	3b0ba54070184367bd753b9ce5be29cc	100.00	pending	https://pay.payos.vn/web/3b0ba54070184367bd753b9ce5be29cc	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62350831CS2NJKVCDC8 PayPN202511281404116304BEFB", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764313451936, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/3b0ba54070184367bd753b9ce5be29cc", "description": "CS2NJKVCDC8 PayPN20251128140411", "accountNumber": "V3CAS6504398884", "paymentLinkId": "3b0ba54070184367bd753b9ce5be29cc"}	\N	2025-11-28 14:04:12.208925	2025-11-28 14:04:12.208925	data:image/png;base64,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
21	purchase	\N	PN-20251128-140708	1764313628834	payos	4431d2b22a4340e78760522ec713646f	100.00	pending	https://pay.payos.vn/web/4431d2b22a4340e78760522ec713646f	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62350831CSL56MQ32T6 PayPN202511281407086304B61B", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764313628834, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/4431d2b22a4340e78760522ec713646f", "description": "CSL56MQ32T6 PayPN20251128140708", "accountNumber": "V3CAS6504398884", "paymentLinkId": "4431d2b22a4340e78760522ec713646f"}	\N	2025-11-28 14:07:09.068078	2025-11-28 14:07:09.068078	data:image/png;base64,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
22	purchase	\N	PN-20251128-141246	1764313966981	payos	7ac56afb7a2743f28b8e722d23a548a2	100.00	pending	https://pay.payos.vn/web/7ac56afb7a2743f28b8e722d23a548a2	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62350831CS9OT1IZD85 PayPN2025112814124663046A9B", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764313966981, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/7ac56afb7a2743f28b8e722d23a548a2", "description": "CS9OT1IZD85 PayPN20251128141246", "accountNumber": "V3CAS6504398884", "paymentLinkId": "7ac56afb7a2743f28b8e722d23a548a2"}	\N	2025-11-28 14:12:47.196487	2025-11-28 14:12:47.196487	data:image/png;base64,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
23	purchase	\N	PN-1764135565530	1764315047748	payos	64e210b30bc44c748b8940f148f54ce3	100.00	pending	https://pay.payos.vn/web/64e210b30bc44c748b8940f148f54ce3	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CSUMES1AT44 PayPN1764135565530630449DA", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764315047748, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/64e210b30bc44c748b8940f148f54ce3", "description": "CSUMES1AT44 PayPN1764135565530", "accountNumber": "V3CAS6504398884", "paymentLinkId": "64e210b30bc44c748b8940f148f54ce3"}	\N	2025-11-28 14:30:48.024219	2025-11-28 14:30:48.024219	data:image/png;base64,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
24	purchase	\N	PN-1764135565530	1764315053349	payos	9af6752d907f4a9ab38b1a0d069567c0	100.00	pending	https://pay.payos.vn/web/9af6752d907f4a9ab38b1a0d069567c0	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CS57KE3VXR8 PayPN176413556553063041177", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764315053349, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/9af6752d907f4a9ab38b1a0d069567c0", "description": "CS57KE3VXR8 PayPN1764135565530", "accountNumber": "V3CAS6504398884", "paymentLinkId": "9af6752d907f4a9ab38b1a0d069567c0"}	\N	2025-11-28 14:30:53.576819	2025-11-28 14:30:53.576819	data:image/png;base64,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
25	purchase	\N	PN-1764135565530	1764315132089	payos	43d48966d6074702992e4860fbf44054	100.00	pending	https://pay.payos.vn/web/43d48966d6074702992e4860fbf44054	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CSN0CTRCID6 PayPN17641355655306304B0A8", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764315132089, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/43d48966d6074702992e4860fbf44054", "description": "CSN0CTRCID6 PayPN1764135565530", "accountNumber": "V3CAS6504398884", "paymentLinkId": "43d48966d6074702992e4860fbf44054"}	\N	2025-11-28 14:32:13.336031	2025-11-28 14:32:13.336031	data:image/png;base64,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
26	purchase	\N	PN-1764135565530	1764315135058	payos	8f2d892edeb848fbb250a2e740891510	100.00	pending	https://pay.payos.vn/web/8f2d892edeb848fbb250a2e740891510	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CSZ6OFCW9W5 PayPN1764135565530630481D2", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764315135058, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/8f2d892edeb848fbb250a2e740891510", "description": "CSZ6OFCW9W5 PayPN1764135565530", "accountNumber": "V3CAS6504398884", "paymentLinkId": "8f2d892edeb848fbb250a2e740891510"}	\N	2025-11-28 14:32:15.267375	2025-11-28 14:32:15.267375	data:image/png;base64,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
27	purchase	\N	PN-20251128-143243	1764315163743	payos	e035adfc739c44a99ab0b8be74b553d6	100.00	pending	https://pay.payos.vn/web/e035adfc739c44a99ab0b8be74b553d6	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62350831CSD5W9S7L43 PayPN20251128143243630481E3", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764315163743, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/e035adfc739c44a99ab0b8be74b553d6", "description": "CSD5W9S7L43 PayPN20251128143243", "accountNumber": "V3CAS6504398884", "paymentLinkId": "e035adfc739c44a99ab0b8be74b553d6"}	\N	2025-11-28 14:32:43.950903	2025-11-28 14:32:43.950903	data:image/png;base64,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
28	purchase	\N	PN-20251128-144038	1764315638133	payos	3bf55b695c3d42ef81264bbd159d191e	100.00	pending	https://pay.payos.vn/web/3bf55b695c3d42ef81264bbd159d191e	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62350831CSFPGGNEX59 PayPN202511281440386304337D", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764315638133, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/3bf55b695c3d42ef81264bbd159d191e", "description": "CSFPGGNEX59 PayPN20251128144038", "accountNumber": "V3CAS6504398884", "paymentLinkId": "3bf55b695c3d42ef81264bbd159d191e"}	\N	2025-11-28 14:40:38.360114	2025-11-28 14:40:38.360114	data:image/png;base64,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
29	purchase	\N	PN-20251128-144941	1764316181953	payos	8886ad5597ec406db6831f9a0076cadc	100.00	pending	https://pay.payos.vn/web/8886ad5597ec406db6831f9a0076cadc	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62350831CSRACSW2G09 PayPN202511281449416304B106", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764316181953, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/8886ad5597ec406db6831f9a0076cadc", "description": "CSRACSW2G09 PayPN20251128144941", "accountNumber": "V3CAS6504398884", "paymentLinkId": "8886ad5597ec406db6831f9a0076cadc"}	\N	2025-11-28 14:49:42.367094	2025-11-28 14:49:42.367094	data:image/png;base64,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
30	purchase	\N	PN-20251128-145156	1764316316634	payos	8a21e3b92312489fab654e1173649885	100.00	pending	https://pay.payos.vn/web/8a21e3b92312489fab654e1173649885	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62350831CSNIM9BZ6U2 PayPN20251128145156630426E6", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764316316634, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/8a21e3b92312489fab654e1173649885", "description": "CSNIM9BZ6U2 PayPN20251128145156", "accountNumber": "V3CAS6504398884", "paymentLinkId": "8a21e3b92312489fab654e1173649885"}	\N	2025-11-28 14:51:57.033178	2025-11-28 14:51:57.033178	data:image/png;base64,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
31	purchase	\N	PN-20251128-145957	1764316797784	payos	f272922e6e1a4e88a28b5688766b4a04	100.00	pending	https://pay.payos.vn/web/f272922e6e1a4e88a28b5688766b4a04	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62350831CSQJ92RLVG3 PayPN202511281459576304C482", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764316797784, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/f272922e6e1a4e88a28b5688766b4a04", "description": "CSQJ92RLVG3 PayPN20251128145957", "accountNumber": "V3CAS6504398884", "paymentLinkId": "f272922e6e1a4e88a28b5688766b4a04"}	\N	2025-11-28 14:59:58.2005	2025-11-28 14:59:58.2005	data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAMQAAADECAYAAADApo5rAAAAAklEQVR4AewaftIAAAjPSURBVO3BS44kS3DAQDLR978yNdAi4KsAElXzeZKb2S+stf7Xw1rreFhrHQ9rreNhrXU8rLWOh7XW8bDWOh7WWsfDWut4WGsdD2ut42GtdTystY6HtdbxsNY6fviQyp9UMancVLyhMlVMKlPFjcpUMan8ThU3KlPFGypTxaTyJ1V84mGtdTystY6Htdbxw5dVfJPKTcWkMqlMFZPKjcpU8QmVT1RMKjcqU8VU8YbKJyq+SeWbHtZax8Na63hYax0//GYqb1R8U8Wk8gmVqWJSual4Q+Wm4kblRmWqmFRuKj6h8kbF7/Sw1joe1lrHw1rr+OE/TmWqmFRuKiaVm4pJ5aZiUnmjYlK5qZgqbipuKv4/eVhrHQ9rreNhrXX88H+MyicqJpWbijcqPlExqUwqU8UnVKaKSWWq+C97WGsdD2ut42Gtdfzwm1X8SRW/k8onKiaVqWJS+YTKGxU3KlPFJyr+JQ9rreNhrXU8rLWOH75M5V+iMlVMKlPFTcWkMlVMKt9UMalMFZPKVDGpvFExqUwVNyr/soe11vGw1joe1lrHDx+q+JeoTBV/ksobFZPKjcpUcVMxqUwVk8qNylRxU/Ff8rDWOh7WWsfDWuv44UMqU8UbKlPFpPJNKlPFpDJVfJPKVDFVvKHyRsVNxaTyhso3VdyoTBWfeFhrHQ9rreNhrXX88I9RmSomlanijYpJ5UblpmJSual4Q2WquKmYVP6mihuVG5WpYqr4poe11vGw1joe1lrHD7+ZylQxVdyovKEyVXxTxaRyU/GGylTxhspUMal8ouKmYlKZKqaKf8nDWut4WGsdD2ut44cPVUwqU8WkMlVMKlPFJ1SmiqniExWTyjepTBVTxaTyRsWkMlW8oTJVTCpTxRsqNxWfeFhrHQ9rreNhrXX88IdVTCo3KlPFTcUbKlPFjcpNxaTyiYo3KiaVT6i8UXFTMam8UTGpfNPDWut4WGsdD2ut44cPqUwVNypTxaQyVUwqv5PKVDFVTCqfqPiEylRxUzGp/EkqNxWTyqQyVXzTw1rreFhrHQ9rreOHL1OZKm5UpopJ5Y2KT6hMKlPFjconVL6p4hMVn1CZKt6ouFGZKj7xsNY6HtZax8Na6/jhD6uYVCaVqWJSmSpuVL5J5Y2KSWVSmSomlZuKT1R8QmWqeEPlX/Kw1joe1lrHw1rr+OFDFZPKjcpUcaNyozJVfFPFjcobFZPKpDJV3KhMFZPKTcWNyicqJpWpYlK5qfidHtZax8Na63hYax32C1+k8k0VNyo3FTcq/5KKSWWqmFSmihuVNyomlaliUpkqblSmir/pYa11PKy1joe11mG/8EUqU8Wk8k0VNypTxY3KVHGjMlVMKlPFpPKJiknlmyo+ofJGxaQyVUwqU8UnHtZax8Na63hYax0/fFnFTcWkclNxozJV3KhMFW+ovFExqbxR8YmKN1TeUJkqPqFyozJVfNPDWut4WGsdD2ut44cPqUwVNypTxaQyqUwVU8WkMlXcqEwVk8pU8TtV3Kh8QuWmYlL5RMUbKn/Tw1rreFhrHQ9rreOHP6zipuJG5aZiUnlDZaqYVG4qJpWbihuVT6jcVHyiYlK5qZhUbir+pIe11vGw1joe1lqH/cIXqUwVk8pUMancVEwqb1RMKp+omFSmikllqphU3qj4hMpNxaTyRsWkMlVMKp+o+MTDWut4WGsdD2ut44cvq5hUpopJ5abiExWTyk3FpHKj8kbFGxU3KlPFn1QxqUwqb1RMKlPFpPJND2ut42GtdTystY4fPqTyTRWTylQxVUwq/xKVqeINlaliqrhRmSqmijcqbireUJkqblSmim96WGsdD2ut42Gtddgv/EYqb1TcqEwVk8rvVDGpfKLiDZWbiknljYpJ5Y2KN1TeqJhUpopPPKy1joe11vGw1jp++DKVqeJGZVL5popJ5Y2KSeWm4kblRmWquKn4JpWp4hMqU8VUMam8UfFND2ut42GtdTystY4f/jEVb6hMFZPKTcUbFW+ovFExqXyiYlK5qbhR+YTKVDFV/E0Pa63jYa11PKy1jh++rOJGZaq4UZkqblSmikllUnmjYlKZKj6hMlXcqLxRMancqEwVk8pUcaMyqdxUTCo3FZ94WGsdD2ut42GtddgvfEDlmyo+ofJGxY3KVDGpTBU3Kp+ouFG5qXhD5abiEypTxY3KVPFND2ut42GtdTystQ77hb9IZaqYVKaKSWWqeENlqphUbiomlZuKSeWm4ptUpopJ5abiRmWqmFSmihuVNyo+8bDWOh7WWsfDWuuwX/iLVKaKG5U3Kt5QmSomlU9UvKEyVUwqU8Wk8kbFGyrfVPGGylTxiYe11vGw1joe1lqH/cIHVL6pYlK5qZhU3qi4UbmpmFS+qWJSeaPiRuW/pOJ3elhrHQ9rreNhrXX88KGK36niRuWbVKaKNyreUHmj4kblb6p4Q2WqmFQmlZuKTzystY6HtdbxsNY6fviQyp9U8UbFpPIJlaliUpkqbiq+qeJG5aZiUpkqJpUblaniRmWquFH5poe11vGw1joe1lrHD19W8U0qNxWTyqQyVUwqb1S8oTJVvKEyVUwqU8WkMlW8UfGJijcq/qaHtdbxsNY6HtZaxw+/mcobFW+o3FTcVHxCZaqYVP4klTdUpooblRuVb1L5kx7WWsfDWut4WGsdP/zHVbyhMlVMKjcVU8VNxY3KTcVNxScqJpU3Kj6h8kbF7/Sw1joe1lrHw1rr+OH/GJU3VN5QmSomlZuKT6hMFTcqNxVTxTep3FRMKjcqNxWfeFhrHQ9rreNhrXX88JtV/EkVk8pNxaTyhspNxU3FpDKpTBXfpHJTMancVHyi4g2Vb3pYax0Pa63jYa112C98QOVPqphUfqeKG5U3KiaVqeJGZar4hMpUMalMFW+ofKLiT3pYax0Pa63jYa112C+stf7Xw1rreFhrHQ9rreNhrXU8rLWOh7XW8bDWOh7WWsfDWut4WGsdD2ut42GtdTystY6HtdbxsNY6/gd74LmbCvuWKwAAAABJRU5ErkJggg==
32	purchase	\N	PN-1764135565530	1764316851682	payos	a7a1a454be1e48a6b3836748debee228	100.00	pending	https://pay.payos.vn/web/a7a1a454be1e48a6b3836748debee228	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CSQGQVP33X7 PayPN176413556553063042069", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764316851682, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/a7a1a454be1e48a6b3836748debee228", "description": "CSQGQVP33X7 PayPN1764135565530", "accountNumber": "V3CAS6504398884", "paymentLinkId": "a7a1a454be1e48a6b3836748debee228"}	\N	2025-11-28 15:00:51.977734	2025-11-28 15:00:51.977734	data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAMQAAADECAYAAADApo5rAAAAAklEQVR4AewaftIAAAjZSURBVO3BQYolyZIAQdUg739lnWIWjq0cgveyuvtjIvYHa63/97DWOh7WWsfDWut4WGsdD2ut42GtdTystY6HtdbxsNY6HtZax8Na63hYax0Pa63jYa11PKy1jh8+pPI3VUwqU8WkclMxqdxUTCpvVEwqU8Wk8kbFpDJVfJPKVDGp/E0Vn3hYax0Pa63jYa11/PBlFd+kclPxRsWkclMxqbxRMam8UXGjclPxCZVvqvgmlW96WGsdD2ut42Gtdfzwy1TeqPiEylRxU/FGxaQyVdxU3KhMFTcVk8pUMalMFZPKGxWfUHmj4jc9rLWOh7XW8bDWOn74j1OZKj6hMlVMKjcq36TyRsWk8omKSeV/2cNa63hYax0Pa63jh/8xKlPFpDJVTBU3FW+oTBVvqEwVk8qkclNxU3FTMalMFf9lD2ut42GtdTystY4fflnF31RxU/GGym9SmSpuVD6hclMxqdxUfKLi3+RhrXU8rLWOh7XW8cOXqfybqEwVk8pUcVMxqUwVk8o3VUwqU8WkMlVMKm9UTCpTxY3Kv9nDWut4WGsdD2ut44cPVfybqEwVf5PKGxWTyo3KVHFTMalMFZPKjcpUcVPxX/Kw1joe1lrHw1rr+OFDKlPFGypTxaTyTSpTxaQyVXyTylQxVbyh8kbFTcWk8obKN1XcqEwVn3hYax0Pa63jYa11/PChikllqphU3qiYVG4qbiomlRuVm4pJ5abiDZWp4qZiUvknVdyo3KhMFb/pYa11PKy1joe11vHDh1SmikllqphUJpWbihuVqeKbKiaVm4o3VKaKN1SmiknlExU3FZPKVDFV/Js8rLWOh7XW8bDWOn74MpVPVNyoTBU3KlPFVPGJiknlm1SmiqliUnmjYlKZKr5JZar4N3lYax0Pa63jYa112B98QOWNijdUpopvUpkqblRuKiaVm4pJZaq4UZkqJpV/UsWNyhsVv+lhrXU8rLWOh7XW8cMvq5hUpopJZaqYVG4qJpXfVDGpvKEyVbxR8UbFjcobFW+o3FRMKpPKVPFND2ut42GtdTystY4f/mEqU8Wk8jep3FTcVLyhMqncVNyoTBWTylRxUzGpvKEyVbxRcaMyVXziYa11PKy1joe11vHDX1YxqUwqU8WkMlVMKp+omFQmlaliUpkqbipuVG5UPqEyVbyhMlW8ofJv8rDWOh7WWsfDWuuwP/gilaliUpkqblTeqLhReaNiUrmpuFF5o2JS+UTFpDJVTCpTxSdUpopJ5abiNz2stY6HtdbxsNY67A++SOWbKm5Ubip+k8pUcaPyiYpJ5RMVk8pUcaNyU3GjMlX8kx7WWsfDWut4WGsd9gdfpDJVTCrfVHGjclPxCZWbihuVqeJGZap4Q+WmYlKZKt5QeaNiUpkqJpWp4hMPa63jYa11PKy1DvuDf5DKTcWNyhsVNypvVEwqn6iYVKaKN1Smim9SmSomld9U8U0Pa63jYa11PKy1jh8+pDJVvFExqUwqU8VNxaRyozJVfKJiUvkmlW9SmSpuVN6ouFH5N3lYax0Pa63jYa11/PDLVKaKSWWq+KaKSeVG5RMVU8WkMlXcVEwqb1RMKlPFjcpNxaRyUzFV3KhMFb/pYa11PKy1joe11vHDX6byhspNxaRyUzGpfKJiUpkq3lB5o+KNiknlpmJSmVSmiknlRmWqmComlZuKTzystY6HtdbxsNY6fvgylW+qmFQmlZuKSeWmYlK5UXmj4o2KG5Wp4m+qmFSmijdUpoqpYlL5poe11vGw1joe1lrHDx+qmFSmiknlDZWpYlL5N1OZKt5QmSqmihuVqWKqeKPipuITFZPKTcU3Pay1joe11vGw1jrsD36Ryk3FGyr/pIpJ5RMVb6jcVEwqb1RMKm9UvKHyTRWfeFhrHQ9rreNhrXX88CGVqeKmYlKZKiaVqeJGZaqYVN6omFRuKm5UblSmipuKb1KZKt5QuamYKiaVNyq+6WGtdTystY6HtdZhf/BFKt9U8QmVm4rfpHJTcaNyU/GGyk3FjcobFZPKVPFv8rDWOh7WWsfDWuv44UMqn6i4UflExaRyo3JTMalMFW+o3FS8oXJT8YbKVDGpTBVvqNxU/E0Pa63jYa11PKy1jh/+YSo3FZ9QmSpuKiaVSWWqmFSmikllqphUJpWpYlL5hMpUcaPyhspUMalMFTcqU8U3Pay1joe11vGw1jp++FDFJ1SmikllqphUbiomlZuKN1R+U8Wk8kbFGyo3FTcqU8WkMlXcqNyoTBWfeFhrHQ9rreNhrXX88C9XMancVEwqU8WNyk3FpPIJlaliUrmpmFTeqJhUpopPqNyoTBVTxY3KNz2stY6HtdbxsNY67A8+oPJNFZPKTcWkclPxTSpvVEwqNxU3KlPFpHJT8QmVv6niNz2stY6HtdbxsNY67A/+w1RuKiaVNyomlTcqblSmir9JZaq4UbmpeENlqphU3qj4xMNa63hYax0Pa63jhw+p/E0VNxU3FZPKVPFGxY3KVDFVTCo3FTcqNxU3KlPFVDGp3KhMFTcqU8WNyjc9rLWOh7XW8bDWOn74sopvUrmpuFH5hMonKj5RcaNyU/EJlanijYo3Kv5JD2ut42GtdTystY4ffpnKGxVvqEwVU8WkMlVMKlPFpDKpTBWfqLhR+U0Vk8qkcqPyTSp/08Na63hYax0Pa63jh/+4ihuVb6p4Q2WqmFTeqHhDZaqYKiaVqWJSmSo+oTKp3FT8poe11vGw1joe1lrHD/9jVN5QuVG5qZhUvqliUpkq3lCZKqaKm4o3VG4qblQmlZuKTzystY6HtdbxsNY6fvhlFX9TxaRyUzGpvKFyU3FTMalMKlPFN6ncVEwqNxXfVHGj8k0Pa63jYa11PKy1DvuDD6j8TRWTym+quFF5o2JSmSpuVKaKT6hMFZPKVPGGyhsVk8pU8Zse1lrHw1rreFhrHfYHa63/97DWOh7WWsfDWut4WGsdD2ut42GtdTystY6HtdbxsNY6HtZax8Na63hYax0Pa63jYa11PKy1jv8D7zzDmjyI5V4AAAAASUVORK5CYII=
33	purchase	\N	PN-1764316797752	1764316858530	payos	0a76049147f444fca1eb7b208bd1d972	100.00	pending	https://pay.payos.vn/web/0a76049147f444fca1eb7b208bd1d972	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CSAOVUSLF58 PayPN17643167977526304324E", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764316858530, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/0a76049147f444fca1eb7b208bd1d972", "description": "CSAOVUSLF58 PayPN1764316797752", "accountNumber": "V3CAS6504398884", "paymentLinkId": "0a76049147f444fca1eb7b208bd1d972"}	\N	2025-11-28 15:00:58.781713	2025-11-28 15:00:58.781713	data:image/png;base64,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
34	purchase	\N	PN-1764316797752	1764317653462	payos	ee85b0429c654100b570f6b2e78e8eed	100.00	pending	https://pay.payos.vn/web/ee85b0429c654100b570f6b2e78e8eed	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CSS3PPX7ND5 PayPN176431679775263041AA9", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764317653462, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/ee85b0429c654100b570f6b2e78e8eed", "description": "CSS3PPX7ND5 PayPN1764316797752", "accountNumber": "V3CAS6504398884", "paymentLinkId": "ee85b0429c654100b570f6b2e78e8eed"}	\N	2025-11-28 15:14:13.733789	2025-11-28 15:14:13.733789	data:image/png;base64,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
35	purchase	\N	PN-1764316797752	1764317659231	payos	8d5125377b4d40cc8e32d5c3d56b7095	100.00	pending	https://pay.payos.vn/web/8d5125377b4d40cc8e32d5c3d56b7095	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CS852B5B099 PayPN176431679775263042DD6", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764317659231, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/8d5125377b4d40cc8e32d5c3d56b7095", "description": "CS852B5B099 PayPN1764316797752", "accountNumber": "V3CAS6504398884", "paymentLinkId": "8d5125377b4d40cc8e32d5c3d56b7095"}	\N	2025-11-28 15:14:19.429949	2025-11-28 15:14:19.429949	data:image/png;base64,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
36	purchase	\N	PN-1764316797752	1764318050110	payos	f1c4d7e0aa064b40849c5801a54982f0	100.00	pending	https://pay.payos.vn/web/f1c4d7e0aa064b40849c5801a54982f0	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CSCM2EK3SD2 PayPN17643167977526304C64C", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764318050110, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/f1c4d7e0aa064b40849c5801a54982f0", "description": "CSCM2EK3SD2 PayPN1764316797752", "accountNumber": "V3CAS6504398884", "paymentLinkId": "f1c4d7e0aa064b40849c5801a54982f0"}	\N	2025-11-28 15:20:50.527291	2025-11-28 15:20:50.527291	data:image/png;base64,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
37	purchase	\N	PN-1764316797752	1764318052928	payos	91fe733c299640bcbb5bdc9414dc6869	100.00	pending	https://pay.payos.vn/web/91fe733c299640bcbb5bdc9414dc6869	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CSWTTJNB8A5 PayPN17643167977526304FE31", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764318052928, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/91fe733c299640bcbb5bdc9414dc6869", "description": "CSWTTJNB8A5 PayPN1764316797752", "accountNumber": "V3CAS6504398884", "paymentLinkId": "91fe733c299640bcbb5bdc9414dc6869"}	\N	2025-11-28 15:20:53.275132	2025-11-28 15:20:53.275132	data:image/png;base64,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
38	purchase	\N	PN-1764316797752	1764318055552	payos	ce73247f4f8a4765805cf8c7cd0e11fb	100.00	pending	https://pay.payos.vn/web/ce73247f4f8a4765805cf8c7cd0e11fb	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CSQSIBCUWB6 PayPN176431679775263049C7F", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764318055552, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/ce73247f4f8a4765805cf8c7cd0e11fb", "description": "CSQSIBCUWB6 PayPN1764316797752", "accountNumber": "V3CAS6504398884", "paymentLinkId": "ce73247f4f8a4765805cf8c7cd0e11fb"}	\N	2025-11-28 15:20:55.741544	2025-11-28 15:20:55.741544	data:image/png;base64,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
39	purchase	\N	PN-1764316797752	1764318300405	payos	1742053f2c2647f0a9eb44d0b4261bf2	100.00	pending	https://pay.payos.vn/web/1742053f2c2647f0a9eb44d0b4261bf2	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CSZW5SVWQV6 PayPN176431679775263041265", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764318300405, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/1742053f2c2647f0a9eb44d0b4261bf2", "description": "CSZW5SVWQV6 PayPN1764316797752", "accountNumber": "V3CAS6504398884", "paymentLinkId": "1742053f2c2647f0a9eb44d0b4261bf2"}	\N	2025-11-28 15:25:00.724166	2025-11-28 15:25:00.724166	data:image/png;base64,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
40	purchase	\N	PN-1764316797752	1764318303978	payos	4b2a1145f685440db3947cf8f2c52765	100.00	pending	https://pay.payos.vn/web/4b2a1145f685440db3947cf8f2c52765	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CSSF43A5OR2 PayPN176431679775263040A35", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764318303978, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/4b2a1145f685440db3947cf8f2c52765", "description": "CSSF43A5OR2 PayPN1764316797752", "accountNumber": "V3CAS6504398884", "paymentLinkId": "4b2a1145f685440db3947cf8f2c52765"}	\N	2025-11-28 15:25:04.308477	2025-11-28 15:25:04.308477	data:image/png;base64,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
41	purchase	\N	PN-1764316797752	1764318313986	payos	f42862b3619543d3b40787b61351e98e	100.00	pending	https://pay.payos.vn/web/f42862b3619543d3b40787b61351e98e	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CSIBL5H3LR3 PayPN17643167977526304BD75", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764318313986, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/f42862b3619543d3b40787b61351e98e", "description": "CSIBL5H3LR3 PayPN1764316797752", "accountNumber": "V3CAS6504398884", "paymentLinkId": "f42862b3619543d3b40787b61351e98e"}	\N	2025-11-28 15:25:14.183311	2025-11-28 15:25:14.183311	data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAMQAAADECAYAAADApo5rAAAAAklEQVR4AewaftIAAAk8SURBVO3BQW4EyZEAQfcC//9lX0KHRJwSKDTJ0WjDzL6x1vqPh7XW8bDWOh7WWsfDWut4WGsdD2ut42GtdTystY6HtdbxsNY6HtZax8Na63hYax0Pa63jYa11fPEhlb9UcaNyUzGp3FR8QuUTFZPKTcWNyhsVk8pNxaTylyo+8bDWOh7WWsfDWuv44odV/CSVG5Wp4kblpuINlZuKSWWquFG5qZhUpoqbiknljYo3Kn6Syk96WGsdD2ut42GtdXzxy1TeqHijYlKZKm4qflLFTcWk8gmVqeKmYlKZKiaVG5Wp4g2VNyp+08Na63hYax0Pa63ji/8xFTcVb6jcVEwqU8VfUpkqJpUblani/5OHtdbxsNY6HtZaxxf/ciqfqJhUpooblaniRmWquFGZKiaVqeKmYlKZKiaVNyr+zR7WWsfDWut4WGsdX/yyit9UMalMFZPKpDJV/KaKG5U3KiaVqeINlaliUvlJFf9NHtZax8Na63hYax1f/DCVv6QyVUwqU8WkcqMyVbyhMlVMKlPFpHKjMlVMKlPFTcWkMlVMKm+o/Dd7WGsdD2ut42Gtddg3/oeo3FRMKm9U3Ki8UTGpTBWTylQxqUwVk8onKv6XPay1joe11vGw1jq++JDKVDGpTBWTylQxqUwVn1CZKv5SxU3FpDJVTCpTxaQyVUwqU8Wk8ptUpooblaniJz2stY6HtdbxsNY67BsfUJkq/pLKTcWkMlVMKlPFb1L5RMUbKlPFpDJVTCo3FTcqU8WkMlXcqEwVn3hYax0Pa63jYa11fPGhiknljYoblTcqfpPKTcWkMlXcVNyo3KjcVEwqU8VNxaQyqbyhMlVMKlPFb3pYax0Pa63jYa112Dc+oDJVTCpTxaRyU3GjclPxhspUcaNyUzGpTBWTylTxk1TeqJhUpopJZaqYVKaKSWWq+EsPa63jYa11PKy1DvvGD1KZKt5Qual4Q2WquFGZKiaVm4pJZaqYVN6ouFH5TRWTylQxqUwVk8pUMam8UfGJh7XW8bDWOh7WWscXv0xlqnijYlKZKj6hcqNyUzGpTBWTyhsVk8pUMVXcqNxUvFExqbxRcVPxlx7WWsfDWut4WGsdX/zDVG5UfpLKVDGpTBWTyqRyo/JGxaQyVfwllaliUnlD5aZiUnmj4hMPa63jYa11PKy1ji8+pDJVvFExqUwVb6hMFZPKTcWk8omKG5WbikllqnijYlKZVKaKSeWm4g2VT1T8pIe11vGw1joe1lrHFx+qeEPlpmJSmSomlTcq3qiYVKaKN1RuVG4qJpWp4kblJ1XcqNxUvFExqUwVn3hYax0Pa63jYa11fPEhlZuKqWJSuam4qZhUJpWpYlKZKn6Syk3FpHKjMlV8omJSual4o2JS+YTKVPGTHtZax8Na63hYax1f/DKVqeINlU9UTCpTxRsVNypTxRsVk8pUMancVLxRMalMFZPKGxVvVEwqk8pU8YmHtdbxsNY6HtZaxxcfqphUpoqbikllqphUbipuKiaVqWJSmSpuKt5Q+UTFT1KZKiaVm4oblZuKSeUvPay1joe11vGw1jq++JDKGypvqLyhMlW8oXKjclPxiYpJZVK5qfhExaQyVUwqNypTxaTy3+RhrXU8rLWOh7XWYd/4B6ncVLyhclNxozJV3KjcVEwqn6i4UZkq3lCZKiaVm4pJ5Y2KSeWm4ic9rLWOh7XW8bDWOuwbv0hlqrhR+UTFpHJTMalMFZ9QeaNiUpkqJpWpYlJ5o2JSuamYVN6o+ITKVPGJh7XW8bDWOh7WWscXH1L5SRVvqEwqb6jcqNxUTCpTxaQyVUwqn1CZKt5QmSr+kspUcVPxkx7WWsfDWut4WGsdX3yo4g2VqWJSuan4N1H5RMVNxaQyqUwVk8pUcaMyVUwVk8pUMalMFZPKGxWfeFhrHQ9rreNhrXV88SGVm4pPVLxRMalMFTcqU8WkMqlMFTcqk8pPqviEylTxhspUMalMFZPKVHGj8pMe1lrHw1rreFhrHV/8sIpJ5UZlqphUpoo3Kj6hMlVMKpPKJyreUJkqPlExqUwVk8pUMancqLyhMlX8pIe11vGw1joe1lqHfeMPqbxRMalMFW+oTBWTylRxozJVTCpTxSdUpopJZaqYVKaKT6jcVEwqU8WkMlX8pYe11vGw1joe1lqHfeMHqbxRMan8kyomlaniDZWp4kblpmJSmSomlaniDZWbihuVNypuVG4qPvGw1joe1lrHw1rrsG/8g1RuKm5UPlExqUwVk8pUcaNyU3Gj8omKSWWqmFSmihuVT1TcqEwVv+lhrXU8rLWOh7XW8cWHVKaKSeUTKlPFVDGp/KaKSWWquKl4o2JSuamYVKaKT6hMFZ9QmSqmihuVqeITD2ut42GtdTystQ77xg9SmSp+k8pNxV9SmSomlaniEyqfqHhDZaqYVKaKSeWNir/0sNY6HtZax8Na67BvfEBlqphUbipuVKaKG5WfVHGj8kbFpPKTKj6hclMxqfykikllqphUpopPPKy1joe11vGw1jq++FDFTcUnKm5UpopJ5abiRmWq+EkVb6jcqHyi4kblpuINlZuKv/Sw1joe1lrHw1rr+OJDKn+pYqqYVKaKSeVGZaqYVG4qJpUblZuKNyomlTdUpoqpYlK5UZkqblT+SQ9rreNhrXU8rLUO+8YHVKaKn6QyVfwlld9U8QmVNyomlaniRuWm4g2Vm4q/9LDWOh7WWsfDWuv44pepvFHxhspUcaMyVdxUfELlL1VMKpPKVPFGxaQyqfwklZuKn/Sw1joe1lrHw1rr+OJfrmJSuamYVG4qJpWpYlK5qfiEyj9J5Y2KSWWquFH5Sw9rreNhrXU8rLWOL/7lVKaKSeWmYlK5qbip+E0Vk8pNxRsqNxWTyo3KVDGpTBVTxY3KVPGJh7XW8bDWOh7WWscXv6ziN1XcVEwqU8VUMancVEwqU8WkMlVMKlPFTcWk8kbFTcUbFTcqU8WkclMxVfykh7XW8bDWOh7WWscXP0zlL6ncVNyoTBVTxSdUblSmiknlpuKm4o2KSeWm4hMqU8WkcqMyVXziYa11PKy1joe11mHfWGv9x8Na63hYax0Pa63jYa11PKy1joe11vGw1joe1lrHw1rreFhrHQ9rreNhrXU8rLWOh7XW8bDWOv4PkoQrlT6MaMkAAAAASUVORK5CYII=
42	purchase	\N	PN-1764316797752	1764318369158	payos	04bec11db5924c55b8f20304fd666c7e	100.00	pending	https://pay.payos.vn/web/04bec11db5924c55b8f20304fd666c7e	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CS8USO4Z931 PayPN17643167977526304A5AB", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764318369158, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/04bec11db5924c55b8f20304fd666c7e", "description": "CS8USO4Z931 PayPN1764316797752", "accountNumber": "V3CAS6504398884", "paymentLinkId": "04bec11db5924c55b8f20304fd666c7e"}	\N	2025-11-28 15:26:09.454513	2025-11-28 15:26:09.454513	data:image/png;base64,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
43	purchase	\N	PN-1764316797752	1764319604058	payos	1ea916acb8e94cc78da788ea99fd8ab6	100.00	pending	https://pay.payos.vn/web/1ea916acb8e94cc78da788ea99fd8ab6	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CSL0BWR9FC5 PayPN176431679775263040BC4", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764319604058, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/1ea916acb8e94cc78da788ea99fd8ab6", "description": "CSL0BWR9FC5 PayPN1764316797752", "accountNumber": "V3CAS6504398884", "paymentLinkId": "1ea916acb8e94cc78da788ea99fd8ab6"}	\N	2025-11-28 15:46:44.353059	2025-11-28 15:46:44.353059	data:image/png;base64,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
44	purchase	\N	PN-1764316797752	1764319607485	payos	270a7c2105024ef9a399b601ede8cb3f	100.00	pending	https://pay.payos.vn/web/270a7c2105024ef9a399b601ede8cb3f	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CSOOHP32BF9 PayPN17643167977526304A934", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764319607485, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/270a7c2105024ef9a399b601ede8cb3f", "description": "CSOOHP32BF9 PayPN1764316797752", "accountNumber": "V3CAS6504398884", "paymentLinkId": "270a7c2105024ef9a399b601ede8cb3f"}	\N	2025-11-28 15:46:47.634034	2025-11-28 15:46:47.634034	data:image/png;base64,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
45	purchase	\N	PN-1764316797752	1764319714304	payos	baa971afdeeb46419b45b1a044495d52	100.00	pending	https://pay.payos.vn/web/baa971afdeeb46419b45b1a044495d52	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CSMBBPFRJ88 PayPN176431679775263041DB8", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764319714304, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/baa971afdeeb46419b45b1a044495d52", "description": "CSMBBPFRJ88 PayPN1764316797752", "accountNumber": "V3CAS6504398884", "paymentLinkId": "baa971afdeeb46419b45b1a044495d52"}	\N	2025-11-28 15:48:34.519974	2025-11-28 15:48:34.519974	data:image/png;base64,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
46	purchase	\N	PN-1764316797752	1764319751853	payos	5adca62ad48240b89861f980cfff1f19	100.00	pending	https://pay.payos.vn/web/5adca62ad48240b89861f980cfff1f19	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CSRUEGZGWC2 PayPN17643167977526304809B", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764319751853, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/5adca62ad48240b89861f980cfff1f19", "description": "CSRUEGZGWC2 PayPN1764316797752", "accountNumber": "V3CAS6504398884", "paymentLinkId": "5adca62ad48240b89861f980cfff1f19"}	\N	2025-11-28 15:49:12.090112	2025-11-28 15:49:12.090112	data:image/png;base64,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
47	purchase	\N	PN-1764316797752	1764319753721	payos	211dc8917d6d41c68be0169f34c207c9	100.00	pending	https://pay.payos.vn/web/211dc8917d6d41c68be0169f34c207c9	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CSNWJ0RC425 PayPN17643167977526304C95B", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764319753721, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/211dc8917d6d41c68be0169f34c207c9", "description": "CSNWJ0RC425 PayPN1764316797752", "accountNumber": "V3CAS6504398884", "paymentLinkId": "211dc8917d6d41c68be0169f34c207c9"}	\N	2025-11-28 15:49:13.861706	2025-11-28 15:49:13.861706	data:image/png;base64,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
48	purchase	\N	PN-1764316797752	1764320449270	payos	a2fce82c8ee04744aa4eea9c5da364ae	100.00	pending	https://pay.payos.vn/web/a2fce82c8ee04744aa4eea9c5da364ae	{"bin": "970418", "amount": 100, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454031005802VN62340830CS8KZF4PQH4 PayPN176431679775263043F7D", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764320449270, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/a2fce82c8ee04744aa4eea9c5da364ae", "description": "CS8KZF4PQH4 PayPN1764316797752", "accountNumber": "V3CAS6504398884", "paymentLinkId": "a2fce82c8ee04744aa4eea9c5da364ae"}	\N	2025-11-28 16:00:49.563076	2025-11-28 16:00:49.563076	data:image/png;base64,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
49	purchase	\N	PN-20251128-160537	1764320737847	payos	29e1d530836a4cebad3d18be9da27923	2000.00	pending	https://pay.payos.vn/web/29e1d530836a4cebad3d18be9da27923	{"bin": "970418", "amount": 2000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA5303704540420005802VN62350831CS27TWHW999 PayPN20251128160537630463BA", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764320737847, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/29e1d530836a4cebad3d18be9da27923", "description": "CS27TWHW999 PayPN20251128160537", "accountNumber": "V3CAS6504398884", "paymentLinkId": "29e1d530836a4cebad3d18be9da27923"}	\N	2025-11-28 16:05:38.07122	2025-11-28 16:05:38.07122	data:image/png;base64,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
50	purchase	\N	PN-1764320737806	1764320745956	payos	1a747e874ac04fb8abae760b399b5242	2000.00	completed	https://pay.payos.vn/web/1a747e874ac04fb8abae760b399b5242	{"code": "00", "desc": "success", "amount": 2000, "currency": "VND", "orderCode": 1764320745956, "reference": "5f499439-b3b6-4ea1-9ca0-3cfa8d0da3f7", "description": "CSGJDOU4Y13 PayPN1764320737806", "accountNumber": "6504398884", "paymentLinkId": "1a747e874ac04fb8abae760b399b5242", "counterAccountName": null, "virtualAccountName": "", "transactionDateTime": "2025-11-28 16:06:11", "counterAccountBankId": "", "counterAccountNumber": null, "virtualAccountNumber": "V3CAS6504398884", "counterAccountBankName": ""}	\N	2025-11-28 16:05:46.152564	2025-11-28 16:06:12.321078	data:image/png;base64,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
51	purchase	\N	PN-20251128-161314	1764321194592	payos	3a4ba8b2b31f4ada9c0534dc0a6903b4	3000.00	pending	https://pay.payos.vn/web/3a4ba8b2b31f4ada9c0534dc0a6903b4	{"bin": "970418", "amount": 3000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA5303704540430005802VN62350831CSALSUQL5T2 PayPN20251128161314630420FD", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764321194592, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/3a4ba8b2b31f4ada9c0534dc0a6903b4", "description": "CSALSUQL5T2 PayPN20251128161314", "accountNumber": "V3CAS6504398884", "paymentLinkId": "3a4ba8b2b31f4ada9c0534dc0a6903b4"}	\N	2025-11-28 16:13:14.772438	2025-11-28 16:13:14.772438	data:image/png;base64,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
52	purchase	\N	PN-1764321194559	1764321201733	payos	1a5f68707cb04a948fbffe3d523b77da	3000.00	pending	https://pay.payos.vn/web/1a5f68707cb04a948fbffe3d523b77da	{"bin": "970418", "amount": 3000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA5303704540430005802VN62340830CSLQ1TWWDB1 PayPN17643211945596304478F", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764321201733, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/1a5f68707cb04a948fbffe3d523b77da", "description": "CSLQ1TWWDB1 PayPN1764321194559", "accountNumber": "V3CAS6504398884", "paymentLinkId": "1a5f68707cb04a948fbffe3d523b77da"}	\N	2025-11-28 16:13:21.984998	2025-11-28 16:13:21.984998	data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAMQAAADECAYAAADApo5rAAAAAklEQVR4AewaftIAAAkeSURBVO3BQYolyZIAQdUg739lnWIWjq0cgveyuvtjIvYHa63/97DWOh7WWsfDWut4WGsdD2ut42GtdTystY6HtdbxsNY6HtZax8Na63hYax0Pa63jYa11PKy1jh8+pPI3Vbyh8kbFGypTxaQyVUwq31QxqUwVk8pUMam8UTGp/E0Vn3hYax0Pa63jYa11/PBlFd+kcqNyU3Gj8omKSWWquKm4UbmpmFSmikllqnijYlJ5o+KbVL7pYa11PKy1joe11vHDL1N5o+KNihuVN1Q+UfGGyhsVk8pU8QmVqWJS+SaVNyp+08Na63hYax0Pa63jh/9xFTcqNxU3KpPKVDGpfELlRmWqmComlU9U/C95WGsdD2ut42GtdfzwH6dyUzGpfEJlqnij4g2VqWJSmSo+UTGp3KhMFf9lD2ut42GtdTystY4fflnFb6qYVG4qvkllqrhR+aaKSWWqeENlqphUvqni3+RhrXU8rLWOh7XW8cOXqfxNKlPFpDJVTCpTxaQyVUwqNypTxaQyVUwqNypTxaQyVdxUTCpTxaTyhsq/2cNa63hYax0Pa63D/uB/iMobFZPKTcWNyhsVk8pUMalMFZPKVDGpfKLif9nDWut4WGsdD2ut44cPqUwVk8pUMalMFZPKVPGbKn5TxU3FpDJVTCpTxaQyVUwqU8Wk8ptUpooblanimx7WWsfDWut4WGsdP/xlKlPFpDJVTCo3FTcqv6niDZWp4kZlqripmFSmikllqphUbipuVKaKSWWqmComlaniEw9rreNhrXU8rLWOHz5U8UbFpDJVTCo3FTcqb6h8omJSmSreqJhUblRuKiaVqeKmYlJ5o2JSmSomlaniNz2stY6HtdbxsNY67A8+oPJGxaRyU/GGyk3FN6ncVEwqU8WkMlV8k8obFZPKVDGpTBWTylQxqUwVk8pU8U0Pa63jYa11PKy1DvuDL1KZKt5QeaNiUrmpuFF5o+JGZaqYVN6ouFH5TRWTyhsVk8pUMalMFZPKVPGJh7XW8bDWOh7WWscPv0xlqnijYlL5hMpNxRsqNxWTyhsVk8pUcVMxqbxRcVPxiYqbikllqvimh7XW8bDWOh7WWof9wRep/E0Vk8pUcaNyU/GGym+quFH5TRWTyjdVTCpTxaQyVXziYa11PKy1joe11vHDh1Smik+oTBWTyqTyTRWTylRxU/GGyhsqU8VNxY3KVDGpTCpTxSdUPlHxTQ9rreNhrXU8rLWOHz5UcaPyRsWk8gmVqWKqeENlqrhRuam4UZkqJpWp4kblExWTylQxqdxUfEJlqvjEw1rreFhrHQ9rrcP+4AMqNxV/k8pUcaMyVbyhMlW8oXJT8QmVqeJGZaqYVG4qblSmijdUpopvelhrHQ9rreNhrXX88MtUpoobld+kMlV8k8pU8UbFpPKJiknlpmJSmSomlUnlpuJG5Q2VqeITD2ut42GtdTystY4fflnFJyomlW9S+UTFJyomlU9U3FTcqEwVk8pU8YbKTcWk8jc9rLWOh7XW8bDWOn74UMWkcqPyhso3VXxC5ZtUpopJ5W+qmFSmikllqphUPlExqfymh7XW8bDWOh7WWscPX1ZxUzGp3FTcqHyTyk3FpHJTMancqNxU3KhMFW+oTBWTyjdVTCpvVHzTw1rreFhrHQ9rreOHL1OZKm4qblSmiqniRmWqmFRuKt6omFTeqJhUblSmiknljYpJ5abijYo3Km5UpopPPKy1joe11vGw1jrsD36RylRxozJVvKFyU3GjclMxqdxUTCpTxaRyUzGp3FS8oTJV/CaVNyp+08Na63hYax0Pa63D/uADKm9UTCpTxaTyb1YxqbxRMalMFW+o3FRMKlPFjcpUMal8U8WkclPxiYe11vGw1joe1lrHDx+q+ETFTcUbKjcVNypTxaQyqdxUTCqTyjdVfEJlqvhNFZPKP+lhrXU8rLWOh7XW8cOHVD5RcaMyVdxUfKJiUpkqJpWpYlJ5o+INlaniExWTylQxqUwVNyqTyr/Jw1rreFhrHQ9rreOHD1VMKlPFjcpUMVXcqNxUTCpTxU3FGyo3FZ9QmSomlaliUpkqbip+U8WkclMxqXzTw1rreFhrHQ9rreOHD6ncqEwVU8WNyk3FpPIJlZuK36RyUzGpTBWTylTxhsonVG5Upop/0sNa63hYax0Pa63D/uCLVKaKG5Wp4hMqn6j4hMpUMalMFTcqn6iYVKaKSWWqmFSmihuVm4oblaniNz2stY6HtdbxsNY67A8+oDJVTCpTxaTyiYpJ5aZiUnmj4jepfKLiEypTxaRyU/GGylTxhspU8YmHtdbxsNY6HtZah/3BF6ncVHyTylTxhspUMalMFW+o3FTcqEwVk8pNxaQyVdyo3FRMKlPFpPJGxaRyU/GJh7XW8bDWOh7WWscPH1KZKiaVSWWquFGZKqaKSWWqmFQ+oXJTcVMxqUwVU8WkclMxqUwV36Ryo/JGxaQyVUwq3/Sw1joe1lrHw1rr+OFDFTcVn6i4UZkqJpWbim9SmSomlanijYoblaliUpkqvqniDZV/k4e11vGw1joe1lrHDx9S+ZsqpoqbikllUpkqpopJ5aZiUrlRuam4UZkqJpWpYlK5qZhU3lCZKj6h8pse1lrHw1rreFhrHT98WcU3qfxNKjcVNyo3Fd9UMal8ouKbKj5R8Tc9rLWOh7XW8bDWOn74ZSpvVLyh8omKSWWqeKNiUplUpoo3VG4qJpWbijcqJpVJ5RMqb1R808Na63hYax0Pa63jh/+4ikllqphUJpVPqLxR8U9SmSreUJkqJpWpYlKZKiaVf9LDWut4WGsdD2ut44f/OJWpYlKZKm5UPlHxmyomlZuKN1RuKiaVG5WpYlKZKiaVqWJSmSo+8bDWOh7WWsfDWuv44ZdV/KaKm4pJZaqYKiaVN1SmikllqphUpoqbiknljYqbijcqblSmik9UfNPDWut4WGsdD2utw/7gAyp/U8WkclMxqdxUfELlExWTyk3FpDJVfELlpuINlTcqblSmik88rLWOh7XW8bDWOuwP1lr/72GtdTystY6HtdbxsNY6HtZax8Na63hYax0Pa63jYa11PKy1joe11vGw1joe1lrHw1rreFhrHf8HXn0Pk4TposQAAAAASUVORK5CYII=
53	purchase	\N	PN-20251128-161341	1764321221862	payos	712b15e206ca423daf3be76a917d3e4e	5000.00	pending	https://pay.payos.vn/web/712b15e206ca423daf3be76a917d3e4e	{"bin": "970418", "amount": 5000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA5303704540450005802VN62350831CSMTP9L5RN9 PayPN202511281613416304D97C", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764321221862, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/712b15e206ca423daf3be76a917d3e4e", "description": "CSMTP9L5RN9 PayPN20251128161341", "accountNumber": "V3CAS6504398884", "paymentLinkId": "712b15e206ca423daf3be76a917d3e4e"}	\N	2025-11-28 16:13:42.037194	2025-11-28 16:13:42.037194	data:image/png;base64,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
54	purchase	\N	PN-1764321221830	1764321228676	payos	e7ffe421c86c4b2fbf3d32d0132ca859	5000.00	pending	https://pay.payos.vn/web/e7ffe421c86c4b2fbf3d32d0132ca859	{"bin": "970418", "amount": 5000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA5303704540450005802VN62340830CSRR0DQ7KL3 PayPN1764321221830630415F0", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764321228676, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/e7ffe421c86c4b2fbf3d32d0132ca859", "description": "CSRR0DQ7KL3 PayPN1764321221830", "accountNumber": "V3CAS6504398884", "paymentLinkId": "e7ffe421c86c4b2fbf3d32d0132ca859"}	\N	2025-11-28 16:13:48.873335	2025-11-28 16:13:48.873335	data:image/png;base64,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
55	purchase	\N	PN-1764321221830	1764752839435	payos	9aa5d0e7b51a4a6f966d5cb1eb8eb704	5000.00	pending	https://pay.payos.vn/web/9aa5d0e7b51a4a6f966d5cb1eb8eb704	{"bin": "970418", "amount": 5000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA5303704540450005802VN62340830CS0O6OJG0M9 PayPN176432122183063049A7F", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764752839435, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/9aa5d0e7b51a4a6f966d5cb1eb8eb704", "description": "CS0O6OJG0M9 PayPN1764321221830", "accountNumber": "V3CAS6504398884", "paymentLinkId": "9aa5d0e7b51a4a6f966d5cb1eb8eb704"}	\N	2025-12-03 16:07:20.860742	2025-12-03 16:07:20.860742	data:image/png;base64,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
56	purchase	\N	PN-1764321221830	1764752840886	payos	a420425a67e2426d94b68d11845604fb	5000.00	pending	https://pay.payos.vn/web/a420425a67e2426d94b68d11845604fb	{"bin": "970418", "amount": 5000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA5303704540450005802VN62340830CS6VQ6LCMI8 PayPN17643212218306304A6C8", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764752840886, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/a420425a67e2426d94b68d11845604fb", "description": "CS6VQ6LCMI8 PayPN1764321221830", "accountNumber": "V3CAS6504398884", "paymentLinkId": "a420425a67e2426d94b68d11845604fb"}	\N	2025-12-03 16:07:21.055697	2025-12-03 16:07:21.055697	data:image/png;base64,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
57	purchase	\N	PN-1764321221830	1764752843035	payos	e04dab3d5176482aa5941affd50b8300	5000.00	pending	https://pay.payos.vn/web/e04dab3d5176482aa5941affd50b8300	{"bin": "970418", "amount": 5000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA5303704540450005802VN62340830CS88MF09NY5 PayPN176432122183063048328", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764752843035, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/e04dab3d5176482aa5941affd50b8300", "description": "CS88MF09NY5 PayPN1764321221830", "accountNumber": "V3CAS6504398884", "paymentLinkId": "e04dab3d5176482aa5941affd50b8300"}	\N	2025-12-03 16:07:23.200565	2025-12-03 16:07:23.200565	data:image/png;base64,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
58	purchase	\N	PN-1764321221830	1764752840211	payos	f0bbb96652904ce4aa783edccab5063a	5000.00	pending	https://pay.payos.vn/web/f0bbb96652904ce4aa783edccab5063a	{"bin": "970418", "amount": 5000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA5303704540450005802VN62340830CSVUN1NZE47 PayPN1764321221830630428B2", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764752840211, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/f0bbb96652904ce4aa783edccab5063a", "description": "CSVUN1NZE47 PayPN1764321221830", "accountNumber": "V3CAS6504398884", "paymentLinkId": "f0bbb96652904ce4aa783edccab5063a"}	\N	2025-12-03 16:07:23.748829	2025-12-03 16:07:23.748829	data:image/png;base64,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
59	purchase	\N	PN-1764321221830	1764752839050	payos	4aec90dd15094116ac4659e0d529bfa9	5000.00	pending	https://pay.payos.vn/web/4aec90dd15094116ac4659e0d529bfa9	{"bin": "970418", "amount": 5000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA5303704540450005802VN62340830CSIPR8JDB72 PayPN17643212218306304A49E", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764752839050, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/4aec90dd15094116ac4659e0d529bfa9", "description": "CSIPR8JDB72 PayPN1764321221830", "accountNumber": "V3CAS6504398884", "paymentLinkId": "4aec90dd15094116ac4659e0d529bfa9"}	\N	2025-12-03 16:07:23.833861	2025-12-03 16:07:23.833861	data:image/png;base64,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
60	purchase	\N	PN-1764321221830	1764752845336	payos	e55c785ba64247f19e328f8c757e3186	5000.00	pending	https://pay.payos.vn/web/e55c785ba64247f19e328f8c757e3186	{"bin": "970418", "amount": 5000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA5303704540450005802VN62340830CS62E7ZW536 PayPN17643212218306304CB79", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764752845336, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/e55c785ba64247f19e328f8c757e3186", "description": "CS62E7ZW536 PayPN1764321221830", "accountNumber": "V3CAS6504398884", "paymentLinkId": "e55c785ba64247f19e328f8c757e3186"}	\N	2025-12-03 16:07:25.483551	2025-12-03 16:07:25.483551	data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAMQAAADECAYAAADApo5rAAAAAklEQVR4AewaftIAAAk5SURBVO3BQYolyZIAQdUg739lnWIWjq0cgveyuvtjIvYHa63/97DWOh7WWsfDWut4WGsdD2ut42GtdTystY6HtdbxsNY6HtZax8Na63hYax0Pa63jYa11PKy1jh8+pPI3VdyoTBWTylTxm1SmiknlmypuVG4qJpU3KiaVv6niEw9rreNhrXU8rLWOH76s4ptUblSmikllqphUpopJ5aZiUpkqbipuVG4qJpWp4qbipuJG5Y2Kb1L5poe11vGw1joe1lrHD79M5Y2KNypuKiaVqeKbKt5QeaNiUpkq3lD5J6m8UfGbHtZax8Na63hYax0//I9Rual4o+JG5aZiUpkqJpUblRuVqeITFZPKVPG/5GGtdTystY6Htdbxw3+cyjepfKLiExWTylQxqUwVNxWTylQxqdyoTBX/ZQ9rreNhrXU8rLWOH35ZxW+qmFSmihuVqeJG5ZtUPlExqUwVb6hMFZPKN1X8mzystY6HtdbxsNY6fvgylb9JZaqYVKaKN1SmiknlRmWqmFSmiknlRmWqmFSmipuKSWWqmFTeUPk3e1hrHQ9rreNhrXXYH/wPUbmpuFH5myomlaliUpkqJpWpYlL5RMX/soe11vGw1joe1lrHDx9SmSomlaliUpkqJpWp4hMqU8VU8QmVm4qbikllqphUpopJZaqYVKaKSeU3qUwVNypTxTc9rLWOh7XW8bDWOuwPfpHKGxW/SWWq+CepTBWTyk3FGypTxaQyVUwqNxU3KlPFpDJV3KhMFZ94WGsdD2ut42GtdfzwIZU3Km5UbireUPkmlZuKSWWqeKNiUrlRuamYVKaKm4pJ5Y2KSWWqmFSmit/0sNY6HtZax8Na67A/+IDKTcWkMlVMKlPFGypTxSdUpopJ5aZiUpkqJpWp4ptU3qiYVKaKSWWqmFSmikllqphUpopvelhrHQ9rreNhrXX88KGKSeUTFZPKVDGpTBWTylRxozJVTCo3FZPKVDGp3KhMFTcq36QyVbyhMlVMKlPFpDJVTCpTxSce1lrHw1rreFhrHfYHv0hlqvgmlW+qmFRuKiaVqWJSeaNiUpkq3lB5o+JG5abim1Smim96WGsdD2ut42GtddgffJHKVHGj8kbFJ1TeqJhUpopJ5TdVvKHyTRWTyjdVTCpTxaQyVXziYa11PKy1joe11vHDh1SmijcqJpWpYlK5qZhUbiomlW+quFF5Q2WquKm4UZkqJpWbik+ofKLimx7WWsfDWut4WGsdP3yo4kbljYpJ5Q2VqWJSmVR+k8pNxY3KVDGp3FRMKlPFJ1SmiknlpuITKlPFJx7WWsfDWut4WGsd9gcfULmpuFGZKj6hclMxqUwVb6hMFW+o3FT8JpWp4kblpuJGZap4Q2Wq+KaHtdbxsNY6HtZah/3BB1TeqHhD5RMVb6h8U8WNylQxqXyi4hMqU8Wk8kbFjconKj7xsNY6HtZax8Na67A/+AepTBU3Kp+omFSmijdUpopPqHyi4g2Vm4pJZap4Q+WmYlJ5o+ITD2ut42GtdTystY4fvkxlqnhD5Y2KSWWquKmYVG4qpopPqEwVk8o3qUwVNypTxaQyVUwqNxU3FZPKb3pYax0Pa63jYa11/PAhlanijYpJZaqYVN5QmSomlTdU3qiYVG5UbipuVKaKqeJGZaqYVD5RMalMFZPKTcU3Pay1joe11vGw1jrsD36Ryk3FjcpU8YbKTcWkMlVMKlPFjcobFZPKVDGpTBWTyhsVk8pNxY3KN1VMKlPFJx7WWsfDWut4WGsdP3xI5aZiUrlRmSreUPkmlRuVm4pJZaqYVD6hMlW8oTJVfKJiUpkqJpWp4qbimx7WWsfDWut4WGsd9gdfpHJTMam8UTGpvFExqbxRcaPyRsWkMlW8oXJTMalMFTcqU8Wk8k+q+MTDWut4WGsdD2ut44cvq5hUJpWbihuVm4pJ5aZiUpkqJpU3KiaVSeWbKj6hMlX8popJZaqYVH7Tw1rreFhrHQ9rreOHD6lMFZ9QeaNiUvlExU3FpDJVTCpvVLyhMlV8omJSmSomlaliUrlR+Td5WGsdD2ut42GtdfzwZSpTxaQyVbyhclMxqUwqU8WkclNxo3JT8QmVqWJSmSomlanipuINlTcqJpWbiknlmx7WWsfDWut4WGsdP3yoYlKZVG5U3qj4myr+JpWbikllqphUpoo3VN6omFRuVKaKf9LDWut4WGsdD2ut44cvq7hReaPiRmWq+DepmFSmiqliUplUblSmikllqphUpoo3VKaKSWWquFGZKqaKb3pYax0Pa63jYa112B98QGWqmFT+popJZaqYVKaKf5LKJyo+oXJTMalMFW+oTBVvqEwVn3hYax0Pa63jYa112B98kcpUMalMFd+kMlVMKjcVb6hMFZPKTcWNylQxqdxUTCpTxaQyVbyhMlVMKm9UTCo3FZ94WGsdD2ut42GtdfzwIZWpYlL5hMpNxY3KVPGGyjdVTCpTxVQxqbyhMlW8oTJVTCo3Km9UTCpTxaTyTQ9rreNhrXU8rLWOHz5UcVPxiYoblaliUvlExaQyVUwqU8WkMlX8popJZaqYKm5UbireUPk3eVhrHQ9rreNhrXX88CGVv6liqphUblRuKiaVG5WpYlK5UbmpmComlaliUrlRuan4hMpU8QmV3/Sw1joe1lrHw1rr+OHLKr5J5RMVk8qNylQxqdyo3FT8JpU3Kn5TxScq/qaHtdbxsNY6HtZaxw+/TOWNijdUpopJ5aZiUnmj4kZlUpkqvqliUpkqPlExqUwqn1B5o+KbHtZax8Na63hYax0//MdVTCo3FZPKjcobKjcVn1D5hMpU8YbKVDGpTBWTylTxhspvelhrHQ9rreNhrXX88B+nMlVMKp+oeKPiN1VMKjcVb6jcVEwqNypTxaQyVdxUTCpTxSce1lrHw1rreFhrHT/8sorfVHFT8UbFpPKJikllqphUpoqbiknljYqbijcqblSmihuVqWKq+KaHtdbxsNY6HtZah/3BB1T+popJ5aZiUrmpuFGZKiaVT1RMKjcVk8pU8QmVm4o3VG4q3lCZKj7xsNY6HtZax8Na67A/WGv9v4e11vGw1joe1lrHw1rreFhrHQ9rreNhrXU8rLWOh7XW8bDWOh7WWsfDWut4WGsdD2ut42Gtdfwfl2QUu76381IAAAAASUVORK5CYII=
61	order	HD-20251205-114600	\N	1764909960620	payos	5b71d83c946c46d399209026769e6c18	20000.00	completed	https://pay.payos.vn/web/5b71d83c946c46d399209026769e6c18	{"code": "00", "desc": "success", "amount": 20000, "currency": "VND", "orderCode": 1764909960620, "reference": "302bd750-d0c0-4843-81f8-d1e4d58a6373", "description": "CSZQEVQFES3 PayHD20251205114600", "accountNumber": "6504398884", "paymentLinkId": "5b71d83c946c46d399209026769e6c18", "counterAccountName": null, "virtualAccountName": "", "transactionDateTime": "2025-12-05 11:46:41", "counterAccountBankId": "", "counterAccountNumber": "0", "virtualAccountNumber": "V3CAS6504398884", "counterAccountBankName": ""}	\N	2025-12-05 11:46:01.080038	2025-12-05 11:46:41.476053	data:image/png;base64,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
62	order	HD-20251205-114732	\N	1764910052123	payos	535c1378461a400c8fb81257ba89837e	10000.00	pending	https://pay.payos.vn/web/535c1378461a400c8fb81257ba89837e	{"bin": "970418", "amount": 10000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA53037045405100005802VN62350831CSJF35S9N75 PayHD20251205114732630489ED", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1764910052123, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/535c1378461a400c8fb81257ba89837e", "description": "CSJF35S9N75 PayHD20251205114732", "accountNumber": "V3CAS6504398884", "paymentLinkId": "535c1378461a400c8fb81257ba89837e"}	\N	2025-12-05 11:47:32.381284	2025-12-05 11:47:32.381284	data:image/png;base64,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
63	purchase	\N	PN-1764760554147	1765103802508	payos	f3e2cddaa44048f295060994bf958edc	4000.00	pending	https://pay.payos.vn/web/f3e2cddaa44048f295060994bf958edc	{"bin": "970418", "amount": 4000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA5303704540440005802VN62340830CSHSPOWJZO8 PayPN176476055414763046830", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1765103802508, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/f3e2cddaa44048f295060994bf958edc", "description": "CSHSPOWJZO8 PayPN1764760554147", "accountNumber": "V3CAS6504398884", "paymentLinkId": "f3e2cddaa44048f295060994bf958edc"}	\N	2025-12-07 17:36:42.944862	2025-12-07 17:36:42.944862	data:image/png;base64,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
64	order	HD-20251207-183914	\N	1765107554343	payos	572cf75cd38148f182da9e6e55707e24	18000.00	pending	https://pay.payos.vn/web/572cf75cd38148f182da9e6e55707e24	{"bin": "970418", "amount": 18000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA53037045405180005802VN62350831CS7P7QUZZY3 PayHD202512071839146304007B", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1765107554343, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/572cf75cd38148f182da9e6e55707e24", "description": "CS7P7QUZZY3 PayHD20251207183914", "accountNumber": "V3CAS6504398884", "paymentLinkId": "572cf75cd38148f182da9e6e55707e24"}	\N	2025-12-07 18:39:14.633037	2025-12-07 18:39:14.633037	data:image/png;base64,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
65	order	HD-20251212-063329	\N	1765496009590	payos	d36553cb764946ad836dfea9cc7ec8b1	45000.00	completed	https://pay.payos.vn/web/d36553cb764946ad836dfea9cc7ec8b1	{"code": "00", "desc": "success", "amount": 45000, "currency": "VND", "orderCode": 1765496009590, "reference": "ad0930c3-b95e-464c-89d1-b830260a4536", "description": "CSGOY4VJTI5 PayHD20251212063329", "accountNumber": "6504398884", "paymentLinkId": "d36553cb764946ad836dfea9cc7ec8b1", "counterAccountName": null, "virtualAccountName": "", "transactionDateTime": "2025-12-12 06:34:21", "counterAccountBankId": "", "counterAccountNumber": "0", "virtualAccountNumber": "V3CAS6504398884", "counterAccountBankName": ""}	\N	2025-12-12 06:33:30.390271	2025-12-12 06:34:16.265254	data:image/png;base64,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
66	order	HD-20251212-063457	\N	1765496097549	payos	3e79dc9bb83f40a39247e74f57620128	40000.00	pending	https://pay.payos.vn/web/3e79dc9bb83f40a39247e74f57620128	{"bin": "970418", "amount": 40000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA53037045405400005802VN62350831CSRMHYMB9I0 PayHD202512120634576304BB10", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1765496097549, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/3e79dc9bb83f40a39247e74f57620128", "description": "CSRMHYMB9I0 PayHD20251212063457", "accountNumber": "V3CAS6504398884", "paymentLinkId": "3e79dc9bb83f40a39247e74f57620128"}	\N	2025-12-12 06:34:57.805988	2025-12-12 06:34:57.805988	data:image/png;base64,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
67	order	HD-20251214-110500	\N	1765685100504	payos	96573517b94847908ea170c76362c660	40000.00	pending	https://pay.payos.vn/web/96573517b94847908ea170c76362c660	{"bin": "970418", "amount": 40000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA53037045405400005802VN62350831CS31V2XF506 PayHD2025121411050063049117", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1765685100504, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/96573517b94847908ea170c76362c660", "description": "CS31V2XF506 PayHD20251214110500", "accountNumber": "V3CAS6504398884", "paymentLinkId": "96573517b94847908ea170c76362c660"}	\N	2025-12-14 11:05:00.90869	2025-12-14 11:05:00.90869	data:image/png;base64,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
68	order	HD-20251214-150035	\N	1765699235806	payos	c08aaa020c8d45afa86aea69ecade519	100000.00	pending	https://pay.payos.vn/web/c08aaa020c8d45afa86aea69ecade519	{"bin": "970418", "amount": 100000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA530370454061000005802VN62350831CS68RZNZG15 PayHD202512141500356304B22F", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1765699235806, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/c08aaa020c8d45afa86aea69ecade519", "description": "CS68RZNZG15 PayHD20251214150035", "accountNumber": "V3CAS6504398884", "paymentLinkId": "c08aaa020c8d45afa86aea69ecade519"}	\N	2025-12-14 15:00:36.586616	2025-12-14 15:00:36.586616	data:image/png;base64,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
69	order	HD-20251214-154958	\N	1765702198189	payos	ee85cee933b7420b913229545654a912	50000.00	completed	https://pay.payos.vn/web/ee85cee933b7420b913229545654a912	{"code": "00", "desc": "success", "amount": 50000, "currency": "VND", "orderCode": 1765702198189, "reference": "85e1551e-ace8-44cb-91bf-d27677908b3e", "description": "CSGCVW3IWH5 PayHD20251214154958", "accountNumber": "6504398884", "paymentLinkId": "ee85cee933b7420b913229545654a912", "counterAccountName": null, "virtualAccountName": "", "transactionDateTime": "2025-12-14 15:50:43", "counterAccountBankId": "", "counterAccountNumber": "0", "virtualAccountNumber": "V3CAS6504398884", "counterAccountBankName": ""}	\N	2025-12-14 15:49:58.559364	2025-12-14 15:50:37.641232	data:image/png;base64,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
70	order	HD-20251215-063509	\N	1765755310092	payos	9ff139ed6e6745499c300d81bbd09277	5000.00	completed	https://pay.payos.vn/web/9ff139ed6e6745499c300d81bbd09277	{"code": "00", "desc": "success", "amount": 5000, "currency": "VND", "orderCode": 1765755310092, "reference": "411e25b6-6bac-46b9-9523-428a11dff56f", "description": "CSR93S3XCO1 PayHD20251215063509", "accountNumber": "6504398884", "paymentLinkId": "9ff139ed6e6745499c300d81bbd09277", "counterAccountName": null, "virtualAccountName": "", "transactionDateTime": "2025-12-15 06:35:49", "counterAccountBankId": "", "counterAccountNumber": "0", "virtualAccountNumber": "V3CAS6504398884", "counterAccountBankName": ""}	\N	2025-12-15 06:35:10.876806	2025-12-15 06:35:42.462212	data:image/png;base64,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
71	order	HD-20251215-093356	\N	1765766036626	payos	9dd53761720b409b883f154eb111c533	25000.00	completed	https://pay.payos.vn/web/9dd53761720b409b883f154eb111c533	{"code": "00", "desc": "success", "amount": 25000, "currency": "VND", "orderCode": 1765766036626, "reference": "e8db4ced-462f-4163-bb69-e48629f79a26", "description": "CSGIQR9KUV1 PayHD20251215093356", "accountNumber": "6504398884", "paymentLinkId": "9dd53761720b409b883f154eb111c533", "counterAccountName": null, "virtualAccountName": "", "transactionDateTime": "2025-12-15 09:34:40", "counterAccountBankId": "", "counterAccountNumber": "0", "virtualAccountNumber": "V3CAS6504398884", "counterAccountBankName": ""}	\N	2025-12-15 09:34:09.690117	2025-12-15 09:34:35.337246	data:image/png;base64,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
72	order	HD-20251215-102512	\N	1765769112209	payos	8947b5bcbed546049ff63b32feb43cc8	50000.00	pending	https://pay.payos.vn/web/8947b5bcbed546049ff63b32feb43cc8	{"bin": "970418", "amount": 50000, "qrCode": "00020101021238590010A000000727012900069704180115V3CAS65043988840208QRIBFTTA53037045405500005802VN62350831CS8X08MF7L2 PayHD2025121510251263045017", "status": "PENDING", "currency": "VND", "expiredAt": null, "orderCode": 1765769112209, "accountName": "DANG THANH TU", "checkoutUrl": "https://pay.payos.vn/web/8947b5bcbed546049ff63b32feb43cc8", "description": "CS8X08MF7L2 PayHD20251215102512", "accountNumber": "V3CAS6504398884", "paymentLinkId": "8947b5bcbed546049ff63b32feb43cc8"}	\N	2025-12-15 10:25:13.07732	2025-12-15 10:25:13.07732	data:image/png;base64,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
\.


--
-- TOC entry 5072 (class 0 OID 33402)
-- Dependencies: 248
-- Data for Name: predictions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.predictions (prediction_id, product_id, predicted_month, predicted_quantity, confidence, created_at) FROM stdin;
1	1	2025-11	60	0.85	2025-10-03 13:29:14.460139
2	2	2025-11	40	0.78	2025-10-03 13:29:14.460139
3	3	2025-11	25	0.92	2025-10-03 13:29:14.460139
4	4	2025-11	120	0.81	2025-10-03 13:29:14.460139
5	5	2025-11	45	0.87	2025-10-03 13:29:14.460139
6	6	2025-11	70	0.76	2025-10-03 13:29:14.460139
7	7	2025-11	6	0.94	2025-10-03 13:29:14.460139
8	8	2025-11	30	0.82	2025-10-03 13:29:14.460139
9	9	2025-11	90	0.79	2025-10-03 13:29:14.460139
10	10	2025-11	20	0.88	2025-10-03 13:29:14.460139
11	11	2025-11	50	0.83	2025-10-03 13:29:14.460139
12	12	2025-11	30	0.91	2025-10-03 13:29:14.460139
13	13	2025-11	200	0.80	2025-10-03 13:29:14.460139
14	14	2025-11	50	0.86	2025-10-03 13:29:14.460139
15	15	2025-11	30	0.89	2025-10-03 13:29:14.460139
16	16	2025-11	50	0.77	2025-10-03 13:29:14.460139
17	17	2025-11	10	0.93	2025-10-03 13:29:14.460139
18	18	2025-11	120	0.84	2025-10-03 13:29:14.460139
106	8	2025-10	0	0.02	2025-12-15 10:32:08.387225
109	9	2025-02	0	0.01	2025-12-15 10:32:08.387225
258284	1	2026-01	0	0.01	2026-01-21 15:55:01.702597
112	9	2025-06	0	0.01	2025-12-15 10:32:08.387225
115	9	2025-10	0	0.01	2025-12-15 10:32:08.387225
118	10	2025-02	0	0.05	2025-12-15 10:32:08.387225
258289	1	2026-02	0	0.01	2026-01-21 15:55:01.702597
121	10	2025-06	0	0.05	2025-12-15 10:32:08.387225
124	10	2025-10	0	0.05	2025-12-15 10:32:08.387225
258294	1	2026-04	0	0.01	2026-01-21 15:55:01.702597
127	11	2025-02	0	0.01	2025-12-15 10:32:08.387225
130	11	2025-06	0	0.01	2025-12-15 10:32:08.387225
133	11	2025-10	0	0.01	2025-12-15 10:32:08.387225
258299	1	2026-08	0	0.01	2026-01-21 15:55:01.702597
136	12	2025-01	0	0.02	2025-12-15 10:32:08.387225
139	12	2025-03	0	0.02	2025-12-15 10:32:08.387225
142	12	2025-07	0	0.02	2025-12-15 10:32:08.387225
258304	1	2026-10	0	0.01	2026-01-21 15:55:01.702597
230	20	2025-08	0	0.05	2025-12-15 10:32:08.387225
258309	2	2026-01	0	0.02	2026-01-21 15:55:01.702597
235	20	2025-10	0	0.05	2025-12-15 10:32:08.387225
258312	2	2026-05	0	0.02	2026-01-21 15:55:01.702597
20	20	2025-11	5	0.14	2025-12-15 10:32:08.387225
258315	2	2026-09	0	0.02	2026-01-21 15:55:01.702597
245	20	2025-12	25	0.04	2025-12-15 10:32:08.387225
166499	24	2025-01	4	0.09	2025-12-12 06:22:25.559555
258318	3	2026-01	0	0.03	2026-01-21 15:55:01.702597
250	21	2025-11	25	0.00	2025-12-15 10:32:08.387225
29231	21	2025-12	25	0.00	2025-12-15 10:32:08.387225
166969	24	2025-12	0	0.07	2025-12-15 10:32:08.387225
170018	25	2025-12	0	0.01	2025-12-15 10:32:08.387225
170019	26	2025-12	0	0.03	2025-12-15 10:32:08.387225
258321	3	2026-05	0	0.03	2026-01-21 15:55:01.702597
258324	3	2026-09	0	0.03	2026-01-21 15:55:01.702597
258327	4	2026-01	0	0.01	2026-01-21 15:55:01.702597
258330	4	2026-05	0	0.01	2026-01-21 15:55:01.702597
258333	4	2026-09	0	0.01	2026-01-21 15:55:01.702597
258402	12	2026-03	0	0.02	2026-01-21 15:55:01.702597
258405	12	2026-07	0	0.02	2026-01-21 15:55:01.702597
258360	7	2026-10	4	0.08	2026-01-21 15:55:01.702597
258363	8	2026-02	0	0.02	2026-01-21 15:55:01.702597
258366	8	2026-06	0	0.02	2026-01-21 15:55:01.702597
258369	8	2026-10	0	0.02	2026-01-21 15:55:01.702597
258372	9	2026-02	0	0.01	2026-01-21 15:55:01.702597
258375	9	2026-06	0	0.01	2026-01-21 15:55:01.702597
258378	9	2026-10	0	0.01	2026-01-21 15:55:01.702597
258381	10	2026-02	0	0.05	2026-01-21 15:55:01.702597
258384	10	2026-06	0	0.05	2026-01-21 15:55:01.702597
258387	10	2026-10	0	0.05	2026-01-21 15:55:01.702597
258390	11	2026-02	0	0.01	2026-01-21 15:55:01.702597
258393	11	2026-06	0	0.01	2026-01-21 15:55:01.702597
258396	11	2026-10	0	0.01	2026-01-21 15:55:01.702597
258399	12	2026-01	0	0.02	2026-01-21 15:55:01.702597
258408	13	2026-01	0	0.00	2026-01-21 15:55:01.702597
258411	13	2026-03	0	0.00	2026-01-21 15:55:01.702597
258414	13	2026-07	0	0.00	2026-01-21 15:55:01.702597
258417	13	2026-10	0	0.00	2026-01-21 15:55:01.702597
258420	14	2026-01	0	0.01	2026-01-21 15:55:01.702597
258423	14	2026-03	0	0.01	2026-01-21 15:55:01.702597
258426	14	2026-07	0	0.01	2026-01-21 15:55:01.702597
258429	15	2026-01	0	0.02	2026-01-21 15:55:01.702597
258432	15	2026-03	0	0.02	2026-01-21 15:55:01.702597
258435	15	2026-07	0	0.02	2026-01-21 15:55:01.702597
258438	16	2026-01	0	0.01	2026-01-21 15:55:01.702597
258441	16	2026-03	0	0.01	2026-01-21 15:55:01.702597
258488	20	2026-04	0	0.05	2026-01-21 15:55:01.702597
258493	20	2026-08	0	0.05	2026-01-21 15:55:01.702597
258498	20	2026-10	0	0.05	2026-01-21 15:55:01.702597
258503	20	2026-11	5	0.14	2026-01-21 15:55:01.702597
258508	20	2026-12	25	0.04	2026-01-21 15:55:01.702597
258513	21	2026-11	25	0.00	2026-01-21 15:55:01.702597
258515	21	2026-12	25	0.00	2026-01-21 15:55:01.702597
258517	24	2026-12	0	0.07	2026-01-21 15:55:01.702597
258518	25	2026-12	0	0.01	2026-01-21 15:55:01.702597
258519	26	2026-12	0	0.03	2026-01-21 15:55:01.702597
258336	5	2026-01	0	0.01	2026-01-21 15:55:01.702597
258339	5	2026-05	0	0.01	2026-01-21 15:55:01.702597
258342	5	2026-09	0	0.01	2026-01-21 15:55:01.702597
258345	6	2026-01	0	0.01	2026-01-21 15:55:01.702597
258348	6	2026-05	0	0.01	2026-01-21 15:55:01.702597
258351	6	2026-09	0	0.01	2026-01-21 15:55:01.702597
258354	7	2026-02	4	0.08	2026-01-21 15:55:01.702597
258357	7	2026-06	4	0.08	2026-01-21 15:55:01.702597
258444	16	2026-07	0	0.01	2026-01-21 15:55:01.702597
258447	17	2026-02	0	0.01	2026-01-21 15:55:01.702597
258450	17	2026-04	0	0.01	2026-01-21 15:55:01.702597
258453	17	2026-08	0	0.01	2026-01-21 15:55:01.702597
258456	18	2026-02	0	0.00	2026-01-21 15:55:01.702597
258459	18	2026-04	0	0.00	2026-01-21 15:55:01.702597
258462	18	2026-08	0	0.00	2026-01-21 15:55:01.702597
258465	18	2026-10	0	0.00	2026-01-21 15:55:01.702597
258468	19	2026-02	0	0.01	2026-01-21 15:55:01.702597
258471	19	2026-04	0	0.01	2026-01-21 15:55:01.702597
258474	19	2026-08	0	0.01	2026-01-21 15:55:01.702597
258477	19	2026-10	0	0.01	2026-01-21 15:55:01.702597
258480	19	2026-11	0	0.01	2026-01-21 15:55:01.702597
258483	20	2026-02	0	0.06	2026-01-21 15:55:01.702597
21	1	2025-01	0	0.01	2025-12-15 10:32:08.387225
26	1	2025-02	0	0.01	2025-12-15 10:32:08.387225
31	1	2025-04	0	0.01	2025-12-15 10:32:08.387225
36	1	2025-08	0	0.01	2025-12-15 10:32:08.387225
41	1	2025-10	0	0.01	2025-12-15 10:32:08.387225
46	2	2025-01	0	0.02	2025-12-15 10:32:08.387225
49	2	2025-05	0	0.02	2025-12-15 10:32:08.387225
52	2	2025-09	0	0.02	2025-12-15 10:32:08.387225
55	3	2025-01	0	0.03	2025-12-15 10:32:08.387225
58	3	2025-05	0	0.03	2025-12-15 10:32:08.387225
61	3	2025-09	0	0.03	2025-12-15 10:32:08.387225
64	4	2025-01	0	0.01	2025-12-15 10:32:08.387225
67	4	2025-05	0	0.01	2025-12-15 10:32:08.387225
70	4	2025-09	0	0.01	2025-12-15 10:32:08.387225
73	5	2025-01	0	0.01	2025-12-15 10:32:08.387225
76	5	2025-05	0	0.01	2025-12-15 10:32:08.387225
79	5	2025-09	0	0.01	2025-12-15 10:32:08.387225
82	6	2025-01	0	0.01	2025-12-15 10:32:08.387225
85	6	2025-05	0	0.01	2025-12-15 10:32:08.387225
88	6	2025-09	0	0.01	2025-12-15 10:32:08.387225
91	7	2025-02	4	0.08	2025-12-15 10:32:08.387225
94	7	2025-06	4	0.08	2025-12-15 10:32:08.387225
97	7	2025-10	4	0.08	2025-12-15 10:32:08.387225
100	8	2025-02	0	0.02	2025-12-15 10:32:08.387225
103	8	2025-06	0	0.02	2025-12-15 10:32:08.387225
145	13	2025-01	0	0.00	2025-12-15 10:32:08.387225
148	13	2025-03	0	0.00	2025-12-15 10:32:08.387225
151	13	2025-07	0	0.00	2025-12-15 10:32:08.387225
154	13	2025-10	0	0.00	2025-12-15 10:32:08.387225
157	14	2025-01	0	0.01	2025-12-15 10:32:08.387225
160	14	2025-03	0	0.01	2025-12-15 10:32:08.387225
163	14	2025-07	0	0.01	2025-12-15 10:32:08.387225
166	15	2025-01	0	0.02	2025-12-15 10:32:08.387225
169	15	2025-03	0	0.02	2025-12-15 10:32:08.387225
172	15	2025-07	0	0.02	2025-12-15 10:32:08.387225
175	16	2025-01	0	0.01	2025-12-15 10:32:08.387225
178	16	2025-03	0	0.01	2025-12-15 10:32:08.387225
181	16	2025-07	0	0.01	2025-12-15 10:32:08.387225
184	17	2025-02	0	0.01	2025-12-15 10:32:08.387225
187	17	2025-04	0	0.01	2025-12-15 10:32:08.387225
190	17	2025-08	0	0.01	2025-12-15 10:32:08.387225
193	18	2025-02	0	0.00	2025-12-15 10:32:08.387225
196	18	2025-04	0	0.00	2025-12-15 10:32:08.387225
199	18	2025-08	0	0.00	2025-12-15 10:32:08.387225
202	18	2025-10	0	0.00	2025-12-15 10:32:08.387225
205	19	2025-02	0	0.01	2025-12-15 10:32:08.387225
208	19	2025-04	0	0.01	2025-12-15 10:32:08.387225
211	19	2025-08	0	0.01	2025-12-15 10:32:08.387225
214	19	2025-10	0	0.01	2025-12-15 10:32:08.387225
19	19	2025-11	0	0.01	2025-12-15 10:32:08.387225
220	20	2025-02	0	0.06	2025-12-15 10:32:08.387225
225	20	2025-04	0	0.05	2025-12-15 10:32:08.387225
\.


--
-- TOC entry 5050 (class 0 OID 33116)
-- Dependencies: 226
-- Data for Name: products; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.products (product_id, name, barcode, description, price, cost_price, stock, image_url, minimum_inventory, maximum_inventory, category_id, unit_id, supplier_id, created_at, updated_at, is_active) FROM stdin;
21	Đồ chơi của mèo Ahihi	6759952462188	null	10000.00	5000.00	21	/uploads/products/1761211063978.jpg	10	100	1	1	2	2025-10-23 16:17:43.994914	2025-12-14 11:09:27.422918	t
26	Thuốc nhỏ mắt cho bé Mèo	3763072402873	undefined	50000.00	30000.00	53	/uploads/products/1765686325475.webp	10	50	1	1	1	2025-12-14 11:25:25.483705	2025-12-15 10:24:26.891381	t
24	Thuốc cho mèo	8437370265537	undefined	50000.00	30000.00	15	/uploads/products/1765494915764.webp	10	100	1	1	1	2025-12-12 06:15:15.774678	2025-12-15 10:24:26.891381	t
25	Thuốc nhỏ mắt cho mèo	6020843967412	undefined	40000.00	20000.00	117	/uploads/products/1765495875231.webp	10	100	1	4	4	2025-12-12 06:31:15.241622	2025-12-14 11:50:20.287816	f
20	Máy cắt lông thú cưng	8950123456789	Máy cắt lông chuyên dụng cho chó mèo	500000.00	400000.00	19	/uploads/products/1761297116798.png	5	20	9	5	6	2025-10-03 13:29:14.460139	2025-12-12 06:16:04.708093	t
4	Băng gạc y tế vô trùng	8934567890123	Băng gạc dùng để băng bó vết thương, hộp 10 cái	50000.00	40000.00	163	/uploads/bandage.jpg	50	200	2	2	2	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139	t
5	Vitamin bổ sung cho thú cưng	8935678901234	Vitamin tổng hợp giúp tăng cường sức đề kháng, lọ 100 viên	100000.00	80000.00	78	/uploads/vitamin.jpg	15	80	7	1	7	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139	t
6	Xà phòng tắm cho chó mèo	8936789012345	Xà phòng khử mùi và diệt khuẩn, chai 500ml	80000.00	60000.00	127	/uploads/shampoo.jpg	20	100	8	5	8	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139	t
7	Máy đo huyết áp thú y	8937890123456	Thiết bị đo huyết áp chuyên dụng cho thú cưng	2000000.00	1600000.00	13	/uploads/bp_monitor.jpg	2	10	9	7	6	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139	t
8	Vòng cổ chống ve rận	8938901234567	Vòng cổ bảo vệ chống ve rận, hiệu quả 6 tháng	150000.00	120000.00	57	/uploads/collar.jpg	10	50	5	5	5	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139	t
9	Khăn lau vệ sinh	8939012345678	Khăn ướt vệ sinh cho thú cưng, gói 50 tờ	40000.00	30000.00	169	/uploads/wipes.jpg	30	150	8	9	8	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139	t
11	Thuốc nhỏ mắt cho thú cưng	8941234567890	Thuốc nhỏ mắt trị viêm kết mạc, lọ 10ml	120000.00	100000.00	85	/uploads/eye_drops.jpg	10	60	1	5	1	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139	t
12	Bột dinh dưỡng cho chim	8942345678901	Bột bổ sung dinh dưỡng cho chim cảnh, hộp 500g	250000.00	200000.00	66	/uploads/bird_powder.jpg	10	50	3	3	3	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139	t
14	Vitamin C cho thỏ	8944567890123	Vitamin C bổ sung cho thỏ, lọ 50 viên	80000.00	60000.00	108	/uploads/vitamin_c_rabbit.jpg	15	80	7	1	7	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139	t
13	Kim tiêm dùng một lần	8943456789012	Kim tiêm vô trùng cho thú y, hộp 100 cái	100000.00	80000.00	333	/uploads/syringe.jpg	100	500	2	2	2	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139	t
19	Bình xịt khử mùi	8949012345678	Bình xịt khử mùi thú cưng, chai 500ml	100000.00	80000.00	105	/uploads/products/1762273549388.webp	20	100	8	5	8	2025-10-03 13:29:14.460139	2025-11-04 23:25:49.397262	t
15	Sữa bột cho mèo con	8945678901234	Sữa bột dinh dưỡng cho mèo con, hộp 400g	300000.00	250000.00	49	/uploads/kitten_milk.jpg	10	50	3	3	3	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139	t
1	Thuốc kháng sinh Amoxicillin cho chó	0833354394763	Thuốc kháng sinh dạng viên cho chó bị nhiễm khuẩn, liều dùng 10mg/kg	140000.00	120000.00	111	/uploads/products/1761296725855.jpg	20	100	1	1	1	2025-10-03 13:29:14.460139	2025-10-28 00:13:00.961393	t
2	Vắc-xin phòng dại cho mèo	8932345678901	Vắc-xin phòng bệnh dại, tiêm 1ml/lần, hiệu quả 1 năm	200000.00	160000.00	60	/uploads/rabies_vaccine.jpg	10	50	6	5	4	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139	t
3	Thức ăn khô cho chó trưởng thành	8933456789012	Thức ăn dinh dưỡng cân bằng cho chó trên 1 tuổi, túi 5kg	500000.00	400000.00	33	/uploads/dog_food.jpg	5	30	3	3	3	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139	t
10	Lồng vận chuyển chó mèo	8940123456789	Lồng nhựa an toàn cho vận chuyển, kích thước trung bình	300000.00	250000.00	23	/uploads/carrier.jpg	5	30	5	5	5	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139	t
18	Thức ăn ướt cho mèo	8948901234567	Thức ăn ướt vị cá ngừ, lon 85g	30000.00	25000.00	224	/uploads/products/1764907462691.webp	30	200	3	5	3	2025-10-03 13:29:14.460139	2025-12-05 11:04:22.697258	t
17	Găng tay y tế	8947890123456	Găng tay cao su dùng một lần, hộp 100 cái	50000.00	40000.00	158	/uploads/products/1765488197489.webp	50	300	2	2	2	2025-10-03 13:29:14.460139	2025-12-12 04:23:17.497887	t
16	Thuốc tẩy giun cho chó	8946789012345	Thuốc tẩy giun nội ngoại ký sinh, hộp 10 viên	150000.00	120000.00	107	/uploads/products/1765488272583.webp	15	80	1	1	1	2025-10-03 13:29:14.460139	2025-12-12 04:24:32.590624	t
\.


--
-- TOC entry 5058 (class 0 OID 33194)
-- Dependencies: 234
-- Data for Name: promotion_categories; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.promotion_categories (promotion_category_id, promotion_id, category_id) FROM stdin;
4	3	3
5	3	7
6	4	2
7	5	5
8	6	7
9	7	8
10	8	9
11	9	5
12	10	10
\.


--
-- TOC entry 5060 (class 0 OID 33213)
-- Dependencies: 236
-- Data for Name: promotion_products; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.promotion_products (promotion_product_id, promotion_id, product_id) FROM stdin;
4	3	3
5	3	18
6	4	4
7	5	8
8	5	20
9	6	5
10	6	14
11	7	9
12	7	19
13	8	7
14	8	15
15	9	13
16	10	10
17	10	16
\.


--
-- TOC entry 5056 (class 0 OID 33171)
-- Dependencies: 232
-- Data for Name: promotions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.promotions (promotion_id, name, discount_percent, start_date, end_date, created_at) FROM stdin;
3	Khuyến mãi thức ăn thú cưng	20.00	2025-04-01	2025-05-31	2025-10-03 13:29:14.460139
4	Giảm giá vật tư y tế	5.00	2025-01-01	2025-03-31	2025-10-03 13:29:14.460139
5	Promo phụ kiện chăm sóc	25.00	2025-12-01	2025-12-31	2025-10-03 13:29:14.460139
6	Khuyến mãi vitamin bổ sung	12.00	2025-02-01	2025-04-30	2025-10-03 13:29:14.460139
7	Sale sản phẩm vệ sinh	18.00	2025-07-01	2025-09-30	2025-10-03 13:29:14.460139
8	Giảm giá thiết bị y tế	8.00	2025-10-01	2025-12-31	2025-10-03 13:29:14.460139
9	Promo game thú cưng	22.00	2025-05-01	2025-07-31	2025-10-03 13:29:14.460139
10	Khuyến mãi khác	10.00	2025-03-01	2025-05-31	2025-10-03 13:29:14.460139
11	Black Friday	50.00	2025-12-14	2025-12-31	2025-12-14 15:48:50.266839
\.


--
-- TOC entry 5068 (class 0 OID 33313)
-- Dependencies: 244
-- Data for Name: purchase_details; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.purchase_details (purchase_detail_id, purchase_id, product_id, quantity, unit_cost, created_at) FROM stdin;
1	1	1	10	120000.00	2025-10-03 13:29:14.460139
2	1	4	20	40000.00	2025-10-03 13:29:14.460139
3	2	3	5	400000.00	2025-10-03 13:29:14.460139
4	3	2	15	160000.00	2025-10-03 13:29:14.460139
5	4	5	10	80000.00	2025-10-03 13:29:14.460139
6	5	6	20	60000.00	2025-10-03 13:29:14.460139
7	6	7	3	1600000.00	2025-10-03 13:29:14.460139
8	7	8	10	120000.00	2025-10-03 13:29:14.460139
9	8	9	30	30000.00	2025-10-03 13:29:14.460139
10	9	10	5	250000.00	2025-10-03 13:29:14.460139
11	10	11	15	100000.00	2025-10-03 13:29:14.460139
12	11	12	10	200000.00	2025-10-03 13:29:14.460139
13	12	13	50	80000.00	2025-10-03 13:29:14.460139
14	13	14	20	60000.00	2025-10-03 13:29:14.460139
15	14	15	10	250000.00	2025-10-03 13:29:14.460139
16	15	16	20	120000.00	2025-10-03 13:29:14.460139
17	16	17	5	40000.00	2025-10-03 13:29:14.460139
18	17	18	50	25000.00	2025-10-03 13:29:14.460139
19	18	19	20	80000.00	2025-10-03 13:29:14.460139
20	19	20	5	400000.00	2025-10-03 13:29:14.460139
21	20	1	15	120000.00	2025-10-03 13:29:14.460139
22	21	2	10	160000.00	2025-10-03 13:29:14.460139
23	22	3	6	400000.00	2025-10-03 13:29:14.460139
24	23	4	25	40000.00	2025-10-03 13:29:14.460139
25	24	5	15	80000.00	2025-10-03 13:29:14.460139
26	25	6	25	60000.00	2025-10-03 13:29:14.460139
27	26	7	4	1600000.00	2025-10-03 13:29:14.460139
28	27	8	15	120000.00	2025-10-03 13:29:14.460139
29	28	9	35	30000.00	2025-10-03 13:29:14.460139
30	29	10	6	250000.00	2025-10-03 13:29:14.460139
31	30	11	20	100000.00	2025-10-03 13:29:14.460139
32	31	12	15	200000.00	2025-10-03 13:29:14.460139
33	32	13	55	80000.00	2025-10-03 13:29:14.460139
34	33	14	25	60000.00	2025-10-03 13:29:14.460139
35	34	15	15	250000.00	2025-10-03 13:29:14.460139
36	35	16	25	120000.00	2025-10-03 13:29:14.460139
37	36	17	6	40000.00	2025-10-03 13:29:14.460139
38	37	18	55	25000.00	2025-10-03 13:29:14.460139
39	38	19	25	80000.00	2025-10-03 13:29:14.460139
40	39	20	6	400000.00	2025-10-03 13:29:14.460139
41	40	1	20	120000.00	2025-10-03 13:29:14.460139
42	41	2	15	160000.00	2025-10-03 13:29:14.460139
43	42	3	7	400000.00	2025-10-03 13:29:14.460139
44	43	4	30	40000.00	2025-10-03 13:29:14.460139
45	44	5	20	80000.00	2025-10-03 13:29:14.460139
46	45	6	30	60000.00	2025-10-03 13:29:14.460139
47	46	7	5	1600000.00	2025-10-03 13:29:14.460139
48	47	8	20	120000.00	2025-10-03 13:29:14.460139
49	48	9	40	30000.00	2025-10-03 13:29:14.460139
50	49	10	7	250000.00	2025-10-03 13:29:14.460139
51	50	11	25	100000.00	2025-10-03 13:29:14.460139
52	1	12	20	200000.00	2025-10-03 13:29:14.460139
53	2	13	60	80000.00	2025-10-03 13:29:14.460139
54	3	14	30	60000.00	2025-10-03 13:29:14.460139
55	4	15	20	250000.00	2025-10-03 13:29:14.460139
56	5	16	30	120000.00	2025-10-03 13:29:14.460139
57	6	17	7	40000.00	2025-10-03 13:29:14.460139
58	7	18	60	25000.00	2025-10-03 13:29:14.460139
59	8	19	30	80000.00	2025-10-03 13:29:14.460139
60	9	20	7	400000.00	2025-10-03 13:29:14.460139
61	10	1	25	120000.00	2025-10-03 13:29:14.460139
65	54	1	5	120000.00	2025-10-28 00:13:00.961393
74	60	21	50	100.00	2025-11-06 00:51:39.106319
75	61	21	10	100.00	2025-11-06 00:52:16.74421
76	62	21	100	100.00	2025-11-06 01:06:54.656918
77	63	21	200	100.00	2025-11-07 11:48:06.111092
78	64	21	20	100.00	2025-11-07 11:53:54.173905
79	65	21	100	100.00	2025-11-21 12:40:51.955519
80	66	21	30	100.00	2025-11-21 13:10:43.649429
81	67	21	20	100.00	2025-11-21 13:16:41.512895
82	68	21	30	100.00	2025-11-21 13:17:59.829594
83	69	21	5	100.00	2025-11-21 13:18:19.544731
84	70	20	4	400000.00	2025-11-21 13:18:47.534845
85	71	20	7	400000.00	2025-11-21 13:21:17.27951
86	72	21	50	100.00	2025-11-21 13:27:31.672081
87	73	20	2	400000.00	2025-11-21 13:33:52.454756
88	74	21	50	100.00	2025-11-21 14:40:51.928748
89	74	20	10	400000.00	2025-11-21 14:40:51.928748
90	75	21	50	100.00	2025-11-21 14:47:41.261917
104	76	21	1	100.00	2025-11-28 14:30:40.354226
107	90	21	1	100.00	2025-11-28 14:49:30.498216
108	91	21	1	100.00	2025-11-28 14:49:41.933856
112	95	20	1	400000.00	2025-11-28 15:01:13.6782
113	94	21	1	100.00	2025-11-28 16:01:44.029507
114	96	21	2	1000.00	2025-11-28 16:05:37.806014
116	98	21	5	1000.00	2025-11-28 16:13:41.831246
118	100	20	40	400000.00	2025-12-03 04:05:09.387723
119	101	21	110	1000.00	2025-12-03 15:05:51.768841
120	102	21	1	1000.00	2025-12-03 16:03:37.212157
121	103	21	112	1000.00	2025-12-03 16:07:13.216957
122	104	21	1	1000.00	2025-12-03 16:20:25.865572
123	105	21	1	1000.00	2025-12-03 16:24:37.261583
128	110	21	1	1000.00	2025-12-03 17:23:54.851294
129	111	21	5	1000.00	2025-12-03 17:24:49.510693
130	112	21	1	1000.00	2025-12-03 17:28:42.274026
136	118	21	2	1000.00	2025-12-03 17:45:48.998512
138	120	21	2	1000.00	2025-12-03 17:56:56.865365
142	124	21	2	1000.00	2025-12-03 18:12:12.374208
143	125	21	2	1000.00	2025-12-03 18:13:25.827329
144	126	21	1	1000.00	2025-12-03 18:14:49.730595
145	127	21	2	1000.00	2025-12-03 18:15:34.894494
147	128	21	4	1000.00	2025-12-07 17:36:41.151731
151	129	21	1	1000.00	2025-12-12 03:01:24.427971
152	130	21	5	5000.00	2025-12-12 04:13:05.665006
167	143	24	1	30000.00	2025-12-14 11:08:17.186075
170	146	21	1	5000.00	2025-12-14 11:09:27.422918
171	147	24	1	30000.00	2025-12-14 11:10:56.302226
175	151	26	1	30000.00	2025-12-14 11:25:38.154966
176	152	26	2	30000.00	2025-12-14 11:50:54.936932
177	153	26	37	30000.00	2025-12-14 12:09:56.213723
178	154	26	1	30000.00	2025-12-14 15:26:33.900475
179	155	26	20	30000.00	2025-12-14 15:27:04.987708
180	156	26	50	30000.00	2025-12-14 16:50:28.152258
181	157	26	10	30000.00	2025-12-15 06:09:46.153096
182	157	24	5	30000.00	2025-12-15 06:09:46.153096
183	158	26	5	30000.00	2025-12-15 10:24:26.891381
184	158	24	1	30000.00	2025-12-15 10:24:26.891381
\.


--
-- TOC entry 5066 (class 0 OID 33288)
-- Dependencies: 242
-- Data for Name: purchases; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.purchases (purchase_id, purchase_number, employee_id, purchase_date, total_amount, amount_paid, payment_method_id, status, created_at, updated_at) FROM stdin;
1	PUR-202501-001	4	2025-01-03 00:00:00	600000.00	600000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
2	PUR-202501-002	5	2025-01-08 00:00:00	800000.00	800000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
3	PUR-202501-003	4	2025-01-13 00:00:00	400000.00	400000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
4	PUR-202501-004	5	2025-01-18 00:00:00	700000.00	700000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
5	PUR-202501-005	4	2025-01-23 00:00:00	300000.00	300000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
6	PUR-202502-001	5	2025-02-03 00:00:00	700000.00	700000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
7	PUR-202502-002	4	2025-02-08 00:00:00	900000.00	900000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
8	PUR-202502-003	5	2025-02-13 00:00:00	500000.00	500000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
9	PUR-202502-004	4	2025-02-18 00:00:00	800000.00	800000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
10	PUR-202502-005	5	2025-02-23 00:00:00	400000.00	400000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
11	PUR-202503-001	4	2025-03-03 00:00:00	800000.00	800000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
12	PUR-202503-002	5	2025-03-08 00:00:00	600000.00	600000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
13	PUR-202503-003	4	2025-03-13 00:00:00	900000.00	900000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
14	PUR-202503-004	5	2025-03-18 00:00:00	500000.00	500000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
15	PUR-202503-005	4	2025-03-23 00:00:00	700000.00	700000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
16	PUR-202504-001	5	2025-04-03 00:00:00	900000.00	900000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
17	PUR-202504-002	4	2025-04-08 00:00:00	700000.00	700000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
18	PUR-202504-003	5	2025-04-13 00:00:00	1000000.00	1000000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
19	PUR-202504-004	4	2025-04-18 00:00:00	600000.00	600000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
20	PUR-202504-005	5	2025-04-23 00:00:00	800000.00	800000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
21	PUR-202505-001	4	2025-05-03 00:00:00	1000000.00	1000000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
22	PUR-202505-002	5	2025-05-08 00:00:00	800000.00	800000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
23	PUR-202505-003	4	2025-05-13 00:00:00	1100000.00	1100000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
24	PUR-202505-004	5	2025-05-18 00:00:00	700000.00	700000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
25	PUR-202505-005	4	2025-05-23 00:00:00	900000.00	900000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
26	PUR-202506-001	5	2025-06-03 00:00:00	1100000.00	1100000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
27	PUR-202506-002	4	2025-06-08 00:00:00	900000.00	900000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
28	PUR-202506-003	5	2025-06-13 00:00:00	1200000.00	1200000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
29	PUR-202506-004	4	2025-06-18 00:00:00	800000.00	800000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
30	PUR-202506-005	5	2025-06-23 00:00:00	1000000.00	1000000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
31	PUR-202507-001	4	2025-07-03 00:00:00	1200000.00	1200000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
32	PUR-202507-002	5	2025-07-08 00:00:00	1000000.00	1000000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
33	PUR-202507-003	4	2025-07-13 00:00:00	1300000.00	1300000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
34	PUR-202507-004	5	2025-07-18 00:00:00	900000.00	900000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
35	PUR-202507-005	4	2025-07-23 00:00:00	1100000.00	1100000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
36	PUR-202508-001	5	2025-08-03 00:00:00	1300000.00	1300000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
37	PUR-202508-002	4	2025-08-08 00:00:00	1100000.00	1100000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
38	PUR-202508-003	5	2025-08-13 00:00:00	1400000.00	1400000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
39	PUR-202508-004	4	2025-08-18 00:00:00	1000000.00	1000000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
40	PUR-202508-005	5	2025-08-23 00:00:00	1200000.00	1200000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
41	PUR-202509-001	4	2025-09-03 00:00:00	1400000.00	1400000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
42	PUR-202509-002	5	2025-09-08 00:00:00	1200000.00	1200000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
43	PUR-202509-003	4	2025-09-13 00:00:00	1500000.00	1500000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
44	PUR-202509-004	5	2025-09-18 00:00:00	1100000.00	1100000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
45	PUR-202509-005	4	2025-09-23 00:00:00	1300000.00	1300000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
46	PUR-202510-001	5	2025-10-03 00:00:00	1500000.00	1500000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
47	PUR-202510-002	4	2025-10-08 00:00:00	1300000.00	1300000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
48	PUR-202510-003	5	2025-10-13 00:00:00	1600000.00	1600000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
49	PUR-202510-004	4	2025-10-18 00:00:00	1200000.00	1200000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
50	PUR-202510-005	5	2025-10-23 00:00:00	1400000.00	1400000.00	2	completed	2025-10-03 13:29:14.460139	2025-10-03 13:29:14.460139
65	PN-1763703651955	1	2025-11-21 12:40:51.955519	10000.00	10000.00	1	completed	2025-11-21 12:40:51.955519	2025-11-21 12:40:51.955519
66	PN-1763705443649	1	2025-11-21 13:10:43.649429	3000.00	3000.00	2	completed	2025-11-21 13:10:43.649429	2025-11-21 13:10:43.649429
67	PN-1763705801512	1	2025-11-21 13:16:41.512895	2000.00	2000.00	1	completed	2025-11-21 13:16:41.512895	2025-11-21 13:16:41.512895
68	PN-1763705879828	1	2025-11-21 13:17:59.829594	3000.00	3000.00	2	completed	2025-11-21 13:17:59.829594	2025-11-21 13:17:59.829594
54	PN-1761585180950	1	2025-10-28 00:00:00	600000.00	600000.00	2	completed	2025-10-28 00:13:00.961393	2025-10-28 00:13:00.961393
60	PN-1762365099105	1	2025-11-06 00:51:39.106319	5000.00	5000.00	2	completed	2025-11-06 00:51:39.106319	2025-11-06 00:51:39.106319
61	PN-1762365136743	1	2025-11-06 00:52:16.74421	1000.00	1000.00	1	completed	2025-11-06 00:52:16.74421	2025-11-06 00:52:16.74421
62	PN-1762366014656	1	2025-11-06 01:06:54.656918	10000.00	10000.00	2	completed	2025-11-06 01:06:54.656918	2025-11-06 01:06:54.656918
69	PN-1763705899544	1	2025-11-21 13:18:19.544731	500.00	500.00	2	completed	2025-11-21 13:18:19.544731	2025-11-21 13:18:19.544731
70	PN-1763705927534	1	2025-11-21 13:18:47.534845	1600000.00	1600000.00	2	completed	2025-11-21 13:18:47.534845	2025-11-21 13:18:47.534845
63	PN-1762490886111	20	2025-11-07 11:48:06.111092	20000.00	20000.00	1	completed	2025-11-07 11:48:06.111092	2025-11-07 11:48:06.111092
64	PN-1762491234173	1	2025-11-07 11:53:54.173905	2000.00	2000.00	2	completed	2025-11-07 11:53:54.173905	2025-11-07 11:53:54.173905
71	PN-1763706077280	1	2025-11-21 13:21:17.27951	2800000.00	2800000.00	1	completed	2025-11-21 13:21:17.27951	2025-11-21 13:21:17.27951
72	PN-1763706451672	1	2025-11-21 13:27:31.672081	5000.00	5000.00	1	completed	2025-11-21 13:27:31.672081	2025-11-21 13:27:31.672081
73	PN-1763706832454	1	2025-11-21 13:33:52.454756	800000.00	800000.00	1	completed	2025-11-21 13:33:52.454756	2025-11-21 13:33:52.454756
74	PN-1763710851929	20	2025-11-21 14:40:51.928748	4005000.00	4005000.00	2	completed	2025-11-21 14:40:51.928748	2025-11-21 14:40:51.928748
75	PN-1763711261261	20	2025-11-21 14:47:41.261917	5000.00	5000.00	1	completed	2025-11-21 14:47:41.261917	2025-11-21 14:47:41.261917
76	PN-1764135565530	1	2025-11-26 12:39:25.529827	100.00	100.00	2	pending	2025-11-26 12:39:25.529827	2025-11-28 14:30:40.354226
90	PN-1764316170498	1	2025-11-28 14:49:30.498216	100.00	100.00	1	completed	2025-11-28 14:49:30.498216	2025-11-28 14:49:30.498216
91	PN-1764316181933	1	2025-11-28 14:49:41.933856	100.00	100.00	\N	completed	2025-11-28 14:49:41.933856	2025-11-28 14:49:41.933856
95	PN-1764316873677	1	2025-11-28 15:01:13.6782	400000.00	400000.00	1	completed	2025-11-28 15:01:13.6782	2025-11-28 15:01:13.6782
94	PN-1764316797752	1	2025-11-28 14:59:57.751909	100.00	100.00	2	pending	2025-11-28 14:59:57.751909	2025-11-28 16:01:44.029507
96	PN-1764320737806	1	2025-11-28 16:05:37.806014	2000.00	2000.00	\N	completed	2025-11-28 16:05:37.806014	2025-11-28 16:06:12.323764
98	PN-1764321221830	1	2025-11-28 16:13:41.831246	5000.00	5000.00	2	pending	2025-11-28 16:13:41.831246	2025-11-28 16:13:41.831246
100	PN-1764709509387	1	2025-12-03 04:05:09.387723	16000000.00	16000000.00	1	completed	2025-12-03 04:05:09.387723	2025-12-03 04:05:09.387723
101	PN-1764749151768	19	2025-12-03 15:05:51.768841	110000.00	110000.00	1	completed	2025-12-03 15:05:51.768841	2025-12-03 15:05:51.768841
102	PN-1764752617212	19	2025-12-03 16:03:37.212157	1000.00	1000.00	1	completed	2025-12-03 16:03:37.212157	2025-12-03 16:03:37.212157
103	PN-1764752833217	19	2025-12-03 16:07:13.216957	112000.00	112000.00	1	completed	2025-12-03 16:07:13.216957	2025-12-03 16:07:13.216957
104	PN-1764753625864	19	2025-12-03 16:20:25.865572	1000.00	1000.00	1	completed	2025-12-03 16:20:25.865572	2025-12-03 16:20:25.865572
105	PN-1764753877261	19	2025-12-03 16:24:37.261583	1000.00	1000.00	1	completed	2025-12-03 16:24:37.261583	2025-12-03 16:24:37.261583
110	PN-1764757434851	1	2025-12-03 17:23:54.851294	1000.00	1000.00	1	completed	2025-12-03 17:23:54.851294	2025-12-03 17:23:54.851294
111	PN-1764757489510	1	2025-12-03 17:24:49.510693	5000.00	5000.00	1	completed	2025-12-03 17:24:49.510693	2025-12-03 17:24:49.510693
112	PN-1764757722273	1	2025-12-03 17:28:42.274026	1000.00	1000.00	1	completed	2025-12-03 17:28:42.274026	2025-12-03 17:28:42.274026
118	PN-1764758748998	1	2025-12-03 17:45:48.998512	2000.00	2000.00	1	completed	2025-12-03 17:45:48.998512	2025-12-03 17:45:48.998512
120	PN-1764759416866	1	2025-12-03 17:56:56.865365	2000.00	2000.00	1	completed	2025-12-03 17:56:56.865365	2025-12-03 17:56:56.865365
124	PN-1764760332374	1	2025-12-03 18:12:12.374208	2000.00	2000.00	1	completed	2025-12-03 18:12:12.374208	2025-12-03 18:12:12.374208
125	PN-1764760405827	1	2025-12-03 18:13:25.827329	2000.00	2000.00	1	completed	2025-12-03 18:13:25.827329	2025-12-03 18:13:25.827329
126	PN-1764760489730	1	2025-12-03 18:14:49.730595	1000.00	1000.00	1	completed	2025-12-03 18:14:49.730595	2025-12-03 18:14:49.730595
127	PN-1764760534894	1	2025-12-03 18:15:34.894494	2000.00	2000.00	1	completed	2025-12-03 18:15:34.894494	2025-12-03 18:15:34.894494
128	PN-1764760554147	1	2025-12-03 18:15:54.147913	4000.00	4000.00	1	pending	2025-12-03 18:15:54.147913	2025-12-07 17:36:41.151731
156	PN-1765705828152	1	2025-12-14 16:50:28.152258	1500000.00	1500000.00	1	completed	2025-12-14 16:50:28.152258	2025-12-14 16:50:28.152258
157	PN-1765753786152	1	2025-12-15 06:09:46.153096	450000.00	450000.00	2	completed	2025-12-15 06:09:46.153096	2025-12-15 06:09:46.153096
129	PN-1765105470918	1	2025-12-07 18:04:30.91934	1000.00	1000.00	2	pending	2025-12-07 18:04:30.91934	2025-12-12 03:01:24.427971
130	PN-1765487585665	1	2025-12-12 04:13:05.665006	25000.00	25000.00	1	completed	2025-12-12 04:13:05.665006	2025-12-12 04:13:05.665006
143	PN-1765685297186	1	2025-12-14 11:08:17.186075	30000.00	30000.00	2	completed	2025-12-14 11:08:17.186075	2025-12-14 11:08:17.186075
146	PN-1765685367422	1	2025-12-14 11:09:27.422918	5000.00	5000.00	1	completed	2025-12-14 11:09:27.422918	2025-12-14 11:09:27.422918
147	PN-1765685456302	1	2025-12-14 11:10:56.302226	30000.00	30000.00	2	completed	2025-12-14 11:10:56.302226	2025-12-14 11:10:56.302226
151	PN-1765686338155	1	2025-12-14 11:25:38.154966	30000.00	30000.00	1	completed	2025-12-14 11:25:38.154966	2025-12-14 11:25:38.154966
152	PN-1765687854937	1	2025-12-14 11:50:54.936932	60000.00	60000.00	2	completed	2025-12-14 11:50:54.936932	2025-12-14 11:50:54.936932
153	PN-1765688996214	1	2025-12-14 12:09:56.213723	1110000.00	1110000.00	1	completed	2025-12-14 12:09:56.213723	2025-12-14 12:09:56.213723
154	PN-1765700793899	19	2025-12-14 15:26:33.900475	30000.00	30000.00	2	completed	2025-12-14 15:26:33.900475	2025-12-14 15:26:33.900475
155	PN-1765700824987	19	2025-12-14 15:27:04.987708	600000.00	600000.00	1	completed	2025-12-14 15:27:04.987708	2025-12-14 15:27:04.987708
158	PN-1765769066891	1	2025-12-15 10:24:26.891381	180000.00	180000.00	1	completed	2025-12-15 10:24:26.891381	2025-12-15 10:24:26.891381
\.


--
-- TOC entry 5048 (class 0 OID 33106)
-- Dependencies: 224
-- Data for Name: suppliers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.suppliers (supplier_id, name, phone, email, address, created_at) FROM stdin;
1	Công ty Dược phẩm Thú y Việt Nam	0901234567	duocphamviet@gmail.com	123 Đường Nguyễn Huệ, Quận 1, TP.HCM	2025-10-03 13:29:14.460139
2	Nhà cung cấp Vật tư Y tế ABC	0912345678	vattuyteabc@gmail.com	456 Đường Lê Lợi, Quận 5, TP.HCM	2025-10-03 13:29:14.460139
3	Công ty Thức ăn Thú cưng Global	0923456789	thucanpetglobal@gmail.com	789 Đường Võ Văn Kiệt, Quận Bình Tân, TP.HCM	2025-10-03 13:29:14.460139
4	Nhà phân phối Vắc-xin Quốc tế	0934567890	vacxinquocte@gmail.com	1011 Đường Phạm Văn Đồng, Quận Gò Vấp, TP.HCM	2025-10-03 13:29:14.460139
5	Công ty Phụ kiện Thú cưng PetShop	0945678901	phukienpetshop@gmail.com	1213 Đường Trường Chinh, Quận Tân Bình, TP.HCM	2025-10-03 13:29:14.460139
6	Nhà cung cấp Thiết bị Y tế MedTech	0956789012	medtech@gmail.com	1415 Đường CMT8, Quận 3, TP.HCM	2025-10-03 13:29:14.460139
7	Công ty Thực phẩm Bổ sung BioLife	0967890123	biolife@gmail.com	1617 Đường Lý Thường Kiệt, Quận 10, TP.HCM	2025-10-03 13:29:14.460139
8	Nhà phân phối Sản phẩm Vệ sinh CleanPet	0978901234	cleanpet@gmail.com	1819 Đường Nguyễn Văn Linh, Quận 7, TP.HCM	2025-10-03 13:29:14.460139
9	Công ty Dụng cụ Game PetFun	0989012345	petfun@gmail.com	2021 Đường Trần Hưng Đạo, Quận 1, TP.HCM	2025-10-03 13:29:14.460139
10	Nhà cung cấp Khác MiscSupply	0990123456	miscsupply@gmail.com	2223 Đường Hoàng Văn Thụ, Quận Phú Nhuận, TP.HCM	2025-10-03 13:29:14.460139
\.


--
-- TOC entry 5046 (class 0 OID 33096)
-- Dependencies: 222
-- Data for Name: units; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.units (unit_id, name, description, created_at) FROM stdin;
1	Viên	Đơn vị cho thuốc dạng viên nén	2025-10-03 13:29:14.460139
2	Hộp	Đơn vị cho sản phẩm đóng hộp	2025-10-03 13:29:14.460139
3	Kg	Đơn vị cho thức ăn theo cân nặng	2025-10-03 13:29:14.460139
4	Lọ	Đơn vị cho thuốc dạng lỏng hoặc vắc-xin	2025-10-03 13:29:14.460139
5	Cái	Đơn vị cho dụng cụ hoặc phụ kiện	2025-10-03 13:29:14.460139
6	Túi	Đơn vị cho thức ăn đóng túi	2025-10-03 13:29:14.460139
7	Bộ	Đơn vị cho set dụng cụ y tế	2025-10-03 13:29:14.460139
8	Ml	Đơn vị cho dung dịch, siro	2025-10-03 13:29:14.460139
9	Gói	Đơn vị cho thực phẩm bổ sung dạng gói	2025-10-03 13:29:14.460139
10	Thùng	Đơn vị cho hàng nhập số lượng lớn	2025-10-03 13:29:14.460139
\.


--
-- TOC entry 5101 (class 0 OID 0)
-- Dependencies: 249
-- Name: alerts_alert_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.alerts_alert_id_seq', 26, true);


--
-- TOC entry 5102 (class 0 OID 0)
-- Dependencies: 219
-- Name: categories_category_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.categories_category_id_seq', 22, true);


--
-- TOC entry 5103 (class 0 OID 0)
-- Dependencies: 227
-- Name: customers_customer_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.customers_customer_id_seq', 16, true);


--
-- TOC entry 5104 (class 0 OID 0)
-- Dependencies: 229
-- Name: employees_employee_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.employees_employee_id_seq', 21, true);


--
-- TOC entry 5105 (class 0 OID 0)
-- Dependencies: 245
-- Name: financial_transactions_transaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.financial_transactions_transaction_id_seq', 453, true);


--
-- TOC entry 5106 (class 0 OID 0)
-- Dependencies: 239
-- Name: order_details_order_detail_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.order_details_order_detail_id_seq', 233, true);


--
-- TOC entry 5107 (class 0 OID 0)
-- Dependencies: 237
-- Name: orders_order_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.orders_order_id_seq', 181, true);


--
-- TOC entry 5108 (class 0 OID 0)
-- Dependencies: 217
-- Name: payment_methods_payment_method_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.payment_methods_payment_method_id_seq', 10, true);


--
-- TOC entry 5109 (class 0 OID 0)
-- Dependencies: 251
-- Name: payments_payment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.payments_payment_id_seq', 72, true);


--
-- TOC entry 5110 (class 0 OID 0)
-- Dependencies: 247
-- Name: predictions_prediction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.predictions_prediction_id_seq', 289434, true);


--
-- TOC entry 5111 (class 0 OID 0)
-- Dependencies: 225
-- Name: products_product_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.products_product_id_seq', 26, true);


--
-- TOC entry 5112 (class 0 OID 0)
-- Dependencies: 233
-- Name: promotion_categories_promotion_category_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.promotion_categories_promotion_category_id_seq', 12, true);


--
-- TOC entry 5113 (class 0 OID 0)
-- Dependencies: 235
-- Name: promotion_products_promotion_product_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.promotion_products_promotion_product_id_seq', 18, true);


--
-- TOC entry 5114 (class 0 OID 0)
-- Dependencies: 231
-- Name: promotions_promotion_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.promotions_promotion_id_seq', 11, true);


--
-- TOC entry 5115 (class 0 OID 0)
-- Dependencies: 243
-- Name: purchase_details_purchase_detail_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.purchase_details_purchase_detail_id_seq', 184, true);


--
-- TOC entry 5116 (class 0 OID 0)
-- Dependencies: 241
-- Name: purchases_purchase_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.purchases_purchase_id_seq', 158, true);


--
-- TOC entry 5117 (class 0 OID 0)
-- Dependencies: 223
-- Name: suppliers_supplier_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.suppliers_supplier_id_seq', 10, true);


--
-- TOC entry 5118 (class 0 OID 0)
-- Dependencies: 221
-- Name: units_unit_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.units_unit_id_seq', 10, true);


--
-- TOC entry 4856 (class 2606 OID 33450)
-- Name: alerts alerts_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.alerts
    ADD CONSTRAINT alerts_pkey PRIMARY KEY (alert_id);


--
-- TOC entry 4808 (class 2606 OID 33094)
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (category_id);


--
-- TOC entry 4818 (class 2606 OID 33156)
-- Name: customers customers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.customers
    ADD CONSTRAINT customers_pkey PRIMARY KEY (customer_id);


--
-- TOC entry 4820 (class 2606 OID 33167)
-- Name: employees employees_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_pkey PRIMARY KEY (employee_id);


--
-- TOC entry 4822 (class 2606 OID 33169)
-- Name: employees employees_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.employees
    ADD CONSTRAINT employees_username_key UNIQUE (username);


--
-- TOC entry 4850 (class 2606 OID 33368)
-- Name: financial_transactions financial_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.financial_transactions
    ADD CONSTRAINT financial_transactions_pkey PRIMARY KEY (transaction_id);


--
-- TOC entry 4838 (class 2606 OID 33276)
-- Name: order_details order_details_order_id_product_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_details
    ADD CONSTRAINT order_details_order_id_product_id_key UNIQUE (order_id, product_id);


--
-- TOC entry 4840 (class 2606 OID 33274)
-- Name: order_details order_details_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_details
    ADD CONSTRAINT order_details_pkey PRIMARY KEY (order_detail_id);


--
-- TOC entry 4834 (class 2606 OID 33244)
-- Name: orders orders_order_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_order_number_key UNIQUE (order_number);


--
-- TOC entry 4836 (class 2606 OID 33242)
-- Name: orders orders_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_pkey PRIMARY KEY (order_id);


--
-- TOC entry 4804 (class 2606 OID 33084)
-- Name: payment_methods payment_methods_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payment_methods
    ADD CONSTRAINT payment_methods_code_key UNIQUE (code);


--
-- TOC entry 4806 (class 2606 OID 33082)
-- Name: payment_methods payment_methods_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payment_methods
    ADD CONSTRAINT payment_methods_pkey PRIMARY KEY (payment_method_id);


--
-- TOC entry 4858 (class 2606 OID 50206)
-- Name: payments payments_pay_code_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pay_code_key UNIQUE (pay_code);


--
-- TOC entry 4860 (class 2606 OID 50204)
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (payment_id);


--
-- TOC entry 4852 (class 2606 OID 33410)
-- Name: predictions predictions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.predictions
    ADD CONSTRAINT predictions_pkey PRIMARY KEY (prediction_id);


--
-- TOC entry 4854 (class 2606 OID 33412)
-- Name: predictions predictions_product_id_predicted_month_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.predictions
    ADD CONSTRAINT predictions_product_id_predicted_month_key UNIQUE (product_id, predicted_month);


--
-- TOC entry 4814 (class 2606 OID 33130)
-- Name: products products_barcode_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_barcode_key UNIQUE (barcode);


--
-- TOC entry 4816 (class 2606 OID 33128)
-- Name: products products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_pkey PRIMARY KEY (product_id);


--
-- TOC entry 4826 (class 2606 OID 33199)
-- Name: promotion_categories promotion_categories_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotion_categories
    ADD CONSTRAINT promotion_categories_pkey PRIMARY KEY (promotion_category_id);


--
-- TOC entry 4828 (class 2606 OID 33201)
-- Name: promotion_categories promotion_categories_promotion_id_category_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotion_categories
    ADD CONSTRAINT promotion_categories_promotion_id_category_id_key UNIQUE (promotion_id, category_id);


--
-- TOC entry 4830 (class 2606 OID 33218)
-- Name: promotion_products promotion_products_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotion_products
    ADD CONSTRAINT promotion_products_pkey PRIMARY KEY (promotion_product_id);


--
-- TOC entry 4832 (class 2606 OID 33220)
-- Name: promotion_products promotion_products_promotion_id_product_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotion_products
    ADD CONSTRAINT promotion_products_promotion_id_product_id_key UNIQUE (promotion_id, product_id);


--
-- TOC entry 4824 (class 2606 OID 33178)
-- Name: promotions promotions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotions
    ADD CONSTRAINT promotions_pkey PRIMARY KEY (promotion_id);


--
-- TOC entry 4846 (class 2606 OID 33320)
-- Name: purchase_details purchase_details_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_details
    ADD CONSTRAINT purchase_details_pkey PRIMARY KEY (purchase_detail_id);


--
-- TOC entry 4848 (class 2606 OID 33322)
-- Name: purchase_details purchase_details_purchase_id_product_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_details
    ADD CONSTRAINT purchase_details_purchase_id_product_id_key UNIQUE (purchase_id, product_id);


--
-- TOC entry 4842 (class 2606 OID 33299)
-- Name: purchases purchases_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchases
    ADD CONSTRAINT purchases_pkey PRIMARY KEY (purchase_id);


--
-- TOC entry 4844 (class 2606 OID 33301)
-- Name: purchases purchases_purchase_number_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchases
    ADD CONSTRAINT purchases_purchase_number_key UNIQUE (purchase_number);


--
-- TOC entry 4812 (class 2606 OID 33114)
-- Name: suppliers suppliers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.suppliers
    ADD CONSTRAINT suppliers_pkey PRIMARY KEY (supplier_id);


--
-- TOC entry 4810 (class 2606 OID 33104)
-- Name: units units_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.units
    ADD CONSTRAINT units_pkey PRIMARY KEY (unit_id);


--
-- TOC entry 4887 (class 2620 OID 50305)
-- Name: orders trg_cancel_transactions_on_order_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_cancel_transactions_on_order_delete BEFORE DELETE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.cancel_transactions_on_order_delete();


--
-- TOC entry 4891 (class 2620 OID 50303)
-- Name: purchases trg_cancel_transactions_on_purchase_delete; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_cancel_transactions_on_purchase_delete BEFORE DELETE ON public.purchases FOR EACH ROW EXECUTE FUNCTION public.cancel_transactions_on_purchase_delete();


--
-- TOC entry 4888 (class 2620 OID 50299)
-- Name: orders trg_sync_transaction_status_from_order; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_sync_transaction_status_from_order AFTER UPDATE OF status ON public.orders FOR EACH ROW EXECUTE FUNCTION public.sync_transaction_status_from_order();


--
-- TOC entry 4892 (class 2620 OID 50301)
-- Name: purchases trg_sync_transaction_status_from_purchase; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_sync_transaction_status_from_purchase AFTER UPDATE OF status ON public.purchases FOR EACH ROW EXECUTE FUNCTION public.sync_transaction_status_from_purchase();


--
-- TOC entry 4893 (class 2620 OID 33695)
-- Name: purchases trigger_create_expense_transaction; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_create_expense_transaction AFTER INSERT ON public.purchases FOR EACH ROW EXECUTE FUNCTION public.create_expense_transaction_on_purchase();


--
-- TOC entry 4889 (class 2620 OID 33466)
-- Name: orders trigger_create_income_transaction; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_create_income_transaction AFTER INSERT ON public.orders FOR EACH ROW EXECUTE FUNCTION public.create_income_transaction_on_order();


--
-- TOC entry 4890 (class 2620 OID 41987)
-- Name: order_details trigger_update_stock_on_order; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_update_stock_on_order AFTER INSERT ON public.order_details FOR EACH ROW EXECUTE FUNCTION public.update_stock_on_order();


--
-- TOC entry 4894 (class 2620 OID 50293)
-- Name: purchase_details trigger_update_stock_on_purchase; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trigger_update_stock_on_purchase AFTER INSERT ON public.purchase_details FOR EACH ROW EXECUTE FUNCTION public.update_stock_on_purchase();


--
-- TOC entry 4885 (class 2606 OID 33456)
-- Name: alerts alerts_related_prediction_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.alerts
    ADD CONSTRAINT alerts_related_prediction_id_fkey FOREIGN KEY (related_prediction_id) REFERENCES public.predictions(prediction_id) ON DELETE SET NULL;


--
-- TOC entry 4886 (class 2606 OID 33451)
-- Name: alerts alerts_related_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.alerts
    ADD CONSTRAINT alerts_related_product_id_fkey FOREIGN KEY (related_product_id) REFERENCES public.products(product_id) ON DELETE SET NULL;


--
-- TOC entry 4878 (class 2606 OID 33376)
-- Name: financial_transactions financial_transactions_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.financial_transactions
    ADD CONSTRAINT financial_transactions_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id) ON DELETE SET NULL;


--
-- TOC entry 4879 (class 2606 OID 33371)
-- Name: financial_transactions financial_transactions_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.financial_transactions
    ADD CONSTRAINT financial_transactions_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(employee_id) ON DELETE RESTRICT;


--
-- TOC entry 4880 (class 2606 OID 33396)
-- Name: financial_transactions financial_transactions_payment_method_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.financial_transactions
    ADD CONSTRAINT financial_transactions_payment_method_id_fkey FOREIGN KEY (payment_method_id) REFERENCES public.payment_methods(payment_method_id) ON DELETE RESTRICT;


--
-- TOC entry 4881 (class 2606 OID 33386)
-- Name: financial_transactions financial_transactions_related_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.financial_transactions
    ADD CONSTRAINT financial_transactions_related_order_id_fkey FOREIGN KEY (related_order_id) REFERENCES public.orders(order_id) ON DELETE SET NULL;


--
-- TOC entry 4882 (class 2606 OID 33391)
-- Name: financial_transactions financial_transactions_related_purchase_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.financial_transactions
    ADD CONSTRAINT financial_transactions_related_purchase_id_fkey FOREIGN KEY (related_purchase_id) REFERENCES public.purchases(purchase_id) ON DELETE SET NULL;


--
-- TOC entry 4883 (class 2606 OID 33381)
-- Name: financial_transactions financial_transactions_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.financial_transactions
    ADD CONSTRAINT financial_transactions_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(supplier_id) ON DELETE SET NULL;


--
-- TOC entry 4872 (class 2606 OID 33277)
-- Name: order_details order_details_order_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_details
    ADD CONSTRAINT order_details_order_id_fkey FOREIGN KEY (order_id) REFERENCES public.orders(order_id) ON DELETE CASCADE;


--
-- TOC entry 4873 (class 2606 OID 33282)
-- Name: order_details order_details_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.order_details
    ADD CONSTRAINT order_details_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(product_id) ON DELETE RESTRICT;


--
-- TOC entry 4868 (class 2606 OID 33245)
-- Name: orders orders_customer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_customer_id_fkey FOREIGN KEY (customer_id) REFERENCES public.customers(customer_id) ON DELETE SET NULL;


--
-- TOC entry 4869 (class 2606 OID 33250)
-- Name: orders orders_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(employee_id) ON DELETE RESTRICT;


--
-- TOC entry 4870 (class 2606 OID 33255)
-- Name: orders orders_payment_method_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_payment_method_id_fkey FOREIGN KEY (payment_method_id) REFERENCES public.payment_methods(payment_method_id) ON DELETE RESTRICT;


--
-- TOC entry 4871 (class 2606 OID 33260)
-- Name: orders orders_promotion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.orders
    ADD CONSTRAINT orders_promotion_id_fkey FOREIGN KEY (promotion_id) REFERENCES public.promotions(promotion_id) ON DELETE SET NULL;


--
-- TOC entry 4884 (class 2606 OID 33413)
-- Name: predictions predictions_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.predictions
    ADD CONSTRAINT predictions_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(product_id) ON DELETE CASCADE;


--
-- TOC entry 4861 (class 2606 OID 33131)
-- Name: products products_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(category_id) ON DELETE RESTRICT;


--
-- TOC entry 4862 (class 2606 OID 33141)
-- Name: products products_supplier_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES public.suppliers(supplier_id) ON DELETE SET NULL;


--
-- TOC entry 4863 (class 2606 OID 33136)
-- Name: products products_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.products
    ADD CONSTRAINT products_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.units(unit_id) ON DELETE RESTRICT;


--
-- TOC entry 4864 (class 2606 OID 33207)
-- Name: promotion_categories promotion_categories_category_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotion_categories
    ADD CONSTRAINT promotion_categories_category_id_fkey FOREIGN KEY (category_id) REFERENCES public.categories(category_id) ON DELETE CASCADE;


--
-- TOC entry 4865 (class 2606 OID 33202)
-- Name: promotion_categories promotion_categories_promotion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotion_categories
    ADD CONSTRAINT promotion_categories_promotion_id_fkey FOREIGN KEY (promotion_id) REFERENCES public.promotions(promotion_id) ON DELETE CASCADE;


--
-- TOC entry 4866 (class 2606 OID 33226)
-- Name: promotion_products promotion_products_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotion_products
    ADD CONSTRAINT promotion_products_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(product_id) ON DELETE CASCADE;


--
-- TOC entry 4867 (class 2606 OID 33221)
-- Name: promotion_products promotion_products_promotion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.promotion_products
    ADD CONSTRAINT promotion_products_promotion_id_fkey FOREIGN KEY (promotion_id) REFERENCES public.promotions(promotion_id) ON DELETE CASCADE;


--
-- TOC entry 4876 (class 2606 OID 33328)
-- Name: purchase_details purchase_details_product_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_details
    ADD CONSTRAINT purchase_details_product_id_fkey FOREIGN KEY (product_id) REFERENCES public.products(product_id) ON DELETE RESTRICT;


--
-- TOC entry 4877 (class 2606 OID 33323)
-- Name: purchase_details purchase_details_purchase_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchase_details
    ADD CONSTRAINT purchase_details_purchase_id_fkey FOREIGN KEY (purchase_id) REFERENCES public.purchases(purchase_id) ON DELETE CASCADE;


--
-- TOC entry 4874 (class 2606 OID 33302)
-- Name: purchases purchases_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchases
    ADD CONSTRAINT purchases_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.employees(employee_id) ON DELETE RESTRICT;


--
-- TOC entry 4875 (class 2606 OID 33307)
-- Name: purchases purchases_payment_method_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.purchases
    ADD CONSTRAINT purchases_payment_method_id_fkey FOREIGN KEY (payment_method_id) REFERENCES public.payment_methods(payment_method_id) ON DELETE RESTRICT;


-- Completed on 2026-01-21 15:55:22

--
-- PostgreSQL database dump complete
--

\unrestrict j5LWfe8NZyhoIjrUx9mc2pi7pa2bja0peoqgmTAtpK0Z9UBugxbcQrJMKmdCzJK

