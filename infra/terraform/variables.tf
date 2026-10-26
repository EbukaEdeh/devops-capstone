variable "aws_region" {
  description = "AWS region for the EKS cluster and ECR repositories."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project name used for ECR repositories."
  type        = string
  default     = "voting-app"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,30}$", var.project_name))
    error_message = "project_name must be lowercase alphanumeric with optional hyphens."
  }
}

variable "environment" {
  description = "Deployment environment tag."
  type        = string
  default     = "capstone"
}

variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
  default     = "voting-capstone"
}

variable "cluster_version" {
  description = "Kubernetes version for EKS."
  type        = string
  default     = "1.33"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Restrict this in real environments."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_enabled_log_types" {
  description = "EKS control-plane log types sent to CloudWatch."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
  default     = ["t3.small"]
}

variable "node_min_size" {
  description = "Minimum worker nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum worker nodes."
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Desired worker nodes."
  type        = number
  default     = 2
}

variable "node_disk_size_gb" {
  description = "Disk size for each worker node."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags applied to every resource."
  type        = map(string)
  default     = {}
}
