--
-- PostgreSQL database dump
--

\restrict KEZmDKpq7KbQOfa7xkmovd66aKbLPXaAkpxd4Vnr5JTbleGGJSYrdO4YxHF1SyQ

-- Dumped from database version 15.18
-- Dumped by pg_dump version 15.18

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

--
-- Name: jobstatus; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.jobstatus AS ENUM (
    'PENDING',
    'ASSIGNED',
    'IN_PROGRESS',
    'COMPLETED',
    'CANCELLED',
    'ON_HOLD'
);


--
-- Name: jobtype; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.jobtype AS ENUM (
    'INSTALL',
    'REPAIR',
    'MAINTENANCE',
    'INSPECTION',
    'DISCONNECT',
    'SERVICE_CHANGE'
);


--
-- Name: technicianstatus; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.technicianstatus AS ENUM (
    'AVAILABLE',
    'ON_JOB',
    'EN_ROUTE',
    'ON_BREAK',
    'OFF_DUTY'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: assignments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assignments (
    id integer NOT NULL,
    job_id integer NOT NULL,
    technician_id integer NOT NULL,
    assigned_at timestamp with time zone NOT NULL,
    sequence integer,
    estimated_travel_time integer,
    estimated_distance double precision,
    estimated_arrival timestamp with time zone,
    actual_travel_time integer,
    actual_arrival timestamp with time zone,
    actual_completion timestamp with time zone,
    actual_duration_minutes integer,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: assignments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.assignments_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: assignments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.assignments_id_seq OWNED BY public.assignments.id;


--
-- Name: jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.jobs (
    id integer NOT NULL,
    job_number character varying(50),
    job_type public.jobtype NOT NULL,
    status public.jobstatus NOT NULL,
    customer_name character varying(100) NOT NULL,
    customer_phone character varying(20),
    customer_email character varying(100),
    service_address character varying(255) NOT NULL,
    service_city character varying(100),
    service_zip character varying(10),
    latitude double precision NOT NULL,
    longitude double precision NOT NULL,
    required_skills jsonb NOT NULL,
    route_criteria character varying(50),
    priority integer NOT NULL,
    scheduled_date timestamp with time zone,
    time_slot_start character varying(5),
    time_slot_end character varying(5),
    estimated_duration integer NOT NULL,
    description text,
    notes text,
    special_instructions text,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL,
    started_at timestamp with time zone,
    completed_at timestamp with time zone
);


--
-- Name: jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.jobs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.jobs_id_seq OWNED BY public.jobs.id;


--
-- Name: technicians; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.technicians (
    id integer NOT NULL,
    name character varying(100) NOT NULL,
    employee_id character varying(50),
    phone character varying(20),
    email character varying(100),
    status public.technicianstatus NOT NULL,
    is_active boolean NOT NULL,
    current_latitude double precision,
    current_longitude double precision,
    last_location_update timestamp with time zone,
    home_latitude double precision NOT NULL,
    home_longitude double precision NOT NULL,
    home_address character varying(255),
    skills jsonb NOT NULL,
    assigned_routes jsonb NOT NULL,
    speed_factor double precision NOT NULL,
    skill_bonuses jsonb NOT NULL,
    shift_start character varying(5),
    shift_end character varying(5),
    max_jobs_per_day integer NOT NULL,
    created_at timestamp with time zone NOT NULL,
    updated_at timestamp with time zone NOT NULL
);


--
-- Name: technicians_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.technicians_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: technicians_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.technicians_id_seq OWNED BY public.technicians.id;


--
-- Name: assignments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assignments ALTER COLUMN id SET DEFAULT nextval('public.assignments_id_seq'::regclass);


--
-- Name: jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jobs ALTER COLUMN id SET DEFAULT nextval('public.jobs_id_seq'::regclass);


--
-- Name: technicians id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technicians ALTER COLUMN id SET DEFAULT nextval('public.technicians_id_seq'::regclass);


--
-- Name: assignments assignments_job_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assignments
    ADD CONSTRAINT assignments_job_id_key UNIQUE (job_id);


--
-- Name: assignments assignments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assignments
    ADD CONSTRAINT assignments_pkey PRIMARY KEY (id);


--
-- Name: jobs jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.jobs
    ADD CONSTRAINT jobs_pkey PRIMARY KEY (id);


--
-- Name: technicians technicians_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.technicians
    ADD CONSTRAINT technicians_pkey PRIMARY KEY (id);


--
-- Name: ix_assignments_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_assignments_id ON public.assignments USING btree (id);


--
-- Name: ix_jobs_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_jobs_id ON public.jobs USING btree (id);


--
-- Name: ix_jobs_job_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ix_jobs_job_number ON public.jobs USING btree (job_number);


--
-- Name: ix_jobs_route_criteria; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_jobs_route_criteria ON public.jobs USING btree (route_criteria);


--
-- Name: ix_jobs_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_jobs_status ON public.jobs USING btree (status);


--
-- Name: ix_technicians_employee_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ix_technicians_employee_id ON public.technicians USING btree (employee_id);


--
-- Name: ix_technicians_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX ix_technicians_id ON public.technicians USING btree (id);


--
-- Name: assignments assignments_job_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assignments
    ADD CONSTRAINT assignments_job_id_fkey FOREIGN KEY (job_id) REFERENCES public.jobs(id);


--
-- Name: assignments assignments_technician_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assignments
    ADD CONSTRAINT assignments_technician_id_fkey FOREIGN KEY (technician_id) REFERENCES public.technicians(id);


--
-- PostgreSQL database dump complete
--

\unrestrict KEZmDKpq7KbQOfa7xkmovd66aKbLPXaAkpxd4Vnr5JTbleGGJSYrdO4YxHF1SyQ

