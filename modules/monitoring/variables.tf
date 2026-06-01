variable "env" {
  type        = string
  description = "Environment name (dev / test / prod)."
}

variable "project" {
  type        = string
  description = "Project/org token included in resource names (e.g. cdvlplatcon). Empty omits it."
  default     = ""
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "location_short" {
  type        = string
  description = "Short region code used in resource names (e.g. aue)."
  default     = "aue"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group to deploy into."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to all resources."
  default     = {}
}
