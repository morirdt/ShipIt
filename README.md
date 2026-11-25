# ShipIt

A small FastAPI service deployed to AWS ECS Fargate behind an ALB, with all infrastructure in Terraform and every change shipped through GitHub Actions.

> Work in progress. Architecture, CI/CD and cost sections will be added as the phases land.

## AWS access

No long-lived AWS credentials are used anywhere.

- **Locally:** short-lived credentials from a console sign-in.
  ```sh
  aws login --profile dev
  export AWS_PROFILE=dev
  aws sts get-caller-identity
  ```
- **CI:** GitHub Actions assumes IAM roles through OIDC. No access keys are stored in GitHub.
