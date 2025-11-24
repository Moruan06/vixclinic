CREATE EXTENSION IF NOT EXISTS "pg_graphql";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "plpgsql";
CREATE EXTENSION IF NOT EXISTS "supabase_vault";
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
--
-- PostgreSQL database dump
--


-- Dumped from database version 17.6
-- Dumped by pg_dump version 17.7

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
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--



--
-- Name: agendamento_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.agendamento_status AS ENUM (
    'AGENDADO',
    'REALIZADO'
);


--
-- Name: cliente_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.cliente_status AS ENUM (
    'ATIVO',
    'INATIVO'
);


--
-- Name: funcionario_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.funcionario_status AS ENUM (
    'ATIVO',
    'INATIVO'
);


--
-- Name: vacina_categoria; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.vacina_categoria AS ENUM (
    'VIRAL',
    'BACTERIANA',
    'OUTRA'
);


--
-- Name: vacina_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.vacina_status AS ENUM (
    'ATIVA',
    'INATIVA'
);


--
-- Name: atualiza_estoque_apos_aplicacao(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.atualiza_estoque_apos_aplicacao() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
    -- Verificar se há estoque disponível
    IF EXISTS (
        SELECT 1 FROM public.lote 
        WHERE numlote = NEW.lote_numlote 
        AND quantidadedisponivel <= 0
    ) THEN
        RAISE EXCEPTION 'Não há vacinas disponíveis neste lote para aplicação.';
    END IF;
    
    -- Diminuir o estoque disponível
    UPDATE public.lote 
    SET quantidadedisponivel = quantidadedisponivel - 1 
    WHERE numlote = NEW.lote_numlote;
    
    RETURN NEW;
END;
$$;


--
-- Name: check_users_exist(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_users_exist() RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  RETURN EXISTS (SELECT 1 FROM auth.users LIMIT 1);
END;
$$;


--
-- Name: finaliza_agendamento_apos_aplicacao(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.finaliza_agendamento_apos_aplicacao() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
    -- Apenas atualiza status para REALIZADO, não deleta mais
    UPDATE public.agendamento 
    SET status = 'REALIZADO' 
    WHERE idagendamento = NEW.agendamento_idagendamento;
    
    RETURN NEW;
END;
$$;


--
-- Name: log_aplicacoes_antes_deletar_cliente(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.log_aplicacoes_antes_deletar_cliente() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
    INSERT INTO public.historico_aplicacoes_cliente 
        (cliente_cpf_deletado, idaplicacao_hist, dataaplicacao_hist, 
         dose_hist, idagendamento_hist, idfuncionario_hist, data_exclusao_cliente)
    SELECT 
        OLD.cpf, 
        idaplicacao, 
        dataaplicacao, 
        dose, 
        agendamento_idagendamento, 
        funcionario_idfuncionario, 
        NOW()
    FROM public.aplicacao
    WHERE cliente_cpf = OLD.cpf;
    
    RETURN OLD;
END;
$$;


--
-- Name: reserva_estoque_ao_agendar(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.reserva_estoque_ao_agendar() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
    disponivel INT;
    total_antes INT;
    total_depois INT;
BEGIN
    -- Verificar valores antes
    SELECT quantidadedisponivel, quantidadeinicial INTO disponivel, total_antes
    FROM public.lote 
    WHERE numlote = NEW.lote_numlote;
    
    IF disponivel <= 0 THEN
        RAISE EXCEPTION 'Não há vacinas disponíveis neste lote para agendamento.';
    ELSE
        -- Ao agendar: diminui APENAS das disponíveis
        UPDATE public.lote 
        SET quantidadedisponivel = quantidadedisponivel - 1 
        WHERE numlote = NEW.lote_numlote;
        
        -- Log para debug
        SELECT quantidadeinicial INTO total_depois
        FROM public.lote 
        WHERE numlote = NEW.lote_numlote;
        
        RAISE NOTICE 'AGENDAR - Lote %: Total antes=%, Total depois=%, Disponivel antes=%', 
            NEW.lote_numlote, total_antes, total_depois, disponivel;
    END IF;
    
    RETURN NEW;
END;
$$;


--
-- Name: retorna_estoque_ao_cancelar(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.retorna_estoque_ao_cancelar() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
    -- Só retorna estoque disponível se o agendamento estava AGENDADO (não REALIZADO ou CANCELADO)
    IF OLD.status = 'AGENDADO' THEN
        UPDATE public.lote 
        SET quantidadedisponivel = quantidadedisponivel + 1 
        WHERE numlote = OLD.lote_numlote;
    END IF;
    
    RETURN OLD;
END;
$$;


--
-- Name: valida_agendamento(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.valida_agendamento() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
    IF NEW.dataagendada <= NOW() THEN
        RAISE EXCEPTION 'A data do agendamento deve ser no futuro.';
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: valida_cliente(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.valida_cliente() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
    IF NEW.datanasc IS NOT NULL AND NEW.datanasc > CURRENT_DATE THEN
        RAISE EXCEPTION 'A data de nascimento não pode ser uma data futura.';
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: valida_funcionario(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.valida_funcionario() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
    IF NEW.dataadmissao IS NOT NULL AND NEW.dataadmissao > CURRENT_DATE THEN
        RAISE EXCEPTION 'A data de admissão não pode ser uma data futura.';
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: valida_lote(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.valida_lote() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
BEGIN
    IF NEW.datavalidade < CURRENT_DATE THEN
        RAISE EXCEPTION 'A data de validade não pode ser anterior à data atual. Lote vencido.';
    END IF;
    RETURN NEW;
END;
$$;


SET default_table_access_method = heap;

--
-- Name: agendamento; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agendamento (
    idagendamento integer NOT NULL,
    dataagendada timestamp without time zone NOT NULL,
    status public.agendamento_status DEFAULT 'AGENDADO'::public.agendamento_status NOT NULL,
    observacoes text,
    cliente_cpf character varying(11) NOT NULL,
    funcionario_idfuncionario integer,
    lote_numlote integer NOT NULL
);


--
-- Name: agendamento_idagendamento_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.agendamento_idagendamento_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: agendamento_idagendamento_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.agendamento_idagendamento_seq OWNED BY public.agendamento.idagendamento;


--
-- Name: aplicacao; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.aplicacao (
    idaplicacao integer NOT NULL,
    dataaplicacao timestamp without time zone NOT NULL,
    dose integer,
    reacoesadversas text,
    observacoes text,
    funcionario_idfuncionario integer NOT NULL,
    cliente_cpf character varying(11) NOT NULL,
    agendamento_idagendamento integer,
    lote_numlote integer,
    precocompra numeric(10,2) DEFAULT 0 NOT NULL,
    precovenda numeric(10,2) DEFAULT 0 NOT NULL,
    CONSTRAINT aplicacao_dose_check CHECK ((dose > 0))
);


--
-- Name: aplicacao_idaplicacao_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.aplicacao_idaplicacao_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: aplicacao_idaplicacao_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.aplicacao_idaplicacao_seq OWNED BY public.aplicacao.idaplicacao;


--
-- Name: cliente; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cliente (
    cpf character varying(11) NOT NULL,
    nomecompleto character varying(255) NOT NULL,
    datanasc date,
    email character varying(255),
    telefone character varying(11),
    alergias text,
    observacoes text,
    status public.cliente_status DEFAULT 'ATIVO'::public.cliente_status NOT NULL
);


--
-- Name: funcionario; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.funcionario (
    idfuncionario integer NOT NULL,
    nomecompleto character varying(255) NOT NULL,
    cpf character varying(11) NOT NULL,
    email character varying(255) NOT NULL,
    telefone character varying(11),
    cargo character varying(100),
    status public.funcionario_status DEFAULT 'ATIVO'::public.funcionario_status NOT NULL,
    dataadmissao date,
    coren character varying(20)
);


--
-- Name: funcionario_idfuncionario_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.funcionario_idfuncionario_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: funcionario_idfuncionario_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.funcionario_idfuncionario_seq OWNED BY public.funcionario.idfuncionario;


--
-- Name: historico_aplicacoes_cliente; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.historico_aplicacoes_cliente (
    idhistorico integer NOT NULL,
    cliente_cpf_deletado character varying(11) NOT NULL,
    idaplicacao_hist integer NOT NULL,
    dataaplicacao_hist date,
    dose_hist integer,
    idagendamento_hist integer,
    idfuncionario_hist integer,
    data_exclusao_cliente timestamp without time zone
);


--
-- Name: historico_aplicacoes_cliente_idhistorico_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.historico_aplicacoes_cliente_idhistorico_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: historico_aplicacoes_cliente_idhistorico_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.historico_aplicacoes_cliente_idhistorico_seq OWNED BY public.historico_aplicacoes_cliente.idhistorico;


--
-- Name: lote; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lote (
    numlote integer NOT NULL,
    codigolote character varying(100) NOT NULL,
    quantidadeinicial integer NOT NULL,
    quantidadedisponivel integer NOT NULL,
    datavalidade date NOT NULL,
    precocompra numeric(10,2) DEFAULT 0 NOT NULL,
    precovenda numeric(10,2) DEFAULT 0 NOT NULL,
    vacina_idvacina integer NOT NULL,
    CONSTRAINT lote_quantidadedisponivel_check CHECK ((quantidadedisponivel >= 0)),
    CONSTRAINT lote_quantidadeinicial_check CHECK ((quantidadeinicial >= 0))
);


--
-- Name: lote_numlote_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.lote_numlote_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: lote_numlote_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.lote_numlote_seq OWNED BY public.lote.numlote;


--
-- Name: vacina; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vacina (
    idvacina integer NOT NULL,
    nome character varying(255) NOT NULL,
    fabricante character varying(255),
    categoria public.vacina_categoria,
    quantidadedoses integer,
    intervalodoses integer,
    descricao text,
    status public.vacina_status DEFAULT 'ATIVA'::public.vacina_status NOT NULL,
    CONSTRAINT vacina_intervalodoses_check CHECK ((intervalodoses >= 0)),
    CONSTRAINT vacina_quantidadedoses_check CHECK ((quantidadedoses > 0))
);


--
-- Name: vacina_idvacina_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.vacina_idvacina_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: vacina_idvacina_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.vacina_idvacina_seq OWNED BY public.vacina.idvacina;


--
-- Name: agendamento idagendamento; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agendamento ALTER COLUMN idagendamento SET DEFAULT nextval('public.agendamento_idagendamento_seq'::regclass);


--
-- Name: aplicacao idaplicacao; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aplicacao ALTER COLUMN idaplicacao SET DEFAULT nextval('public.aplicacao_idaplicacao_seq'::regclass);


--
-- Name: funcionario idfuncionario; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.funcionario ALTER COLUMN idfuncionario SET DEFAULT nextval('public.funcionario_idfuncionario_seq'::regclass);


--
-- Name: historico_aplicacoes_cliente idhistorico; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.historico_aplicacoes_cliente ALTER COLUMN idhistorico SET DEFAULT nextval('public.historico_aplicacoes_cliente_idhistorico_seq'::regclass);


--
-- Name: lote numlote; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lote ALTER COLUMN numlote SET DEFAULT nextval('public.lote_numlote_seq'::regclass);


--
-- Name: vacina idvacina; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vacina ALTER COLUMN idvacina SET DEFAULT nextval('public.vacina_idvacina_seq'::regclass);


--
-- Name: agendamento agendamento_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agendamento
    ADD CONSTRAINT agendamento_pkey PRIMARY KEY (idagendamento);


--
-- Name: aplicacao aplicacao_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aplicacao
    ADD CONSTRAINT aplicacao_pkey PRIMARY KEY (idaplicacao);


--
-- Name: cliente cliente_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cliente
    ADD CONSTRAINT cliente_pkey PRIMARY KEY (cpf);


--
-- Name: funcionario funcionario_cpf_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.funcionario
    ADD CONSTRAINT funcionario_cpf_key UNIQUE (cpf);


--
-- Name: funcionario funcionario_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.funcionario
    ADD CONSTRAINT funcionario_email_key UNIQUE (email);


--
-- Name: funcionario funcionario_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.funcionario
    ADD CONSTRAINT funcionario_pkey PRIMARY KEY (idfuncionario);


--
-- Name: historico_aplicacoes_cliente historico_aplicacoes_cliente_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.historico_aplicacoes_cliente
    ADD CONSTRAINT historico_aplicacoes_cliente_pkey PRIMARY KEY (idhistorico);


--
-- Name: lote lote_codigolote_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lote
    ADD CONSTRAINT lote_codigolote_key UNIQUE (codigolote);


--
-- Name: lote lote_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lote
    ADD CONSTRAINT lote_pkey PRIMARY KEY (numlote);


--
-- Name: vacina vacina_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vacina
    ADD CONSTRAINT vacina_pkey PRIMARY KEY (idvacina);


--
-- Name: idx_agendamento_cliente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agendamento_cliente ON public.agendamento USING btree (cliente_cpf);


--
-- Name: idx_agendamento_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agendamento_data ON public.agendamento USING btree (dataagendada);


--
-- Name: idx_agendamento_lote; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agendamento_lote ON public.agendamento USING btree (lote_numlote);


--
-- Name: idx_agendamento_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agendamento_status ON public.agendamento USING btree (status);


--
-- Name: idx_aplicacao_cliente; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_aplicacao_cliente ON public.aplicacao USING btree (cliente_cpf);


--
-- Name: idx_aplicacao_data; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_aplicacao_data ON public.aplicacao USING btree (dataaplicacao);


--
-- Name: idx_aplicacao_funcionario; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_aplicacao_funcionario ON public.aplicacao USING btree (funcionario_idfuncionario);


--
-- Name: idx_cliente_nome; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cliente_nome ON public.cliente USING btree (nomecompleto);


--
-- Name: idx_cliente_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cliente_status ON public.cliente USING btree (status);


--
-- Name: idx_funcionario_cpf; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_funcionario_cpf ON public.funcionario USING btree (cpf);


--
-- Name: idx_funcionario_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_funcionario_email ON public.funcionario USING btree (email);


--
-- Name: idx_funcionario_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_funcionario_status ON public.funcionario USING btree (status);


--
-- Name: idx_historico_cpf; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_historico_cpf ON public.historico_aplicacoes_cliente USING btree (cliente_cpf_deletado);


--
-- Name: idx_historico_data_exclusao; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_historico_data_exclusao ON public.historico_aplicacoes_cliente USING btree (data_exclusao_cliente);


--
-- Name: idx_lote_codigo; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_lote_codigo ON public.lote USING btree (codigolote);


--
-- Name: idx_lote_disponivel; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lote_disponivel ON public.lote USING btree (quantidadedisponivel);


--
-- Name: idx_lote_vacina; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lote_vacina ON public.lote USING btree (vacina_idvacina);


--
-- Name: idx_lote_validade; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_lote_validade ON public.lote USING btree (datavalidade);


--
-- Name: idx_vacina_categoria; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_vacina_categoria ON public.vacina USING btree (categoria);


--
-- Name: idx_vacina_nome; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_vacina_nome ON public.vacina USING btree (nome);


--
-- Name: idx_vacina_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_vacina_status ON public.vacina USING btree (status);


--
-- Name: aplicacao trg_finaliza_agendamento; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_finaliza_agendamento AFTER INSERT ON public.aplicacao FOR EACH ROW EXECUTE FUNCTION public.finaliza_agendamento_apos_aplicacao();


--
-- Name: cliente trg_log_aplicacoes; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_log_aplicacoes BEFORE DELETE ON public.cliente FOR EACH ROW EXECUTE FUNCTION public.log_aplicacoes_antes_deletar_cliente();


--
-- Name: agendamento trg_reserva_estoque; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_reserva_estoque BEFORE INSERT ON public.agendamento FOR EACH ROW EXECUTE FUNCTION public.reserva_estoque_ao_agendar();


--
-- Name: agendamento trg_retorna_estoque; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_retorna_estoque BEFORE DELETE ON public.agendamento FOR EACH ROW EXECUTE FUNCTION public.retorna_estoque_ao_cancelar();


--
-- Name: agendamento trg_valida_agendamento; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_valida_agendamento BEFORE INSERT ON public.agendamento FOR EACH ROW EXECUTE FUNCTION public.valida_agendamento();


--
-- Name: cliente trg_valida_cliente; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_valida_cliente BEFORE INSERT OR UPDATE ON public.cliente FOR EACH ROW EXECUTE FUNCTION public.valida_cliente();


--
-- Name: funcionario trg_valida_funcionario; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_valida_funcionario BEFORE INSERT OR UPDATE ON public.funcionario FOR EACH ROW EXECUTE FUNCTION public.valida_funcionario();


--
-- Name: lote trg_valida_lote; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_valida_lote BEFORE INSERT OR UPDATE ON public.lote FOR EACH ROW EXECUTE FUNCTION public.valida_lote();


--
-- Name: aplicacao trigger_atualiza_estoque_apos_aplicacao; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_atualiza_estoque_apos_aplicacao AFTER INSERT ON public.aplicacao FOR EACH ROW WHEN ((new.lote_numlote IS NOT NULL)) EXECUTE FUNCTION public.atualiza_estoque_apos_aplicacao();


--
-- Name: agendamento agendamento_cliente_cpf_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agendamento
    ADD CONSTRAINT agendamento_cliente_cpf_fkey FOREIGN KEY (cliente_cpf) REFERENCES public.cliente(cpf) ON DELETE CASCADE;


--
-- Name: agendamento agendamento_funcionario_idfuncionario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agendamento
    ADD CONSTRAINT agendamento_funcionario_idfuncionario_fkey FOREIGN KEY (funcionario_idfuncionario) REFERENCES public.funcionario(idfuncionario) ON DELETE SET NULL;


--
-- Name: agendamento agendamento_lote_numlote_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agendamento
    ADD CONSTRAINT agendamento_lote_numlote_fkey FOREIGN KEY (lote_numlote) REFERENCES public.lote(numlote) ON DELETE RESTRICT;


--
-- Name: aplicacao aplicacao_agendamento_idagendamento_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aplicacao
    ADD CONSTRAINT aplicacao_agendamento_idagendamento_fkey FOREIGN KEY (agendamento_idagendamento) REFERENCES public.agendamento(idagendamento) ON DELETE SET NULL;


--
-- Name: aplicacao aplicacao_cliente_cpf_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aplicacao
    ADD CONSTRAINT aplicacao_cliente_cpf_fkey FOREIGN KEY (cliente_cpf) REFERENCES public.cliente(cpf) ON DELETE RESTRICT;


--
-- Name: aplicacao aplicacao_funcionario_idfuncionario_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aplicacao
    ADD CONSTRAINT aplicacao_funcionario_idfuncionario_fkey FOREIGN KEY (funcionario_idfuncionario) REFERENCES public.funcionario(idfuncionario) ON DELETE RESTRICT;


--
-- Name: aplicacao aplicacao_lote_numlote_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aplicacao
    ADD CONSTRAINT aplicacao_lote_numlote_fkey FOREIGN KEY (lote_numlote) REFERENCES public.lote(numlote);


--
-- Name: agendamento fk_agendamento_cliente; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agendamento
    ADD CONSTRAINT fk_agendamento_cliente FOREIGN KEY (cliente_cpf) REFERENCES public.cliente(cpf) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: agendamento fk_agendamento_funcionario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agendamento
    ADD CONSTRAINT fk_agendamento_funcionario FOREIGN KEY (funcionario_idfuncionario) REFERENCES public.funcionario(idfuncionario) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: agendamento fk_agendamento_lote; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agendamento
    ADD CONSTRAINT fk_agendamento_lote FOREIGN KEY (lote_numlote) REFERENCES public.lote(numlote) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: aplicacao fk_aplicacao_agendamento; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aplicacao
    ADD CONSTRAINT fk_aplicacao_agendamento FOREIGN KEY (agendamento_idagendamento) REFERENCES public.agendamento(idagendamento) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: aplicacao fk_aplicacao_cliente; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aplicacao
    ADD CONSTRAINT fk_aplicacao_cliente FOREIGN KEY (cliente_cpf) REFERENCES public.cliente(cpf) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: aplicacao fk_aplicacao_funcionario; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aplicacao
    ADD CONSTRAINT fk_aplicacao_funcionario FOREIGN KEY (funcionario_idfuncionario) REFERENCES public.funcionario(idfuncionario) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: aplicacao fk_aplicacao_lote; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.aplicacao
    ADD CONSTRAINT fk_aplicacao_lote FOREIGN KEY (lote_numlote) REFERENCES public.lote(numlote) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: lote fk_lote_vacina; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lote
    ADD CONSTRAINT fk_lote_vacina FOREIGN KEY (vacina_idvacina) REFERENCES public.vacina(idvacina) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: lote lote_vacina_idvacina_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lote
    ADD CONSTRAINT lote_vacina_idvacina_fkey FOREIGN KEY (vacina_idvacina) REFERENCES public.vacina(idvacina) ON DELETE CASCADE;


--
-- Name: agendamento Usuarios autenticados podem atualizar agendamentos; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem atualizar agendamentos" ON public.agendamento FOR UPDATE USING ((auth.role() = 'authenticated'::text));


--
-- Name: aplicacao Usuarios autenticados podem atualizar aplicacoes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem atualizar aplicacoes" ON public.aplicacao FOR UPDATE USING ((auth.role() = 'authenticated'::text));


--
-- Name: cliente Usuarios autenticados podem atualizar clientes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem atualizar clientes" ON public.cliente FOR UPDATE USING ((auth.role() = 'authenticated'::text));


--
-- Name: lote Usuarios autenticados podem atualizar lotes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem atualizar lotes" ON public.lote FOR UPDATE USING ((auth.role() = 'authenticated'::text));


--
-- Name: vacina Usuarios autenticados podem atualizar vacinas; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem atualizar vacinas" ON public.vacina FOR UPDATE USING ((auth.role() = 'authenticated'::text));


--
-- Name: agendamento Usuarios autenticados podem deletar agendamentos; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem deletar agendamentos" ON public.agendamento FOR DELETE USING ((auth.role() = 'authenticated'::text));


--
-- Name: aplicacao Usuarios autenticados podem deletar aplicacoes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem deletar aplicacoes" ON public.aplicacao FOR DELETE USING ((auth.role() = 'authenticated'::text));


--
-- Name: cliente Usuarios autenticados podem deletar clientes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem deletar clientes" ON public.cliente FOR DELETE USING ((auth.role() = 'authenticated'::text));


--
-- Name: lote Usuarios autenticados podem deletar lotes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem deletar lotes" ON public.lote FOR DELETE USING ((auth.role() = 'authenticated'::text));


--
-- Name: vacina Usuarios autenticados podem deletar vacinas; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem deletar vacinas" ON public.vacina FOR DELETE USING ((auth.role() = 'authenticated'::text));


--
-- Name: funcionario Usuarios autenticados podem gerenciar funcionarios; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem gerenciar funcionarios" ON public.funcionario TO authenticated USING ((auth.uid() IS NOT NULL)) WITH CHECK ((auth.uid() IS NOT NULL));


--
-- Name: agendamento Usuarios autenticados podem inserir agendamentos; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem inserir agendamentos" ON public.agendamento FOR INSERT WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: aplicacao Usuarios autenticados podem inserir aplicacoes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem inserir aplicacoes" ON public.aplicacao FOR INSERT WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: cliente Usuarios autenticados podem inserir clientes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem inserir clientes" ON public.cliente FOR INSERT WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: historico_aplicacoes_cliente Usuarios autenticados podem inserir historico; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem inserir historico" ON public.historico_aplicacoes_cliente FOR INSERT WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: lote Usuarios autenticados podem inserir lotes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem inserir lotes" ON public.lote FOR INSERT WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: vacina Usuarios autenticados podem inserir vacinas; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem inserir vacinas" ON public.vacina FOR INSERT WITH CHECK ((auth.role() = 'authenticated'::text));


--
-- Name: agendamento Usuarios autenticados podem ver agendamentos; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem ver agendamentos" ON public.agendamento FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: aplicacao Usuarios autenticados podem ver aplicacoes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem ver aplicacoes" ON public.aplicacao FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: cliente Usuarios autenticados podem ver clientes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem ver clientes" ON public.cliente FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: historico_aplicacoes_cliente Usuarios autenticados podem ver historico; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem ver historico" ON public.historico_aplicacoes_cliente FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: lote Usuarios autenticados podem ver lotes; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem ver lotes" ON public.lote FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: vacina Usuarios autenticados podem ver vacinas; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Usuarios autenticados podem ver vacinas" ON public.vacina FOR SELECT USING ((auth.role() = 'authenticated'::text));


--
-- Name: agendamento; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.agendamento ENABLE ROW LEVEL SECURITY;

--
-- Name: aplicacao; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.aplicacao ENABLE ROW LEVEL SECURITY;

--
-- Name: cliente; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cliente ENABLE ROW LEVEL SECURITY;

--
-- Name: funcionario; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.funcionario ENABLE ROW LEVEL SECURITY;

--
-- Name: historico_aplicacoes_cliente; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.historico_aplicacoes_cliente ENABLE ROW LEVEL SECURITY;

--
-- Name: lote; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.lote ENABLE ROW LEVEL SECURITY;

--
-- Name: vacina; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.vacina ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--


