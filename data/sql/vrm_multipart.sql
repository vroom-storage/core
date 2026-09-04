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
-- Name: vrm_clean_deleted(interval); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_clean_deleted(IN age interval)
    LANGUAGE plpgsql
    AS $$
BEGIN
    EXECUTE format('DELETE FROM uploads WHERE erased_since + %L < now()', age);
END;
$$;


--
-- Name: vrm_complete_upload(text); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_complete_upload(IN id text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    EXECUTE format('UPDATE uploads SET complete = 1 WHERE id = %L', id);
END;
$$;


--
-- Name: vrm_create_upload(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_create_upload(bucket text, key text, mime text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE id TEXT;
BEGIN
    EXECUTE format('INSERT INTO uploads (bucket, key, mime) VALUES(%L, %L, %L) RETURNING id', bucket, key, mime)
        INTO id;
    RETURN id;
END;
$$;


--
-- Name: vrm_delete_upload(text); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_delete_upload(IN id text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    EXECUTE format('UPDATE uploads SET erased_since = now(), bucket = gen_random_uuid(), key = gen_random_uuid() WHERE id = %L', id);
END;
$$;


--
-- Name: vrm_get_upload(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_get_upload(id text) RETURNS TABLE(bucket text, key text, erased_since timestamp without time zone, mime text, complete integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY EXECUTE format('SELECT bucket, key, erased_since, mime, complete FROM uploads WHERE id = %L', id);
END;
$$;


--
-- Name: vrm_get_upload_part(text, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_get_upload_part(upload_id text, part_id bigint) RETURNS TABLE(size bigint, address bytea, etag text)
    LANGUAGE plpgsql
    AS $$
BEGIN
RETURN QUERY EXECUTE format('SELECT size, address, etag FROM upload_parts WHERE upload_id = %L AND part_id = %L', upload_id, part_id);
END;
$$;


--
-- Name: vrm_get_upload_parts(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_get_upload_parts(id text) RETURNS TABLE(part_id bigint, size bigint, effective_size bigint, address bytea, etag text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY EXECUTE format('SELECT part_id, size, effective_size, address, etag FROM upload_parts WHERE upload_id = %L', id);
END;
$$;


--
-- Name: vrm_get_uploads(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_get_uploads(bucket text) RETURNS TABLE(id uuid, key text, mime text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY EXECUTE format('SELECT id, key, mime FROM uploads WHERE erased_since IS NULL AND bucket = %L', bucket);
END;
$$;


--
-- Name: vrm_lock_upload(text); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_lock_upload(IN id text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM pg_advisory_lock(hashtext(id));
END;
$$;


--
-- Name: vrm_put_multipart(text, bigint, bigint, bigint, bytea, text); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_put_multipart(IN id text, IN part_id bigint, IN size bigint, IN effective_size bigint, IN address bytea, IN etag text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    EXECUTE format('
        INSERT INTO upload_parts (upload_id, part_id, size, effective_size, address, etag)
        VALUES (%L, %L, %L, %L, %L, %L) ON CONFLICT(upload_id, part_id) DO UPDATE SET
        size = EXCLUDED.size, effective_size = EXCLUDED.effective_size, address = EXCLUDED.address, etag = EXCLUDED.etag',
        id, part_id, size, effective_size, address, etag);
END;
$$;


--
-- Name: vrm_unlock_upload(text); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_unlock_upload(IN id text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM pg_advisory_unlock(hashtext(id));
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: upload_parts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.upload_parts (
    id bigint NOT NULL,
    upload_id uuid NOT NULL,
    part_id bigint NOT NULL,
    size bigint NOT NULL,
    effective_size bigint NOT NULL,
    address bytea NOT NULL,
    etag text NOT NULL
);


--
-- Name: upload_parts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.upload_parts ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.upload_parts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: uploads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.uploads (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    bucket text NOT NULL,
    key text NOT NULL,
    erased_since timestamp without time zone,
    mime text,
    complete integer DEFAULT 0 NOT NULL
);


--
-- Name: upload_parts upload_parts_upload_id_part_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.upload_parts
    ADD CONSTRAINT upload_parts_upload_id_part_id_key UNIQUE (upload_id, part_id);


--
-- Name: uploads uploads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.uploads
    ADD CONSTRAINT uploads_pkey PRIMARY KEY (id);


--
-- Name: upload_parts upload_parts_upload_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.upload_parts
    ADD CONSTRAINT upload_parts_upload_id_fkey FOREIGN KEY (upload_id) REFERENCES public.uploads(id) ON DELETE CASCADE;
