-- Create an external BigQuery table that queries CSV files directly from a GCS bucket.
-- Replace the placeholders with your actual project, dataset, table name, and GCS bucket URI.

CREATE OR REPLACE EXTERNAL TABLE `your_project.your_dataset.your_table_name`
OPTIONS (
  format = 'CSV',
  uris = ['gs://your-bucket-name/path/to/files/*.csv'],
  skip_leading_rows = 1 -- Assumes your CSV has a header row. Change to 0 if it doesn't.
)
;
