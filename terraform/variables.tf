variable "env" {
  description = "short slug for the environment"
  type        = string
}

variable "hosted_zone" {
  description = "name  of the hosted used for the deployment. must already exist."
  type        = string
}

variable "loki_username" {
  description = "Grafana Cloud's Loki username"
  type        = string
}

variable "loki_password" {
  description = "Grafana Cloud's Loki password"
  type        = string
}

variable "new_relic_api_key" {
  description = "New Relic Insights API Key"
  type        = string
}