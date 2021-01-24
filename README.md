# deno.wperron.io

Personal deno module registry

## Prerequisites

- Terraform >= v0.13 installed
- A valid pair of AWS access keys

## Deployment

Move into the `terraform/` directory and create a file called `terraform.tfvars`
with the following content:

```hcl
env         = "prod"
hosted_zone = "example.org"
```

The `env` parameter is only used to name and tag AWS resources, it does not
affect anything user-facing like domain name or visual labels. The `hosted_zone`
parameter is the name of the DNS hosted to which the website will be attached.
The website will be deployed as the `deno.` subdomain of that hosted zone.

> :warning: The hosted zone _must_ already exist in Route53, and must be a
> Route53 managed DNS zone.

Before the first apply, you'll need to comment out these lines from the
`meta.tf` file:

```hcl
terraform {
  required_version = ">= 0.13"
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
  # backend "s3" {
  #   key    = "terraform.tfstate"
  #   region = "ca-central-1"
  # }
}
```

Finally, run the following commands:

```text
terraform init
terraform plan -var-file terraform.tfvars -out plan.tfplan
terraform apply plan.tfplan
```

then, re-initialize using the s3 bucket that was created specifically to host
Terraform statefiles:

```text
terraform init \
  -backend-config="bucket=deno.{{your hosted zone}}-state-{{random id}}" \
```

From there, if you need to change something to the configuration, you simply
need to run the plan/apply loop directly:

```text
terraform plan -var-file terraform.tfvars -out plan.tfplan
```
