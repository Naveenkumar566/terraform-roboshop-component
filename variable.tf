variable "project" {
  default = "roboshop"
}

variable "environment" {
  default = dev
}

variable "component" {
  type = string
}


variable "role_priority" {
}

variable "app_version" {
  type = string
  default = "V3"
}

variable "domain_name" {
  type = string
  default = "naveenkanna.online"
}