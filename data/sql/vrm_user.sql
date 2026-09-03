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
-- Name: vrm_add_user(text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_add_user(username text, password text, arn text) RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE id TEXT;
BEGIN
    EXECUTE format('INSERT INTO users (name, password, arn) VALUES (%L, %L, %L) RETURNING id',
        username, password, arn) INTO id;
    RETURN id;
END;
$$;


--
-- Name: vrm_add_user_key(text, text, text, text, timestamp without time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_add_user_key(IN username text, IN access_key text, IN secret_key text, IN session_token text, IN expires timestamp without time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    EXECUTE format('
        INSERT INTO keys (username, access_key, secret_key, session_token, expires)
        VALUES (%L, %L, %L, %L, %L)',
        username, access_key, secret_key, session_token, expires);
END;
$$;


--
-- Name: vrm_get_user_policy(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_get_user_policy(username text) RETURNS TABLE(name text, value json)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY EXECUTE format('SELECT name, value FROM policies WHERE username = %L', username);
END;
$$;


--
-- Name: vrm_list_user_keys(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_list_user_keys(username text) RETURNS TABLE(access_key text, secret_key text, session_token text, expires timestamp without time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY EXECUTE format('
        SELECT access_key, secret_key, session_token, expires FROM keys
        WHERE username = %L AND (expires >= now() OR expires IS NULL)', username);
END;
$$;


--
-- Name: vrm_list_users(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_list_users() RETURNS TABLE(username text)
    LANGUAGE sql
    AS $$
    SELECT name FROM users;
$$;


--
-- Name: vrm_put_user_policy(text, text, json); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_put_user_policy(IN username text, IN name text, IN policy json)
    LANGUAGE plpgsql
    AS $$
BEGIN
    EXECUTE format('INSERT INTO policies (username, name, value) VALUES (%L, %L, %L)', username, name, policy);
END;
$$;


--
-- Name: vrm_query_key(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_query_key(access_key text) RETURNS TABLE(id uuid, username text, secret_key text, session_token text, expires timestamp without time zone, arn text, super_user integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY EXECUTE format('
        SELECT id, username, secret_key, session_token, expires, arn, super_user FROM keys
        JOIN users ON username = name WHERE access_key = %L AND (expires >= now() OR expires IS NULL)', access_key);
END;
$$;


--
-- Name: vrm_query_user(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.vrm_query_user(username text) RETURNS TABLE(id uuid, password text, arn text, super_user integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY EXECUTE format('SELECT id, password, arn, super_user FROM users WHERE name = %L',
        username);
END;
$$;


--
-- Name: vrm_remove_expired_keys(timestamp without time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_remove_expired_keys(IN expired_before timestamp without time zone)
    LANGUAGE plpgsql
    AS $$
BEGIN
    EXECUTE format('DELETE FROM keys WHERE expires <= %L', expired_before);
END;
$$;


--
-- Name: vrm_remove_key(text); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_remove_key(IN access_key text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    EXECUTE format('DELETE from keys WHERE access_key = %L', access_key);
END;
$$;


--
-- Name: vrm_remove_user(text); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_remove_user(IN username text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    EXECUTE format('DELETE FROM users WHERE name = %L', username);
END;
$$;


--
-- Name: vrm_remove_user_policy(text, text); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_remove_user_policy(IN username text, IN name text)
    LANGUAGE plpgsql
    AS $$
BEGIN
    EXECUTE format('DELETE FROM policies WHERE username = %L and name = %L', username, name);
END;
$$;


--
-- Name: vrm_set_super_user(text, integer); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.vrm_set_super_user(IN username text, IN value integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    EXECUTE format('UPDATE users SET super_user = %L WHERE name = %L', value, username);
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.keys (
    username text NOT NULL,
    access_key text NOT NULL,
    secret_key text NOT NULL,
    session_token text,
    expires timestamp without time zone
);


--
-- Name: policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.policies (
    username text NOT NULL,
    name text NOT NULL,
    value json NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    password text,
    arn text,
    super_user integer DEFAULT 0 NOT NULL
);


--
-- Name: keys keys_access_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.keys
    ADD CONSTRAINT keys_access_key_key UNIQUE (access_key);


--
-- Name: policies policies_name_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.policies
    ADD CONSTRAINT policies_name_username_key UNIQUE (name, username);


--
-- Name: users users_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_name_key UNIQUE (name);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: expires_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX expires_idx ON public.keys USING btree (expires);


--
-- Name: keys keys_username_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.keys
    ADD CONSTRAINT keys_username_fkey FOREIGN KEY (username) REFERENCES public.users(name) ON DELETE CASCADE;


--
-- Name: policies policies_username_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.policies
    ADD CONSTRAINT policies_username_fkey FOREIGN KEY (username) REFERENCES public.users(name) ON DELETE CASCADE;
