--
-- PostgreSQL database dump
--

-- Dumped from database version 12.12 (Ubuntu 12.12-0ubuntu0.20.04.1)
-- Dumped by pg_dump version 12.12 (Ubuntu 12.12-0ubuntu0.20.04.1)

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

COPY public.semanal_mapabase (orden, titulo, descripcion, href) FROM stdin;
0	anomalía de precipitación	Mapa de anomalía de precipitación semanal de la Cuenca del Plata en base a observaciones puntuales interpoladas. La anomalía se calcula con respecto al periodo 1991-2020	https://alerta.ina.gob.ar/siyah_informes/static/semanal/png/CDP.png
1	humedad del suelo	Mapa de humedad del suelo de la Cuenca del Plata simulada mediante un modelo de balance hídrico en base a observaciones puntuales de precipitación interpoladas	https://alerta.ina.gob.ar/siyah_informes/static/semanal/png/CDP_invertido.png
2	pronóstico de precipitación	Mapa de precipitación semanal de la Cuenca del Plata pronosticada resultante del modelo GFS de SMN	https://alerta.ina.gob.ar/siyah_informes/static/semanal/png/CDP_gris.png
\.

