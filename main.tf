variable "project" {}
variable "region" {}
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "4.5.0"
    }
  }
}

provider "google" {
  region = var.region
}

resource "google_storage_bucket" "bucket" {
  name     = "${var.project}-bucket"
  location = "eu"
  project  = var.project
}

resource "google_storage_bucket_object" "fake_message" {
  /*
    The hive partitoned table defined in google_bigquery_table.hive_table
    requires that the partitions locations exist when the table is created, in order to do so
    we have to create this fake message, without it the deployment of the table fails with:

     > Cannot query hive partitioned data for table braze_egress_messages without any associated files

    */
  name    = "publish/dt=2000-01-01/hr=00/min=00/fake_message.json"
  content = "{\"column1\": \"XXX\"}"
  bucket  = google_storage_bucket.bucket.name
}

resource "google_bigquery_dataset" "hive_store" {
  dataset_id = "hive_store"
  location   = "EU"
  project    = var.project
}

resource "google_bigquery_table" "hive_table" {
  /*
    to query:
    bq query --nouse_legacy_sql "select * from hive_store.messages"
    */
  dataset_id          = google_bigquery_dataset.hive_store.dataset_id
  project             = var.project
  table_id            = "messages"
  deletion_protection = false
  external_data_configuration {
    schema = <<EOF
    [
        {
            "name": "column1",
            "type": "STRING",
            "mode": "NULLABLE"
        }
    ]
  EOF
    autodetect    = false
    source_uris   = ["gs://${google_storage_bucket.bucket.name}/publish/*"]
    source_format = "NEWLINE_DELIMITED_JSON"
    hive_partitioning_options {
      mode                     = "CUSTOM"
      source_uri_prefix        = "gs://${google_storage_bucket.bucket.name}/publish/{dt:STRING}/{hr:STRING}/{min:STRING}"
      require_partition_filter = false
    }
  }
  depends_on = [
    google_storage_bucket_object.fake_message
  ]
}