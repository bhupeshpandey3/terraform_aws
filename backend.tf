terraform {
  backend "s3" {
    bucket       = "myapp-tfstate-685197708357"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true # S3 native locking — requires Terraform >= 1.10
    # key is injected per environment via -backend-config flag:
    # terraform init -backend-config="key=dev/terraform.tfstate"
  }
}
