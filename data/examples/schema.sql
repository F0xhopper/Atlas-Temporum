-- Atlas Temporum — runnable PostGIS schema (MVP)
-- Postgres 16 + PostGIS 3.4. See docs/02-data-models.md for the model rationale.

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;   -- fuzzy search

-- ---------- enums ----------
CREATE TYPE polity_kind AS ENUM ('kingdom','earldom','principality','duchy','lordship','other');
CREATE TYPE event_type  AS ENUM ('battle','coronation','treaty','law','rebellion','disease','castle','other');
CREATE TYPE confidence  AS ENUM ('attested','approximate','disputed');

-- ---------- identity tables ----------
CREATE TABLE polity (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  slug          TEXT NOT NULL UNIQUE,
  name          TEXT NOT NULL,
  kind          polity_kind NOT NULL DEFAULT 'kingdom',
  color         TEXT NOT NULL,                 -- '#RRGGBB'
  description   TEXT NOT NULL DEFAULT '',
  founded_year  INT,
  dissolved_year INT
);

CREATE TABLE person (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  slug        TEXT NOT NULL UNIQUE,
  name        TEXT NOT NULL,
  epithet     TEXT,
  house       TEXT,
  birth_year  INT,
  death_year  INT,
  bio         TEXT
);

CREATE TABLE city (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  slug         TEXT NOT NULL UNIQUE,
  name         TEXT NOT NULL,
  geom         geometry(Point, 4326) NOT NULL,
  founded_year INT,
  description  TEXT
);
CREATE INDEX city_geom_gix ON city USING GIST (geom);

-- ---------- time-varying tables ----------
CREATE TABLE territory_version (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  polity_id      BIGINT NOT NULL REFERENCES polity(id) ON DELETE CASCADE,
  geom           geometry(MultiPolygon, 4326) NOT NULL,
  valid_from     INT NOT NULL,
  valid_to       INT,                          -- NULL = open through 1500
  color_override TEXT,
  confidence     confidence NOT NULL DEFAULT 'approximate',
  note           TEXT,
  CHECK (valid_to IS NULL OR valid_to > valid_from)
);
CREATE INDEX territory_geom_gix  ON territory_version USING GIST (geom);
CREATE INDEX territory_valid_ix  ON territory_version (valid_from, valid_to);
CREATE INDEX territory_polity_ix ON territory_version (polity_id);

CREATE TABLE reign (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  person_id       BIGINT NOT NULL REFERENCES person(id) ON DELETE CASCADE,
  polity_id       BIGINT NOT NULL REFERENCES polity(id) ON DELETE CASCADE,
  title           TEXT NOT NULL,
  reign_from      INT NOT NULL,
  reign_to        INT,                          -- NULL = open
  reign_from_date TEXT,
  reign_to_date   TEXT,
  is_disputed     BOOLEAN NOT NULL DEFAULT FALSE,
  CHECK (reign_to IS NULL OR reign_to > reign_from)
);
CREATE INDEX reign_range_ix ON reign (reign_from, reign_to);

CREATE TABLE event (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  slug         TEXT NOT NULL UNIQUE,
  title        TEXT NOT NULL,
  type         event_type NOT NULL,
  year         INT NOT NULL,                    -- filtering key
  date_start   TEXT,
  date_end     TEXT,
  date_display TEXT NOT NULL DEFAULT '',
  is_circa     BOOLEAN NOT NULL DEFAULT FALSE,
  geom         geometry(Point, 4326),           -- nullable (non-spatial laws)
  city_id      BIGINT REFERENCES city(id) ON DELETE SET NULL,
  polity_id    BIGINT REFERENCES polity(id) ON DELETE SET NULL,
  summary      TEXT NOT NULL DEFAULT '',
  description  TEXT NOT NULL DEFAULT '',
  outcome      TEXT,
  importance   SMALLINT NOT NULL DEFAULT 3 CHECK (importance BETWEEN 1 AND 5)
);
CREATE INDEX event_year_ix ON event (year);
CREATE INDEX event_geom_gix ON event USING GIST (geom);
CREATE INDEX event_title_trgm ON event USING GIN (title gin_trgm_ops);

CREATE TABLE event_participant (
  event_id  BIGINT NOT NULL REFERENCES event(id) ON DELETE CASCADE,
  person_id BIGINT NOT NULL REFERENCES person(id) ON DELETE CASCADE,
  role      TEXT NOT NULL DEFAULT '',
  PRIMARY KEY (event_id, person_id)
);

CREATE TABLE population_sample (
  id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  city_id   BIGINT NOT NULL REFERENCES city(id) ON DELETE CASCADE,
  year      INT NOT NULL,
  size_rank SMALLINT NOT NULL CHECK (size_rank BETWEEN 1 AND 5),
  UNIQUE (city_id, year)
);
CREATE INDEX popsample_city_year_ix ON population_sample (city_id, year);

-- Optional: a single-row table to bump for cache busting (ETag source).
CREATE TABLE data_version (
  id      INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  version TEXT NOT NULL,
  loaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
