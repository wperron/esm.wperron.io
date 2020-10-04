provider "aws" {
  region = "ca-central-1"
}

provider "aws" {
  alias = "useast"
  region = "us-east-1"
}