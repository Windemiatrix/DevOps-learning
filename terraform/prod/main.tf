provider "google" {
  # Версия провайдера
  version = "~> 2.15"
  #ID проекта
  project = var.project
  region = var.region
}

module "app" {
  source          = "../modules/app"
  public_key_path = var.public_key_path
  zone            = var.zone
  app_disk_image  = var.app_disk_image
  private_key_path = var.private_key_path
  project          = var.project
}

module "db" {
  source          = "../modules/db"
  public_key_path = var.public_key_path
  zone            = var.zone
  db_disk_image   = var.db_disk_image
  private_key_path = var.private_key_path
  project          = var.project
}

module "vpc" {
  source          = "../modules/vpc"
  source_ranges   = ["91.221.30.239/32"]
}

