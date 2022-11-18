CREATE EXTENSION postgis;
CREATE EXTENSION postgis_raster;
CREATE EXTENSION postgis_topology;
--
-- PostgreSQL database dump
--

-- Dumped from database version 9.5.25
-- Dumped by pg_dump version 14.5 (Ubuntu 14.5-0ubuntu0.22.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

-- FUNCTIONS

CREATE OR REPLACE FUNCTION public.area_calc()
 RETURNS trigger
 LANGUAGE plpgsql
 STABLE
AS $function$
begin
    if new.geom is null then raise notice 'geom is null';return null;end if;
    new.area = st_area(st_transform(new.geom,22185)); return new;
end;
$function$

;
CREATE OR REPLACE FUNCTION public.estacion_id_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
new_id int;
begin
    if new.id is null then
       select coalesce(max(id)+1,1) into new_id from estaciones where tabla=new.tabla;
       if not found then
  new.id := 1;
   else
 new.id := new_id;
   end if;
end if;
    return new;
end $function$

;
CREATE OR REPLACE FUNCTION public.obs_hora_corte_constraint_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$ 
declare
_sql text;
_hora_corte interval;
_new_hora_corte interval;
_dt interval;
_check boolean;

begin
_sql := 'select fuentes.def_dt from fuentes,series_areal where fuentes.id=series_areal.fuentes_id and series_areal.id='||new.series_id;
execute _sql into _dt;
IF _dt IS NULL
THEN return NEW;
END IF;
_sql := 'select fuentes.hora_corte from fuentes,series_areal where fuentes.id=series_areal.fuentes_id and series_areal.id='||new.series_id;
execute _sql into _hora_corte;
IF _hora_corte IS NULL 
THEN return NEW;
END IF;
_sql := 'select extract(epoch from case when '''||_hora_corte||'''::interval<interval ''0 seconds'' then interval ''1 day''+'''||_hora_corte||'''::interval else '''||_hora_corte||'''::interval end)=(extract(epoch from '''||new.timestart||'''::timestamp-'''||new.timestart||'''::date))::integer%extract(epoch from '''||_dt||'''::interval)::integer';
execute _sql into _check;
IF _check
then return NEW;
ELSE
 raise notice 'new hora corte invalid';
     return NULL;
END IF;
end
$function$

;
CREATE OR REPLACE FUNCTION public.obs_dt_constraint_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
_sql text;
_dt interval;
_time_support interval;
_new_dt interval;

begin
_sql := 'select fuentes.def_dt,var."timeSupport" from fuentes,series_areal,var where fuentes.id=series_areal.fuentes_id and series_areal.id='||new.series_id||' AND series_areal.var_id=var.id';
execute _sql into _dt, _time_support;
-- _new_dt := new.timeend - new.timestart;
--raise notice 'new_dt: %, def_dt: %', _new_dt, _dt;
IF _time_support IS NOT NULL
THEN IF (new.timeend - _time_support = new.timestart OR new.timestart + _time_support = new.timeend)
    THEN RETURN NEW;
    ELSE raise notice 'new time support is invalid';
         return NULL;
    END IF;
ELSE
    IF (new.timeend - _dt = new.timestart OR new.timestart + _dt = new.timeend)
    then return NEW;
    ELSE raise notice 'new dt is invalid';
         return NULL;
    END IF;
END IF;
end
$function$

;
CREATE OR REPLACE FUNCTION public.obs_puntual_dt_constraint_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$

declare
_sql text;
_dt interval;
_hora_corte interval;
_new_dt interval;
_sql2 text;
_match boolean;

begin
_sql := 'select var."timeSupport",def_hora_corte  from var,series where var.id=series.var_id and series.id='||new.series_id;
execute _sql into _dt, _hora_corte;
IF (_dt is null)
THEN 
	return NEW;
ELSE
	IF (new.timeend - _dt = new.timestart OR new.timestart + _dt = new.timeend) 
	THEN 
		_sql2 := 'select exists (select 1 from observaciones where observaciones.series_id='||new.series_id||' AND '''||new.timestart||'''<observaciones.timeend AND '''||new.timeend||'''> observaciones.timestart AND '''||new.timestart||'''!=observaciones.timestart and '''||new.timeend||'''!=observaciones.timeend AND coalesce('||new.id||',-1) != observaciones.id)';
		execute _sql2 into _match;
		IF _match = TRUE
		THEN
			raise notice 'El intervalo intersecta con un registro existente'; 
			return NULL;
		ELSE 
			IF _hora_corte is null
			THEN
				return NEW;
			ELSE
				IF extract(epoch from case when _hora_corte<interval '0 seconds' then interval '1 day'+_hora_corte else _hora_corte end)=(extract(epoch from new.timestart-new.timestart::date))::integer%extract(epoch from _dt)::integer
				THEN 
					return NEW;
				ELSE
					raise notice 'new hora_corte is invalid';
					return NULL;
				END IF;
			END IF;
		END IF;
	ELSE 
		 raise notice 'new dt is invalid';
		 return NULL;
	END IF;
END IF;
end
$function$

;
CREATE OR REPLACE FUNCTION public.obs_range_constraint_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
_sql text;
_match boolean;
begin
_sql := 'select exists (select 1 from observaciones_areal where tsrange('''||new.timestart||''','''||new.timeend||''',''[)'') && tsrange(observaciones_areal.timestart,observaciones_areal.timeend,''[)'') AND '''||new.timestart||'''!=observaciones_areal.timestart and '''||new.timeend||'''!=observaciones_areal.timeend and observaciones_areal.series_id='||new.series_id||')';
execute _sql into _match;
--raise notice 'match: %', _match;
IF _match = TRUE
THEN return NULL;
ELSE return NEW;
END IF;
end
$function$

;
CREATE OR REPLACE FUNCTION public.check_par_lims()
 RETURNS trigger
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
bounds record;
begin
    if new.model_id is null then raise notice 'model_id is null'; return null; end if;
    if new.orden is null then raise notice 'orden is null'; return null; end if;
    execute ( 'select * from parametros where model_id=' || new.model_id || ' and orden=' || new.orden) into bounds;
    if bounds is null then raise notice 'No se encontro parametro'; return null;end if;
    if (new.valor < coalesce(bounds.lim_inf,'-inf') or new.valor > coalesce(bounds.lim_sup,'inf'))
    then raise notice 'ERROR: El valor excede el rango valido para el parametro. %>=%>=%', bounds.lim_inf, bounds.nombre, bounds.lim_sup;
         return null;
    else 
         return new;
    end if;
end;
$function$

;
CREATE OR REPLACE FUNCTION public.get_model_id()
 RETURNS trigger
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
mid int;
begin
    if new.cal_id is null then raise notice 'cal_id is null';return null;end if;
    execute ( 'select model_id from calibrados where id=' || new.cal_id ) into mid;
    new.model_id := mid;
    if new.model_id is null then raise notice 'model_id no encontrado para cal_id=%',new.cal_id;return null;end if;
    return new;
end;
$function$

;
CREATE OR REPLACE FUNCTION public.orden_model_forz()
 RETURNS trigger
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
orden int :=1;
begin
    execute ( 'select coalesce(max(orden)+1,1) from ' || TG_TABLE_NAME || ' where model_id=' || new.model_id ) into orden;
    new.orden := orden;
    return new;
end;
$function$

;
CREATE OR REPLACE FUNCTION public.insert_condicion()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
    if NEW.condicion is null then
        NEW.condicion := case when NEW.altura_pronostico < NEW.altura_hoy then 'baja' when NEW.altura_pronostico = NEW.altura_hoy then 'permanece' else 'crece' end || ':' || case when NEW.altura_pronostico < NEW.nivel_de_aguas_bajas then 'l' else case when NEW.altura_pronostico < NEW.nivel_de_alerta then 'n' when NEW.altura_pronostico < NEW.nivel_de_evacuacion then 'a' else 'e' end end;
    end if;
    return new;
end;
$function$

;
CREATE OR REPLACE FUNCTION public.insert_estacion_id()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
    if NEW.estacion_id is null then
        NEW.estacion_id := NEW.unid;
    end if;
    return new;
end;
$function$

;
CREATE OR REPLACE FUNCTION public.insert_tvp()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
    if NEW.valor is null then
        NEW.valor := to_json( ARRAY[ARRAY[to_char(NEW.fecha_hoy,'YYYY-MM-DD'),NEW.altura_hoy::text],ARRAY[to_char(NEW.fecha_pronostico,'YYYY-MM-DD'),NEW.altura_pronostico::text],ARRAY[to_char(NEW.fecha_tendencia,'YYYY-MM-DD'),NEW.altura_tendencia::text]]
        )::text;
    end if;
    return new;
end;
$function$

;
CREATE OR REPLACE FUNCTION public.check_key_tab(integer[], character varying, character varying)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  arrIds ALIAS for $1;
  tab ALIAS for $2;
  key ALIAS for $3;
  retVal boolean :=true;
  thisval boolean;
begin
   if arrIds is null
   then raise notice 'null array';
        return true;
   else
       for I in array_lower(arrIds,1)..array_upper(arrIds,1) LOOP
          execute ( 'select exists (select 1 from ' || quote_ident(tab) || ' where ' || quote_ident(key) || ' = ' || arrIds[I] ||')' ) into thisval;
    --    raise notice 'I:% thisval:%', arrIds[I], thisval;
          if thisval = true
          then 
          -- raise notice 'exists';
               retVal := retVal;
           else
            raise notice 'campo % valor % no existe en tabla %', key, arrIds[I], tab;
                retVal := false;
            end if;
       end loop;
    end if;
return retVal;
end;
$function$

;

-- END FUNCTIONS

--
-- Name: accessors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.accessors (
    class character varying,
    url character varying,
    series_tipo character varying,
    series_source_id integer,
    time_update timestamp without time zone,
    name character varying NOT NULL,
    config json,
    series_id integer,
    upload_fields json DEFAULT '{}'::json,
    title character varying,
    token character varying,
    token_expiry_date timestamp without time zone
);


--
-- Name: areas_pluvio; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.areas_pluvio (
    id integer,
    geom public.geometry(Polygon,4326),
    exutorio public.geometry(Point,4326),
    nombre character varying(64),
    area double precision DEFAULT 0,
    unid integer,
    rho real DEFAULT 0.5,
    ae real DEFAULT 1,
    wp real DEFAULT 0.03,
    uru_index integer,
    activar boolean DEFAULT true,
    as_max real,
    rast public.raster,
    mostrar boolean DEFAULT true,
    exutorio_id integer
);


--
-- Name: estaciones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.estaciones (
    tabla character varying,
    id integer NOT NULL,
    tipo character varying(1),
    "real" boolean,
    nombre character varying,
    id_externo character varying,
    has_obs boolean,
    has_area boolean,
    has_prono boolean,
    rio character varying,
    distrito character varying,
    pais character varying,
    geom public.geometry(Point),
    var character varying,
    cero_ign real,
    cero_mop real,
    id_cuenca integer,
    abrev character varying,
    rule real[],
    propietario character varying,
    unid integer NOT NULL,
    automatica boolean DEFAULT false,
    url character varying,
    habilitar boolean DEFAULT true,
    coordinates_url integer[],
    ubicacion character varying,
    localidad character varying,
    tipo_2 character varying,
    orden integer DEFAULT 100,
    observaciones character varying,
    altitud real
);


--
-- Name: observaciones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.observaciones (
    id bigint NOT NULL,
    series_id integer,
    timestart timestamp without time zone,
    timeend timestamp without time zone,
    nombre character varying,
    descripcion character varying,
    unit_id integer,
    timeupdate timestamp without time zone DEFAULT now()
);


--
-- Name: series; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.series (
    id integer NOT NULL,
    estacion_id integer NOT NULL,
    var_id integer NOT NULL,
    proc_id integer NOT NULL,
    unit_id integer NOT NULL
);


--
-- Name: valores_numarr; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.valores_numarr (
    obs_id bigint NOT NULL,
    valor real[]
);


--
-- Name: valores_num; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.valores_num (
    obs_id bigint NOT NULL,
    valor real
);


--
-- Name: alturas_alerta; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.alturas_alerta (
    unid integer NOT NULL,
    nombre character varying,
    valor real NOT NULL,
    estado character varying(1) NOT NULL
);


--
-- Name: h_q; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.h_q (
    formula character varying,
    escala_id integer,
    anti character varying,
    sql_expr character varying,
    r_function character varying,
    max real,
    anti_sql_expr character varying,
    anti_r_function character varying,
    from_date date,
    h_rmse real,
    q_rmse real,
    obs character varying,
    unid integer NOT NULL,
    activar boolean
);


--
-- Name: calibrados; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.calibrados (
    id integer NOT NULL,
    nombre character varying(40),
    modelo character varying(40),
    parametros real[],
    estados_iniciales real[],
    activar boolean,
    selected boolean DEFAULT false,
    out_id integer,
    area_id integer,
    in_id integer[],
    model_id integer,
    tramo_id integer,
    dt interval DEFAULT '1 day'::interval NOT NULL,
    t_offset interval DEFAULT '09:00:00'::interval NOT NULL,
    public boolean DEFAULT false,
    grupo_id integer,
    CONSTRAINT calibrados_in_id_check CHECK (public.check_key_tab(in_id, 'estaciones'::character varying, 'unid'::character varying))
);


--
-- Name: corridas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.corridas (
    cal_id integer NOT NULL,
    date timestamp without time zone NOT NULL,
    id integer NOT NULL,
    series_n integer DEFAULT 1,
    plan_cor_id integer
);


--
-- Name: modelos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.modelos (
    id integer NOT NULL,
    nombre character varying(40),
    parametros text[],
    estados text[],
    n_estados integer,
    n_parametros integer,
    script text,
    tipo character varying DEFAULT 'P-Q'::character varying,
    def_var_id integer DEFAULT 4 NOT NULL,
    def_unit_id integer DEFAULT 10 NOT NULL
);


--
-- Name: pronosticos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pronosticos (
    id integer NOT NULL,
    cor_id integer NOT NULL,
    series_id integer NOT NULL,
    timestart timestamp without time zone NOT NULL,
    timeend timestamp without time zone NOT NULL,
    qualifier character varying(50) DEFAULT 'main'::character varying
);


--
-- Name: valores_prono_num; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.valores_prono_num (
    prono_id integer NOT NULL,
    valor real
);


--
-- Name: observaciones_rast; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.observaciones_rast (
    id integer NOT NULL,
    series_id integer NOT NULL,
    timestart timestamp without time zone NOT NULL,
    timeend timestamp without time zone NOT NULL,
    valor public.raster NOT NULL,
    timeupdate timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: observaciones_areal; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.observaciones_areal (
    id integer NOT NULL,
    series_id integer NOT NULL,
    timestart timestamp without time zone,
    timeend timestamp without time zone,
    nombre character varying,
    descripcion character varying,
    unit_id integer,
    timeupdate timestamp without time zone DEFAULT now()
);


--
-- Name: series_areal; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.series_areal (
    id integer NOT NULL,
    area_id integer NOT NULL,
    proc_id integer NOT NULL,
    var_id integer NOT NULL,
    unit_id integer NOT NULL,
    fuentes_id integer NOT NULL
);


--
-- Name: valores_num_areal; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.valores_num_areal (
    obs_id integer NOT NULL,
    valor real NOT NULL
);


--
-- Name: areas_pluvio_unid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.areas_pluvio_unid_seq
    START WITH 240
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: areas_pluvio_unid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.areas_pluvio_unid_seq OWNED BY public.areas_pluvio.unid;


--
-- Name: asociaciones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asociaciones (
    id integer NOT NULL,
    source_tipo character varying,
    source_series_id integer NOT NULL,
    dest_tipo character varying,
    dest_series_id integer NOT NULL,
    agg_func character varying,
    dt interval,
    t_offset interval,
    "precision" integer,
    source_time_support interval,
    source_is_inst boolean,
    habilitar boolean DEFAULT true,
    expresion character varying
);


--
-- Name: asociaciones_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.asociaciones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: asociaciones_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.asociaciones_id_seq OWNED BY public.asociaciones.id;


--
-- Name: series_rast; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.series_rast (
    id integer NOT NULL,
    escena_id integer NOT NULL,
    fuentes_id integer NOT NULL,
    var_id integer NOT NULL,
    proc_id integer NOT NULL,
    unit_id integer NOT NULL,
    nombre character varying
);


--
-- Name: cal_estados; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cal_estados (
    id integer NOT NULL,
    cal_id integer NOT NULL,
    model_id integer DEFAULT 1 NOT NULL,
    orden integer NOT NULL,
    valor real NOT NULL
);


--
-- Name: cal_estados_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cal_estados_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cal_estados_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cal_estados_id_seq OWNED BY public.cal_estados.id;


--
-- Name: cal_out; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cal_out (
    id integer NOT NULL,
    cal_id integer NOT NULL,
    series_table character varying DEFAULT 'series'::character varying NOT NULL,
    series_id integer NOT NULL,
    orden integer DEFAULT 1 NOT NULL,
    model_id integer NOT NULL,
    CONSTRAINT series_id_foreign_key_check CHECK (public.check_key_tab(ARRAY[series_id], series_table, 'id'::character varying)),
    CONSTRAINT series_table_constraint CHECK ((((series_table)::text = 'series'::text) OR ((series_table)::text = 'series_areal'::text)))
);


--
-- Name: cal_out_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cal_out_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cal_out_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cal_out_id_seq OWNED BY public.cal_out.id;


--
-- Name: cal_pars; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cal_pars (
    id integer NOT NULL,
    cal_id integer NOT NULL,
    valor real NOT NULL,
    orden integer DEFAULT 1,
    model_id integer DEFAULT 1
);


--
-- Name: cal_pars_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cal_pars_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cal_pars_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cal_pars_id_seq OWNED BY public.cal_pars.id;


--
-- Name: cal_stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cal_stats (
    id integer NOT NULL,
    cal_id integer NOT NULL,
    model_id integer NOT NULL,
    timestart timestamp without time zone,
    timeend timestamp without time zone,
    n_cal integer,
    rnash_cal real[],
    rnash_val real[],
    beta real,
    omega real,
    repetir integer,
    iter integer,
    rmse real[],
    stats_json json,
    pvalues real[],
    calib_period timestamp without time zone[]
);


--
-- Name: cal_stats_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cal_stats_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cal_stats_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cal_stats_id_seq OWNED BY public.cal_stats.id;


--
-- Name: calibrados_grupos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.calibrados_grupos (
    id integer NOT NULL,
    nombre character varying
);


--
-- Name: calibrados_grupos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.calibrados_grupos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: calibrados_grupos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.calibrados_grupos_id_seq OWNED BY public.calibrados_grupos.id;


--
-- Name: calibrados_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.calibrados_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: calibrados_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.calibrados_id_seq OWNED BY public.calibrados.id;


--
-- Name: calibrados_out; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.calibrados_out (
    id integer NOT NULL,
    cal_id integer NOT NULL,
    out_id integer NOT NULL
);


--
-- Name: calibrados_out_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.calibrados_out_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: calibrados_out_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.calibrados_out_id_seq OWNED BY public.calibrados_out.id;


--
-- Name: calibrados_series_out; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.calibrados_series_out (
    id integer NOT NULL,
    cal_id integer NOT NULL,
    series_id integer NOT NULL
);


--
-- Name: calibrados_series_out_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.calibrados_series_out_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: calibrados_series_out_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.calibrados_series_out_id_seq OWNED BY public.calibrados_series_out.id;


--
-- Name: var; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.var (
    id integer NOT NULL,
    var character varying(6) NOT NULL,
    nombre character varying,
    abrev character varying,
    type character varying DEFAULT 'num'::character varying,
    datatype character varying DEFAULT 'Continuous'::character varying,
    valuetype character varying DEFAULT 'Field Observation'::character varying,
    "GeneralCategory" character varying DEFAULT 'Unknown'::character varying NOT NULL,
    "VariableName" character varying,
    "SampleMedium" character varying DEFAULT 'Unknown'::character varying NOT NULL,
    arr_names text[],
    def_unit_id integer DEFAULT 0 NOT NULL,
    "timeSupport" interval,
    def_hora_corte interval
);


--
-- Name: corridas_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.corridas_data (
    cor_id integer NOT NULL,
    data jsonb NOT NULL
);


--
-- Name: corridas_guardadas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.corridas_guardadas (
    cal_id integer NOT NULL,
    date timestamp without time zone NOT NULL,
    id integer NOT NULL,
    series_n integer,
    plan_cor_id integer
);


--
-- Name: pronosticos_guardados; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pronosticos_guardados (
    id integer,
    cor_id integer,
    series_id integer,
    timestart timestamp without time zone,
    timeend timestamp without time zone,
    qualifier character varying(50)
);


--
-- Name: valores_prono_num_guardados; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.valores_prono_num_guardados (
    prono_id integer,
    valor real
);


--
-- Name: corridas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.corridas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: corridas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.corridas_id_seq OWNED BY public.corridas.id;


--
-- Name: cuantiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cuantiles (
    escala_id integer,
    doy integer,
    min double precision,
    noventa double precision,
    mediana double precision,
    diez double precision,
    max double precision,
    unid integer
);


--
-- Name: cuantiles_mensuales; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cuantiles_mensuales (
    escala_id integer NOT NULL,
    month integer NOT NULL,
    min double precision,
    noventa double precision,
    mediana double precision,
    diez double precision,
    max double precision,
    media double precision,
    qmed double precision,
    n_h integer,
    n_q integer,
    unid integer
);


--
-- Name: cuantiles_suave; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cuantiles_suave (
    escala_id integer,
    doy integer,
    min double precision,
    noventa double precision,
    mediana double precision,
    diez double precision,
    max double precision,
    unid integer
);


--
-- Name: datatypes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.datatypes (
    id integer NOT NULL,
    term character varying NOT NULL,
    in_waterml1_cv boolean DEFAULT false,
    waterml2_code character varying,
    waterml2_uri character varying
);


--
-- Name: datatypes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.datatypes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: datatypes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.datatypes_id_seq OWNED BY public.datatypes.id;


--
-- Name: escenas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.escenas (
    id integer NOT NULL,
    geom public.geometry NOT NULL,
    nombre character varying
);


--
-- Name: escenas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.escenas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: escenas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.escenas_id_seq OWNED BY public.escenas.id;


--
-- Name: estaciones_unid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.estaciones_unid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: estaciones_unid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.estaciones_unid_seq OWNED BY public.estaciones.unid;


--
-- Name: redes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.redes (
    tabla_id character varying,
    id integer NOT NULL,
    nombre character varying,
    public boolean DEFAULT true,
    public_his_plata boolean DEFAULT false NOT NULL,
    user_id integer DEFAULT 4
);


--
-- Name: estados; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.estados (
    id integer NOT NULL,
    model_id integer NOT NULL,
    nombre character varying NOT NULL,
    range_min real NOT NULL,
    range_max real NOT NULL,
    def_val real,
    orden integer DEFAULT 1
);


--
-- Name: estados_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.estados_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: estados_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.estados_id_seq OWNED BY public.estados.id;


--
-- Name: extra_pars; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.extra_pars (
    id integer NOT NULL,
    cal_id integer NOT NULL,
    model_id integer NOT NULL,
    stddev_forzantes real[],
    stddev_estados real,
    var_innov text[],
    trim_sm boolean[],
    rule real[],
    asim text[],
    update text[],
    xpert boolean,
    sm_transform real[],
    replicates integer,
    par_fg real[],
    func character varying,
    lags integer[],
    windowsize integer,
    max_npasos integer,
    no_check1 boolean,
    no_check2 boolean,
    rk2 boolean,
    CONSTRAINT extra_pars_max_npasos_check CHECK ((max_npasos >= 1))
);


--
-- Name: extra_pars_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.extra_pars_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: extra_pars_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.extra_pars_id_seq OWNED BY public.extra_pars.id;


--
-- Name: fuentes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fuentes (
    id integer NOT NULL,
    nombre character varying NOT NULL,
    data_table character varying,
    data_column character varying,
    tipo character varying,
    def_proc_id integer,
    def_dt interval DEFAULT '1 day'::interval,
    hora_corte interval hour DEFAULT '12:00:00'::interval hour,
    def_unit_id integer,
    def_var_id integer,
    fd_column character varying,
    mad_table character varying,
    scale_factor real,
    data_offset real,
    def_pixel_height real,
    def_pixel_width real,
    def_srid integer DEFAULT 4326,
    def_extent public.geometry DEFAULT public.st_setsrid(public.st_makepolygon(public.st_geomfromtext('LINESTRING(-70 -40, -70 -10, -40 -10, -40 -40, -70 -40)'::text)), 4326),
    date_column character varying,
    def_pixeltype character varying(5) DEFAULT '32BF'::character varying,
    abstract character varying,
    source character varying,
    public boolean DEFAULT true
);


--
-- Name: procedimiento; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.procedimiento (
    id integer NOT NULL,
    nombre character varying NOT NULL,
    abrev character varying,
    descripcion character varying
);


--
-- Name: unidades; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.unidades (
    id integer NOT NULL,
    nombre character varying,
    abrev character varying,
    "UnitsID" integer DEFAULT 0 NOT NULL,
    "UnitsType" character varying DEFAULT 'Unknown'::character varying NOT NULL
);


--
-- Name: valores_numarr_areal; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.valores_numarr_areal (
    obs_id integer NOT NULL,
    valor real[] NOT NULL
);


--
-- Name: forzantes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.forzantes (
    id integer NOT NULL,
    cal_id integer NOT NULL,
    series_table character varying NOT NULL,
    series_id integer NOT NULL,
    cal boolean DEFAULT false,
    orden integer DEFAULT 1,
    model_id integer DEFAULT 1,
    CONSTRAINT forzantes_check CHECK (public.check_key_tab(ARRAY[series_id], series_table, 'id'::character varying)),
    CONSTRAINT forzantes_series_table_check CHECK ((((series_table)::text = 'series'::text) OR ((series_table)::text = 'series_areal'::text)))
);


--
-- Name: forzantes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.forzantes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: forzantes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.forzantes_id_seq OWNED BY public.forzantes.id;


--
-- Name: modelos_forzantes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.modelos_forzantes (
    id integer NOT NULL,
    model_id integer,
    orden integer DEFAULT 1,
    var_id integer,
    unit_id integer,
    nombre character varying,
    inst boolean DEFAULT true,
    tipo character varying DEFAULT 'areal'::character varying NOT NULL,
    required boolean DEFAULT true
);


--
-- Name: fuentes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.fuentes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: fuentes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.fuentes_id_seq OWNED BY public.fuentes.id;


--
-- Name: tramos; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tramos (
    unid integer NOT NULL,
    nombre character varying,
    out_id integer,
    in_id integer,
    area_id integer,
    longitud real,
    geom public.geometry(LineString,4326),
    rio character varying
);


--
-- Name: modelos_forzantes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.modelos_forzantes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: modelos_forzantes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.modelos_forzantes_id_seq OWNED BY public.modelos_forzantes.id;


--
-- Name: modelos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.modelos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: modelos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.modelos_id_seq OWNED BY public.modelos.id;


--
-- Name: modelos_out; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.modelos_out (
    id integer NOT NULL,
    model_id integer NOT NULL,
    orden integer DEFAULT 1 NOT NULL,
    var_id integer NOT NULL,
    unit_id integer NOT NULL,
    nombre character varying,
    inst boolean DEFAULT true,
    series_table character varying DEFAULT 'series'::character varying NOT NULL,
    CONSTRAINT modelos_out_series_table_check CHECK ((((series_table)::text = 'series'::text) OR ((series_table)::text = 'series_areal'::text)))
);


--
-- Name: modelos_out_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.modelos_out_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: modelos_out_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.modelos_out_id_seq OWNED BY public.modelos_out.id;


--
-- Name: observaciones_areal_guardadas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.observaciones_areal_guardadas (
    id integer NOT NULL,
    series_id integer NOT NULL,
    timestart timestamp without time zone,
    timeend timestamp without time zone,
    nombre character varying,
    descripcion character varying,
    unit_id integer,
    timeupdate timestamp without time zone DEFAULT now(),
    valor real NOT NULL
);


--
-- Name: observaciones_areal_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.observaciones_areal_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: observaciones_areal_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.observaciones_areal_id_seq OWNED BY public.observaciones_areal.id;


--
-- Name: observaciones_guardadas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.observaciones_guardadas (
    id bigint NOT NULL,
    series_id integer,
    timestart timestamp without time zone,
    timeend timestamp without time zone,
    nombre character varying,
    descripcion character varying,
    unit_id integer,
    timeupdate timestamp without time zone DEFAULT now(),
    valor real NOT NULL
);


--
-- Name: observaciones_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.observaciones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: observaciones_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.observaciones_id_seq OWNED BY public.observaciones.id;


--
-- Name: observaciones_rast_guardadas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.observaciones_rast_guardadas (
    id integer NOT NULL,
    series_id integer NOT NULL,
    timestart timestamp without time zone NOT NULL,
    timeend timestamp without time zone NOT NULL,
    valor public.raster NOT NULL,
    timeupdate timestamp without time zone DEFAULT now() NOT NULL
);


--
-- Name: observaciones_rast_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.observaciones_rast_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: observaciones_rast_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.observaciones_rast_id_seq OWNED BY public.observaciones_rast.id;


--
-- Name: observaciones_tramo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.observaciones_tramo (
    series_id integer NOT NULL,
    timestart timestamp without time zone NOT NULL,
    timeend timestamp without time zone NOT NULL,
    id integer NOT NULL
);


--
-- Name: observaciones_tramo_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.observaciones_tramo_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: observaciones_tramo_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.observaciones_tramo_id_seq OWNED BY public.observaciones_tramo.id;


--
-- Name: parametros; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.parametros (
    id integer NOT NULL,
    model_id integer,
    nombre character varying NOT NULL,
    lim_inf real,
    range_min real NOT NULL,
    range_max real NOT NULL,
    lim_sup real DEFAULT 'Infinity'::real,
    orden integer DEFAULT 1
);


--
-- Name: parametros_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.parametros_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: parametros_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.parametros_id_seq OWNED BY public.parametros.id;


--
-- Name: planes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.planes (
    id integer NOT NULL,
    nombre character varying,
    def_warmup_days integer DEFAULT '-90'::integer,
    def_horiz_days integer DEFAULT 7,
    cal_ids integer[] NOT NULL,
    def_t_offset interval DEFAULT '00:00:00'::interval
);


--
-- Name: planes_corridas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.planes_corridas (
    id integer NOT NULL,
    plan_id integer NOT NULL,
    date timestamp without time zone DEFAULT now() NOT NULL,
    series_n integer DEFAULT 1
);


--
-- Name: planes_corridas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.planes_corridas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: planes_corridas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.planes_corridas_id_seq OWNED BY public.planes_corridas.id;


--
-- Name: planes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.planes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: planes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.planes_id_seq OWNED BY public.planes.id;


--
-- Name: procedimiento_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.procedimiento_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: procedimiento_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.procedimiento_id_seq OWNED BY public.procedimiento.id;


--
-- Name: process_type_waterml2; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.process_type_waterml2 (
    proc_id integer,
    name character varying NOT NULL,
    notation character varying NOT NULL,
    uri character varying NOT NULL
);


--
-- Name: pronosticos_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pronosticos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pronosticos_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pronosticos_id_seq OWNED BY public.pronosticos.id;


--
-- Name: redes_accessors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.redes_accessors (
    id integer NOT NULL,
    tipo character varying NOT NULL,
    tabla_id character varying NOT NULL,
    var_id integer NOT NULL,
    accessor character varying,
    asociacion boolean DEFAULT false,
    CONSTRAINT redes_accessors_check CHECK ((((accessor IS NULL) AND (asociacion = true)) OR ((accessor IS NOT NULL) AND (asociacion = false)))),
    CONSTRAINT redes_accessors_tipo_check CHECK ((((tipo)::text = 'puntual'::text) OR ((tipo)::text = 'areal'::text) OR ((tipo)::text = 'raster'::text)))
);


--
-- Name: redes_accessors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.redes_accessors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: redes_accessors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.redes_accessors_id_seq OWNED BY public.redes_accessors.id;


--
-- Name: redes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.redes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: redes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.redes_id_seq OWNED BY public.redes.id;


--
-- Name: series_areal_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.series_areal_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: series_areal_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.series_areal_id_seq OWNED BY public.series_areal.id;


--
-- Name: series_doy_percentiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.series_doy_percentiles (
    tipo character varying NOT NULL,
    series_id integer NOT NULL,
    doy integer NOT NULL,
    percentil real NOT NULL,
    count integer,
    window_size integer,
    timestart date,
    timeend date,
    valor real NOT NULL,
    CONSTRAINT doy_constraint CHECK (((doy > 0) AND (doy <= 366))),
    CONSTRAINT percentil_constraint CHECK (((percentil > (0)::double precision) AND (percentil <= (1)::double precision) AND (((percentil)::numeric % 0.01) = (0)::numeric))),
    CONSTRAINT tipo_constraint CHECK ((((tipo)::text = 'puntual'::text) OR ((tipo)::text = 'areal'::text) OR ((tipo)::text = 'raster'::text)))
);


--
-- Name: series_doy_stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.series_doy_stats (
    tipo character varying NOT NULL,
    series_id integer NOT NULL,
    doy integer NOT NULL,
    count integer,
    min real,
    max real,
    mean real,
    p01 real,
    p10 real,
    p50 real,
    p90 real,
    p99 real,
    window_size integer,
    timestart date,
    timeend date
);


--
-- Name: series_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.series_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: series_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.series_id_seq OWNED BY public.series.id;


--
-- Name: series_mon_stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.series_mon_stats (
    tipo character varying NOT NULL,
    series_id integer NOT NULL,
    mon integer NOT NULL,
    count integer,
    min real,
    max real,
    mean real,
    p01 real,
    p10 real,
    p50 real,
    p90 real,
    p99 real,
    timestart timestamp without time zone,
    timeend timestamp without time zone
);


--
-- Name: series_rast_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.series_rast_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: series_rast_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.series_rast_id_seq OWNED BY public.series_rast.id;


--
-- Name: series_tramo; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.series_tramo (
    id integer NOT NULL,
    var_id integer NOT NULL,
    unit_id integer NOT NULL,
    proc_id integer NOT NULL,
    tramo_id integer NOT NULL
);


--
-- Name: series_tramo_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.series_tramo_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: series_tramo_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.series_tramo_id_seq OWNED BY public.series_tramo.id;


--
-- Name: tipo_estaciones; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tipo_estaciones (
    tipo character varying(1),
    id integer NOT NULL,
    nombre character varying
);


--
-- Name: tipo_estaciones_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tipo_estaciones_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tipo_estaciones_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tipo_estaciones_id_seq OWNED BY public.tipo_estaciones.id;


--
-- Name: unidades_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.unidades_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: unidades_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.unidades_id_seq OWNED BY public.unidades.id;


--
-- Name: user_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_roles (
    name character varying NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id integer NOT NULL,
    name character varying NOT NULL,
    pass_enc bytea,
    role character varying,
    password character varying,
    token bytea,
    protected boolean DEFAULT false
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: valores_tramo_num; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.valores_tramo_num (
    obs_id integer NOT NULL,
    valor real NOT NULL
);


--
-- Name: var_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.var_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: var_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.var_id_seq OWNED BY public.var.id;


--
-- Name: areas_pluvio unid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.areas_pluvio ALTER COLUMN unid SET DEFAULT nextval('public.areas_pluvio_unid_seq'::regclass);


--
-- Name: asociaciones id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asociaciones ALTER COLUMN id SET DEFAULT nextval('public.asociaciones_id_seq'::regclass);


--
-- Name: cal_estados id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cal_estados ALTER COLUMN id SET DEFAULT nextval('public.cal_estados_id_seq'::regclass);


--
-- Name: cal_out id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cal_out ALTER COLUMN id SET DEFAULT nextval('public.cal_out_id_seq'::regclass);


--
-- Name: cal_pars id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cal_pars ALTER COLUMN id SET DEFAULT nextval('public.cal_pars_id_seq'::regclass);


--
-- Name: cal_stats id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cal_stats ALTER COLUMN id SET DEFAULT nextval('public.cal_stats_id_seq'::regclass);


--
-- Name: calibrados id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calibrados ALTER COLUMN id SET DEFAULT nextval('public.calibrados_id_seq'::regclass);


--
-- Name: calibrados_grupos id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calibrados_grupos ALTER COLUMN id SET DEFAULT nextval('public.calibrados_grupos_id_seq'::regclass);


--
-- Name: calibrados_out id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calibrados_out ALTER COLUMN id SET DEFAULT nextval('public.calibrados_out_id_seq'::regclass);


--
-- Name: calibrados_series_out id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calibrados_series_out ALTER COLUMN id SET DEFAULT nextval('public.calibrados_series_out_id_seq'::regclass);


--
-- Name: corridas id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.corridas ALTER COLUMN id SET DEFAULT nextval('public.corridas_id_seq'::regclass);


--
-- Name: datatypes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.datatypes ALTER COLUMN id SET DEFAULT nextval('public.datatypes_id_seq'::regclass);


--
-- Name: escenas id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escenas ALTER COLUMN id SET DEFAULT nextval('public.escenas_id_seq'::regclass);


--
-- Name: estaciones unid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estaciones ALTER COLUMN unid SET DEFAULT nextval('public.estaciones_unid_seq'::regclass);


--
-- Name: estados id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estados ALTER COLUMN id SET DEFAULT nextval('public.estados_id_seq'::regclass);


--
-- Name: extra_pars id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.extra_pars ALTER COLUMN id SET DEFAULT nextval('public.extra_pars_id_seq'::regclass);


--
-- Name: forzantes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forzantes ALTER COLUMN id SET DEFAULT nextval('public.forzantes_id_seq'::regclass);


--
-- Name: fuentes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fuentes ALTER COLUMN id SET DEFAULT nextval('public.fuentes_id_seq'::regclass);


--
-- Name: modelos id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modelos ALTER COLUMN id SET DEFAULT nextval('public.modelos_id_seq'::regclass);


--
-- Name: modelos_forzantes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modelos_forzantes ALTER COLUMN id SET DEFAULT nextval('public.modelos_forzantes_id_seq'::regclass);


--
-- Name: modelos_out id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modelos_out ALTER COLUMN id SET DEFAULT nextval('public.modelos_out_id_seq'::regclass);


--
-- Name: observaciones id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones ALTER COLUMN id SET DEFAULT nextval('public.observaciones_id_seq'::regclass);


--
-- Name: observaciones_areal id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_areal ALTER COLUMN id SET DEFAULT nextval('public.observaciones_areal_id_seq'::regclass);


--
-- Name: observaciones_rast id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_rast ALTER COLUMN id SET DEFAULT nextval('public.observaciones_rast_id_seq'::regclass);


--
-- Name: observaciones_tramo id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_tramo ALTER COLUMN id SET DEFAULT nextval('public.observaciones_tramo_id_seq'::regclass);


--
-- Name: parametros id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.parametros ALTER COLUMN id SET DEFAULT nextval('public.parametros_id_seq'::regclass);


--
-- Name: planes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planes ALTER COLUMN id SET DEFAULT nextval('public.planes_id_seq'::regclass);


--
-- Name: planes_corridas id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planes_corridas ALTER COLUMN id SET DEFAULT nextval('public.planes_corridas_id_seq'::regclass);


--
-- Name: procedimiento id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.procedimiento ALTER COLUMN id SET DEFAULT nextval('public.procedimiento_id_seq'::regclass);


--
-- Name: pronosticos id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pronosticos ALTER COLUMN id SET DEFAULT nextval('public.pronosticos_id_seq'::regclass);


--
-- Name: redes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.redes ALTER COLUMN id SET DEFAULT nextval('public.redes_id_seq'::regclass);


--
-- Name: redes_accessors id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.redes_accessors ALTER COLUMN id SET DEFAULT nextval('public.redes_accessors_id_seq'::regclass);


--
-- Name: series id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series ALTER COLUMN id SET DEFAULT nextval('public.series_id_seq'::regclass);


--
-- Name: series_areal id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_areal ALTER COLUMN id SET DEFAULT nextval('public.series_areal_id_seq'::regclass);


--
-- Name: series_rast id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_rast ALTER COLUMN id SET DEFAULT nextval('public.series_rast_id_seq'::regclass);


--
-- Name: series_tramo id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_tramo ALTER COLUMN id SET DEFAULT nextval('public.series_tramo_id_seq'::regclass);


--
-- Name: tipo_estaciones id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipo_estaciones ALTER COLUMN id SET DEFAULT nextval('public.tipo_estaciones_id_seq'::regclass);


--
-- Name: unidades id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unidades ALTER COLUMN id SET DEFAULT nextval('public.unidades_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: var id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.var ALTER COLUMN id SET DEFAULT nextval('public.var_id_seq'::regclass);


--
-- Name: accessors accessors_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.accessors
    ADD CONSTRAINT accessors_name_key UNIQUE (name);


--
-- Name: alturas_alerta alturas_alerta_unid_estado_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alturas_alerta
    ADD CONSTRAINT alturas_alerta_unid_estado_key UNIQUE (unid, estado);


--
-- Name: alturas_alerta alturas_alerta_unid_valor_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alturas_alerta
    ADD CONSTRAINT alturas_alerta_unid_valor_key UNIQUE (unid, valor);


--
-- Name: areas_pluvio areas_pluvio_unid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.areas_pluvio
    ADD CONSTRAINT areas_pluvio_unid_key UNIQUE (unid);


--
-- Name: asociaciones asociaciones_dest_tipo_dest_series_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asociaciones
    ADD CONSTRAINT asociaciones_dest_tipo_dest_series_id_key UNIQUE (dest_tipo, dest_series_id);


--
-- Name: asociaciones asociaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asociaciones
    ADD CONSTRAINT asociaciones_pkey PRIMARY KEY (id);


--
-- Name: asociaciones asociaciones_source_tipo_source_series_id_dest_tipo_dest_se_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asociaciones
    ADD CONSTRAINT asociaciones_source_tipo_source_series_id_dest_tipo_dest_se_key UNIQUE (source_tipo, source_series_id, dest_tipo, dest_series_id, dt, t_offset, agg_func);


--
-- Name: cal_estados cal_estados_cal_id_orden_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cal_estados
    ADD CONSTRAINT cal_estados_cal_id_orden_key UNIQUE (cal_id, orden);


--
-- Name: cal_out cal_out_cal_id_orden_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cal_out
    ADD CONSTRAINT cal_out_cal_id_orden_key UNIQUE (cal_id, orden);


--
-- Name: cal_out cal_out_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cal_out
    ADD CONSTRAINT cal_out_pkey PRIMARY KEY (id);


--
-- Name: cal_pars cal_pars_cal_id_orden_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cal_pars
    ADD CONSTRAINT cal_pars_cal_id_orden_key UNIQUE (cal_id, orden);


--
-- Name: cal_stats cal_stats_cal_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cal_stats
    ADD CONSTRAINT cal_stats_cal_id_key UNIQUE (cal_id);


--
-- Name: calibrados_grupos calibrados_grupos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calibrados_grupos
    ADD CONSTRAINT calibrados_grupos_pkey PRIMARY KEY (id);


--
-- Name: calibrados_out calibrados_out_cal_id_out_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calibrados_out
    ADD CONSTRAINT calibrados_out_cal_id_out_id_key UNIQUE (cal_id, out_id);


--
-- Name: calibrados_out calibrados_out_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calibrados_out
    ADD CONSTRAINT calibrados_out_pkey PRIMARY KEY (id);


--
-- Name: calibrados calibrados_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calibrados
    ADD CONSTRAINT calibrados_pkey PRIMARY KEY (id);


--
-- Name: calibrados_series_out calibrados_series_out_cal_id_series_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calibrados_series_out
    ADD CONSTRAINT calibrados_series_out_cal_id_series_id_key UNIQUE (cal_id, series_id);


--
-- Name: calibrados_series_out calibrados_series_out_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calibrados_series_out
    ADD CONSTRAINT calibrados_series_out_pkey PRIMARY KEY (id);


--
-- Name: corridas corridas_cal_id_date_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.corridas
    ADD CONSTRAINT corridas_cal_id_date_key UNIQUE (cal_id, date);


--
-- Name: corridas_data corridas_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.corridas_data
    ADD CONSTRAINT corridas_data_pkey PRIMARY KEY (cor_id);


--
-- Name: corridas_guardadas corridas_guardadas_cal_id_date_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.corridas_guardadas
    ADD CONSTRAINT corridas_guardadas_cal_id_date_key UNIQUE (cal_id, date);


--
-- Name: corridas_guardadas corridas_guardadas_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.corridas_guardadas
    ADD CONSTRAINT corridas_guardadas_id_key UNIQUE (id);


--
-- Name: corridas corridas_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.corridas
    ADD CONSTRAINT corridas_id_key UNIQUE (id);


--
-- Name: cuantiles cuantiles_escala_id_doy_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cuantiles
    ADD CONSTRAINT cuantiles_escala_id_doy_key UNIQUE (escala_id, doy);


--
-- Name: cuantiles_mensuales cuantiles_mensuales_escala_id_month_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cuantiles_mensuales
    ADD CONSTRAINT cuantiles_mensuales_escala_id_month_key UNIQUE (escala_id, month);


--
-- Name: cuantiles_suave cuantiles_suave_escala_id_doy_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cuantiles_suave
    ADD CONSTRAINT cuantiles_suave_escala_id_doy_key UNIQUE (escala_id, doy);


--
-- Name: datatypes datatypes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.datatypes
    ADD CONSTRAINT datatypes_pkey PRIMARY KEY (id);


--
-- Name: datatypes datatypes_term_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.datatypes
    ADD CONSTRAINT datatypes_term_key UNIQUE (term);


--
-- Name: escenas escenas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.escenas
    ADD CONSTRAINT escenas_pkey PRIMARY KEY (id);


--
-- Name: estaciones estaciones_id_externo_tabla_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estaciones
    ADD CONSTRAINT estaciones_id_externo_tabla_key UNIQUE (id_externo, tabla);


--
-- Name: estaciones estaciones_id_tabla_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estaciones
    ADD CONSTRAINT estaciones_id_tabla_key UNIQUE (id, tabla);


--
-- Name: estaciones estaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estaciones
    ADD CONSTRAINT estaciones_pkey PRIMARY KEY (unid);


--
-- Name: estados estados_model_id_orden_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estados
    ADD CONSTRAINT estados_model_id_orden_key UNIQUE (model_id, orden);


--
-- Name: extra_pars extra_pars_cal_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.extra_pars
    ADD CONSTRAINT extra_pars_cal_id_key UNIQUE (cal_id);


--
-- Name: forzantes forzantes_cal_id_orden_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forzantes
    ADD CONSTRAINT forzantes_cal_id_orden_key UNIQUE (cal_id, orden);


--
-- Name: forzantes forzantes_cal_id_series_table_series_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forzantes
    ADD CONSTRAINT forzantes_cal_id_series_table_series_id_key UNIQUE (cal_id, series_table, series_id);


--
-- Name: fuentes fuentes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fuentes
    ADD CONSTRAINT fuentes_pkey PRIMARY KEY (id);


--
-- Name: h_q h_q_unid_activar_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.h_q
    ADD CONSTRAINT h_q_unid_activar_key UNIQUE (unid, activar);


--
-- Name: modelos_forzantes modelos_forzantes_model_id_nombre_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modelos_forzantes
    ADD CONSTRAINT modelos_forzantes_model_id_nombre_key UNIQUE (model_id, nombre);


--
-- Name: modelos_forzantes modelos_forzantes_model_id_orden_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modelos_forzantes
    ADD CONSTRAINT modelos_forzantes_model_id_orden_key UNIQUE (model_id, orden);


--
-- Name: modelos modelos_nombre_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modelos
    ADD CONSTRAINT modelos_nombre_key UNIQUE (nombre);


--
-- Name: modelos_out modelos_out_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modelos_out
    ADD CONSTRAINT modelos_out_pkey PRIMARY KEY (model_id, orden);


--
-- Name: modelos modelos_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modelos
    ADD CONSTRAINT modelos_pkey PRIMARY KEY (id);


--
-- Name: observaciones_areal_guardadas observaciones_areal_guardadas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_areal_guardadas
    ADD CONSTRAINT observaciones_areal_guardadas_pkey PRIMARY KEY (id);


--
-- Name: observaciones_areal_guardadas observaciones_areal_guardadas_series_id_timestart_timeend_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_areal_guardadas
    ADD CONSTRAINT observaciones_areal_guardadas_series_id_timestart_timeend_key UNIQUE (series_id, timestart, timeend);


--
-- Name: observaciones_areal observaciones_areal_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_areal
    ADD CONSTRAINT observaciones_areal_pkey PRIMARY KEY (id);


--
-- Name: observaciones_areal observaciones_areal_series_id_timestart_timeend_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_areal
    ADD CONSTRAINT observaciones_areal_series_id_timestart_timeend_key UNIQUE (series_id, timestart, timeend);


--
-- Name: observaciones_guardadas observaciones_guardadas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_guardadas
    ADD CONSTRAINT observaciones_guardadas_pkey PRIMARY KEY (id);


--
-- Name: observaciones_guardadas observaciones_guardadas_series_id_timestart_timeend_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_guardadas
    ADD CONSTRAINT observaciones_guardadas_series_id_timestart_timeend_key UNIQUE (series_id, timestart, timeend);


--
-- Name: observaciones observaciones_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones
    ADD CONSTRAINT observaciones_pkey PRIMARY KEY (id);


--
-- Name: observaciones_rast_guardadas observaciones_rast_guardadas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_rast_guardadas
    ADD CONSTRAINT observaciones_rast_guardadas_pkey PRIMARY KEY (id);


--
-- Name: observaciones_rast_guardadas observaciones_rast_guardadas_series_id_timestart_timeend_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_rast_guardadas
    ADD CONSTRAINT observaciones_rast_guardadas_series_id_timestart_timeend_key UNIQUE (series_id, timestart, timeend);


--
-- Name: observaciones_rast observaciones_rast_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_rast
    ADD CONSTRAINT observaciones_rast_pkey PRIMARY KEY (id);


--
-- Name: observaciones_rast observaciones_rast_series_id_timestart_timeend_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_rast
    ADD CONSTRAINT observaciones_rast_series_id_timestart_timeend_key UNIQUE (series_id, timestart, timeend);


--
-- Name: observaciones observaciones_series_id_timestart_timeend_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones
    ADD CONSTRAINT observaciones_series_id_timestart_timeend_key UNIQUE (series_id, timestart, timeend);


--
-- Name: observaciones_tramo observaciones_tramo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_tramo
    ADD CONSTRAINT observaciones_tramo_pkey PRIMARY KEY (id);


--
-- Name: parametros parametros_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.parametros
    ADD CONSTRAINT parametros_id_key UNIQUE (id);


--
-- Name: parametros parametros_model_id_orden_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.parametros
    ADD CONSTRAINT parametros_model_id_orden_key UNIQUE (model_id, orden);


--
-- Name: planes_corridas planes_corridas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planes_corridas
    ADD CONSTRAINT planes_corridas_pkey PRIMARY KEY (id);


--
-- Name: planes_corridas planes_corridas_plan_id_date_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planes_corridas
    ADD CONSTRAINT planes_corridas_plan_id_date_key UNIQUE (plan_id, date);


--
-- Name: planes planes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planes
    ADD CONSTRAINT planes_pkey PRIMARY KEY (id);


--
-- Name: procedimiento procedimiento_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.procedimiento
    ADD CONSTRAINT procedimiento_pkey PRIMARY KEY (id);


--
-- Name: process_type_waterml2 process_type_waterml2_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.process_type_waterml2
    ADD CONSTRAINT process_type_waterml2_pkey PRIMARY KEY (uri);


--
-- Name: pronosticos pronosticos_cor_id_series_id_timestart_timeend_qualifier_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pronosticos
    ADD CONSTRAINT pronosticos_cor_id_series_id_timestart_timeend_qualifier_key UNIQUE (cor_id, series_id, timestart, timeend, qualifier);


--
-- Name: pronosticos_guardados pronosticos_guardados_cor_id_series_id_timestart_timeend_qu_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pronosticos_guardados
    ADD CONSTRAINT pronosticos_guardados_cor_id_series_id_timestart_timeend_qu_key UNIQUE (cor_id, series_id, timestart, timeend, qualifier);


--
-- Name: pronosticos_guardados pronosticos_guardados_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pronosticos_guardados
    ADD CONSTRAINT pronosticos_guardados_id_key UNIQUE (id);


--
-- Name: pronosticos pronosticos_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pronosticos
    ADD CONSTRAINT pronosticos_id_key UNIQUE (id);


--
-- Name: redes_accessors redes_accessors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.redes_accessors
    ADD CONSTRAINT redes_accessors_pkey PRIMARY KEY (id);


--
-- Name: redes_accessors redes_accessors_tipo_tabla_id_var_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.redes_accessors
    ADD CONSTRAINT redes_accessors_tipo_tabla_id_var_id_key UNIQUE (tipo, tabla_id, var_id);


--
-- Name: redes redes_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.redes
    ADD CONSTRAINT redes_id_key UNIQUE (id);


--
-- Name: redes redes_tabla_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.redes
    ADD CONSTRAINT redes_tabla_id_key UNIQUE (tabla_id);


--
-- Name: series_areal series_areal_fuentes_id_proc_id_unit_id_var_id_area_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_areal
    ADD CONSTRAINT series_areal_fuentes_id_proc_id_unit_id_var_id_area_id_key UNIQUE (fuentes_id, proc_id, unit_id, var_id, area_id);


--
-- Name: series_areal series_areal_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_areal
    ADD CONSTRAINT series_areal_id_key UNIQUE (id);


--
-- Name: series_doy_percentiles series_doy_percentiles_tipo_series_id_doy_percentil_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_doy_percentiles
    ADD CONSTRAINT series_doy_percentiles_tipo_series_id_doy_percentil_key UNIQUE (tipo, series_id, doy, percentil);


--
-- Name: series_doy_stats series_doy_stats_tipo_series_id_doy_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_doy_stats
    ADD CONSTRAINT series_doy_stats_tipo_series_id_doy_key UNIQUE (tipo, series_id, doy);


--
-- Name: series series_estacion_id_var_id_proc_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series
    ADD CONSTRAINT series_estacion_id_var_id_proc_id_key UNIQUE (estacion_id, var_id, proc_id);


--
-- Name: series_mon_stats series_mon_stats_tipo_series_id_mon_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_mon_stats
    ADD CONSTRAINT series_mon_stats_tipo_series_id_mon_key UNIQUE (tipo, series_id, mon);


--
-- Name: series series_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series
    ADD CONSTRAINT series_pkey PRIMARY KEY (id);


--
-- Name: series_rast series_rast_escena_id_fuentes_id_var_id_proc_id_unit_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_rast
    ADD CONSTRAINT series_rast_escena_id_fuentes_id_var_id_proc_id_unit_id_key UNIQUE (escena_id, fuentes_id, var_id, proc_id, unit_id);


--
-- Name: series_rast series_rast_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_rast
    ADD CONSTRAINT series_rast_pkey PRIMARY KEY (id);


--
-- Name: series_tramo series_tramo_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_tramo
    ADD CONSTRAINT series_tramo_pkey PRIMARY KEY (id);


--
-- Name: tipo_estaciones tipo_estaciones_tipo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tipo_estaciones
    ADD CONSTRAINT tipo_estaciones_tipo_key UNIQUE (tipo);


--
-- Name: tramos tramos_unid_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tramos
    ADD CONSTRAINT tramos_unid_key UNIQUE (unid);


--
-- Name: unidades unidades_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.unidades
    ADD CONSTRAINT unidades_pkey PRIMARY KEY (id);


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (name);


--
-- Name: users users_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_id_key UNIQUE (id);


--
-- Name: users users_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_name_key UNIQUE (name);


--
-- Name: valores_num_areal valores_num_areal_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.valores_num_areal
    ADD CONSTRAINT valores_num_areal_pkey PRIMARY KEY (obs_id);


--
-- Name: valores_num valores_num_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.valores_num
    ADD CONSTRAINT valores_num_pkey PRIMARY KEY (obs_id);


--
-- Name: valores_numarr_areal valores_numarr_areal_obs_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.valores_numarr_areal
    ADD CONSTRAINT valores_numarr_areal_obs_id_key UNIQUE (obs_id);


--
-- Name: valores_numarr valores_numarr_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.valores_numarr
    ADD CONSTRAINT valores_numarr_pkey PRIMARY KEY (obs_id);


--
-- Name: valores_prono_num_guardados valores_prono_num_guardados_prono_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.valores_prono_num_guardados
    ADD CONSTRAINT valores_prono_num_guardados_prono_id_key UNIQUE (prono_id);


--
-- Name: valores_prono_num valores_prono_num_prono_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.valores_prono_num
    ADD CONSTRAINT valores_prono_num_prono_id_key UNIQUE (prono_id);


--
-- Name: var var_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.var
    ADD CONSTRAINT var_pkey PRIMARY KEY (id);


--
-- Name: var var_var_GeneralCategory_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.var
    ADD CONSTRAINT "var_var_GeneralCategory_key" UNIQUE (var, "GeneralCategory");


--
-- Name: sidx_estaciones_geom; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sidx_estaciones_geom ON public.estaciones USING gist (geom);


--
-- Name: cal_pars apars_get_mid; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER apars_get_mid BEFORE INSERT ON public.cal_pars FOR EACH ROW EXECUTE PROCEDURE public.get_model_id();


--
-- Name: areas_pluvio area_pluvio_calc; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER area_pluvio_calc BEFORE INSERT ON public.areas_pluvio FOR EACH ROW EXECUTE PROCEDURE public.area_calc();


--
-- Name: cal_pars check_par_lims; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER check_par_lims BEFORE INSERT ON public.cal_pars FOR EACH ROW EXECUTE PROCEDURE public.check_par_lims();


--
-- Name: cal_estados est_get_mid; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER est_get_mid BEFORE INSERT ON public.cal_estados FOR EACH ROW EXECUTE PROCEDURE public.get_model_id();


--
-- Name: estados est_ord; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER est_ord BEFORE INSERT ON public.estados FOR EACH ROW EXECUTE PROCEDURE public.orden_model_forz();


--
-- Name: estaciones estacion_id_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER estacion_id_trigger BEFORE INSERT OR UPDATE ON public.estaciones FOR EACH ROW EXECUTE PROCEDURE public.estacion_id_trigger();


--
-- Name: extra_pars extrapars_get_model_id; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER extrapars_get_model_id BEFORE INSERT ON public.extra_pars FOR EACH ROW EXECUTE PROCEDURE public.get_model_id();


--
-- Name: cal_out get_mid; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER get_mid BEFORE INSERT ON public.cal_out FOR EACH ROW EXECUTE PROCEDURE public.get_model_id();


--
-- Name: forzantes get_mid; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER get_mid BEFORE INSERT ON public.forzantes FOR EACH ROW EXECUTE PROCEDURE public.get_model_id();


--
-- Name: cal_stats get_model_id_calstats; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER get_model_id_calstats BEFORE INSERT ON public.cal_stats FOR EACH ROW EXECUTE PROCEDURE public.get_model_id();


--
-- Name: observaciones_areal hora_corte_trig; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER hora_corte_trig BEFORE INSERT ON public.observaciones_areal FOR EACH ROW EXECUTE PROCEDURE public.obs_hora_corte_constraint_trigger();


--
-- Name: modelos_forzantes mod_forz_ord; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER mod_forz_ord BEFORE INSERT ON public.modelos_forzantes FOR EACH ROW EXECUTE PROCEDURE public.orden_model_forz();


--
-- Name: observaciones_areal obs_dt_trig; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER obs_dt_trig BEFORE INSERT ON public.observaciones_areal FOR EACH ROW EXECUTE PROCEDURE public.obs_dt_constraint_trigger();


--
-- Name: observaciones obs_puntual_dt_constraint_trigger; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER obs_puntual_dt_constraint_trigger BEFORE INSERT OR UPDATE ON public.observaciones FOR EACH ROW EXECUTE PROCEDURE public.obs_puntual_dt_constraint_trigger();


--
-- Name: observaciones_areal obs_range_tr; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER obs_range_tr BEFORE INSERT ON public.observaciones_areal FOR EACH ROW EXECUTE PROCEDURE public.obs_range_constraint_trigger();

ALTER TABLE public.observaciones_areal DISABLE TRIGGER obs_range_tr;


--
-- Name: parametros par_ord; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER par_ord BEFORE INSERT ON public.parametros FOR EACH ROW EXECUTE PROCEDURE public.orden_model_forz();


--
-- Name: alturas_alerta alturas_alerta_unid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.alturas_alerta
    ADD CONSTRAINT alturas_alerta_unid_fkey FOREIGN KEY (unid) REFERENCES public.estaciones(unid);


--
-- Name: areas_pluvio areas_pluvio_exutorio_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.areas_pluvio
    ADD CONSTRAINT areas_pluvio_exutorio_id_fkey FOREIGN KEY (exutorio_id) REFERENCES public.estaciones(unid);


--
-- Name: cal_estados cal_estados_cal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cal_estados
    ADD CONSTRAINT cal_estados_cal_id_fkey FOREIGN KEY (cal_id) REFERENCES public.calibrados(id);


--
-- Name: cal_estados cal_estados_model_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cal_estados
    ADD CONSTRAINT cal_estados_model_id_fkey FOREIGN KEY (model_id, orden) REFERENCES public.estados(model_id, orden);


--
-- Name: cal_out cal_out_cal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cal_out
    ADD CONSTRAINT cal_out_cal_id_fkey FOREIGN KEY (cal_id) REFERENCES public.calibrados(id) ON DELETE CASCADE;


--
-- Name: cal_out cal_out_model_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cal_out
    ADD CONSTRAINT cal_out_model_id_fkey FOREIGN KEY (model_id) REFERENCES public.modelos(id);


--
-- Name: cal_out cal_out_modelos_out_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cal_out
    ADD CONSTRAINT cal_out_modelos_out_fkey FOREIGN KEY (model_id, orden) REFERENCES public.modelos_out(model_id, orden);


--
-- Name: cal_pars cal_pars_cal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cal_pars
    ADD CONSTRAINT cal_pars_cal_id_fkey FOREIGN KEY (cal_id) REFERENCES public.calibrados(id);


--
-- Name: cal_pars cal_pars_model_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cal_pars
    ADD CONSTRAINT cal_pars_model_id_fkey FOREIGN KEY (model_id, orden) REFERENCES public.parametros(model_id, orden);


--
-- Name: cal_stats cal_stats_cal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cal_stats
    ADD CONSTRAINT cal_stats_cal_id_fkey FOREIGN KEY (cal_id) REFERENCES public.calibrados(id);


--
-- Name: cal_stats cal_stats_model_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cal_stats
    ADD CONSTRAINT cal_stats_model_id_fkey FOREIGN KEY (model_id) REFERENCES public.modelos(id);


--
-- Name: calibrados calibrados_area_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calibrados
    ADD CONSTRAINT calibrados_area_id_fkey FOREIGN KEY (area_id) REFERENCES public.areas_pluvio(unid);


--
-- Name: calibrados calibrados_grupo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calibrados
    ADD CONSTRAINT calibrados_grupo_id_fkey FOREIGN KEY (grupo_id) REFERENCES public.calibrados_grupos(id);


--
-- Name: calibrados calibrados_model_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calibrados
    ADD CONSTRAINT calibrados_model_id_fkey FOREIGN KEY (model_id) REFERENCES public.modelos(id);


--
-- Name: calibrados_out calibrados_out_cal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calibrados_out
    ADD CONSTRAINT calibrados_out_cal_id_fkey FOREIGN KEY (cal_id) REFERENCES public.calibrados(id) ON DELETE CASCADE;


--
-- Name: calibrados calibrados_out_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calibrados
    ADD CONSTRAINT calibrados_out_id_fkey FOREIGN KEY (out_id) REFERENCES public.estaciones(unid);


--
-- Name: calibrados_out calibrados_out_out_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calibrados_out
    ADD CONSTRAINT calibrados_out_out_id_fkey FOREIGN KEY (out_id) REFERENCES public.estaciones(unid);


--
-- Name: calibrados_series_out calibrados_series_out_cal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calibrados_series_out
    ADD CONSTRAINT calibrados_series_out_cal_id_fkey FOREIGN KEY (cal_id) REFERENCES public.calibrados(id);


--
-- Name: calibrados_series_out calibrados_series_out_series_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calibrados_series_out
    ADD CONSTRAINT calibrados_series_out_series_id_fkey FOREIGN KEY (series_id) REFERENCES public.series(id);


--
-- Name: calibrados calibrados_tramo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calibrados
    ADD CONSTRAINT calibrados_tramo_id_fkey FOREIGN KEY (tramo_id) REFERENCES public.tramos(unid);


--
-- Name: corridas corridas_cal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.corridas
    ADD CONSTRAINT corridas_cal_id_fkey FOREIGN KEY (cal_id) REFERENCES public.calibrados(id);


--
-- Name: corridas_data corridas_data_cor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.corridas_data
    ADD CONSTRAINT corridas_data_cor_id_fkey FOREIGN KEY (cor_id) REFERENCES public.corridas(id);


--
-- Name: corridas_guardadas corridas_guardadas_cal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.corridas_guardadas
    ADD CONSTRAINT corridas_guardadas_cal_id_fkey FOREIGN KEY (cal_id) REFERENCES public.calibrados(id);


--
-- Name: corridas_guardadas corridas_guardadas_plan_cor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.corridas_guardadas
    ADD CONSTRAINT corridas_guardadas_plan_cor_id_fkey FOREIGN KEY (plan_cor_id) REFERENCES public.planes_corridas(id);


--
-- Name: corridas corridas_plan_cor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.corridas
    ADD CONSTRAINT corridas_plan_cor_id_fkey FOREIGN KEY (plan_cor_id) REFERENCES public.planes_corridas(id);


--
-- Name: cuantiles_mensuales cuantiles_mensuales_unid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cuantiles_mensuales
    ADD CONSTRAINT cuantiles_mensuales_unid_fkey FOREIGN KEY (unid) REFERENCES public.estaciones(unid);


--
-- Name: cuantiles cuantiles_unid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cuantiles
    ADD CONSTRAINT cuantiles_unid_fkey FOREIGN KEY (unid) REFERENCES public.estaciones(unid);


--
-- Name: estaciones estaciones_tabla_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estaciones
    ADD CONSTRAINT estaciones_tabla_fkey FOREIGN KEY (tabla) REFERENCES public.redes(tabla_id);


--
-- Name: estados estados_model_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estados
    ADD CONSTRAINT estados_model_id_fkey FOREIGN KEY (model_id) REFERENCES public.modelos(id);


--
-- Name: extra_pars extra_pars_cal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.extra_pars
    ADD CONSTRAINT extra_pars_cal_id_fkey FOREIGN KEY (cal_id) REFERENCES public.calibrados(id);


--
-- Name: extra_pars extra_pars_model_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.extra_pars
    ADD CONSTRAINT extra_pars_model_id_fkey FOREIGN KEY (model_id) REFERENCES public.modelos(id);


--
-- Name: forzantes forzantes_cal_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forzantes
    ADD CONSTRAINT forzantes_cal_id_fkey FOREIGN KEY (cal_id) REFERENCES public.calibrados(id);


--
-- Name: forzantes forzantes_model_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.forzantes
    ADD CONSTRAINT forzantes_model_id_fkey FOREIGN KEY (model_id, orden) REFERENCES public.modelos_forzantes(model_id, orden);


--
-- Name: fuentes fuentes_def_proc_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fuentes
    ADD CONSTRAINT fuentes_def_proc_id_fkey FOREIGN KEY (def_proc_id) REFERENCES public.procedimiento(id);


--
-- Name: fuentes fuentes_def_srid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fuentes
    ADD CONSTRAINT fuentes_def_srid_fkey FOREIGN KEY (def_srid) REFERENCES public.spatial_ref_sys(srid);


--
-- Name: fuentes fuentes_def_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fuentes
    ADD CONSTRAINT fuentes_def_unit_id_fkey FOREIGN KEY (def_unit_id) REFERENCES public.unidades(id);


--
-- Name: fuentes fuentes_def_var_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fuentes
    ADD CONSTRAINT fuentes_def_var_id_fkey FOREIGN KEY (def_var_id) REFERENCES public.var(id);


--
-- Name: modelos modelos_def_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modelos
    ADD CONSTRAINT modelos_def_unit_id_fkey FOREIGN KEY (def_unit_id) REFERENCES public.unidades(id);


--
-- Name: modelos modelos_def_var_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modelos
    ADD CONSTRAINT modelos_def_var_id_fkey FOREIGN KEY (def_var_id) REFERENCES public.var(id);


--
-- Name: modelos_forzantes modelos_forzantes_model_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modelos_forzantes
    ADD CONSTRAINT modelos_forzantes_model_id_fkey FOREIGN KEY (model_id) REFERENCES public.modelos(id);


--
-- Name: modelos_forzantes modelos_forzantes_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modelos_forzantes
    ADD CONSTRAINT modelos_forzantes_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.unidades(id);


--
-- Name: modelos_forzantes modelos_forzantes_var_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modelos_forzantes
    ADD CONSTRAINT modelos_forzantes_var_id_fkey FOREIGN KEY (var_id) REFERENCES public.var(id);


--
-- Name: modelos_out modelos_out_model_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modelos_out
    ADD CONSTRAINT modelos_out_model_id_fkey FOREIGN KEY (model_id) REFERENCES public.modelos(id);


--
-- Name: modelos_out modelos_out_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modelos_out
    ADD CONSTRAINT modelos_out_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.unidades(id);


--
-- Name: modelos_out modelos_out_var_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modelos_out
    ADD CONSTRAINT modelos_out_var_id_fkey FOREIGN KEY (var_id) REFERENCES public.var(id);


--
-- Name: observaciones_areal_guardadas observaciones_areal_guardadas_series_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_areal_guardadas
    ADD CONSTRAINT observaciones_areal_guardadas_series_id_fkey FOREIGN KEY (series_id) REFERENCES public.series_areal(id);


--
-- Name: observaciones_areal_guardadas observaciones_areal_guardadas_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_areal_guardadas
    ADD CONSTRAINT observaciones_areal_guardadas_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.unidades(id);


--
-- Name: observaciones_areal observaciones_areal_series_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_areal
    ADD CONSTRAINT observaciones_areal_series_id_fkey FOREIGN KEY (series_id) REFERENCES public.series_areal(id);


--
-- Name: observaciones_areal observaciones_areal_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_areal
    ADD CONSTRAINT observaciones_areal_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.unidades(id);


--
-- Name: observaciones_guardadas observaciones_guardadas_series_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_guardadas
    ADD CONSTRAINT observaciones_guardadas_series_id_fkey FOREIGN KEY (series_id) REFERENCES public.series(id) ON DELETE CASCADE;


--
-- Name: observaciones_guardadas observaciones_guardadas_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_guardadas
    ADD CONSTRAINT observaciones_guardadas_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.unidades(id);


--
-- Name: observaciones_rast_guardadas observaciones_rast_guardadas_series_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_rast_guardadas
    ADD CONSTRAINT observaciones_rast_guardadas_series_id_fkey FOREIGN KEY (series_id) REFERENCES public.series_rast(id);


--
-- Name: observaciones_rast observaciones_rast_series_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_rast
    ADD CONSTRAINT observaciones_rast_series_id_fkey FOREIGN KEY (series_id) REFERENCES public.series_rast(id);


--
-- Name: observaciones observaciones_series_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones
    ADD CONSTRAINT observaciones_series_id_fkey FOREIGN KEY (series_id) REFERENCES public.series(id) ON DELETE CASCADE;


--
-- Name: observaciones_tramo observaciones_tramo_series_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones_tramo
    ADD CONSTRAINT observaciones_tramo_series_id_fkey FOREIGN KEY (series_id) REFERENCES public.series_tramo(id);


--
-- Name: observaciones observaciones_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.observaciones
    ADD CONSTRAINT observaciones_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.unidades(id);


--
-- Name: parametros parametros_model_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.parametros
    ADD CONSTRAINT parametros_model_id_fkey FOREIGN KEY (model_id) REFERENCES public.modelos(id);


--
-- Name: planes_corridas planes_corridas_plan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planes_corridas
    ADD CONSTRAINT planes_corridas_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES public.planes(id);


--
-- Name: process_type_waterml2 process_type_waterml2_proc_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.process_type_waterml2
    ADD CONSTRAINT process_type_waterml2_proc_id_fkey FOREIGN KEY (proc_id) REFERENCES public.procedimiento(id);


--
-- Name: pronosticos pronosticos_cor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pronosticos
    ADD CONSTRAINT pronosticos_cor_id_fkey FOREIGN KEY (cor_id) REFERENCES public.corridas(id);


--
-- Name: pronosticos_guardados pronosticos_guardados_cor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pronosticos_guardados
    ADD CONSTRAINT pronosticos_guardados_cor_id_fkey FOREIGN KEY (cor_id) REFERENCES public.corridas_guardadas(id) ON DELETE CASCADE;


--
-- Name: pronosticos_guardados pronosticos_guardados_series_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pronosticos_guardados
    ADD CONSTRAINT pronosticos_guardados_series_id_fkey FOREIGN KEY (series_id) REFERENCES public.series(id);


--
-- Name: pronosticos pronosticos_series_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pronosticos
    ADD CONSTRAINT pronosticos_series_id_fkey FOREIGN KEY (series_id) REFERENCES public.series(id);


--
-- Name: redes_accessors redes_accessors_accessor_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.redes_accessors
    ADD CONSTRAINT redes_accessors_accessor_fkey FOREIGN KEY (accessor) REFERENCES public.accessors(name);


--
-- Name: redes_accessors redes_accessors_tabla_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.redes_accessors
    ADD CONSTRAINT redes_accessors_tabla_id_fkey FOREIGN KEY (tabla_id) REFERENCES public.redes(tabla_id);


--
-- Name: redes_accessors redes_accessors_var_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.redes_accessors
    ADD CONSTRAINT redes_accessors_var_id_fkey FOREIGN KEY (var_id) REFERENCES public.var(id);


--
-- Name: redes redes_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.redes
    ADD CONSTRAINT redes_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: series_areal series_areal_area_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_areal
    ADD CONSTRAINT series_areal_area_id_fkey FOREIGN KEY (area_id) REFERENCES public.areas_pluvio(unid);


--
-- Name: series_areal series_areal_fuentes_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_areal
    ADD CONSTRAINT series_areal_fuentes_id_fkey FOREIGN KEY (fuentes_id) REFERENCES public.fuentes(id);


--
-- Name: series_areal series_areal_proc_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_areal
    ADD CONSTRAINT series_areal_proc_id_fkey FOREIGN KEY (proc_id) REFERENCES public.procedimiento(id);


--
-- Name: series_areal series_areal_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_areal
    ADD CONSTRAINT series_areal_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.unidades(id);


--
-- Name: series_areal series_areal_var_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_areal
    ADD CONSTRAINT series_areal_var_id_fkey FOREIGN KEY (var_id) REFERENCES public.var(id);


--
-- Name: series series_estacion_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series
    ADD CONSTRAINT series_estacion_id_fkey FOREIGN KEY (estacion_id) REFERENCES public.estaciones(unid);


--
-- Name: series series_proc_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series
    ADD CONSTRAINT series_proc_id_fkey FOREIGN KEY (proc_id) REFERENCES public.procedimiento(id);


--
-- Name: series_rast series_rast_escena_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_rast
    ADD CONSTRAINT series_rast_escena_id_fkey FOREIGN KEY (escena_id) REFERENCES public.escenas(id);


--
-- Name: series_rast series_rast_fuentes_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_rast
    ADD CONSTRAINT series_rast_fuentes_id_fkey FOREIGN KEY (fuentes_id) REFERENCES public.fuentes(id);


--
-- Name: series_rast series_rast_proc_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_rast
    ADD CONSTRAINT series_rast_proc_id_fkey FOREIGN KEY (proc_id) REFERENCES public.procedimiento(id);


--
-- Name: series_rast series_rast_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_rast
    ADD CONSTRAINT series_rast_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.unidades(id);


--
-- Name: series_rast series_rast_var_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_rast
    ADD CONSTRAINT series_rast_var_id_fkey FOREIGN KEY (var_id) REFERENCES public.var(id);


--
-- Name: series_tramo series_tramo_proc_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_tramo
    ADD CONSTRAINT series_tramo_proc_id_fkey FOREIGN KEY (proc_id) REFERENCES public.procedimiento(id);


--
-- Name: series_tramo series_tramo_tramo_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_tramo
    ADD CONSTRAINT series_tramo_tramo_id_fkey FOREIGN KEY (tramo_id) REFERENCES public.tramos(unid);


--
-- Name: series_tramo series_tramo_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_tramo
    ADD CONSTRAINT series_tramo_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES public.unidades(id);


--
-- Name: series_tramo series_tramo_var_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series_tramo
    ADD CONSTRAINT series_tramo_var_id_fkey FOREIGN KEY (var_id) REFERENCES public.var(id);


--
-- Name: series series_var_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series
    ADD CONSTRAINT series_var_id_fkey FOREIGN KEY (var_id) REFERENCES public.var(id);


--
-- Name: estaciones tipo_est; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.estaciones
    ADD CONSTRAINT tipo_est FOREIGN KEY (tipo) REFERENCES public.tipo_estaciones(tipo);


--
-- Name: tramos tramos_area_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tramos
    ADD CONSTRAINT tramos_area_id_fkey FOREIGN KEY (area_id) REFERENCES public.areas_pluvio(unid);


--
-- Name: tramos tramos_in_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tramos
    ADD CONSTRAINT tramos_in_id_fkey FOREIGN KEY (in_id) REFERENCES public.estaciones(unid);


--
-- Name: tramos tramos_out_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tramos
    ADD CONSTRAINT tramos_out_id_fkey FOREIGN KEY (out_id) REFERENCES public.estaciones(unid);


--
-- Name: areas_pluvio unid_es; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.areas_pluvio
    ADD CONSTRAINT unid_es FOREIGN KEY (unid) REFERENCES public.estaciones(unid);


--
-- Name: series unidades_ser; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.series
    ADD CONSTRAINT unidades_ser FOREIGN KEY (unit_id) REFERENCES public.unidades(id);


--
-- Name: users users_role_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_role_fkey FOREIGN KEY (role) REFERENCES public.user_roles(name);


--
-- Name: valores_num_areal valores_num_areal_obs_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.valores_num_areal
    ADD CONSTRAINT valores_num_areal_obs_id_fkey FOREIGN KEY (obs_id) REFERENCES public.observaciones_areal(id);


--
-- Name: valores_num valores_num_obs_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.valores_num
    ADD CONSTRAINT valores_num_obs_id_fkey FOREIGN KEY (obs_id) REFERENCES public.observaciones(id) ON DELETE CASCADE;


--
-- Name: valores_numarr_areal valores_numarr_areal_obs_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.valores_numarr_areal
    ADD CONSTRAINT valores_numarr_areal_obs_id_fkey FOREIGN KEY (obs_id) REFERENCES public.observaciones_areal(id);


--
-- Name: valores_numarr valores_numarr_obs_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.valores_numarr
    ADD CONSTRAINT valores_numarr_obs_id_fkey FOREIGN KEY (obs_id) REFERENCES public.observaciones(id) ON DELETE CASCADE;


--
-- Name: valores_prono_num_guardados valores_prono_num_guardados_prono_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.valores_prono_num_guardados
    ADD CONSTRAINT valores_prono_num_guardados_prono_id_fkey FOREIGN KEY (prono_id) REFERENCES public.pronosticos_guardados(id) ON DELETE CASCADE;


--
-- Name: valores_prono_num valores_prono_num_prono_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.valores_prono_num
    ADD CONSTRAINT valores_prono_num_prono_id_fkey FOREIGN KEY (prono_id) REFERENCES public.pronosticos(id);


--
-- Name: valores_tramo_num valores_tramo_num_obs_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.valores_tramo_num
    ADD CONSTRAINT valores_tramo_num_obs_id_fkey FOREIGN KEY (obs_id) REFERENCES public.observaciones_tramo(id);


--
-- Name: var var_datatype_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.var
    ADD CONSTRAINT var_datatype_fkey FOREIGN KEY (datatype) REFERENCES public.datatypes(term);


--
-- Name: var var_def_unit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.var
    ADD CONSTRAINT var_def_unit_id_fkey FOREIGN KEY (def_unit_id) REFERENCES public.unidades(id);


--
-- PostgreSQL database dump complete
--

