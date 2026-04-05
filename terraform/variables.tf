# terraform/variables.tf

# Project & naming
variable "project_name" {
  type        = string
  description = "Short name of the project, used for resource naming."
  default     = "online-voting"
}

variable "location" {
  type        = string
  description = "Azure region to deploy resources in."
  default     = "South Africa North"
}

# Resource group
variable "resource_group_name" {
  type        = string
  description = "Name of the resource group for all resources."
  default     = "iac-rg"
}

# Virtual Network
variable "vnet_cidr" {
  type        = string
  description = "CIDR block for the virtual network."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type        = string
  description = "CIDR block for the public subnet."
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  type        = string
  description = "CIDR block for the private subnet."
  default     = "10.0.2.0/24"
}

# Backend Database
variable "db_username" {
  type        = string
  description = "Administrator username for the PostgreSQL database."
  default     = "adminuser"
}

# Container App Resources
variable "backend_cpu" {
  type        = number
  description = "CPU allocation for backend container app."
  default     = 0.5
}

variable "backend_memory" {
  type        = string
  description = "Memory allocation for backend container app."
  default     = "1Gi"
}

variable "frontend_cpu" {
  type        = number
  description = "CPU allocation for frontend container app."
  default     = 0.25
}

variable "frontend_memory" {
  type        = string
  description = "Memory allocation for frontend container app."
  default     = "0.5Gi"
}

# Container Registry
variable "acr_sku" {
  type        = string
  description = "SKU for Azure Container Registry."
  default     = "Basic"
}