provider "google" {
  project = "tfm-dbre"
  region = var.region
}

resource "google_compute_network" "private_network" {
  name = "private-network"
}

resource "google_compute_global_address" "private_ip_address" {

  name          = "private-ip-address"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.private_network.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.private_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]
}


// RandomID generator resource
resource "random_id" "db_name_suffix" {
  byte_length = 4
}

// Create Primary PostgreSQL database
resource "google_sql_database_instance" "primary" {
  name             = "primary-${random_id.db_name_suffix.hex}"
  region           = var.region
  database_version = "POSTGRES_13"

  depends_on = [google_service_networking_connection.private_vpc_connection]

  settings {
    tier              = var.machine_type
    availability_type = "REGIONAL"
    disk_size         = "100"
    backup_configuration {
      enabled = true
    }
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.private_network.id
    }
    location_preference {
      zone = "us-central1-a"
    }
  }
}

// Create database and database user
resource "google_sql_user" "main" {
  depends_on = [
    google_sql_database_instance.primary
  ]
  name     = var.master_user_name
  instance = google_sql_database_instance.primary.name
  password = var.master_user_password
}

resource "google_sql_database" "main" {
  depends_on = [
    google_sql_user.main
  ]
  name     = "main"
  instance = google_sql_database_instance.primary.name
}


// Create read-replica
resource "google_sql_database_instance" "replica" {
  name                 = "replica-${random_id.db_name_suffix.hex}"
  master_instance_name = "tfm-dbre:${google_sql_database_instance.primary.name}"
  region               = var.region
  database_version     = "POSTGRES_13"

  replica_configuration {
    failover_target = false
  }

  settings {
    tier              = var.machine_type
    availability_type = "ZONAL"
    disk_size         = "100"
    backup_configuration {
      enabled = false
    }
    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.private_network.id
    }
    location_preference {
      zone = "us-central1-a"
    }
  }
  depends_on = [google_sql_database_instance.primary, google_service_networking_connection.private_vpc_connection]
}

// based from code found in the article at
// https://servian.dev/gcp-periodic-export-of-mysql-backups-to-a-bucket-with-terraform-aa8854db35

# https://www.terraform.io/docs/providers/google/r/app_engine_application.html
# App Engine applications cannot be deleted once they're created; 
# you have to delete the entire project to delete the application.
# Terraform will report the application has been successfully deleted;
# this is a limitation of Terraform, and will go away in the future.
# Terraform is not able to delete App Engine applications.
#
# If this resource is marked as deleted by terraform, re-import it with:
# terraform import "google_app_engine_application.db_export_scheduler_app" "[project_id]"

resource "google_app_engine_application" "db_export_scheduler_app" {
  # count       = "${var.create_export_function}"
  # See comment above - this resource can only be created and never destroyed
  project = "${var.project_id}"
  location_id = "us-central"
}

## Create bucket
resource "random_id" "db_bucket_suffix" {
  byte_length = 2
  keepers = {
    project_id = "${var.project_id}"
  }
}
resource "google_storage_bucket" "db_backup_bucket" {
  name     = "replica-db-backup-${random_id.db_bucket_suffix.hex}"
  project  = "${var.project_id}"
  location = var.region
  storage_class = "REGIONAL"

  versioning {
    enabled = "false"
  }

  lifecycle_rule {
    action {
      type          = "Delete"
    }
    condition {
        age = 15
    }
  }
}

resource "google_storage_bucket_iam_member" "db_service_account-roles_storage-objectAdmin" {
  bucket = "${google_storage_bucket.db_backup_bucket.name}"
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_sql_database_instance.replica.service_account_email_address}"
}

# create local zip of code
data "archive_file" "function_dist" {
  output_path = "./dist/export_function_source.zip"
  source_dir  = "./app/"
  type        = "zip"
}

# upload the file_md5 to GCP bucket
resource "google_storage_bucket_object" "cloudfunction_source_code" {
  depends_on = [data.archive_file.function_dist]

  name   = "code/export_database-${lower(replace(base64encode(md5(file("./app/export_database.js"))), "=", ""))}.zip"
  bucket = "${google_storage_bucket.db_backup_bucket.name}"
  source = "./dist/export_function_source.zip"
}

# create function using the file_md5 as the source
resource "google_cloudfunctions_function" "export_database_to_bucket" {
  depends_on            = [google_storage_bucket_object.cloudfunction_source_code]
  project               = "${var.project_id}"
  region                = var.region
  name                  = "export_database_to_bucket"
  description           = "[Managed by Terraform] This function exports the main database instance to the backup bucket"
  available_memory_mb   = 128
  source_archive_bucket = "${google_storage_bucket.db_backup_bucket.name}"
  source_archive_object = "code/export_database-${lower(replace(base64encode(md5(file("./app/export_database.js"))), "=", ""))}.zip"
  runtime               = "nodejs8"
  entry_point           = "exportDatabase"
  trigger_http          = "true"
}

data "google_compute_default_service_account" "default" {
  project = "${var.project_id}"
}

data "template_file" "cloudfunction_params" {

  template = <<EOF
{
    "project_name": "${var.project_id}",
    "postgresql_instance_name": "${google_sql_database_instance.replica.name}",
    "bucket_name": "${google_storage_bucket.db_backup_bucket.name}"
}
EOF
}

resource "google_cloud_scheduler_job" "db_export_trigger" {
  depends_on  = [google_storage_bucket_object.cloudfunction_source_code]
  project     = var.project_id
  name        = "db-export-scheduler-job"
  schedule    = "0 0 * * *"
  description = "Exports the database at 12am daily"
  region   = var.region
  retry_config {
    retry_count = 1
  }
  http_target {
    uri         = "${google_cloudfunctions_function.export_database_to_bucket.*.https_trigger_url[0]}"
    http_method = "POST"
    body = "${base64encode(data.template_file.cloudfunction_params.rendered)}"
    oidc_token {
      service_account_email = "${data.google_compute_default_service_account.default.email}"
    }
  }
}