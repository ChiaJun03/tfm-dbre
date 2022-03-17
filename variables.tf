variable "project_id" {
  default = "tfm-dbre"
}

variable "region" {
  description = "The region to host the database in."
  default = "us-central1"
}

variable "master_user_name" {
  description = "The username part for the default user credentials, i.e. 'master_user_name'@'master_user_host' IDENTIFIED BY 'master_user_password'. This should typically be set as the environment variable TF_VAR_master_user_name so you don't check it into source control."
}

variable "master_user_password" {
  description = "The password part for the default user credentials, i.e. 'master_user_name'@'master_user_host' IDENTIFIED BY 'master_user_password'. This should typically be set as the environment variable TF_VAR_master_user_password so you don't check it into source control."
}

variable "machine_type" {
  description = "The machine type to use, see https://cloud.google.com/sql/pricing for more details"
  default     = "db-f1-micro"
}

variable "create_export_function" {
  description = "Create an export function and bucket to allow exporting database backups"
  default     = 1
}