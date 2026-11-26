variable "region" {
  description = "AWS Region for all resources. The project SCP allows only eu-north-1."
  type        = string
  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-\\d$", var.region))
    error_message = "Must look like an AWS Region, e.g. eu-north-1."
  }
}

variable "account_id" {
  description = "AWS Account ID for all resources."
  type        = string
  validation {
    condition     = can(regex("^\\d{12}$", var.account_id))
    error_message = "Must be a valid AWS Account ID, e.g. 123456789012."
  }
}
