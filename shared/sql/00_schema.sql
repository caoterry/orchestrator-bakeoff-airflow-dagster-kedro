CREATE SCHEMA IF NOT EXISTS poc;

CREATE TABLE IF NOT EXISTS poc.raw_input (
  ds DATE NOT NULL,
  user_id INT NOT NULL,
  amount NUMERIC NOT NULL,
  category TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS poc.output_agg (
  ds DATE NOT NULL,
  category TEXT NOT NULL,
  total_amount NUMERIC NOT NULL,
  PRIMARY KEY (ds, category)
);
