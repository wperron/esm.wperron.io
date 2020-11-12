variable "env" {
  description = "short slug for the environment"
  type        = string
}

variable "hosted_zone" {
  description = "name  of the hosted used for the deployment. must already exist."
  type        = string
}