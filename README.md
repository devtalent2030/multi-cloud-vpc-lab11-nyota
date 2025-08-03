# Multi-Cloud VPC / VNet Lab 11

> **Author:** Nyota ✦ **Role:** Cloud Security Engineer  
> **Date:** 2025-08-03

## 📜 Purpose

Replicate a secure **public + private network tier** across **AWS, GCP, and Azure**  
to demonstrate:

* Consistent network segmentation (/24 subnets inside a /16)
* Controlled ingress via ALB / HTTPS LB / Azure LB
* Egress-only Internet for private workloads via NAT (AWS NAT GW, Cloud NAT, Azure NAT GW)
* Cloud-native “security group” equivalents (AWS SG, GCP firewall, Azure NSG)

## 🏗 Repo structure

| Path | What you’ll find |
|------|------------------|
| `aws/` | Bash scripts to build / destroy the AWS topology + diagram |
| `gcp/` | Bash scripts for GCP (Cloud Shell) + diagram |
| `azure/` | Bash scripts for Azure (Cloud Shell) + diagram |
| `docs/` | Word report, Lucidchart PNGs, grading screenshots |

## 🚀 Quick start

```bash
# AWS
cd aws && ./build_aws_net.sh
# GCP
cd gcp && ./build_gcp_net.sh
# Azure
cd azure && ./build_azure_net.sh
