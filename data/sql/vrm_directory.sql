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
-- Name: bucket_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.bucket_status AS ENUM (
    'Normal',
    'Deleted'
);


--
-- Name: object_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.object_status AS ENUM (
    'Normal',
    'Deleted',
    'Collected'
);


--
-- Name: versioning_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.versioning_type AS ENUM (
    'Disabled',
    'Enabled',
    'Suspended'
);


--
-- Name: ceiled_now(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ceiled_now() RETURNS timestamp without time zone
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN CURRENT_TIMESTAMP(0) + '1 second'::interval;
END;
$$;


--
-- Name: vrm_bucket_cors(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_bucket_cors(bucket text) RETURNS TABLE(cors xml)
    LANGUAGE plpgsql
    AS $$
DECLARE cors_record XML;
BEGIN
    SELECT buckets.cors INTO cors_record FROM buckets WHERE name = bucket;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bucket "%s" does not exist in buckets table', bucket;
    END IF;

    RETURN QUERY SELECT cors_record;
END;
$$;


--
-- Name: vrm_bucket_exists(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_bucket_exists(bucket text) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
BEGIN
    CALL vrm_check_bucket(bucket);
    -- Now caller expects exception when it doesn't exist; no one use it's return value
    RETURN TRUE;
    -- RETURN EXISTS (SELECT 1 FROM __buckets WHERE name = bucket);
END;
$$;


--
-- Name: vrm_bucket_policy(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_bucket_policy(bucket text) RETURNS TABLE(policy json)
    LANGUAGE plpgsql
    AS $$
DECLARE policy_record JSON;
BEGIN
    -- Execute the query and save the result to a variable
    SELECT buckets.policy INTO policy_record
    FROM buckets
    WHERE name = bucket;

    -- Check if the bucket was found
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bucket "%s" does not exist in buckets table', bucket;
    END IF;

    -- Return the policy
    RETURN QUERY SELECT policy_record;
END;
$$;


--
-- Name: vrm_bucket_set_cors(text, xml); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_bucket_set_cors(IN bucket text, IN config xml)
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE buckets SET cors = XMLPARSE(DOCUMENT config) WHERE name = bucket;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bucket "%s" does not exist in buckets table', bucket;
    END IF;
END;
$$;


--
-- Name: vrm_bucket_set_policy(text, json); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_bucket_set_policy(IN bucket text, IN new_policy json)
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE buckets
    SET policy = new_policy
    WHERE name = bucket;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bucket "%s" does not exist in buckets table', bucket;
    END IF;
END;
$$;


--
-- Name: vrm_bucket_set_versioning(text, public.versioning_type); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_bucket_set_versioning(IN bucket text, IN vt public.versioning_type)
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE buckets SET versioning = vt WHERE name = bucket;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bucket "%s" does not exist in buckets table', bucket;
    END IF;
END;
$$;


--
-- Name: vrm_bucket_versioning(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_bucket_versioning(bucket text) RETURNS TABLE(status text)
    LANGUAGE plpgsql
    AS $$
DECLARE rv TEXT;
BEGIN
    SELECT versioning INTO rv FROM buckets WHERE name = bucket;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bucket "%s" does not exist in buckets table', bucket;
    END IF;

    RETURN QUERY SELECT rv;
END;
$$;


--
-- Name: vrm_check_bucket(text); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_check_bucket(IN bucket text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM 1 FROM buckets WHERE name = bucket AND status = 'Normal'
    ORDER BY id DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bucket "%s" does not exist in buckets table', bucket;
    END IF;
END
$$;


--
-- Name: vrm_clear_deleted_buckets(); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_clear_deleted_buckets()
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM buckets b WHERE status = 'Deleted'
        AND NOT EXISTS (SELECT 1 FROM objects o WHERE o.bucket_id = b.id);
END
$$;


--
-- Name: vrm_create_bucket(text); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_create_bucket(IN bucket text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    PERFORM 1 FROM buckets WHERE name = bucket AND status = 'Normal';

    IF FOUND THEN
        RAISE EXCEPTION 'Bucket "%s" already exists', bucket;
    END IF;

    INSERT INTO buckets (name) VALUES (bucket);
END
$$;


--
-- Name: vrm_data_size(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_data_size() RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE result BIGINT;
BEGIN
    SELECT SUM(size) INTO result FROM objects WHERE status = 'Normal';
    RETURN COALESCE(result, 0);
END;
$$;


--
-- Name: vrm_dec_reference(bigint); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_dec_reference(IN target_id bigint)
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM objects o
        WHERE o.id = target_id
    ) THEN
        RAISE EXCEPTION 'object not found';
    END IF;

    UPDATE object_refs
    SET refs = refs - 1
    WHERE object_id = target_id;

    DELETE FROM object_refs
    WHERE object_id = target_id AND refs <= 0;
END
$$;


--
-- Name: vrm_delete_bucket(text); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_delete_bucket(IN bucket text)
    LANGUAGE plpgsql
    AS $$
DECLARE
    b_id BIGINT;
BEGIN
    SELECT vrm_get_bucket_id(bucket) INTO b_id;
    UPDATE buckets SET status = 'Deleted' WHERE id = b_id;
END;
$$;


--
-- Name: vrm_delete_object(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_delete_object(bucket text, object text) RETURNS TABLE(delete_marker boolean, version uuid)
    LANGUAGE plpgsql
    AS $$
DECLARE
    b_versioning versioning_type;
    obj_id BIGINT;
    obj_sticky BOOLEAN;
    obj_status object_status;
BEGIN
    SELECT versioning FROM vrm_get_bucket_info(bucket) INTO b_versioning;
    SELECT id, sticky, status FROM vrm_get_object(bucket, object) INTO obj_id, obj_sticky, obj_status;

    IF obj_id IS NULL OR obj_status = 'Deleted' THEN
        RAISE EXCEPTION 'Cannot delete object "%" in bucket "%", as it does not appear to exist.', object, bucket;
    END IF;

    IF b_versioning = 'Enabled' THEN

        SELECT id FROM vrm_put_object(bucket, object, '', 0, NULL, NULL) INTO obj_id;
        UPDATE objects SET status = 'Deleted', deleted_at = now(), sticky = True WHERE id = obj_id;

        RETURN QUERY SELECT True, o.version FROM objects o WHERE id = obj_id;

    ELSEIF b_versioning = 'Suspended' THEN

        IF obj_sticky THEN
            SELECT id FROM vrm_put_object(bucket, object, '', 0, NULL, NULL) INTO obj_id;
        END IF;

        UPDATE objects SET status = 'Deleted', deleted_at = now(), sticky = True WHERE id = obj_id;

        RETURN QUERY SELECT True, o.version FROM objects o WHERE id = obj_id;

    ELSE

        UPDATE objects SET status = 'Deleted', deleted_at = now() WHERE id = obj_id;
        RETURN QUERY SELECT True, NULL::UUID FROM objects WHERE id = obj_id;

    END IF;
END;
$$;


--
-- Name: vrm_delete_object_by_id(bigint); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_delete_object_by_id(IN target_id bigint)
    LANGUAGE plpgsql
    AS $$
BEGIN
    DELETE FROM objects WHERE id = target_id;
END
$$;


--
-- Name: vrm_delete_object_null_version(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_delete_object_null_version(bucket text, object text) RETURNS TABLE(delete_marker boolean, version uuid)
    LANGUAGE plpgsql
    AS $$
DECLARE
    obj_id BIGINT;
BEGIN
    SELECT id FROM objects WHERE NOT sticky AND status = 'Normal' AND name = object AND bucket_id = vrm_get_bucket_id(bucket) INTO obj_id;

    IF obj_id IS NULL THEN
        RAISE EXCEPTION 'Cannot delete object "%" in bucket "%", as it does not appear to exist.', object, bucket;
    END IF;

    UPDATE objects SET status = 'Deleted', deleted_at = now() WHERE id = obj_id;
    RETURN QUERY SELECT False, NULL::UUID;
END;
$$;


--
-- Name: vrm_delete_object_version(text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_delete_object_version(bucket text, object text, version_id uuid) RETURNS TABLE(delete_marker boolean, version uuid)
    LANGUAGE plpgsql
    AS $$
DECLARE
    obj_id BIGINT;
    obj_sticky BOOLEAN;
    obj_status object_status;
BEGIN
    SELECT id, sticky, status FROM vrm_get_object_by_version(bucket, object, version_id) INTO obj_id, obj_sticky, obj_status;

    IF obj_id IS NULL THEN
        RAISE EXCEPTION 'Cannot delete object "%" in bucket "%", as it does not appear to exist.', object, bucket;
    END IF;

    UPDATE objects SET status = 'Deleted', deleted_at = now(), sticky = False WHERE id = obj_id;
    RETURN QUERY SELECT obj_status = 'Deleted', NULL::UUID;
END;
$$;


--
-- Name: vrm_get_bucket_id(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_get_bucket_id(bucket text) RETURNS bigint
    LANGUAGE plpgsql
    AS $$
DECLARE b_id BIGINT;
BEGIN
    SELECT id INTO b_id FROM buckets WHERE status != 'Deleted' AND name = bucket
    ORDER BY id DESC
    LIMIT 1;

    IF b_id IS NULL THEN
        RAISE EXCEPTION 'Bucket "%" does not exist.', bucket;
    END IF;

    RETURN b_id;
END;
$$;


--
-- Name: vrm_get_bucket_info(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_get_bucket_info(bucket text) RETURNS TABLE(id bigint, versioning public.versioning_type)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY SELECT buckets.id, buckets.versioning FROM buckets WHERE name = bucket AND status = 'Normal';
END;
$$;


--
-- Name: vrm_get_object(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_get_object(bucket text, object text) RETURNS TABLE(id bigint, name text, address bytea, size bigint, last_modified timestamp without time zone, etag text, mime text, version uuid, status public.object_status, sticky boolean)
    LANGUAGE plpgsql
    AS $$
DECLARE
    b_id BIGINT;
    b_ver versioning_type;
BEGIN
    SELECT vrm_get_bucket_info.id, versioning FROM vrm_get_bucket_info(bucket) INTO b_id, b_ver;

    IF b_ver = 'Disabled' THEN

        RETURN QUERY
            SELECT o.id, o.name, o.address, o.size, o.last_modified, o.etag, o.mime, NULL::UUID, o.status, o.sticky FROM objects o
            JOIN (
                SELECT max(o2.id) AS max_id FROM objects o2 WHERE o2.status = 'Normal' AND o2.bucket_id = vrm_get_bucket_id(bucket) AND o2.name = object
            ) temp ON o.id = temp.max_id;

    ELSE

        RETURN QUERY
            SELECT o.id, o.name, o.address, o.size, o.last_modified, o.etag, o.mime, o.version, o.status, o.sticky FROM objects o
            JOIN (
                SELECT max(o2.id) AS max_id FROM objects o2 WHERE NOT (o2.status = 'Deleted' and NOT o2.sticky) AND o2.bucket_id = vrm_get_bucket_id(bucket) AND o2.name = object
            ) temp ON o.id = temp.max_id;
    END IF;
END;
$$;


--
-- Name: vrm_get_object_by_version(text, text, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_get_object_by_version(bucket text, object text, ver uuid) RETURNS TABLE(id bigint, name text, address bytea, size bigint, last_modified timestamp without time zone, etag text, mime text, version uuid, status public.object_status, sticky boolean)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
        SELECT o.id, o.name, o.address, o.size, o.last_modified, o.etag, o.mime, o.version, o.status, o.sticky
         FROM objects o
         WHERE bucket_id = vrm_get_bucket_id(bucket) AND o.name = object AND o.version = ver
        ORDER BY id DESC
        LIMIT 1;
END;
$$;


--
-- Name: vrm_inc_reference(bigint); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_inc_reference(IN target_id bigint)
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM objects o
        WHERE o.id = target_id
    ) THEN
        RAISE EXCEPTION 'object not found';
    END IF;

    INSERT INTO object_refs (object_id, refs)
    VALUES (target_id, 1)
    ON CONFLICT (object_id)
        DO UPDATE SET refs = object_refs.refs + 1;
END
$$;


--
-- Name: vrm_list_buckets(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_list_buckets() RETURNS TABLE(name character varying)
    LANGUAGE sql
    AS $$SELECT name FROM buckets WHERE status = 'Normal';$$;


--
-- Name: vrm_list_object_versions(text, text, text, uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_list_object_versions(bucket text, prefix text, key_marker text, version_marker uuid, max_keys integer) RETURNS TABLE(id bigint, name text, size bigint, last_modified timestamp without time zone, etag text, mime text, version uuid, status public.object_status)
    LANGUAGE plpgsql
    AS $$
DECLARE
    min_id BIGINT;
    condition TEXT;
    query TEXT;
BEGIN
    IF version_marker IS NOT NULL THEN
        SELECT o.id FROM objects o, buckets b WHERE o.bucket_id = b.id AND b.name = bucket AND o.name = key_marker AND o.version = version_marker INTO min_id;

        IF FOUND THEN
            SELECT format(' AND o.id >= %s', min_id) INTO condition;
        END IF;
    END IF;

    IF prefix IS NOT NULL THEN
        SELECT format('%s AND o.name LIKE %L || ''%%''', condition, prefix) INTO condition;
    END IF;

    RETURN QUERY EXECUTE format('SELECT o.id, o.name, o.size, o.last_modified, o.etag, o.mime, o.version, o.status FROM objects o, buckets b WHERE '
        || ' o.bucket_id = b.id AND b.name = %L AND (o.status = ''Normal'' OR o.sticky) %s ORDER BY o.name ASC, o.id DESC LIMIT %L' , bucket, condition, max_keys);
END
$$;


--
-- Name: vrm_list_objects(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_list_objects(bucket text) RETURNS TABLE(id bigint, name text, size bigint, last_modified timestamp without time zone, etag text, mime text, version uuid, status public.object_status)
    LANGUAGE plpgsql
    AS $$
BEGIN
    CALL vrm_check_bucket(bucket);
    RETURN QUERY
        SELECT o.id, o.name, o.size, o.last_modified, o.etag, o.mime, o.version, o.status FROM objects o
        JOIN (
            SELECT o2.name, o2.bucket_id, max(o2.id) AS max_id FROM objects o2 GROUP BY o2.name, o2.bucket_id
        ) temp ON o.id = temp.max_id
        WHERE o.bucket_id = vrm_get_bucket_id(bucket) AND o.status = 'Normal'
        ORDER BY o.name;
END;
$$;


--
-- Name: vrm_list_objects(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_list_objects(bucket text, prefix text, lower_bound text) RETURNS TABLE(id bigint, name text, size bigint, last_modified timestamp without time zone, etag text, mime text, version uuid, status public.object_status)
    LANGUAGE plpgsql
    AS $$
BEGIN
    CALL vrm_check_bucket(bucket);
    RETURN QUERY
        SELECT o.id, o.name, o.size, o.last_modified, o.etag, o.mime, o.version, o.status FROM objects o
        JOIN (
            SELECT o2.name, o2.bucket_id, max(o2.id) AS max_id FROM objects o2 GROUP BY o2.name, o2.bucket_id
        ) temp ON o.id = temp.max_id
        WHERE o.bucket_id = vrm_get_bucket_id(bucket)
          AND o.name LIKE prefix || '%'
          AND o.status = 'Normal'
          AND (lower_bound = '' OR
               (o.name > lower_bound AND NOT starts_with(o.name, lower_bound)))
        ORDER BY o.name;
END;
$$;


--
-- Name: vrm_next_deleted(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_next_deleted() RETURNS TABLE(id bigint, address bytea)
    LANGUAGE plpgsql
    AS $$
DECLARE target_id BIGINT;
        target_address BYTEA;
BEGIN
    SELECT o.id, o.address
       INTO target_id, target_address
    FROM objects o
    LEFT JOIN object_refs r ON o.id = r.object_id
    LEFT JOIN buckets b ON b.id = o.bucket_id
    WHERE o.status = 'Deleted' AND o.sticky = False AND r.object_id IS NULL
    LIMIT 1;

    IF NOT FOUND THEN
       RETURN;
    END IF;

    UPDATE objects o SET status = 'Collected' WHERE o.id = target_id;

    RETURN QUERY SELECT target_id, target_address;
END
$$;


--
-- Name: vrm_put_object(text, text, bytea, bigint, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_put_object(bucket text, object text, address bytea, size bigint, etag text, mime text) RETURNS TABLE(id bigint, version uuid)
    LANGUAGE plpgsql
    AS $$
DECLARE b_id BIGINT;
        b_ver versioning_type;
        o_id BIGINT;
        o_sticky BOOLEAN;
BEGIN
    SELECT vrm_get_bucket_info.id, versioning FROM vrm_get_bucket_info(bucket) INTO b_id, b_ver;

    IF b_ver = 'Disabled' THEN

        SELECT vrm_get_object.id FROM vrm_get_object(bucket, object) INTO o_id;

        IF o_id IS NOT NULL THEN
            UPDATE objects SET status = 'Deleted', deleted_at = now() WHERE objects.id = o_id;
        END IF;

        RETURN QUERY INSERT INTO objects (bucket_id, name, address, size, last_modified, etag, mime)
            VALUES (b_id, object, address, size, ceiled_now(), etag, mime) RETURNING objects.id, NULL::UUID;

    ELSEIF b_ver = 'Enabled' THEN

        RETURN QUERY INSERT INTO objects (bucket_id, name, address, size, last_modified, etag, mime, sticky)
            VALUES (b_id, object, address, size, ceiled_now(), etag, mime, True) RETURNING objects.id, objects.version;

    ELSEIF b_ver = 'Suspended' THEN

        SELECT vrm_get_object.id, sticky FROM vrm_get_object(bucket, object) INTO o_id, o_sticky;

        IF o_id IS NOT NULL AND NOT o_sticky THEN
            UPDATE objects SET status = 'Deleted', deleted_at = now() WHERE objects.id = o_id;
        END IF;

        RETURN QUERY INSERT INTO objects (bucket_id, name, address, size, last_modified, etag, mime)
            VALUES (b_id, object, address, size, ceiled_now(), etag, mime) RETURNING objects.id, NULL::UUID;

    END IF;
END
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: buckets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.buckets (
    id bigint NOT NULL,
    name character varying(64) NOT NULL,
    policy json,
    last_modified timestamp without time zone DEFAULT now() NOT NULL,
    version uuid DEFAULT gen_random_uuid() NOT NULL,
    cors xml,
    versioning public.versioning_type DEFAULT 'Disabled'::public.versioning_type NOT NULL,
    status public.bucket_status DEFAULT 'Normal'::public.bucket_status NOT NULL,
    deleted_at timestamp without time zone
);


--
-- Name: __buckets_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.buckets ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.__buckets_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: objects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.objects (
    id bigint NOT NULL,
    bucket_id bigint NOT NULL,
    name text NOT NULL,
    address bytea NOT NULL,
    size bigint NOT NULL,
    last_modified timestamp without time zone NOT NULL,
    etag text,
    mime text,
    version uuid DEFAULT gen_random_uuid() NOT NULL,
    status public.object_status DEFAULT 'Normal'::public.object_status NOT NULL,
    deleted_at timestamp without time zone,
    sticky boolean DEFAULT false NOT NULL
);


--
-- Name: __objects_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.objects ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.__objects_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: object_refs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.object_refs (
    object_id bigint NOT NULL,
    refs integer NOT NULL
);


--
-- Name: buckets __buckets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.buckets
    ADD CONSTRAINT __buckets_pkey PRIMARY KEY (id);


--
-- Name: objects __objects_bucket_id_name_version_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.objects
    ADD CONSTRAINT __objects_bucket_id_name_version_key UNIQUE (bucket_id, name, version);


--
-- Name: objects __objects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.objects
    ADD CONSTRAINT __objects_pkey PRIMARY KEY (id);


--
-- Name: object_refs object_refs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.object_refs
    ADD CONSTRAINT object_refs_pkey PRIMARY KEY (object_id);


--
-- Name: buckets unique_name_version; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.buckets
    ADD CONSTRAINT unique_name_version UNIQUE (name, version);


--
-- Name: objects __objects_bucket_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.objects
    ADD CONSTRAINT __objects_bucket_id_fkey FOREIGN KEY (bucket_id) REFERENCES public.buckets(id) ON DELETE RESTRICT;


--
-- Name: object_refs object_refs_object_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.object_refs
    ADD CONSTRAINT object_refs_object_id_fkey FOREIGN KEY (object_id) REFERENCES public.objects(id) ON DELETE RESTRICT;
